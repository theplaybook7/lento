import 'package:intl/intl.dart';
import 'tcmb_service.dart';
import 'emlak_data_service.dart';

/// AI Teklif Hesaplama Motoru
/// TCMB istatistiksel tahmin + Emlak piyasa verisi entegrasyonu
class AiTeklifService {
  final TcmbService _tcmb = TcmbService();

  /// TCMB verilerini güncellemeye çalışır
  Future<bool> verileriGuncelle() => _tcmb.verileriGuncelle();

  String get veriKaynagi => _tcmb.veriKaynagi;

  String? get tcmbHataMesaji => _tcmb.sonHataMesaji;

  int insaatSuresiHesapla(double toplamM2) =>
      TcmbService.insaatSuresiHesapla(toplamM2);

  /// Enflasyon projeksiyonu (detaylı — min/avg/max)
  Map<String, dynamic> enflasyonProjeksiyonu({
    required double guncelMaliyet,
    required double toplamM2,
  }) {
    final sure = insaatSuresiHesapla(toplamM2);
    return _tcmb.maliyetProjeksiyonuDetayli(
      guncelMaliyet: guncelMaliyet,
      aySayisi: sure,
    );
  }

  /// Min/Max m² fiyat önerisi
  Map<String, double> minMaxFiyatOnerisi({
    required double guncelMaliyet,
    required double toplamM2,
    required double karOrani,
  }) {
    final sure = insaatSuresiHesapla(toplamM2);
    return _tcmb.minMaxM2FiyatOnerisi(
      guncelMaliyet: guncelMaliyet,
      aySayisi: sure,
      karOrani: karOrani,
    );
  }

  /// Pazar analizi
  String pazarAnalizi({
    required String il,
    required String ilce,
    required String mahalle,
    required int insaatSuresi,
    required List<Map<String, dynamic>> daireler,
  }) {
    return EmlakDataService.pazarAnalizi(
      il: il,
      ilce: ilce,
      mahalle: mahalle,
      insaatSuresi: insaatSuresi,
      daireler: daireler,
    );
  }

  /// Senaryo 1: Müteahhit daire almıyor
  Map<String, dynamic> senaryo1Hesapla({
    required double guncelM2Maliyet,
    required double toplamInsaatM2,
    required double karOrani,
    required List<Map<String, dynamic>> daireler,
    required double hibeTutari,
    required double krediTutari,
  }) {
    final proj = enflasyonProjeksiyonu(
      guncelMaliyet: guncelM2Maliyet,
      toplamM2: toplamInsaatM2,
    );

    final ortMaliyet = proj['ortalamaMaliyet'] as double;
    final minMaliyet = proj['minMaliyet'] as double;
    final maxMaliyet = proj['maxMaliyet'] as double;

    final karliM2Fiyat = ortMaliyet * (1 + karOrani / 100);
    final insaatSuresi = proj['aySayisi'] as int;
    final yillikEnflasyon = proj['yillikEnflasyon'] as double;

    final daireDetaylari = <Map<String, dynamic>>[];
    for (final daire in daireler) {
      final m2 = (daire['m2'] as num).toDouble();
      final kat = daire['kat'] as int? ?? 1;
      final hibeVar = daire['hibeVar'] as bool? ?? false;
      final krediVar = daire['krediVar'] as bool? ?? false;
      final tip = daire['tip'] as String? ?? 'Daire';

      final daireMaliyeti = m2 * karliM2Fiyat;
      final hibeDusulmus = hibeVar ? (daireMaliyeti - hibeTutari) : daireMaliyeti;
      final krediDusulmus = krediVar ? (hibeDusulmus - krediTutari) : hibeDusulmus;
      final netOdeme = krediDusulmus < 0 ? 0.0 : krediDusulmus;

      daireDetaylari.add({
        'tip': tip,
        'm2': m2,
        'kat': kat,
        'brutMaliyet': daireMaliyeti,
        'hibeVar': hibeVar,
        'krediVar': krediVar,
        'hibeTutari': hibeVar ? hibeTutari : 0,
        'krediTutari': krediVar ? krediTutari : 0,
        'netOdeme': netOdeme,
      });
    }

    return {
      'senaryo': 1,
      'guncelM2Maliyet': guncelM2Maliyet,
      'enflasyonluM2Maliyet': ortMaliyet,
      'minM2Maliyet': minMaliyet,
      'maxM2Maliyet': maxMaliyet,
      'karliM2Fiyat': karliM2Fiyat,
      'minKarliM2': minMaliyet * (1 + karOrani / 100),
      'maxKarliM2': maxMaliyet * (1 + karOrani / 100),
      'karOrani': karOrani,
      'insaatSuresi': insaatSuresi,
      'yillikEnflasyon': yillikEnflasyon,
      'toplamInsaatM2': toplamInsaatM2,
      'toplamMaliyet': toplamInsaatM2 * karliM2Fiyat,
      'daireler': daireDetaylari,
      'hibeTutari': hibeTutari,
      'krediTutari': krediTutari,
      'veriKaynagi': _tcmb.veriKaynagi,
    };
  }

