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

  print('[UPLOAD] REST API başlıyor: ${ref.fullPath} (${bytes.length} bytes)');

  final token = await user.getIdToken();
  print('[UPLOAD] Token alındı: ${token != null ? "OK" : "NULL"}');

  final bucket = ref.storage.bucket;
  final encodedPath = Uri.encodeComponent(ref.fullPath);
  print('[UPLOAD] Bucket: $bucket');

  final uploadUrl = Uri.parse(
    'https://firebasestorage.googleapis.com/v0/b/$bucket/o'
    '?uploadType=media&name=$encodedPath',
  );
  print('[UPLOAD] URL: $uploadUrl');

  try {
    final response = await http.post(
      uploadUrl,
      headers: {
        'Authorization': 'Firebase $token',
        'Content-Type': metadata.contentType ?? 'application/octet-stream',
      },
      body: bytes,
    );

    print('[UPLOAD] Response: ${response.statusCode}');

    if (response.statusCode != 200) {
      print('[UPLOAD] ❌ Body: ${response.body.substring(0, response.body.length.clamp(0, 500))}');
      throw Exception('Upload failed (${response.statusCode}): ${response.body}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final downloadToken = json['downloadTokens'] as String;
    final url = 'https://firebasestorage.googleapis.com/v0/b/$bucket/o/$encodedPath?alt=media&token=$downloadToken';
    print('[UPLOAD] ✅ Başarılı: $url');
    return url;
  } catch (e) {
    print('[UPLOAD] ❌ Exception: $e');
    rethrow;
  }
}
