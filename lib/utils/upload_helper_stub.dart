import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';

Future<void> platformUploadBytes(
  Reference ref,
  Uint8List bytes,
  SettableMetadata metadata,
) {
  throw UnsupportedError('Mobile upload not supported on this platform');
}
