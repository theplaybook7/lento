import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class FcmService {
  static final FcmService _instance = FcmService._();
  FcmService._();
  factory FcmService() => _instance;

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

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

      // Web için VAPID key gerekiyor
      String? token;
      if (kIsWeb) {
        // Firebase Console → Project Settings → Cloud Messaging → Web Push certificates
        // Bu key'i Firebase Console'dan alıp buraya koymanız gerekir
        token = await _messaging.getToken(
          vapidKey: 'YOUR_VAPID_KEY', // TODO: Firebase Console'dan alınacak
        );
      } else {
        token = await _messaging.getToken();
      }

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

      String? token;
      if (kIsWeb) {
        token = await _messaging.getToken();
      } else {
        token = await _messaging.getToken();
      }

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
