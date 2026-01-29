import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'dart:async';

class PaymentService {
  static final PaymentService _instance = PaymentService._internal();
  
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final InAppPurchase _iap = InAppPurchase.instance;

  late StreamSubscription<List<PurchaseDetails>> _subscription;
  
  // Ürün ID'leri - Subscription
  static const String yearlySubscriptionId = 'company_yearly_subscription';
  static const String monthlySubscriptionId = 'company_monthly_subscription';
  static const String trialSubscriptionId = 'company_trial_subscription';
  
  // Fiyatlandırma
  static const double yearlyPrice = 99.99;  // $99.99/yıl
  static const double monthlyPrice = 9.99;  // $9.99/ay
  static const double trialPrice = 0.0;     // 7 gün ücretsiz

  factory PaymentService() {
    return _instance;
  }

  PaymentService._internal();

  Future<void> initialize() async {
    final iapAvailable = await _iap.isAvailable();
    
    if (iapAvailable) {
      _subscription = _iap.purchaseStream.listen(
        (List<PurchaseDetails> purchases) async {
          for (var purchase in purchases) {
            await _handlePurchaseUpdate(purchase);
          }
        },
        onError: (error) {
          // IAP Error handling
        },
      );
    }
  }

  Future<void> _handlePurchaseUpdate(PurchaseDetails purchase) async {
    if (purchase.status == PurchaseStatus.purchased ||
        purchase.status == PurchaseStatus.restored) {
      
      final user = _auth.currentUser;
      if (user != null) {
        // Ödeme başarılı, Firestore'da kaydet
        await _firestore.collection('users').doc(user.uid).set({
          'companyCreationPaid': true,
          'paidAt': DateTime.now(),
          'productId': purchase.productID,
          'transactionId': purchase.purchaseID,
        }, SetOptions(merge: true));
      }

      // Ödemeyi tamamla
      if (purchase.pendingCompletePurchase) {
        await _iap.completePurchase(purchase);
      }
    }
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
      final ProductDetailsResponse response = await _iap.queryProductDetails(
        {yearlySubscriptionId, monthlySubscriptionId, trialSubscriptionId},
      );

      if (response.error != null) {
        return [];
      }

      return response.productDetails;
    } catch (e) {
      return [];
    }
  }

  /// Subscription satın alma işlemini başlat
  Future<bool> purchaseSubscription(String productId) async {
    try {
      final products = await fetchSubscriptionProducts();
      
      if (products.isEmpty) {
        return false;
      }

      final productDetails = products.firstWhere(
        (p) => p.id == productId,
        orElse: () => products.first,
      );

      final PurchaseParam purchaseParam = PurchaseParam(
        productDetails: productDetails,
      );

      final success = await _iap.buyNonConsumable(
        purchaseParam: purchaseParam,
      );

      return success;
    } catch (e) {
      return false;
    }
  }

  /// Stripe ile web ödemesi (Türkiye için iyzico de kullanılabilir)
  Future<bool> processWebPayment(String email) async {
    try {
      // TODO: Stripe Checkout Session oluştur
      // Firebase Cloud Function çağır: initStripeCheckout
      // Kullanıcıyı Stripe Checkout'a yönlendir
      // Webhook ile ödeme doğrulamasını yap
      return false; // Şimdilik placeholder
    } catch (e) {
      return false;
    }
  }

  /// Restore purchases (kullanıcı uygulamayı yeniden yüklerse)
  Future<void> restorePurchases() async {
    try {
      await _iap.restorePurchases();
    } catch (e) {
      // Restore hatası
    }
  }

  /// Temizle
  void dispose() {
    _subscription.cancel();
  }
}
