import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:developer' as developer;
import 'project_core.dart';

/// Audit Log Servisi - T?fm aktiviteleri kaydet
class AuditLogServisi {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Aktivite kaydet
  static Future<void> aktiviteKaydet({
    required String projeId,
    required String islem,
    required String detay,
    Map<String, dynamic>? extraData,
  }) async {
    try {
      final sistem = SistemYoneticisi();
      final email = sistem.girisYapanEmail ?? "Bilinmeyen";
      final sirketId = sistem.aktifSirket?.id ?? "unknown";

      await _firestore
          .collection('auditLog')
          .add({
        'projeId': projeId,
        'sirketId': sirketId,
        'email': email,
        'islem': islem,
        'detay': detay,
        'tarih': FieldValue.serverTimestamp(),
        if (extraData != null) ...extraData,
      });
    } catch (e) {
      developer.log("Audit log kaydı hatası: $e");
    }
  }

  /// Proje i?fin t?fm aktiviteleri getir
  static Stream<QuerySnapshot> getProjeAktiviteleri(String projeId) {
    return _firestore
        .collection('auditLog')
        .where('projeId', isEqualTo: projeId)
        .orderBy('tarih', descending: true)
        .limit(50)
        .snapshots();
  }

  /// ?.irket i?fin t?fm aktiviteleri getir
  static Stream<QuerySnapshot> getSirketAktiviteleri(String sirketId) {
    return _firestore
        .collection('auditLog')
        .where('sirketId', isEqualTo: sirketId)
        .orderBy('tarih', descending: true)
        .limit(100)
        .snapshots();
  }

  /// Kullan?"c?"n?"n aktivitelerini getir
  static Stream<QuerySnapshot> getKullaniciAktiviteleri(String email) {
    return _firestore
        .collection('auditLog')
        .where('email', isEqualTo: email)
        .orderBy('tarih', descending: true)
        .limit(50)
        .snapshots();
  }

  /// Aktivite log formatter
  static String formatAktivite(Map<String, dynamic> data) {
    final islem = data['islem'] ?? 'Bilinmeyen';
    final detay = data['detay'] ?? '';
    final email = data['email'] ?? 'Bilinmeyen';
    final ts = data['tarih'] as Timestamp?;
    final dt = ts?.toDate();
    final tarihStr = dt != null
      ? '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}'
      : 'Tarih bilinmiyor';

    return '$email ?? $islem - $detay ($tarihStr)';
  }
}