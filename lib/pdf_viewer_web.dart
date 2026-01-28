import 'dart:typed_data';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

class PdfViewerWeb extends StatefulWidget {
  final Uint8List pdfBytes;
  final String filename;

  const PdfViewerWeb({
    super.key,
    required this.pdfBytes,
    required this.filename,
  });

  @override
  State<PdfViewerWeb> createState() => _PdfViewerWebState();
}

class _PdfViewerWebState extends State<PdfViewerWeb> {
  String? _iframeUrl;

  @override
  void initState() {
    super.initState();
    _createPdfBlob();
  }

  void _createPdfBlob() {
    try {
      final blob = html.Blob([widget.pdfBytes], 'application/pdf');
      _iframeUrl = html.Url.createObjectUrlFromBlob(blob);
      
      // Register iframe view
      ui_web.platformViewRegistry.registerViewFactory(
        'pdf-viewer-${widget.filename}',
        (int viewId) {
          final iframe = html.IFrameElement()
            ..src = _iframeUrl!
            ..style.border = 'none'
            ..style.width = '100%'
            ..style.height = '100%';
          return iframe;
        },
      );
      
      setState(() {});
    } catch (e) {
      print('PDF blob oluşturma hatası: $e');
    }
  }

  @override
  void dispose() {
    if (_iframeUrl != null) {
      html.Url.revokeObjectUrl(_iframeUrl!);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.filename),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: () async {
              try {
                await Printing.sharePdf(
                  bytes: widget.pdfBytes,
                  filename: widget.filename,
                );
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('İndirme hatası: $e')),
                  );
                }
              }
            },
            tooltip: 'İndir',
          ),
        ],
      ),
      body: _iframeUrl == null
          ? const Center(child: CircularProgressIndicator())
          : HtmlElementView(viewType: 'pdf-viewer-${widget.filename}'),
    );
  }
}
