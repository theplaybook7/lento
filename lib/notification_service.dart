import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'dart:developer' as developer;
import 'project_core.dart';

class BildirimServisi {
  static const String modulRuhsat = 'ruhsat';
  static const String modulSantiye = 'santiye';
  static const String modulMuhasebe = 'muhasebe';
  static const String modulGorev = 'gorev';

  static const String tipInfo = 'info';
  static const String tipWarning = 'warning';
  static const String tipSuccess = 'success';

  static String _normalizeEmail(String? value) =>
      (value ?? '').trim().toLowerCase();

  static String _normalizeTip(String? value) {
    final t = (value ?? '').trim().toLowerCase();
    if (t == tipWarning || t == tipSuccess || t == tipInfo) return t;
    return tipInfo;
  }

  static String _tipFromBaslikMesaj(String baslik, String mesaj) {
    final text = '${baslik.toLowerCase()} ${mesaj.toLowerCase()}';
    if (text.contains('tamamlandı') ||
        text.contains('başar') ||
        text.contains('onaylandı') ||
        text.contains('completed')) {
      return tipSuccess;
    }
    if (text.contains('uyarı') ||
        text.contains('gecik') ||
        text.contains('hata') ||
        text.contains('pasif') ||
        text.contains('eksik') ||
        text.contains('risk')) {
      return tipWarning;
    }
    return tipInfo;
  }

  static String _tipFromModul(String modul) {
    switch (modul) {
      case modulRuhsat:
      case modulSantiye:
        return tipWarning;
      default:
        return tipInfo;
    }
  }

  static String _normalizeModul(String? modul) =>
      (modul ?? '').trim().toLowerCase();

  static String bildirimTipi(Map<String, dynamic> bildirim) {
    final rawTip = _normalizeTip(bildirim['tip'] as String?);
    if (rawTip != tipInfo || (bildirim['tip'] as String?)?.isNotEmpty == true) {
      return rawTip;
    }

    final modul = _normalizeModul(bildirim['modul'] as String?);
    if (modul.isNotEmpty) {
      return _tipFromModul(modul);
    }

    final baslik = (bildirim['baslik'] as String? ?? '').trim();
    final mesaj = (bildirim['mesaj'] as String? ?? '').trim();
    return _tipFromBaslikMesaj(baslik, mesaj);
  }

  static Color bildirimRenk(Map<String, dynamic> bildirim) {
    final modul = _normalizeModul(bildirim['modul'] as String?);
    switch (modul) {
      case modulRuhsat:
        return Colors.red;
      case modulSantiye:
        return Colors.orange;
      case modulMuhasebe:
        return Colors.blue;
      case modulGorev:
        return Colors.indigo;
      default:
        final tip = bildirimTipi(bildirim);
        if (tip == tipWarning) return Colors.deepOrange;
        if (tip == tipSuccess) return Colors.green;
        return Colors.teal;
    }
  }

  static IconData bildirimIkon(Map<String, dynamic> bildirim) {
    final modul = _normalizeModul(bildirim['modul'] as String?);
    switch (modul) {
      case modulRuhsat:
        return Icons.description_outlined;
      case modulSantiye:
        return Icons.construction;
      case modulMuhasebe:
        return Icons.account_balance_wallet;
      case modulGorev:
        return Icons.assignment_turned_in_outlined;
      default:
        final tip = bildirimTipi(bildirim);
        if (tip == tipWarning) return Icons.warning_amber_rounded;
        if (tip == tipSuccess) return Icons.check_circle_outline;
        return Icons.notifications_active;
    }
  }

  static bool _okuyanlarIcerir(List<dynamic> okuyanlar, String normalizedEmail) {
    if (normalizedEmail.isEmpty) return false;
    return okuyanlar.any((e) => _normalizeEmail(e.toString()) == normalizedEmail);
  }

  static bool okunduMu(
    Map<String, dynamic> bildirim, {
    required String? email,
    String? docId,
    Set<String>? localOkunanlar,
  }) {
    final normalized = _normalizeEmail(email);
    final okuyanlar = (bildirim['okuyanlar'] as List?)?.cast<dynamic>() ?? const [];
    final uzaktanOkunmus = _okuyanlarIcerir(okuyanlar, normalized);
    final yerelOkunmus = docId != null && (localOkunanlar?.contains(docId) ?? false);
    return uzaktanOkunmus || yerelOkunmus;
  }

