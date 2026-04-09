import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import 'upload_helper_stub.dart'
    if (dart.library.io) 'upload_helper_io.dart' as platform;

/// Firebase Storage'a bytes yükle.
/// Web'de putData, mobilde (iOS/Android) putFile kullanır.
/// iOS'taki cancelFetcher / "Upload has already been finalized" hatasını önler.
/// Hata durumunda dosyanın yüklenip yüklenmediğini kontrol eder ve gerekirse tekrar dener.
Future<void> uploadToStorage(
  Reference ref,
  Uint8List bytes,
  SettableMetadata metadata,
) async {
  if (kIsWeb) {
    await ref.putData(bytes, metadata);
    return;
  }
  try {
    await platform.platformUploadBytes(ref, bytes, metadata);
  } catch (e) {
    // iOS cancelFetcher hatası: yükleme başarılı olmuş olabilir
    // getDownloadURL ile kontrol et
    try {
      await ref.getDownloadURL();
      return; // Dosya yüklendi, hatayı yoksay
    } catch (_) {
      // Dosya gerçekten yüklenemedi, bir kez daha dene
      await platform.platformUploadBytes(ref, bytes, metadata);
    }
  }
}
