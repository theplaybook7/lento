import 'package:cloud_firestore/cloud_firestore.dart';
import 'project_core.dart';

class BildirimServisi {
  
  static Future<void> bildirimGonder({
    required String baslik,
    required String mesaj,
    required String projeId, 
  }) async {
    if (SistemYoneticisi().aktifSirket == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('sirketler')
          .doc(SistemYoneticisi().aktifSirket!.id)
          .collection('bildirimler')
          .add({
        'baslik': baslik,
        'mesaj': mesaj,
        'projeId': projeId,
        'gonderen': SistemYoneticisi().girisYapanEmail ?? "Sistem",
        'tarih': FieldValue.serverTimestamp(),
        'okuyanlar': [] 
      });
    } catch (e) {
      // Hata durumunda loglama
    }
  }

  static Stream<QuerySnapshot> bildirimleriDinle() {
    if (SistemYoneticisi().aktifSirket == null) return const Stream.empty();
    
    return FirebaseFirestore.instance
        .collection('sirketler')
        .doc(SistemYoneticisi().aktifSirket!.id)
        .collection('bildirimler')
        .orderBy('tarih', descending: true)
        .limit(20)
        .snapshots();
  }
}