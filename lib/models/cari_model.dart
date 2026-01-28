import 'package:cloud_firestore/cloud_firestore.dart';

class CariHareket {
  final String id;
  final String tip; // borc, alacak
  final double tutar; // Orijinal tutar
  final double tutarTL; // TL karşılığı
  final String paraBirimi; // TL, USD, EUR, GBP, ALTIN
  final double kur;
  final String aciklama;
  final DateTime tarih;
  final List<String> fotoUrls; // Yeni: Fotoğraf URLleri
  final String? projeId;
  final String? projeAd;

  CariHareket({
    required this.id,
    required this.tip,
    required this.tutar,
    required this.tutarTL,
    required this.paraBirimi,
    required this.kur,
    required this.aciklama,
    required this.tarih,
    required this.fotoUrls,
    this.projeId,
    this.projeAd,
  });

  factory CariHareket.fromMap(String id, Map<String, dynamic> data) {
    return CariHareket(
      id: id,
      tip: data['tip'] ?? 'borc',
      tutar: ((data['tutar'] ?? 0.0) as num).toDouble(),
      tutarTL: ((data['tutarTL'] ?? 0.0) as num).toDouble(),
      paraBirimi: data['paraBirimi'] ?? 'TL',
      kur: ((data['kur'] ?? 1.0) as num).toDouble(),
      aciklama: data['aciklama'] ?? '',
      tarih: (data['tarih'] as Timestamp?)?.toDate() ?? DateTime.now(),
      fotoUrls: List<String>.from(data['fotoUrls'] ?? []),
      projeId: data['projeId'],
      projeAd: data['projeAd'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'tip': tip,
      'tutar': tutar,
      'tutarTL': tutarTL,
      'paraBirimi': paraBirimi,
      'kur': kur,
      'aciklama': aciklama,
      'tarih': Timestamp.fromDate(tarih),
      'fotoUrls': fotoUrls,
      'projeId': projeId,
      'projeAd': projeAd,
    };
  }
}
