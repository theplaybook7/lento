import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'dart:async';

class PaymentService {
  static final PaymentService _instance = PaymentService._internal();
  
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final InAppPurchase _iap = InAppPurchase.instance;

  StreamSubscription<List<PurchaseDetails>>? _subscription;
  bool _initialized = false;
  String _lastError = '';
  Completer<bool>? _purchaseCompleter;
  String? _pendingProductId;
  
  // Ürün ID'leri - Subscription
  static const String yearlySubscriptionId = 'company_yearly_subscription';
  static const String monthlySubscriptionId = 'company_monthly_subscription';
  static const Set<String> _subscriptionProductIds = {
    yearlySubscriptionId,
    monthlySubscriptionId,
  };
  
  
  // Fiyatlandırma
  static const double yearlyPrice = 29999.00;  // ₺29.999,00/yıl
  static const double monthlyPrice = 2999.99;  // ₺2.999,99/ay

  factory PaymentService() {
    return _instance;
  }

  PaymentService._internal();

  String get lastError => _lastError;

  bool get isApplePaymentSupported {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
  }

  bool get isIOSPaymentSupported => isApplePaymentSupported;

  Future<void> initialize() async {
    if (_initialized) return;

    if (!isApplePaymentSupported) {
      _lastError = 'Bu uygulamada ödeme yalnızca Apple App Store (iOS/macOS) üzerinden desteklenir.';
      return;
    }

    final iapAvailable = await _iap.isAvailable();
    if (!iapAvailable) {
      _lastError = 'App Store ödeme servisi şu anda kullanılamıyor.';
      return;
    }

    if (iapAvailable) {
      _subscription = _iap.purchaseStream.listen(
        (List<PurchaseDetails> purchases) async {
          for (var purchase in purchases) {
            await _handlePurchaseUpdate(purchase);
          }
        },
        onError: (error) {
          _lastError = 'Ödeme akışı hatası: $error';
          _completePurchaseFlow(false);
        },
      );
      _initialized = true;
    }
  }

  String? _subscriptionTypeFromProductId(String productId) {
    if (productId == yearlySubscriptionId) return 'yearly';
    if (productId == monthlySubscriptionId) return 'monthly';
    return null;
  }

  DateTime _subscriptionEndDateForType(String type) {
    if (type == 'yearly') {
      return DateTime.now().add(const Duration(days: 365));
    }
    return DateTime.now().add(const Duration(days: 30));
  }

  bool _isStoreKitNoResponse(String message) {
    final normalized = message.toLowerCase();
    return normalized.contains('storekit') &&
        (normalized.contains('failed to get response from platform') ||
            normalized.contains('no response'));
  }

  String _storeKitNoResponseMessage() {
    return 'StoreKit platformdan yanit alamadi. iOS Simulator kullaniyorsaniz bu durum gorulebilir. '
        'Gercek cihaz + Sandbox Apple ID ile tekrar deneyin veya Xcode StoreKit Configuration ayari yapin.';
  }

  Future<ProductDetailsResponse> _querySubscriptionProductsWithRetry() async {
    var response = await _iap.queryProductDetails(_subscriptionProductIds);

    if (response.error != null && _isStoreKitNoResponse(response.error!.message)) {
      await Future.delayed(const Duration(milliseconds: 1200));
      response = await _iap.queryProductDetails(_subscriptionProductIds);
    }

    return response;
  }

  Future<void> _handlePurchaseUpdate(PurchaseDetails purchase) async {
    if (purchase.status == PurchaseStatus.purchased || purchase.status == PurchaseStatus.restored) {
      final user = _auth.currentUser;
      final subscriptionType = _subscriptionTypeFromProductId(purchase.productID);

      if (user != null && subscriptionType != null) {
        final subscriptionEndDate = _subscriptionEndDateForType(subscriptionType);

        await _firestore.collection('users').doc(user.uid).set({
          'companyCreationPaid': true,
          'paidAt': DateTime.now(),
          'productId': purchase.productID,
          'transactionId': purchase.purchaseID,
          'subscriptionType': subscriptionType,
          'subscriptionEndDate': Timestamp.fromDate(subscriptionEndDate),
          'autoRenew': true,
          'lastPurchaseStatus': purchase.status.name,
        }, SetOptions(merge: true));

        _lastError = '';
        _completePurchaseFlow(true, productId: purchase.productID);
      } else if (_pendingProductId == purchase.productID) {
        _lastError = 'Satın alma doğrulaması tamamlanamadı.';
        _completePurchaseFlow(false, productId: purchase.productID);
      }
    }

    if (purchase.status == PurchaseStatus.error) {
      _lastError = purchase.error?.message ?? 'Ödeme sırasında beklenmeyen bir hata oluştu.';
      _completePurchaseFlow(false, productId: purchase.productID);
    }

    if (purchase.status == PurchaseStatus.canceled) {
      _lastError = 'Ödeme işlemi iptal edildi.';
      _completePurchaseFlow(false, productId: purchase.productID);
    }

    if (purchase.pendingCompletePurchase) {
      await _iap.completePurchase(purchase);
    }
  }

