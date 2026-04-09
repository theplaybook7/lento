import 'dart:async';
import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';

/// Firebase Storage'a bytes yükle.
/// iOS'ta cancelFetcher hatasını bypass eder.
Future<void> uploadToStorage(
  Reference ref,
  Uint8List bytes,
  SettableMetadata metadata,
) async {
  print('[UPLOAD] Başlıyor: ${ref.fullPath} (${bytes.length} bytes)');

  final task = ref.putData(bytes, metadata);

  final completer = Completer<void>();

  late StreamSubscription<TaskSnapshot> subscription;
  subscription = task.snapshotEvents.listen(
    (snapshot) {
      print('[UPLOAD] State: ${snapshot.state} (${ref.fullPath})');
      if (snapshot.state == TaskState.success && !completer.isCompleted) {
        print('[UPLOAD] ✅ Başarılı: ${ref.fullPath}');
        completer.complete();
        subscription.cancel();
      } else if (snapshot.state == TaskState.error && !completer.isCompleted) {
        print('[UPLOAD] ⚠️ Stream error, doğrulanıyor: ${ref.fullPath}');
        _verifyAndComplete(ref, completer);
        subscription.cancel();
      }
    },
    onError: (e) {
      print('[UPLOAD] ❌ onError: $e');
      if (!completer.isCompleted) {
        _verifyAndComplete(ref, completer, fallbackError: e);
        subscription.cancel();
      }
    },
    onDone: () {
      if (!completer.isCompleted) {
        print('[UPLOAD] Stream bitti, doğrulanıyor: ${ref.fullPath}');
        _verifyAndComplete(ref, completer);
      }
    },
  );

  task.then((_) {
    if (!completer.isCompleted) {
      print('[UPLOAD] ✅ Future resolved: ${ref.fullPath}');
      completer.complete();
      subscription.cancel();
    }
  }).catchError((e) {
    if (!completer.isCompleted) {
      print('[UPLOAD] ❌ Future error: $e');
      _verifyAndComplete(ref, completer, fallbackError: e);
      subscription.cancel();
    }
  });

  return completer.future;
}

Future<void> _verifyAndComplete(
  Reference ref,
  Completer<void> completer, {
  Object? fallbackError,
}) async {
  try {
    final url = await ref.getDownloadURL();
    print('[UPLOAD] ✅ Doğrulandı, dosya mevcut: $url');
    if (!completer.isCompleted) completer.complete();
  } catch (verifyError) {
    print('[UPLOAD] ❌ Doğrulama başarısız: $verifyError');
    if (!completer.isCompleted) {
      completer.completeError(fallbackError ?? verifyError);
    }
  }
}
