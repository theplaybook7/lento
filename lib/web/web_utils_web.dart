import 'dart:typed_data';
import 'dart:ui_web' as ui_web;
import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

Widget buildWebPreview({
  required Uint8List bytes,
  required bool isPdf,
  required String fileName,
}) {
  final mimeType = isPdf ? 'application/pdf' : 'image/png';
  final url = Uri.dataFromBytes(bytes, mimeType: mimeType).toString();
  final viewId = 'preview-${DateTime.now().millisecondsSinceEpoch}';

  ui_web.platformViewRegistry.registerViewFactory(viewId, (int viewIdInt) {
    final iframe = web.HTMLIFrameElement()
      ..src = url
      ..style.border = 'none'
      ..style.width = '100%'
      ..style.height = '100%';
    return iframe;
  });

  return HtmlElementView(viewType: viewId);
}

Widget buildWebPreviewFromUrl({
  required String url,
  required bool isPdf,
  required String fileName,
}) {
  final viewId = 'preview-url-${DateTime.now().millisecondsSinceEpoch}';

  ui_web.platformViewRegistry.registerViewFactory(viewId, (int viewIdInt) {
    final iframe = web.HTMLIFrameElement()
      ..src = url
      ..style.border = 'none'
      ..style.width = '100%'
      ..style.height = '100%';
    return iframe;
  });

  return HtmlElementView(viewType: viewId);
}

Future<void> downloadFile(String url, String fileName) async {
  await _fetchAndDownload(url, fileName);
}

Future<void> downloadImage(String url, {String? fileName}) async {
  await _fetchAndDownload(url, fileName ?? 'image.jpg');
}

/// Cross-origin (Firebase Storage) URL'leri için: önce fetch ile bytes indir,
/// sonra blob URL üzerinden download anchor tetikle. Doğrudan `<a download href=...>`
/// yöntemi cross-origin'de çalışmaz; tarayıcı dosyayı yeni sekmede açar.
Future<void> _fetchAndDownload(String url, String fileName) async {
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = fileName
    ..target = '_blank'
    ..style.display = 'none';
  web.document.body?.append(anchor);
  anchor.click();
  web.document.body?.removeChild(anchor);
}
