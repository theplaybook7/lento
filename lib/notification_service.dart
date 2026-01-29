import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:developer' as developer;
import 'project_core.dart';

class BildirimServisi {
  
  static Future<void> bildirimGonder({
    required String baslik,
    required String mesaj,
    required String projeId, 
  }) async {
    if (SistemYoneticisi().aktifSirket == null) {
      developer.log('⚠️ Bildirim gönderilemedi: Aktif şirket yok');
      return;
    }

    try {
      final sirketId = SistemYoneticisi().aktifSirket!.id;
      final gonderenEmail = SistemYoneticisi().girisYapanEmail ?? "Sistem";
      await FirebaseFirestore.instance
          .collection('sirketler')
          .doc(sirketId)
          .collection('bildirimler')
          .add({
        'baslik': baslik,
        'mesaj': mesaj,
        'projeId': projeId,
        'gonderen': gonderenEmail,
        'tarih': FieldValue.serverTimestamp(),
        'okuyanlar': gonderenEmail == "Sistem" ? [] : [gonderenEmail]
      });
      
      developer.log('✅ Bildirim Firestore\'a kaydedildi: $baslik - $mesaj (Şirket: $sirketId)');
    } catch (e) {
      developer.log('❌ Bildirim gönderme hatası: $e');
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