  /// Senaryo 2: Müteahhit daire alıyor
  Map<String, dynamic> senaryo2Hesapla({
    required double guncelM2Maliyet,
    required double toplamInsaatM2,
    required double karOrani,
    required List<Map<String, dynamic>> daireler,
    required double hibeTutari,
    required double krediTutari,
    required String il,
    required String ilce,
    required int insaatSuresi,
  }) {
    final proj = enflasyonProjeksiyonu(
      guncelMaliyet: guncelM2Maliyet,
      toplamM2: toplamInsaatM2,
    );

    final ortMaliyet = proj['ortalamaMaliyet'] as double;
    final minMaliyet = proj['minMaliyet'] as double;
    final maxMaliyet = proj['maxMaliyet'] as double;
    final karliM2Fiyat = ortMaliyet * (1 + karOrani / 100);
    final yillikEnflasyon = proj['yillikEnflasyon'] as double;
    final toplamMaliyet = toplamInsaatM2 * karliM2Fiyat;

    double muteahhitSatisGeliri = 0;
    double muteahhitSatisMin = 0;
    double muteahhitSatisMax = 0;
    final muteahhitDaireleri = <Map<String, dynamic>>[];
    final malSahibiDaireleri = <Map<String, dynamic>>[];
    double malSahibiToplamM2 = 0;

    for (final daire in daireler) {
      final sahip = daire['sahip'] as String? ?? 'malSahibi';
      final m2 = (daire['m2'] as num).toDouble();
      final kat = daire['kat'] as int? ?? 1;
      final tip = daire['tip'] as String? ?? 'Daire';

      if (sahip == 'muteahhit') {
        // Emlak verisinden min/avg/max satış tahmini
        final tahmin = EmlakDataService.daireSatisTahmini(
          il: il,
          ilce: ilce,
          m2: m2,
          kat: kat,
          tip: tip,
          insaatSuresi: insaatSuresi,
        );

        final avgFiyat = tahmin['avgToplam']!;
        final minFiyat = tahmin['minToplam']!;
        final maxFiyat = tahmin['maxToplam']!;

        muteahhitSatisGeliri += avgFiyat;
        muteahhitSatisMin += minFiyat;
        muteahhitSatisMax += maxFiyat;

        muteahhitDaireleri.add({
          ...daire,
          'tahminiSatisFiyati': avgFiyat,
          'minSatisFiyati': minFiyat,
          'maxSatisFiyati': maxFiyat,
          'tahminiM2Fiyat': (avgFiyat / m2).round(),
          'minM2Fiyat': (minFiyat / m2).round(),
          'maxM2Fiyat': (maxFiyat / m2).round(),
          'katCarpani': tahmin['katCarpani'],
          'tipCarpani': tahmin['tipCarpani'],
        });
      } else {
        malSahibiToplamM2 += m2;
        malSahibiDaireleri.add(daire);
      }
    }

    final kalanMaliyet = toplamMaliyet - muteahhitSatisGeliri;
    final kalanMaliyetPozitif = kalanMaliyet < 0 ? 0.0 : kalanMaliyet;

    final daireDetaylari = <Map<String, dynamic>>[];
    for (final daire in malSahibiDaireleri) {
      final m2 = (daire['m2'] as num).toDouble();
      final kat = daire['kat'] as int? ?? 1;
      final hibeVar = daire['hibeVar'] as bool? ?? false;
      final krediVar = daire['krediVar'] as bool? ?? false;
      final tip = daire['tip'] as String? ?? 'Daire';

      final oran = malSahibiToplamM2 > 0 ? m2 / malSahibiToplamM2 : 0.0;
      final dairePayi = kalanMaliyetPozitif * oran;
      final hibeDusulmus = hibeVar ? (dairePayi - hibeTutari) : dairePayi;
      final krediDusulmus = krediVar ? (hibeDusulmus - krediTutari) : hibeDusulmus;
      final netOdeme = krediDusulmus < 0 ? 0.0 : krediDusulmus;

      daireDetaylari.add({
        'tip': tip,
        'm2': m2,
        'kat': kat,
        'brutMaliyet': dairePayi,
        'hibeVar': hibeVar,
        'krediVar': krediVar,
        'hibeTutari': hibeVar ? hibeTutari : 0,
        'krediTutari': krediVar ? krediTutari : 0,
        'netOdeme': netOdeme,
        'oran': oran * 100,
      });
    }

    return {
      'senaryo': 2,
      'guncelM2Maliyet': guncelM2Maliyet,
      'enflasyonluM2Maliyet': ortMaliyet,
      'minM2Maliyet': minMaliyet,
      'maxM2Maliyet': maxMaliyet,
      'karliM2Fiyat': karliM2Fiyat,
      'minKarliM2': minMaliyet * (1 + karOrani / 100),
      'maxKarliM2': maxMaliyet * (1 + karOrani / 100),
      'karOrani': karOrani,
      'insaatSuresi': insaatSuresi,
      'yillikEnflasyon': yillikEnflasyon,
      'toplamInsaatM2': toplamInsaatM2,
      'toplamMaliyet': toplamMaliyet,
      'muteahhitDaireleri': muteahhitDaireleri,
      'muteahhitSatisGeliri': muteahhitSatisGeliri,
      'muteahhitSatisMin': muteahhitSatisMin,
      'muteahhitSatisMax': muteahhitSatisMax,
      'kalanMaliyet': kalanMaliyetPozitif,
      'malSahibiDaireleri': daireDetaylari,
      'hibeTutari': hibeTutari,
      'krediTutari': krediTutari,
      'veriKaynagi': _tcmb.veriKaynagi,
    };
  }

