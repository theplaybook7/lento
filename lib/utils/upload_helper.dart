import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:http/http.dart' as http;

/// Firebase Storage'a bytes yükle.
/// iOS'ta native SDK 412/400 hataları veriyor; REST API ile bypass ediyoruz.
/// Web ve Android'de normal putData kullanılır.
Future<void> uploadToStorage(
  Reference ref,
  Uint8List bytes,
  SettableMetadata metadata,
) async {
  final useRestApi = !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
       defaultTargetPlatform == TargetPlatform.macOS);

  if (useRestApi) {
    await _uploadViaRestApi(ref, bytes, metadata);
  } else {
    await ref.putData(bytes, metadata);
    print('[UPLOAD] ✅ Başarılı: ${ref.fullPath}');
  }
}

/// Firebase Storage REST API ile doğrudan upload.
/// Native iOS SDK'yı tamamen bypass eder.
Future<void> _uploadViaRestApi(
  Reference ref,
  Uint8List bytes,
  SettableMetadata metadata,
) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) throw Exception('Kullanıcı giriş yapmamış');

  final token = await user.getIdToken();
  final bucket = ref.storage.bucket;
  final objectPath = ref.fullPath;

  // Firebase Storage v0 REST API — Firebase ID token ile çalışır
  final uploadUrl = Uri.parse(
    'https://firebasestorage.googleapis.com/v0/b/$bucket/o'
    '?name=${Uri.encodeComponent(objectPath)}'
    '&uploadType=media',
  );

  print('[UPLOAD] 📡 REST API ile yükleniyor: $objectPath (${bytes.length} bytes)');
  print('[UPLOAD] 📡 Bucket: $bucket');

  final response = await http.post(
    uploadUrl,
    headers: {
      'Authorization': 'Firebase $token',
      'Content-Type': metadata.contentType ?? 'application/octet-stream',
    },
    body: bytes,
  );

  if (response.statusCode == 200) {
    print('[UPLOAD] ✅ REST API başarılı: $objectPath');
  } else {
    print('[UPLOAD] ❌ REST API hata: ${response.statusCode} ${response.body}');
    throw Exception(
      'Upload failed: ${response.statusCode} ${response.reasonPhrase}',
    );
  }
}