  static Future<void> okunduIsaretleDoc(String docId) async {
    final normalizedEmail = _normalizeEmail(SistemYoneticisi().girisYapanEmail);
    final sirketId = SistemYoneticisi().aktifSirket?.id;
    if (normalizedEmail.isEmpty || sirketId == null || docId.isEmpty) return;

    await FirebaseFirestore.instance
        .collection('sirketler')
        .doc(sirketId)
        .collection('bildirimler')
        .doc(docId)
        .update({'okuyanlar': FieldValue.arrayUnion([normalizedEmail])});
  }
  
  static Future<void> bildirimGonder({
    required String baslik,
    required String mesaj,
    required String projeId,
    String? modul,
    String? hedefEmail, // sadece bu kullanıcıya gösterilsin (görev atama vb.)
    String? tip,
    int dedupeSeconds = 5,
  }) async {
    if (SistemYoneticisi().aktifSirket == null) {
      developer.log('⚠️ Bildirim gönderilemedi: Aktif şirket yok');
      return;
    }

    try {
      final sirketId = SistemYoneticisi().aktifSirket!.id;
      final gonderenEmail = _normalizeEmail(SistemYoneticisi().girisYapanEmail);
      final hedef = _normalizeEmail(hedefEmail);
      final normalizedModul = _normalizeModul(modul);
      final normalizedTip = _normalizeTip(
        tip ?? (normalizedModul.isNotEmpty ? _tipFromModul(normalizedModul) : _tipFromBaslikMesaj(baslik, mesaj)),
      );
      final normalizedGonderen = gonderenEmail.isEmpty ? 'sistem' : gonderenEmail;

      // Kısa süreli çift-tıklama/yeniden deneme kaynaklı tekrar bildirimleri bastır.
      if (dedupeSeconds > 0) {
        try {
          final latest = await FirebaseFirestore.instance
              .collection('sirketler')
              .doc(sirketId)
              .collection('bildirimler')
              .orderBy('tarih', descending: true)
              .limit(10)
              .get();

          final now = DateTime.now();
          final duplicate = latest.docs.any((doc) {
            final d = doc.data();
            final ts = d['tarih'] as Timestamp?;
            if (ts == null) return false;
            final age = now.difference(ts.toDate()).inSeconds;
            if (age < 0 || age > dedupeSeconds) return false;
            return (d['baslik'] == baslik) &&
                (d['mesaj'] == mesaj) &&
                (d['projeId'] == projeId) &&
                    ((d['modul'] ?? '') == normalizedModul) &&
                    ((d['tip'] ?? tipInfo) == normalizedTip) &&
                (_normalizeEmail(d['hedefEmail'] as String?) == hedef);
          });
          if (duplicate) {
            developer.log('ℹ️ Yinelenen bildirim bastırıldı: $baslik');
            return;
          }
        } catch (_) {
          // Dedupe kontrolü başarısız olsa bile bildirim gönderimi devam etsin.
        }
      }

      await FirebaseFirestore.instance
          .collection('sirketler')
          .doc(sirketId)
          .collection('bildirimler')
          .add({
        'baslik': baslik,
        'mesaj': mesaj,
        'projeId': projeId,
        'gonderen': normalizedGonderen,
        'modul': normalizedModul,
        'tip': normalizedTip,
        'hedefEmail': hedef,
        'tarih': FieldValue.serverTimestamp(),
        'okuyanlar': normalizedGonderen == 'sistem' ? [] : [normalizedGonderen]
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
      final me = _normalizeEmail(SistemYoneticisi().girisYapanEmail);
      return _normalizeEmail(hedefEmail) == me;
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
      return !okunduMu(b, email: email, docId: doc.id) && _yetkisiVarMi(b);
    }).toList();
  }

  /// Tüm okunmamış bildirimleri okundu olarak işaretler
  static Future<void> tumunuOkunduIsaretle(List<QueryDocumentSnapshot> okunmamislar) async {
    final email = _normalizeEmail(SistemYoneticisi().girisYapanEmail);
    final sirketId = SistemYoneticisi().aktifSirket?.id;
    if (email.isEmpty || sirketId == null || okunmamislar.isEmpty) return;
    
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