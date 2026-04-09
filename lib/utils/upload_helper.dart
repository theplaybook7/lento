import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';

/// Firebase Storage'a bytes yükle.
/// iOS'ta "Upload has already been finalized" hatası upload'un
/// aslında başarılı olduğu anlamına gelir. Bu durumda getDownloadURL
/// ile doğrular ve hatayı yoksayar.
Future<void> uploadToStorage(
  Reference ref,
  Uint8List bytes,
  SettableMetadata metadata,
) async {
  try {
    await ref.putData(bytes, metadata);
    print('[UPLOAD] ✅ Başarılı: ${ref.fullPath}');
  } catch (e) {
    print('[UPLOAD] ⚠️ putData hata: $e');
    // iOS cancelFetcher: "Upload has already been finalized" = dosya yüklendi ama
    // SDK finalization adımında hata aldı. 1 saniye bekleyip doğrula.
    await Future.delayed(const Duration(seconds: 2));
    try {
      final url = await ref.getDownloadURL();
      print('[UPLOAD] ✅ Doğrulandı (dosya yüklendi): $url');
      return; // Başarılı
    } catch (verifyError) {
      print('[UPLOAD] ❌ Doğrulama başarısız: $verifyError');
      // Dosya gerçekten yüklenmedi, orjinal hatayı fırlat
      throw e;
    }
  }
}
