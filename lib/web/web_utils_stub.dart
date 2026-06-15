import 'dart:typed_data';
import 'package:flutter/widgets.dart';

Widget buildWebPreview({
  required Uint8List bytes,
  required bool isPdf,
  required String fileName,
}) {
  return const SizedBox.shrink();
}

Widget buildWebPreviewFromUrl({
  required String url,
  required bool isPdf,
  required String fileName,
}) {
  return const SizedBox.shrink();
}

Future<void> downloadFile(String url, String fileName) async {}

Future<void> downloadImage(String url, {String? fileName}) async {}
