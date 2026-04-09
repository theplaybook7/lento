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
    return;
  } catch (e) {
    print('[UPLOAD] ⚠️ putData hata: $e');
  }

  // putData hata verdi. iOS'ta bu genelde "Upload has already been finalized" (400)
  // veya plist çakışması (412) olabilir. Dosyanın yüklenip yüklenmediğini kontrol et.
  for (int attempt = 1; attempt <= 3; attempt++) {
    await Future.delayed(Duration(seconds: attempt * 2));
    try {
      final url = await ref.getDownloadURL();
      print('[UPLOAD] ✅ Doğrulandı (attempt $attempt): $url');
      return;
    } catch (_) {
      print('[UPLOAD] ⏳ Doğrulama attempt $attempt başarısız, tekrar deneniyor...');
    }
  }

  // Dosya yüklenmemiş. Varsa kısmı dosyayı silip sıfırdan yükle.
  print('[UPLOAD] 🔄 Tam yeniden yükleme: ${ref.fullPath}');
  try {
    await ref.delete();
  } catch (_) {}
  await ref.putData(bytes, metadata);
  print('[UPLOAD] ✅ Yeniden yükleme başarılı: ${ref.fullPath}');
}
