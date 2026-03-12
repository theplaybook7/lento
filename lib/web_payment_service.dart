import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

class WebPaymentService {
  static final WebPaymentService _instance = WebPaymentService._internal();
  factory WebPaymentService() => _instance;
  WebPaymentService._internal();

  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String _lastError = '';
  String get lastError => _lastError;

  bool get isWebPaymentSupported => kIsWeb;

  /// Web fiyatları (Stripe'dan alınan - Cloud Function ile senkron tutulmalı)
  static const Map<String, Map<String, dynamic>> webPlans = {
    'monthly': {
      'name': 'Aylık Abonelik',
      'price': '₺2.999,99',
      'interval': 'ay',
    },
    'yearly': {
      'name': 'Yıllık Abonelik',
      'price': '₺29.999,00',
      'interval': 'yıl',
    },
  };

  /// Stripe Checkout Session oluştur ve ödeme sayfasına yönlendir
  Future<bool> startCheckout({required String planType}) async {
    _lastError = '';
    final user = _auth.currentUser;
    if (user == null) {
      _lastError = 'Oturum bulunamadı. Lütfen giriş yapın.';
      return false;
    }

    try {
      final callable = _functions.httpsCallable('initStripeCheckout');
      final result = await callable.call<Map<String, dynamic>>({
        'email': user.email,
        'planType': planType,
        'successUrl': '${Uri.base.origin}/?payment=success',
        'cancelUrl': '${Uri.base.origin}/?payment=cancelled',
      });

      final data = result.data;
      final url = data['url'] as String?;

      if (url != null && url.isNotEmpty) {
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          return true;
        } else {
          _lastError = 'Ödeme sayfası açılamadı.';
          return false;
        }
      } else {
        _lastError = 'Stripe checkout URL alınamadı.';
        return false;
      }
    } on FirebaseFunctionsException catch (e) {
      _lastError = e.message ?? 'Ödeme servisi hatası.';
      return false;
    } catch (e) {
      _lastError = 'Ödeme başlatma hatası: $e';
      return false;
    }
  }

  /// Ödeme durumunu kontrol et
  Future<Map<String, dynamic>> getSubscriptionStatus() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return {'active': false, 'type': null};

      final userDoc = await _firestore.collection('users').doc(user.uid).get();

      if (userDoc.exists) {
        final data = userDoc.data() as Map<String, dynamic>;
        final endDate = data['subscriptionEndDate'] as Timestamp?;
        final type = data['subscriptionType'] as String?;
        final paid = data['companyCreationPaid'] as bool? ?? false;

        if (endDate != null) {
          final isActive = endDate.toDate().isAfter(DateTime.now());
          return {
            'active': isActive,
            'type': type,
            'endDate': endDate.toDate(),
          };
        }

        // Legacy one-time payment check
        if (paid) {
          return {'active': true, 'type': 'legacy'};
        }
      }

      return {'active': false, 'type': null};
    } catch (e) {
      return {'active': false, 'type': null};
    }
  }
}
