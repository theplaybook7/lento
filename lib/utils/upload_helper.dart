import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';

/// Firebase Storage'a bytes yükle.
/// Yükleme hatasında dosyanın yüklenip yüklenmediğini kontrol eder.
Future<void> uploadToStorage(
  Reference ref,
  Uint8List bytes,
  SettableMetadata metadata,
) async {
  try {
    await ref.putData(bytes, metadata);
  } catch (e) {
    // cancelFetcher hatası: yükleme başarılı olmuş olabilir
    try {
      await ref.getDownloadURL();
      return; // Dosya yüklendi, hatayı yoksay
    } catch (_) {
      rethrow; // Gerçek hata, yukarı ilet
    }
  }
}
