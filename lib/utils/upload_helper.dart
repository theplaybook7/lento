import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:http/http.dart' as http;

bool get _isApplePlatform =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.iOS ||
     defaultTargetPlatform == TargetPlatform.macOS);

/// Firebase Storage'a bytes yükle ve download URL döndür.
/// iOS/macOS: native SDK 412 hatası veriyor, REST API ile bypass.
/// Web/Android: normal putData + getDownloadURL.
Future<String> uploadToStorage(
  Reference ref,
  Uint8List bytes,
  SettableMetadata metadata,
) async {
  if (_isApplePlatform) {
    return _uploadViaRestApi(ref, bytes, metadata);
  }
  await ref.putData(bytes, metadata);
  return await ref.getDownloadURL();
}

/// Firebase Storage REST API ile upload + download URL döndür.
Future<String> _uploadViaRestApi(
  Reference ref,
  Uint8List bytes,
  SettableMetadata metadata,
) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) throw Exception('Kullanıcı giriş yapmamış');

  final token = await user.getIdToken();
  final bucket = ref.storage.bucket;
  final encodedPath = Uri.encodeComponent(ref.fullPath);

  final uploadUrl = Uri.parse(
    'https://firebasestorage.googleapis.com/v0/b/$bucket/o'
    '?uploadType=media&name=$encodedPath',
  );

  final response = await http.post(
    uploadUrl,
    headers: {
      'Authorization': 'Firebase $token',
      'Content-Type': metadata.contentType ?? 'application/octet-stream',
    },
    body: bytes,
  );

  if (response.statusCode != 200) {
    throw Exception('Upload failed (${response.statusCode}): ${response.body}');
  }

  final json = jsonDecode(response.body) as Map<String, dynamic>;
  final downloadToken = json['downloadTokens'] as String;

  return 'https://firebasestorage.googleapis.com/v0/b/$bucket/o/$encodedPath?alt=media&token=$downloadToken';
}
