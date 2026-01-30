import 'dart:typed_data';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'package:flutter/widgets.dart';

Widget buildWebPreview({
  required Uint8List bytes,
  required bool isPdf,
  required String fileName,
}) {
  final mimeType = isPdf ? 'application/pdf' : 'image/png';
  final blob = html.Blob([bytes], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final viewId = 'preview-${DateTime.now().millisecondsSinceEpoch}';

  // ignore: undefined_prefixed_name
  ui_web.platformViewRegistry.registerViewFactory(
    viewId,
    (int viewIdInt) {
      final iframe = html.IFrameElement()
        ..src = url
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%';
      return iframe;
    },
  );

  return HtmlElementView(viewType: viewId);
}

Future<void> downloadFile(String url, String fileName) async {
  final anchor = html.AnchorElement(href: url)
    ..setAttribute('download', fileName)
    ..style.display = 'none';

  html.document.body?.children.add(anchor);
  anchor.click();

  await Future.delayed(const Duration(milliseconds: 100));
  html.document.body?.children.remove(anchor);
}

Future<void> downloadImage(String url, {String? fileName}) async {
  final anchor = html.AnchorElement(href: url)
    ..setAttribute('download', fileName ?? 'image.jpg')
    ..style.display = 'none';

  html.document.body?.children.add(anchor);
  anchor.click();

  await Future.delayed(const Duration(milliseconds: 100));
  html.document.body?.children.remove(anchor);
}
