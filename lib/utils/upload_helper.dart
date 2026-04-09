import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';

/// Firebase Storage'a bytes yükle.
/// iOS'ta "Upload has already been finalized" (HTTP 400) hatası
/// dosyanın başarıyla yüklendiği anlamına gelir — SDK cleanup adımında
/// hata alıyor. Bu durumda getDownloadURL ile doğrulayıp hatayı yoksayıyoruz.
Future<void> uploadToStorage(
  Reference ref,
  Uint8List bytes,
  SettableMetadata metadata,
) async {
  try {
    await ref.putData(bytes, metadata);
  } catch (e) {
    // iOS cancelFetcher: "Upload has already been finalized" = dosya yüklendi.
    // Doğrula ve devam et.
    await Future.delayed(const Duration(seconds: 1));
    try {
      await ref.getDownloadURL();
      return; // Dosya yüklenmiş, hata değil
    } catch (_) {
      rethrow; // Gerçekten yüklenememiş
    }
  }
}
