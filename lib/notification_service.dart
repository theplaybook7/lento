import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:developer' as developer;
import 'project_core.dart';

class BildirimServisi {
  
  static Future<void> bildirimGonder({
    required String baslik,
    required String mesaj,
    required String projeId,
    String? modul,
    String? hedefEmail, // sadece bu kullanıcıya gösterilsin (görev atama vb.)
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
        'hedefEmail': hedefEmail,
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
    // Hedef kullanıcı belirtilmişse sadece o kullanıcıya göster
    final hedefEmail = bildirim['hedefEmail'] as String?;
    if (hedefEmail != null && hedefEmail.isNotEmpty) {
      final me = SistemYoneticisi().girisYapanEmail?.trim().toLowerCase() ?? '';
      return hedefEmail.trim().toLowerCase() == me;
    }
    final modul = bildirim['modul'] as String?;
    if (modul == null || modul.isEmpty) return true; // modül yoksa herkese göster
    return SistemYoneticisi().yetkiVarMi(modul);
  }

  /// Public wrapper - UI için yetki/hedef filtresi
  static bool yetkiliMi(Map<String, dynamic> bildirim) => _yetkisiVarMi(bildirim);

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

  /// Tüm bildirimleri sayfalı getir (okunmuş + okunmamış)
  static Future<QuerySnapshot> tumBildirimleriGetir({
    DocumentSnapshot? sonDoc,
    int limit = 30,
  }) async {
    if (SistemYoneticisi().aktifSirket == null) {
      return await FirebaseFirestore.instance
          .collection('_bos_')
          .limit(0)
          .get();
    }

    var query = FirebaseFirestore.instance
        .collection('sirketler')
        .doc(SistemYoneticisi().aktifSirket!.id)
        .collection('bildirimler')
        .orderBy('tarih', descending: true)
        .limit(limit);

    if (sonDoc != null) {
      query = query.startAfterDocument(sonDoc);
    }

    return query.get();
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

  /// Tüm okunmamış bildirimleri okundu olarak işaretler
  static Future<void> tumunuOkunduIsaretle(List<QueryDocumentSnapshot> okunmamislar) async {
    final email = SistemYoneticisi().girisYapanEmail;
    final sirketId = SistemYoneticisi().aktifSirket?.id;
    if (email == null || sirketId == null) return;
    
    final batch = FirebaseFirestore.instance.batch();
    for (final doc in okunmamislar) {
      batch.update(
        FirebaseFirestore.instance
            .collection('sirketler').doc(sirketId)
            .collection('bildirimler').doc(doc.id),
        {'okuyanlar': FieldValue.arrayUnion([email])},
      );
    }
    await batch.commit();
  }
}