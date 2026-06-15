import 'dart:typed_data';
import 'dart:developer' as developer;
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:web/web.dart' as web;
import 'utils/error_handler.dart';

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
  late final String _viewType;
  static int _viewCounter = 0;

  @override
  void initState() {
    super.initState();
    _viewType = 'pdf-viewer-${_viewCounter++}';
    _createPdfBlob();
  }

  void _createPdfBlob() {
    try {
      final base64 = Uri.dataFromBytes(widget.pdfBytes, mimeType: 'application/pdf').toString();
      _iframeUrl = base64;
      
      // Register iframe view with unique name each time
      ui_web.platformViewRegistry.registerViewFactory(
        _viewType,
        (int viewId) {
          final iframe = web.HTMLIFrameElement()
            ..src = _iframeUrl!
            ..style.border = 'none'
            ..style.width = '100%'
            ..style.height = '100%';
          return iframe;
        },
      );
      
      setState(() {});
    } catch (e) {
      developer.log('PDF blob oluşturma hatası: $e', name: 'pdf_viewer_web');
    }
  }

  @override
  void dispose() {
    _iframeUrl = null;
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
                    SnackBar(content: Text(hataCevir(e))),
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
          : HtmlElementView(viewType: _viewType),
    );
  }
}
