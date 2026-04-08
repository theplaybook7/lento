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
  Future<void> checkAndNotifyUpcomingInstallments(String projectId) async {
    try {
      final upcomingInstallments = await _firebase.getUpcomingInstallments(
        projectId,
        daysAhead: 7, // 7 gün içindeki taksitleri al
      );

      for (var installment in upcomingInstallments) {
        await showNotification(
          id: installment.id.hashCode,
          title: 'Ödeme Tarihi Yaklaşıyor',
          body: 'Taksit #${installment.installmentNumber} - ₺${installment.amount.toStringAsFixed(2)}',
          payload: installment.id,
        );
      }

      developer.log('${upcomingInstallments.length} bildirim gönderildi');
    } catch (e) {
      developer.log('Taksitleri kontrol etme hatası: $e');
    }
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

  /// Background task başlat (her 24 saatte bir taksitleri kontrol et)
  Future<void> initializeBackgroundTasks() async {
    try {
      if (kIsWeb) {
        return;
      }

      if (defaultTargetPlatform != TargetPlatform.iOS) {
        return;
      }

      await Workmanager().initialize(
        callbackDispatcher,
      );

      await Workmanager().registerPeriodicTask(
        _paymentBackgroundTaskName,
        _paymentBackgroundTaskName,
        frequency: const Duration(hours: 24),
        initialDelay: const Duration(minutes: 15),
      );

      developer.log('Background task başlatıldı');
    } catch (e) {
      developer.log('Background task hatası: $e');
    }
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
