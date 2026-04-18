import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';
import 'package:flutter/foundation.dart';
import 'dart:developer' as developer;
import 'firebase_service.dart';

const String _paymentBackgroundTaskName = 'payment_check';

class PaymentNotificationService {
  static final PaymentNotificationService _instance = PaymentNotificationService._internal();
  
  factory PaymentNotificationService() => _instance;
  PaymentNotificationService._internal();

  late FlutterLocalNotificationsPlugin _notificationsPlugin;
  final _firebase = FirebaseService();

  Future<void> initialize() async {
    _notificationsPlugin = FlutterLocalNotificationsPlugin();

    // iOS ayarları
    final iosInitialization = DarwinInitializationSettings(
      onDidReceiveLocalNotification: _onDidReceiveLocalNotification,
    );

    final initSettings = InitializationSettings(
      iOS: iosInitialization,
    );

    await _notificationsPlugin.initialize(initSettings);

    // iOS local notifications için kullanıcı izni iste.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      await _notificationsPlugin
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );
    }

    developer.log('Bildirim servisi başlatıldı');
  }

  /// Bildirim göster
  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    try {
      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const notificationDetails = NotificationDetails(
        iOS: iosDetails,
      );

      await _notificationsPlugin.show(
        id,
        title,
        body,
        notificationDetails,
        payload: payload,
      );

      developer.log('Bildirim gösterildi: $title');
    } catch (e) {
      developer.log('Bildirim gösterme hatası: $e');
    }
  }

  /// Yaklaşan taksitleri kontrol et ve bildirim gönder
  /// NOT: Eski ödeme planı sistemi kaldırıldı. Taksitli plan sistemi cari_hesap_screen üzerinden çalışıyor.
  Future<void> checkAndNotifyUpcomingInstallments(String projectId) async {
    // Eski payment_installments koleksiyonu artık kullanılmıyor
    developer.log('Eski ödeme planı bildirim kontrolü devre dışı');
  }

  /// iOS için eski bildirim callback
  void _onDidReceiveLocalNotification(
    int id,
    String? title,
    String? body,
    String? payload,
  ) {
    developer.log('iOS Bildirim: $title - $body');
  }

  /// Background task başlat
  /// NOT: Eski ödeme planı sistemi kaldırıldı, background task devre dışı.
  Future<void> initializeBackgroundTasks() async {
    // Eski background task gereksiz iOS kaynak tüketimi yapıyordu, devre dışı bırakıldı
    developer.log('Background task devre dışı (eski ödeme sistemi kaldırıldı)');
  }

  /// Background task'i durdur
  Future<void> stopBackgroundTasks() async {
    try {
      await Workmanager().cancelByUniqueName(_paymentBackgroundTaskName);
      developer.log('Background task durduruldu');
    } catch (e) {
      developer.log('Background task durdurma hatası: $e');
    }
  }
}

/// Callback dispatcher for Workmanager
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    try {
      if (taskName == _paymentBackgroundTaskName) {
        // Tüm projelerin taksitlerini kontrol et
        // Not: Burada gerçek uygulamada kompanı ID'si ve proje ID'si gerekir
        // Şimdilik örnek olarak gösterilmiştir
        developer.log('Taksitleri kontrol eden arka plan task çalışıyor');
      }
      return true;
    } catch (e) {
      developer.log('Callback dispatcher hatası: $e');
      return false;
    }
  });
}
