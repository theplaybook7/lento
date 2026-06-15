import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class FcmService {
  static final FcmService _instance = FcmService._();
  FcmService._();
  factory FcmService() => _instance;

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  Future<String?> _resolveFcmToken() async {
    if (kIsWeb) {
      return _messaging.getToken(
        vapidKey: 'BIIx0YZjIcdBoXPcUpCzMSldawZYzeg9DKrLWs9820RxEXhf_uYV-fhj1YJwX5RzGJlFYsSRDRkafpDiCfHB2rk',
      );
    }

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      await _messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      for (var attempt = 0; attempt < 5; attempt++) {
        final apnsToken = await _messaging.getAPNSToken();
        if (apnsToken != null && apnsToken.isNotEmpty) {
          break;
        }
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }

    return _messaging.getToken();
  }

  /// Bildirim izni iste ve FCM token'ı Firestore'a kaydet
  Future<void> initialize() async {
    try {
      // İzin iste
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        return;
      }

      final token = await _resolveFcmToken();

      if (token != null) {
        await _saveToken(token);
      }

      // Token yenilendiğinde güncelle
      _messaging.onTokenRefresh.listen(_saveToken);
    } catch (e) {
      debugPrint('FCM init hatası: $e');
    }
  }

  /// Token'ı Firestore'a kaydet
  Future<void> _saveToken(String token) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .set({
      'fcmTokens': FieldValue.arrayUnion([token]),
      'lastTokenUpdate': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Çıkış yaparken token'ı sil
  Future<void> removeToken() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final token = await _resolveFcmToken();

      if (token != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .update({
          'fcmTokens': FieldValue.arrayRemove([token]),
        });
      }
    } catch (_) {}
  }
}
