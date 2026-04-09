import 'dart:async';
import 'dart:typed_data';
import 'dart:developer' as developer;
import 'package:firebase_storage/firebase_storage.dart';

/// Firebase Storage'a bytes yükle.
/// iOS'ta cancelFetcher hatasını bypass eder:
/// UploadTask'ın snapshotEvents stream'ini dinler,
/// TaskState.success geldiğinde tamamlar.
Future<void> uploadToStorage(
  Reference ref,
  Uint8List bytes,
  SettableMetadata metadata,
) async {
  final task = ref.putData(bytes, metadata);

  final completer = Completer<void>();

  late StreamSubscription<TaskSnapshot> subscription;
  subscription = task.snapshotEvents.listen(
    (snapshot) {
      if (snapshot.state == TaskState.success && !completer.isCompleted) {
        developer.log('Upload başarılı: ${ref.fullPath}', name: 'upload');
        completer.complete();
        subscription.cancel();
      } else if (snapshot.state == TaskState.error && !completer.isCompleted) {
        developer.log('Upload stream error: ${ref.fullPath}', name: 'upload');
        // Error state — ama cancelFetcher yüzünden olabilir, doğrula
        _verifyAndComplete(ref, completer);
        subscription.cancel();
      }
    },
    onError: (e) {
      developer.log('Upload onError: $e (${e.runtimeType})', name: 'upload');
      if (!completer.isCompleted) {
        _verifyAndComplete(ref, completer, fallbackError: e);
        subscription.cancel();
      }
    },
    onDone: () {
      if (!completer.isCompleted) {
        // Stream kapandı ama ne success ne error geldi — doğrula
        _verifyAndComplete(ref, completer);
      }
    },
  );

  // Ayrıca task'ın future'ını da dinle (success durumunda ilk tetiklenecek olan bu olabilir)
  task.then((_) {
    if (!completer.isCompleted) {
      developer.log('Upload future resolved: ${ref.fullPath}', name: 'upload');
      completer.complete();
      subscription.cancel();
    }
  }).catchError((e) {
    if (!completer.isCompleted) {
      developer.log('Upload future error: $e', name: 'upload');
      _verifyAndComplete(ref, completer, fallbackError: e);
      subscription.cancel();
    }
  });

  return completer.future;
}

/// Dosyanın gerçekten yüklenip yüklenmediğini doğrula
Future<void> _verifyAndComplete(
  Reference ref,
  Completer<void> completer, {
  Object? fallbackError,
}) async {
  try {
    await ref.getDownloadURL();
    developer.log('Upload doğrulandı (dosya mevcut): ${ref.fullPath}', name: 'upload');
    if (!completer.isCompleted) completer.complete();
  } catch (verifyError) {
    developer.log('Upload doğrulama başarısız: $verifyError', name: 'upload');
    if (!completer.isCompleted) {
      completer.completeError(fallbackError ?? verifyError);
    }
  }
}
