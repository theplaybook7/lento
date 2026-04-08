import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import 'upload_helper_stub.dart'
    if (dart.library.io) 'upload_helper_io.dart' as platform;

/// Firebase Storage'a bytes yükle.
/// Web'de putData, mobilde (iOS/Android) putFile kullanır.
/// iOS'taki cancelFetcher / "Upload has already been finalized" hatasını önler.
Future<TaskSnapshot> uploadToStorage(
  Reference ref,
  Uint8List bytes,
  SettableMetadata metadata,
) async {
  if (kIsWeb) {
    return await ref.putData(bytes, metadata);
  }
  return await platform.platformUploadBytes(ref, bytes, metadata);
}
