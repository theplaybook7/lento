import 'dart:typed_data';
import 'package:flutter/material.dart';

class PdfViewerWeb extends StatelessWidget {
  final Uint8List pdfBytes;
  final String filename;

  const PdfViewerWeb({
    super.key,
    required this.pdfBytes,
    required this.filename,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(filename),
      ),
      body: const Center(
        child: Text('PDF önizleme bu platformda desteklenmiyor.'),
      ),
    );
  }
}
