export 'pdf_viewer_stub.dart'
	if (dart.library.html) 'pdf_viewer_web.dart'
	if (dart.library.io) 'pdf_viewer_mobile.dart';
