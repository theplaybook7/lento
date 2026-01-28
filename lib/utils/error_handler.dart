/// Error handling utilities
library;
import 'package:flutter/material.dart';
import 'dart:developer' as developer;
import '../config/app_config.dart';

typedef AsyncVoidCallback = Future<void> Function();
typedef AsyncValueCallback<T> = Future<T> Function();

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
          SnackBar(content: Text('Hata: $e')),
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
          SnackBar(content: Text('Hata: $e')),
        );
      }
    }
    return null;
  }
}
