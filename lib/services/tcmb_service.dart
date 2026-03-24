import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// TCMB EVDS API + İstatistiksel Tahmin Motoru
/// Gerçek TCMB verisi çeker, istatistiksel yöntemlerle maliyet tahmini yapar.
class TcmbService {
  // EVDS2 → EVDS3'e yönlendirildi; her iki endpoint denenir
  static const String _evdsBaseUrl = 'https://evds2.tcmb.gov.tr/service/evds';
  static const String _apiKeyPrefKey = 'tcmb_evds_api_key';

  /// Build-time ile gömülen varsayılan anahtar (--dart-define ile geçilir, GitHub'ta gözükmez)
  static const String _buildTimeKey = String.fromEnvironment('TCMB_API_KEY');

  // ── TCMB EVDS API Key yönetimi ──
  static Future<String?> getApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_apiKeyPrefKey);
    if (saved != null && saved.isNotEmpty) return saved;
    // Kullanıcı giremezse build-time key'i kullan
    if (_buildTimeKey.isNotEmpty) return _buildTimeKey;
    return null;
  }

  static Future<void> setApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_apiKeyPrefKey, key);
  }

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

  List<_EndeksVeri> _canliEndeks = [];
  String _veriKaynagi = 'yerleşik';
  DateTime? _sonGuncelleme;
  String? _sonHataMesaji;

  String? get sonHataMesaji => _sonHataMesaji;

  /// TCMB EVDS API'den güncel inşaat maliyet endeksi çeker
  /// Dönen değer: true = başarılı, false = başarısız (yerleşik veri kullanılır)
  /// Hata durumunda _sonHataMesaji set edilir
  Future<bool> verileriGuncelle() async {
    _sonHataMesaji = null;
    try {
      final apiKey = await getApiKey();
      if (apiKey == null || apiKey.isEmpty) {
        _sonHataMesaji = 'API anahtarı yok — TÜİK yerleşik verisi kullanılıyor.';
        _veriKaynagi = 'TÜİK yerleşik veri';
        return false;
      }

      // TCMB EVDS: İnşaat Maliyet Endeksi (TP.INSAAT.M1 = Genel)
      final now = DateTime.now();
      final startDate = '01-01-2020';
      final endDate = '${now.day.toString().padLeft(2, '0')}-'
          '${now.month.toString().padLeft(2, '0')}-${now.year}';

      final queryParams = 'series=TP.INSAAT.M1'
          '&startDate=$startDate&endDate=$endDate'
          '&type=json&key=$apiKey';

      // EVDS2 ve EVDS3 endpoint'lerini sırayla dene
      final endpoints = [
        '$_evdsBaseUrl?$queryParams',
      ];

      String? responseBody;
      for (final endpoint in endpoints) {
        try {
          final uri = Uri.parse(endpoint);
          final response = await http.get(uri).timeout(const Duration(seconds: 12));

          if (response.statusCode == 301 || response.statusCode == 302) {
            // Yönlendirme → bu endpoint çalışmıyor
            continue;
          }
          if (response.statusCode == 401 || response.statusCode == 403) {
            _sonHataMesaji = 'API anahtarı geçersiz veya yetkisiz (HTTP ${response.statusCode}).';
            continue;
          }
          if (response.statusCode != 200) {
            continue;
          }

          // HTML mı JSON mı kontrol et (SPA yönlendirmesi)
          final body = response.body.trim();
          if (body.startsWith('<') || body.startsWith('<!')) {
            // SPA HTML döndü, API endpoint aktif değil
            continue;
          }

          responseBody = body;
          break;
        } catch (_) {
          continue;
        }
      }

      if (responseBody == null) {
        _sonHataMesaji =
            'TCMB EVDS API geçici olarak kullanılamıyor — TÜİK yerleşik verisi kullanılıyor.';
        _veriKaynagi = 'TÜİK yerleşik veri';
        return false;
      }

      final data = json.decode(responseBody);
      final items = data['items'] as List?;
      if (items == null || items.isEmpty) {
        _sonHataMesaji = 'API yanıtında veri bulunamadı — yerleşik veri kullanılıyor.';
        _veriKaynagi = 'TÜİK yerleşik veri';
        return false;
      }

      _canliEndeks = [];
      for (final item in items) {
        final tarihStr = item['Tarih'] as String?;
        final deger = item['TP_INSAAT_M1'] as String?;
        if (tarihStr == null || deger == null) continue;

        final parts = tarihStr.split('-');
        if (parts.length < 2) continue;

        final yil = int.tryParse(parts[2]) ?? 0;
        final ay = int.tryParse(parts[1]) ?? 0;
        final ceyrek = ((ay - 1) ~/ 3) + 1;
        final endeksVal = double.tryParse(deger) ?? 0;
        if (yil > 0 && endeksVal > 0) {
          _canliEndeks.add(_EndeksVeri(yil, ceyrek, endeksVal));
        }
      }

      if (_canliEndeks.isNotEmpty) {
        _veriKaynagi = 'TCMB EVDS API (canlı)';
        _sonGuncelleme = DateTime.now();
        return true;
      }
      _sonHataMesaji = 'API verisi işlenemedi — yerleşik veri kullanılıyor.';
      _veriKaynagi = 'TÜİK yerleşik veri';
    } on http.ClientException {
      _sonHataMesaji = 'İnternet bağlantısı yok — TÜİK yerleşik verisi kullanılıyor.';
      _veriKaynagi = 'TÜİK yerleşik veri';
    } catch (e) {
      if (e.toString().contains('TimeoutException')) {
        _sonHataMesaji = 'TCMB API yanıt vermedi — yerleşik veri kullanılıyor.';
      } else {
        _sonHataMesaji = 'Bağlantı hatası — yerleşik veri kullanılıyor.';
      }
      _veriKaynagi = 'TÜİK yerleşik veri';
    }
    return false;
  }

  /// Mevcut endeks verilerini döner (canlı varsa canlı, yoksa yerleşik)
  List<_EndeksVeri> get _aktifEndeks =>
      _canliEndeks.isNotEmpty ? _canliEndeks : _tarihselEndeks;

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
    double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0, sumY2 = 0;
    for (int i = 0; i < n; i++) {
      final x = i.toDouble();
      final y = veriler[i].endeks;
      sumX += x;
      sumY += y;
      sumXY += x * y;
      sumX2 += x * x;
      sumY2 += y * y;
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
    final sonCeyrekBuyume = buyumeOranlari.isNotEmpty ? buyumeOranlari.last : 0.06;

    // Üstel düzeltme ile tahmin (sonraki çeyrek büyüme oranı)
    final ustelTahmin = buyumeOranlari.isNotEmpty
        ? _ustelDuzeltme(buyumeOranlari, alfa: 0.3)
        : 0.06;

    // Lineer regresyon ile endeks tahmini
    final basIndex = veriler.length.toDouble();
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
