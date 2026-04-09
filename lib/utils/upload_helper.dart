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
    print('[UPLOAD] ✅ putData başarılı: ${ref.fullPath}');
  } catch (e) {
    print('[UPLOAD] ⚠️ putData hata: $e');
    // iOS cancelFetcher: "Upload has already been finalized" = dosya yüklendi.
    // Birkaç deneme ile doğrula.
    for (int i = 1; i <= 3; i++) {
      await Future.delayed(Duration(seconds: i));
      try {
        final url = await ref.getDownloadURL();
        print('[UPLOAD] ✅ Doğrulandı (deneme $i): $url');
        return; // Dosya yüklenmiş, hata değil
      } catch (verifyErr) {
        print('[UPLOAD] ⏳ Doğrulama $i başarısız: $verifyErr');
      }
    }
    print('[UPLOAD] ❌ Yükleme tamamen başarısız: ${ref.fullPath}');
    rethrow;
  }
}
