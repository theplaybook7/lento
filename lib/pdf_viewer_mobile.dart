import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

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
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: () async {
              try {
                await Printing.sharePdf(
                  bytes: pdfBytes,
                  filename: filename,
                );
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Indirme hatasi: $e')),
                  );
                }
              }
            },
            tooltip: 'Indir',
          ),
        ],
      ),
      body: SfPdfViewer.memory(pdfBytes),
    );
  }
}