  void _completePurchaseFlow(bool value, {String? productId}) {
    if (_purchaseCompleter == null || _purchaseCompleter!.isCompleted) {
      return;
    }

    if (productId != null && _pendingProductId != null && productId != _pendingProductId) {
      return;
    }

    _purchaseCompleter!.complete(value);
    _purchaseCompleter = null;
    _pendingProductId = null;
  }

  /// Subscription durumunu kontrol et
  Future<Map<String, dynamic>> getSubscriptionStatus() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return {'active': false, 'type': null};

      final userDoc = await _firestore
          .collection('users')
          .doc(user.uid)
          .get();

      if (userDoc.exists) {
        final data = userDoc.data() as Map<String, dynamic>;
        final endDate = data['subscriptionEndDate'] as Timestamp?;
        final type = data['subscriptionType'] as String?;
        
        if (endDate != null) {
          final isActive = endDate.toDate().isAfter(DateTime.now());
          return {
            'active': isActive,
            'type': type,
            'endDate': endDate.toDate(),
          };
        }
      }
      
      return {'active': false, 'type': null};
    } catch (e) {
      return {'active': false, 'type': null};
    }
  }

  /// Subscription ürünlerini yükle
  Future<List<ProductDetails>> fetchSubscriptionProducts() async {
    try {
      if (!isApplePaymentSupported) {
        _lastError = 'Bu uygulamada ödeme yalnızca Apple App Store (iOS/macOS) üzerinden desteklenir.';
        return [];
      }

      final ProductDetailsResponse response = await _querySubscriptionProductsWithRetry();

      if (response.error != null) {
        final platformMessage = response.error!.message;
        _lastError = _isStoreKitNoResponse(platformMessage)
            ? _storeKitNoResponseMessage()
            : platformMessage;
        return [];
      }

      if (response.notFoundIDs.isNotEmpty) {
        _lastError = 'App Store ürünleri bulunamadı: ${response.notFoundIDs.join(', ')}';
      }

      return response.productDetails;
    } catch (e) {
      final errorText = e.toString();
      _lastError = _isStoreKitNoResponse(errorText)
          ? _storeKitNoResponseMessage()
          : 'Ürünler yüklenemedi: $e';
      return [];
    }
  }

  /// Subscription satın alma işlemini başlat
  Future<bool> purchaseSubscription(String productId) async {
    try {
      _lastError = '';
      await initialize();

      if (!isApplePaymentSupported) {
        _lastError = 'Bu uygulamada ödeme yalnızca Apple App Store (iOS/macOS) üzerinden desteklenir.';
        return false;
      }

      if (!_initialized) {
        if (_lastError.isEmpty) {
          _lastError = 'App Store ödeme servisi başlatılamadı.';
        }
        return false;
      }

      if (_purchaseCompleter != null && !_purchaseCompleter!.isCompleted) {
        _lastError = 'Ödeme işlemi zaten devam ediyor. Lütfen bekleyin.';
        return false;
      }

      final products = await fetchSubscriptionProducts();
      
      if (products.isEmpty) {
        if (_lastError.isEmpty) {
          _lastError = 'Satın alınabilir ürün bulunamadı.';
        }
        return false;
      }

      final productDetails = products.firstWhere(
        (p) => p.id == productId,
        orElse: () => ProductDetails(
          id: '',
          title: '',
          description: '',
          price: '',
          rawPrice: 0,
          currencyCode: '',
        ),
      );

      if (productDetails.id.isEmpty) {
        _lastError = 'Seçilen abonelik ürünü App Store üzerinde bulunamadı.';
        return false;
      }

      final PurchaseParam purchaseParam = PurchaseParam(
        productDetails: productDetails,
      );

      _purchaseCompleter = Completer<bool>();
      _pendingProductId = productId;

      final started = await _iap.buyNonConsumable(
        purchaseParam: purchaseParam,
      );

      if (!started) {
        _lastError = 'Ödeme başlatılamadı.';
        _completePurchaseFlow(false, productId: productId);
        return false;
      }

      final completed = await _purchaseCompleter!.future.timeout(
        const Duration(minutes: 3),
        onTimeout: () {
          _lastError = 'Ödeme onayı zaman aşımına uğradı. Lütfen tekrar deneyin.';
          _completePurchaseFlow(false, productId: productId);
          return false;
        },
      );

      return completed;
    } catch (e) {
      final errorText = e.toString();
      _lastError = _isStoreKitNoResponse(errorText)
          ? _storeKitNoResponseMessage()
          : 'Satın alma hatası: $e';
      _completePurchaseFlow(false, productId: productId);
      return false;
    }
  }

  /// Restore purchases (kullanıcı uygulamayı yeniden yüklerse)
  Future<bool> restorePurchases() async {
    try {
      _lastError = '';
      if (!isApplePaymentSupported) {
        _lastError = 'Geri yükleme yalnızca Apple App Store (iOS/macOS) için kullanılabilir.';
        return false;
      }

      await _iap.restorePurchases();
      return true;
    } catch (e) {
      final errorText = e.toString();
      _lastError = _isStoreKitNoResponse(errorText)
          ? _storeKitNoResponseMessage()
          : 'Geri yükleme hatası: $e';
      return false;
    }
  }

  /// Temizle
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _initialized = false;
  }
}
