import 'dart:io';
import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';

Future<void> platformUploadBytes(
  Reference ref,
  Uint8List bytes,
  SettableMetadata metadata,
) async {
  final tempFile = File(
    '${Directory.systemTemp.path}/fb_upload_${DateTime.now().millisecondsSinceEpoch}.tmp',
  );
  await tempFile.writeAsBytes(bytes, flush: true);
  await ref.putFile(tempFile, metadata);
  // Dosyayı hemen silme — iOS SDK arka planda kullanıyor olabilir
  Future.delayed(const Duration(seconds: 10), () async {
    try {
      await tempFile.delete();
    } catch (_) {}
  });
}