  /// Teklif özet raporu oluşturur
  String teklifOzetiOlustur(Map<String, dynamic> hesapSonucu) {
    final f = NumberFormat('#,###', 'tr_TR');
    final senaryo = hesapSonucu['senaryo'] as int;
    final insaatSuresi = hesapSonucu['insaatSuresi'];
    final yillikEnflasyon = (hesapSonucu['yillikEnflasyon'] as double).toStringAsFixed(1);
    final guncelM2 = f.format((hesapSonucu['guncelM2Maliyet'] as double).round());
    final enflasyonluM2 = f.format((hesapSonucu['enflasyonluM2Maliyet'] as double).round());
    final karliM2 = f.format((hesapSonucu['karliM2Fiyat'] as double).round());
    final minKarliM2 = f.format((hesapSonucu['minKarliM2'] as double).round());
    final maxKarliM2 = f.format((hesapSonucu['maxKarliM2'] as double).round());
    final karOrani = hesapSonucu['karOrani'];
    final toplamM2 = f.format((hesapSonucu['toplamInsaatM2'] as double).round());
    final toplamMaliyet = f.format((hesapSonucu['toplamMaliyet'] as double).round());
    final kaynak = hesapSonucu['veriKaynagi'] ?? 'yerleşik';

    final sb = StringBuffer();

    sb.writeln('İnşaat Teklif Analiz Raporu');
    sb.writeln('══════════════════════════════════');
    sb.writeln();
    sb.writeln('Veri kaynağı: $kaynak');
    sb.writeln();
    sb.writeln('Toplam $toplamM2 m² inşaat alanı için tahmini inşaat süresi '
        '$insaatSuresi ay olarak hesaplanmıştır.');
    sb.writeln();
    sb.writeln('İstatistiksel Maliyet Tahmini:');
    sb.writeln('• Güncel m² imalat maliyeti: $guncelM2 ₺');
    sb.writeln('• Yıllık inşaat enflasyonu: %$yillikEnflasyon');
    sb.writeln('• İnşaat sonrası tahmini m² maliyet: $enflasyonluM2 ₺');
    sb.writeln('• %$karOrani kar oranıyla m² fiyat: $karliM2 ₺');
    sb.writeln('  (Aralık: $minKarliM2 ₺ — $maxKarliM2 ₺)');
    sb.writeln();

    if (senaryo == 1) {
      sb.writeln('Senaryo 1 (Müteahhit Daire Almıyor):');
      sb.writeln('Toplam inşaat maliyeti $toplamMaliyet ₺ olarak hesaplanmıştır. '
          'Bu tutar mal sahibi daireleri arasında m² oranlarına göre paylaştırılmıştır.');
    } else {
      final mutSatis = f.format((hesapSonucu['muteahhitSatisGeliri'] as double).round());
      final mutMin = f.format((hesapSonucu['muteahhitSatisMin'] as double).round());
      final mutMax = f.format((hesapSonucu['muteahhitSatisMax'] as double).round());
      final kalan = f.format((hesapSonucu['kalanMaliyet'] as double).round());
      final mutDaireler = hesapSonucu['muteahhitDaireleri'] as List;
      final malDaireler = hesapSonucu['malSahibiDaireleri'] as List;

      sb.writeln('Senaryo 2 (Müteahhit Daire Alıyor):');
      sb.writeln('• Müteahhite ${mutDaireler.length} daire tahsis edilmiştir.');
      sb.writeln('• Tahmini toplam satış geliri: $mutSatis ₺');
      sb.writeln('  (Aralık: $mutMin ₺ — $mutMax ₺)');
      sb.writeln('• Toplam inşaat maliyeti: $toplamMaliyet ₺');
      sb.writeln('• Müteahhit geliri düşüldükten sonra kalan: $kalan ₺');
      sb.writeln('• Bu tutar ${malDaireler.length} mal sahibi dairesine paylaştırılmıştır.');

      sb.writeln();
      sb.writeln('Müteahhit Daire Satış Tahminleri:');
      for (final d in mutDaireler) {
        final dTip = d['tip'] ?? 'Daire';
        final dM2 = d['m2'];
        final dKat = d['kat'];
        final dMin = f.format((d['minSatisFiyati'] as num).round());
        final dAvg = f.format((d['tahminiSatisFiyati'] as num).round());
        final dMax = f.format((d['maxSatisFiyati'] as num).round());
        sb.writeln('  $dTip ${dM2} m² (${dKat}. kat):');
        sb.writeln('    Min: $dMin ₺  |  Ort: $dAvg ₺  |  Max: $dMax ₺');
      }
    }

    sb.writeln();
    sb.writeln('⚠️ Bu hesaplamalar TCMB İnşaat Maliyet Endeksi tarihsel verilerine '
        'dayalı istatistiksel tahminlerdir. Gerçek maliyetler piyasa koşullarına '
        'göre değişiklik gösterebilir. Satış fiyatları ilçe bazlı pazar verilerine '
        'dayalıdır.');

    return sb.toString();
  }
}
