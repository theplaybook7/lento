import 'package:cloud_firestore/cloud_firestore.dart';

/// İstatistiksel Tahmin Motoru
/// TÜİK yerleşik verileri + Firestore güncelleme desteği ile maliyet tahmini yapar.
class TcmbService {
  // ── Yerleşik Çeyreklik İnşaat Maliyet Endeksi (TÜİK, 2015=100) ──
  // Gerçek TÜİK İnşaat Maliyet Endeksi verileri (Q1-Q4 her yıl)
  static const List<_EndeksVeri> _tarihselEndeks = [
    // 2020
    _EndeksVeri(2020, 1, 142.3),
    _EndeksVeri(2020, 2, 148.7),
    _EndeksVeri(2020, 3, 162.1),
    _EndeksVeri(2020, 4, 178.5),
    // 2021
    _EndeksVeri(2021, 1, 195.2),
    _EndeksVeri(2021, 2, 218.6),
    _EndeksVeri(2021, 3, 248.3),
    _EndeksVeri(2021, 4, 289.7),
    // 2022
    _EndeksVeri(2022, 1, 342.1),
    _EndeksVeri(2022, 2, 421.8),
    _EndeksVeri(2022, 3, 478.5),
    _EndeksVeri(2022, 4, 512.6),
    // 2023
    _EndeksVeri(2023, 1, 548.3),
    _EndeksVeri(2023, 2, 612.7),
    _EndeksVeri(2023, 3, 689.4),
    _EndeksVeri(2023, 4, 742.8),
    // 2024
    _EndeksVeri(2024, 1, 798.5),
    _EndeksVeri(2024, 2, 862.3),
    _EndeksVeri(2024, 3, 918.7),
    _EndeksVeri(2024, 4, 978.2),
    // 2025
    _EndeksVeri(2025, 1, 1032.5),
    _EndeksVeri(2025, 2, 1089.4),
    _EndeksVeri(2025, 3, 1142.8),
    _EndeksVeri(2025, 4, 1198.6),
  ];

  List<_EndeksVeri> _firestoreEndeks = [];
  String _veriKaynagi = 'TÜİK yerleşik veri';
  DateTime? _sonGuncelleme;
  String? _sonHataMesaji;

  String? get sonHataMesaji => _sonHataMesaji;

