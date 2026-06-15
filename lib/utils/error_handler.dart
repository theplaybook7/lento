/// Error handling utilities
library;
import 'package:flutter/material.dart';
import 'dart:developer' as developer;
import '../config/app_config.dart';

typedef AsyncVoidCallback = Future<void> Function();
typedef AsyncValueCallback<T> = Future<T> Function();

/// Firebase ve genel hata mesajlarını Türkçeye çevirir
String hataCevir(Object e) {
  final mesaj = e.toString();

  // Firebase Auth hataları
  if (mesaj.contains('permission-denied') || mesaj.contains('insufficient permissions')) {
    return 'Erişim izni yok. Lütfen yöneticinize başvurun.';
  }
  if (mesaj.contains('not-found')) {
    return 'Kayıt bulunamadı.';
  }
  if (mesaj.contains('already-exists')) {
    return 'Bu kayıt zaten mevcut.';
  }
  if (mesaj.contains('unauthenticated') || mesaj.contains('requires-auth')) {
    return 'Oturum süresi dolmuş. Lütfen tekrar giriş yapın.';
  }
  if (mesaj.contains('network-request-failed') || mesaj.contains('unavailable')) {
    return 'İnternet bağlantısı yok. Lütfen bağlantınızı kontrol edin.';
  }
  if (mesaj.contains('deadline-exceeded') || mesaj.contains('timeout')) {
    return 'İşlem zaman aşımına uğradı. Lütfen tekrar deneyin.';
  }
  if (mesaj.contains('resource-exhausted')) {
    return 'Kullanım limiti aşıldı. Lütfen daha sonra tekrar deneyin.';
  }
  if (mesaj.contains('cancelled')) {
    return 'İşlem iptal edildi.';
  }
  if (mesaj.contains('invalid-argument')) {
    return 'Geçersiz veri gönderildi.';
  }
  if (mesaj.contains('wrong-password') || mesaj.contains('invalid-credential')) {
    return 'E-posta veya şifre hatalı.';
  }
  if (mesaj.contains('user-not-found')) {
    return 'Bu e-posta ile kayıtlı kullanıcı bulunamadı.';
  }
  if (mesaj.contains('email-already-in-use')) {
    return 'Bu e-posta zaten kullanılıyor.';
  }
  if (mesaj.contains('weak-password')) {
    return 'Şifre çok zayıf. En az 6 karakter olmalıdır.';
  }
  if (mesaj.contains('too-many-requests')) {
    return 'Çok fazla deneme yapıldı. Lütfen biraz bekleyin.';
  }
  if (mesaj.contains('quota-exceeded') || mesaj.contains('storage/quota-exceeded')) {
    return 'Depolama kotası aşıldı.';
  }
  if (mesaj.contains('object-not-found')) {
    return 'Dosya bulunamadı.';
  }
  if (mesaj.contains('storage/unauthorized') || mesaj.contains('storage/unauthenticated')) {
    return 'Dosya yükleme izni yok. Lütfen tekrar giriş yapın.';
  }
  if (mesaj.contains('storage/retry-limit-exceeded')) {
    return 'Dosya yükleme başarısız. Lütfen tekrar deneyin.';
  }
  if (mesaj.contains('storage/canceled')) {
    return 'Dosya yükleme iptal edildi.';
  }
  if (mesaj.contains('Null check')) {
    return 'Veri okunamadı. Lütfen tekrar deneyin.';
  }

  if (mesaj.startsWith('Exception: ')) {
    return mesaj.replaceFirst('Exception: ', '').trim();
  }

  // Genel hata — teknik detayı göstermeden kısa bir mesaj
  return 'Beklenmeyen bir hata oluştu. Lütfen tekrar deneyin.';
}

/// Hata işleme wrapper - logging ve error handling standartlaştırması
Future<void> safeAsyncOperation(
  AsyncVoidCallback operation, {
  String operationName = 'Operation',
  BuildContext? context,
  VoidCallback? onSuccess,
  Function(Object)? onError,
  bool showSnackBar = true,
}) async {
  try {
    await operation();
    if (AppConfig.debugMode) {
      developer.log('✓ $operationName tamamlandı');
    }
    onSuccess?.call();
  } catch (e, stackTrace) {
    developer.log(
      '✗ $operationName hatası: $e',
      error: e,
      stackTrace: stackTrace,
    );
    onError?.call(e);
    if (showSnackBar && context != null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(hataCevir(e))),
        );
      }
    }
  }
}

/// Hata işleme wrapper - değer döndüren işlemler için
Future<T?> safeAsyncValue<T>(
  AsyncValueCallback<T> operation, {
  String operationName = 'Operation',
  BuildContext? context,
  VoidCallback? onSuccess,
  Function(Object)? onError,
  bool showSnackBar = false,
}) async {
  try {
    final result = await operation();
    if (AppConfig.debugMode) {
      developer.log('✓ $operationName tamamlandı');
    }
    onSuccess?.call();
    return result;
  } catch (e, stackTrace) {
    developer.log(
      '✗ $operationName hatası: $e',
      error: e,
      stackTrace: stackTrace,
    );
    onError?.call(e);
    if (showSnackBar && context != null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(hataCevir(e))),
        );
      }
    }
    return null;
  }
}
