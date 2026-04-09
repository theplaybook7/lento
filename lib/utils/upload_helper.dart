import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';

/// Firebase Storage'a bytes yükle.
Future<void> uploadToStorage(
  Reference ref,
  Uint8List bytes,
  SettableMetadata metadata,
) async {
  await ref.putData(bytes, metadata);
}