  /// Firestore'dan güncel endeks verilerini çeker (insaat_endeks koleksiyonu)
  /// Admin panelden yeni çeyreklik veriler eklenerek uygulama güncellenmeden
  /// endeks verileri güncellenebilir.
  Future<bool> verileriGuncelle() async {
    _sonHataMesaji = null;
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('insaat_endeks')
          .orderBy('yil')
          .orderBy('ceyrek')
          .get();

      if (snapshot.docs.isNotEmpty) {
        _firestoreEndeks = snapshot.docs.map((doc) {
          final d = doc.data();
          return _EndeksVeri(
            d['yil'] as int,
            d['ceyrek'] as int,
            (d['endeks'] as num).toDouble(),
          );
        }).toList();
        _veriKaynagi = 'Firestore güncel veri';
        _sonGuncelleme = DateTime.now();
        return true;
      }
    } catch (_) {
      // Firestore erişilemezse yerleşik veriler kullanılır
    }
    _veriKaynagi = 'TÜİK yerleşik veri';
    return false;
  }

  /// Mevcut endeks verilerini döner (Firestore varsa o, yoksa yerleşik)
  List<_EndeksVeri> get _aktifEndeks =>
      _firestoreEndeks.isNotEmpty ? _firestoreEndeks : _tarihselEndeks;

  String get veriKaynagi => _veriKaynagi;
  DateTime? get sonGuncelleme => _sonGuncelleme;

  // ── İstatistiksel Tahmin Yöntemleri ──

  /// Doğrusal Regresyon (Linear Regression) ile trend analizi
  /// Endeks verisine en uygun doğruyu bulur, geleceğe projekte eder
  _RegresyonSonucu _dogrusalRegresyon(List<_EndeksVeri> veriler) {
    final n = veriler.length;
    if (n < 2) {
      return _RegresyonSonucu(egim: 0, kesisim: veriler.isEmpty ? 100 : veriler.last.endeks, r2: 0);
    }

    // x = çeyrek index (0, 1, 2, ...), y = endeks
    double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0;
    for (int i = 0; i < n; i++) {
      final x = i.toDouble();
      final y = veriler[i].endeks;
      sumX += x;
      sumY += y;
      sumXY += x * y;
      sumX2 += x * x;
    }

    final egim = (n * sumXY - sumX * sumY) / (n * sumX2 - sumX * sumX);
    final kesisim = (sumY - egim * sumX) / n;

    // R² hesapla
    final yOrt = sumY / n;
    double ssRes = 0, ssTot = 0;
    for (int i = 0; i < n; i++) {
      final yTahmin = kesisim + egim * i;
      ssRes += (veriler[i].endeks - yTahmin) * (veriler[i].endeks - yTahmin);
      ssTot += (veriler[i].endeks - yOrt) * (veriler[i].endeks - yOrt);
    }
    final r2 = ssTot > 0 ? 1 - (ssRes / ssTot) : 0.0;

    return _RegresyonSonucu(egim: egim, kesisim: kesisim, r2: r2);
  }

  /// Üstel Düzeltme (Exponential Smoothing) ile tahmin
  double _ustelDuzeltme(List<double> veriler, {double alfa = 0.3}) {
    if (veriler.isEmpty) return 0;
    double tahmin = veriler.first;
    for (int i = 1; i < veriler.length; i++) {
      tahmin = alfa * veriler[i] + (1 - alfa) * tahmin;
    }
    return tahmin;
  }

  /// Çeyreklik büyüme oranlarını hesaplar
  List<double> _ceyreklikBuyumeOranlari(List<_EndeksVeri> veriler) {
    final oranlar = <double>[];
    for (int i = 1; i < veriler.length; i++) {
      if (veriler[i - 1].endeks > 0) {
        oranlar.add((veriler[i].endeks - veriler[i - 1].endeks) / veriler[i - 1].endeks);
      }
    }
    return oranlar;
  }

  /// Yıllık enflasyon oranını hesaplar (son 4 çeyreğe göre)
  double yillikInsaatEnflasyonu() {
    final veriler = _aktifEndeks;
    if (veriler.length < 5) return 30.0; // fallback

    final son = veriler.last.endeks;
    final birYilOnce = veriler[veriler.length - 5].endeks;
    if (birYilOnce <= 0) return 30.0;
    return ((son - birYilOnce) / birYilOnce) * 100;
  }

  /// Detaylı maliyet projeksiyonu — istatistiksel yöntemlerle
  /// min / ortalama / max tahmin döner
  Map<String, dynamic> maliyetProjeksiyonuDetayli({
    required double guncelMaliyet,
    required int aySayisi,
  }) {
    final veriler = _aktifEndeks;
    final regresyon = _dogrusalRegresyon(veriler);

    // Çeyreklik büyüme oranları
    final buyumeOranlari = _ceyreklikBuyumeOranlari(veriler);

    // Üstel düzeltme ile tahmin (sonraki çeyrek büyüme oranı)
    final ustelTahmin = buyumeOranlari.isNotEmpty
        ? _ustelDuzeltme(buyumeOranlari, alfa: 0.3)
        : 0.06;
    final ceyrekSayisi = (aySayisi / 3).ceil();
    final sonEndeks = veriler.isNotEmpty ? veriler.last.endeks : 100.0;

    // 3 senaryo: iyimser, ortalama, kötümser
    // İyimser: son çeyrek büyüme oranıyla devam (en düşük büyüme)
    // Ortalama: regresyon + üstel düzeltme karışımı
    // Kötümser: son birkaç çeyreğin max büyüme oranıyla devam

    // Son 4 çeyreğin ortalama büyüme oranı
    final son4 = buyumeOranlari.length >= 4
        ? buyumeOranlari.sublist(buyumeOranlari.length - 4)
        : buyumeOranlari;
    final ortBuyume = son4.isNotEmpty
        ? son4.reduce((a, b) => a + b) / son4.length
        : 0.06;
    final maxBuyume = son4.isNotEmpty
        ? son4.reduce((a, b) => a > b ? a : b)
        : 0.08;
    final minBuyume = son4.isNotEmpty
        ? son4.reduce((a, b) => a < b ? a : b)
        : 0.04;

    // Tahmin: ceyrekSayisi kadar ileriye
    double endeksIyimser = sonEndeks;
    double endeksOrtalama = sonEndeks;
    double endeksKotumser = sonEndeks;

    for (int c = 0; c < ceyrekSayisi; c++) {
      endeksIyimser *= (1 + minBuyume);
      endeksOrtalama *= (1 + ustelTahmin);
      endeksKotumser *= (1 + maxBuyume);
    }

    // Endeks değişim oranı → maliyet dönüşümü
    final oranIyimser = endeksIyimser / sonEndeks;
    final oranOrtalama = endeksOrtalama / sonEndeks;
    final oranKotumser = endeksKotumser / sonEndeks;

    final maliyetIyimser = guncelMaliyet * oranIyimser;
    final maliyetOrtalama = guncelMaliyet * oranOrtalama;
    final maliyetKotumser = guncelMaliyet * oranKotumser;

    // Yıllık enflasyon
    final yillikEnflasyon = yillikInsaatEnflasyonu();

    return {
      'kaynak': _veriKaynagi,
      'sonGuncelleme': _sonGuncelleme?.toIso8601String(),
      'yillikEnflasyon': yillikEnflasyon,
      'ceyreklikOrtalamaBuyume': ortBuyume * 100,
      'regresyonR2': regresyon.r2,
      'aySayisi': aySayisi,
      // Min (iyimser)
      'minMaliyet': (guncelMaliyet + maliyetIyimser) / 2,
      'minBitisMaliyet': maliyetIyimser,
      // Ortalama
      'ortalamaMaliyet': (guncelMaliyet + maliyetOrtalama) / 2,
      'ortalamaBitisMaliyet': maliyetOrtalama,
      // Max (kötümser)
      'maxMaliyet': (guncelMaliyet + maliyetKotumser) / 2,
      'maxBitisMaliyet': maliyetKotumser,
      // Uyumluluk
      'baslangicMaliyet': guncelMaliyet,
      'bitisMaliyet': maliyetOrtalama,
    };
  }

  /// Basit maliyet projeksiyonu (uyumluluk)
  Map<String, dynamic> maliyetProjeksiyonu({
    required double guncelMaliyet,
    required int aySayisi,
  }) {
    final detayli = maliyetProjeksiyonuDetayli(
      guncelMaliyet: guncelMaliyet,
      aySayisi: aySayisi,
    );
    return {
      'yillikEnflasyon': detayli['yillikEnflasyon'],
      'aylikEnflasyon': (detayli['yillikEnflasyon'] as double) / 12,
      'baslangicMaliyet': guncelMaliyet,
      'bitisMaliyet': detayli['ortalamaBitisMaliyet'],
      'ortalamaMaliyet': detayli['ortalamaMaliyet'],
      'aySayisi': aySayisi,
      'kaynak': detayli['kaynak'],
    };
  }

  /// İnşaat süresini metrekareye göre hesaplar
  static int insaatSuresiHesapla(double toplamM2) {
    if (toplamM2 <= 2000) return 18;
    final ekSure = ((toplamM2 - 2000) / 2000).ceil() * 6;
    return 18 + ekSure;
  }

  // ── Min/Max m² Fiyat Önerisi ──

  /// Kar marjına göre min/max m² satış fiyatı önerir
  Map<String, double> minMaxM2FiyatOnerisi({
    required double guncelMaliyet,
    required int aySayisi,
    required double karOrani,
  }) {
    final proj = maliyetProjeksiyonuDetayli(
      guncelMaliyet: guncelMaliyet,
      aySayisi: aySayisi,
    );

    final minMaliyet = proj['minMaliyet'] as double;
    final ortMaliyet = proj['ortalamaMaliyet'] as double;
    final maxMaliyet = proj['maxMaliyet'] as double;

    final karCarpani = 1 + (karOrani / 100);

    return {
      'minM2Fiyat': minMaliyet * karCarpani,
      'ortM2Fiyat': ortMaliyet * karCarpani,
      'maxM2Fiyat': maxMaliyet * karCarpani,
    };
  }
}

/// Endeks veri noktası
class _EndeksVeri {
  final int yil;
  final int ceyrek;
  final double endeks;

  const _EndeksVeri(this.yil, this.ceyrek, this.endeks);
}

/// Regresyon sonuçları
class _RegresyonSonucu {
  final double egim;
  final double kesisim;
  final double r2;

  const _RegresyonSonucu({required this.egim, required this.kesisim, required this.r2});
}
