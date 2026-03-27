import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:developer' as developer;
import 'project_core.dart';

class BildirimServisi {
  
  static Future<void> bildirimGonder({
    required String baslik,
    required String mesaj,
    required String projeId,
    String? modul,
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
        'modul': modul,
        'tarih': FieldValue.serverTimestamp(),
        'okuyanlar': gonderenEmail == "Sistem" ? [] : [gonderenEmail]
      });
      
      developer.log('✅ Bildirim Firestore\'a kaydedildi: $baslik - $mesaj (Şirket: $sirketId, Modül: $modul)');
    } catch (e) {
      developer.log('❌ Bildirim gönderme hatası: $e');
    }
  }

  /// Kullanıcının yetkisi olan bildirimleri filtreler
  static bool _yetkisiVarMi(Map<String, dynamic> bildirim) {
    final modul = bildirim['modul'] as String?;
    if (modul == null || modul.isEmpty) return true; // modül yoksa herkese göster
    return SistemYoneticisi().yetkiVarMi(modul);
  }

  static Stream<QuerySnapshot> bildirimleriDinle() {
    if (SistemYoneticisi().aktifSirket == null) return const Stream.empty();
    
    return FirebaseFirestore.instance
        .collection('sirketler')
        .doc(SistemYoneticisi().aktifSirket!.id)
        .collection('bildirimler')
        .orderBy('tarih', descending: true)
        .limit(50)
        .snapshots();
  }

  /// Yetkiye göre filtrelenmiş okunmamış bildirimleri döndürür
  static List<QueryDocumentSnapshot> okunmamisBildirimler(QuerySnapshot snapshot) {
    final email = SistemYoneticisi().girisYapanEmail;
    return snapshot.docs.where((doc) {
      final b = doc.data() as Map<String, dynamic>;
      final okuyanlar = (b['okuyanlar'] as List?)?.cast<String>() ?? [];
      return !okuyanlar.contains(email) && _yetkisiVarMi(b);
    }).toList();
  }
}