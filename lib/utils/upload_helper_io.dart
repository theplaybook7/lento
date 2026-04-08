import 'dart:io';
import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';

Future<TaskSnapshot> platformUploadBytes(
  Reference ref,
  Uint8List bytes,
  SettableMetadata metadata,
) async {
  final tempFile = File(
    '${Directory.systemTemp.path}/fb_upload_${DateTime.now().millisecondsSinceEpoch}.tmp',
  );
  await tempFile.writeAsBytes(bytes);
  try {
    return await ref.putFile(tempFile, metadata);
  } finally {
    try {
      await tempFile.delete();
    } catch (_) {}
  }
}
