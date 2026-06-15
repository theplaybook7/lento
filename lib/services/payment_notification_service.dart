import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';
import 'dart:developer' as developer;

class PaymentNotificationService {
  static final PaymentNotificationService _instance =
      PaymentNotificationService._internal();

  factory PaymentNotificationService() => _instance;
  PaymentNotificationService._internal();

  late FlutterLocalNotificationsPlugin _notificationsPlugin;

  Future<void> initialize() async {
    _notificationsPlugin = FlutterLocalNotificationsPlugin();

    // iOS ayarları
    final iosInitialization = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    final initSettings = InitializationSettings(iOS: iosInitialization);

    await _notificationsPlugin.initialize(settings: initSettings);

    // iOS local notifications için kullanıcı izni iste.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      await _notificationsPlugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
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

      const notificationDetails = NotificationDetails(iOS: iosDetails);

      await _notificationsPlugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: notificationDetails,
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

  /// Background task'i durdur
  Future<void> stopBackgroundTasks() async {
    developer.log('Background task devre disi; durdurulacak aktif gorev yok');
  }
}
