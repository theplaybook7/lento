import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

class WebPaymentService {
  static final WebPaymentService _instance = WebPaymentService._internal();
  factory WebPaymentService() => _instance;
  WebPaymentService._internal();

  static const String _checkoutUrl =
      'https://us-central1-insaat-yonetim-takip.cloudfunctions.net/initStripeCheckout';

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

  /// Mevcut kullanıcıyı al (web'de currentUser bazen null olabiliyor)
  Future<User?> _getCurrentUser() async {
    final user = _auth.currentUser;
    if (user != null) return user;
    // Web'de auth state gecikmeli yüklenebilir, stream'den kontrol et
    return await _auth.authStateChanges().first;
  }

  /// Stripe Checkout Session oluştur ve ödeme sayfasına yönlendir
  /// [email] parametresi verilirse auth gerekmez (yeni kullanıcı akışı)
  Future<bool> startCheckout({required String planType, String? email}) async {
    _lastError = '';

    // Auth'lu kullanıcı varsa onun emailini kullan, yoksa parametre olarak gelen emaili
    final user = _auth.currentUser;
    final checkoutEmail = email ?? user?.email;

    if (checkoutEmail == null || checkoutEmail.isEmpty) {
      _lastError = 'E-posta adresi gerekli.';
      return false;
    }

    try {
      final response = await http.post(
        Uri.parse(_checkoutUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': checkoutEmail,
          'planType': planType,
          'successUrl': '${Uri.base.origin}/?payment=success&email=${Uri.encodeComponent(checkoutEmail)}',
          'cancelUrl': '${Uri.base.origin}/?payment=cancelled',
        }),
      );

      if (response.statusCode != 200) {
        final errorData = jsonDecode(response.body);
        _lastError = errorData['error'] ?? 'Ödeme servisi hatası.';
        return false;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
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
    } catch (e) {
      _lastError = 'Ödeme başlatma hatası: $e';
      return false;
    }
  }

  /// Ödeme durumunu kontrol et
  Future<Map<String, dynamic>> getSubscriptionStatus() async {
    try {
      final user = await _getCurrentUser();
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

  /// Email bazlı ödeme durumu kontrol et (kayıt olmamış kullanıcılar için)
  Future<Map<String, dynamic>> checkPaymentByEmail(String email) async {
    try {
      final normalizedEmail = email.trim().toLowerCase();
      final doc = await _firestore
          .collection('pending_payments')
          .doc(normalizedEmail)
          .get();

      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        final paid = data['paid'] as bool? ?? false;
        if (paid) {
          return {
            'active': true,
            'planType': data['planType'],
            'email': normalizedEmail,
          };
        }
      }

      return {'active': false};
    } catch (e) {
      return {'active': false};
    }
  }
}
