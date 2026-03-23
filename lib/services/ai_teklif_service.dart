import 'package:intl/intl.dart';
import 'tcmb_service.dart';

class AiTeklifService {
  final TcmbService _tcmb = TcmbService();

  /// İnşaat süresini hesaplar
  int insaatSuresiHesapla(double toplamM2) {
    return TcmbService.insaatSuresiHesapla(toplamM2);
  }

  /// Enflasyon projeksiyonu yapar (senkron, API yok)
  Map<String, dynamic> enflasyonProjeksiyonu({
    required double guncelMaliyet,
    required double toplamM2,
  }) {
    final sure = insaatSuresiHesapla(toplamM2);
    return _tcmb.maliyetProjeksiyonu(
      guncelMaliyet: guncelMaliyet,
      aySayisi: sure,
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
    final projeksiyon = enflasyonProjeksiyonu(
      guncelMaliyet: guncelM2Maliyet,
      toplamM2: toplamInsaatM2,
    );

    final enflasyonluMaliyet = projeksiyon['ortalamaMaliyet'] as double;
    final karliM2Fiyat = enflasyonluMaliyet * (1 + karOrani / 100);
    final insaatSuresi = projeksiyon['aySayisi'] as int;
    final yillikEnflasyon = projeksiyon['yillikEnflasyon'] as double;

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
      'enflasyonluM2Maliyet': enflasyonluMaliyet,
      'karliM2Fiyat': karliM2Fiyat,
      'karOrani': karOrani,
      'insaatSuresi': insaatSuresi,
      'yillikEnflasyon': yillikEnflasyon,
      'toplamInsaatM2': toplamInsaatM2,
      'toplamMaliyet': toplamInsaatM2 * karliM2Fiyat,
      'daireler': daireDetaylari,
      'hibeTutari': hibeTutari,
      'krediTutari': krediTutari,
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
    required int insaatSuresi,
  }) {
    final projeksiyon = enflasyonProjeksiyonu(
      guncelMaliyet: guncelM2Maliyet,
      toplamM2: toplamInsaatM2,
    );

    final enflasyonluMaliyet = projeksiyon['ortalamaMaliyet'] as double;
    final karliM2Fiyat = enflasyonluMaliyet * (1 + karOrani / 100);
    final yillikEnflasyon = projeksiyon['yillikEnflasyon'] as double;
    final toplamMaliyet = toplamInsaatM2 * karliM2Fiyat;

    double muteahhitSatisGeliri = 0;
    final muteahhitDaireleri = <Map<String, dynamic>>[];
    final malSahibiDaireleri = <Map<String, dynamic>>[];
    double malSahibiToplamM2 = 0;

    for (final daire in daireler) {
      final sahip = daire['sahip'] as String? ?? 'malSahibi';
      final m2 = (daire['m2'] as num).toDouble();
      final kat = daire['kat'] as int? ?? 1;
      final tip = daire['tip'] as String? ?? 'Daire';

      if (sahip == 'muteahhit') {
        final satisFiyati = TcmbService.daireSatisFiyatiTahminEt(
          il: il,
          m2: m2,
          kat: kat,
          insaatSuresi: insaatSuresi,
          tip: tip,
        );
        muteahhitSatisGeliri += satisFiyati;
        muteahhitDaireleri.add({
          ...daire,
          'tahminiSatisFiyati': satisFiyati,
          'tahminiM2Fiyat': (satisFiyati / m2).round(),
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
      'enflasyonluM2Maliyet': enflasyonluMaliyet,
      'karliM2Fiyat': karliM2Fiyat,
      'karOrani': karOrani,
      'insaatSuresi': insaatSuresi,
      'yillikEnflasyon': yillikEnflasyon,
      'toplamInsaatM2': toplamInsaatM2,
      'toplamMaliyet': toplamMaliyet,
      'muteahhitDaireleri': muteahhitDaireleri,
      'muteahhitSatisGeliri': muteahhitSatisGeliri,
      'kalanMaliyet': kalanMaliyetPozitif,
      'malSahibiDaireleri': daireDetaylari,
      'hibeTutari': hibeTutari,
      'krediTutari': krediTutari,
    };
  }

  /// Teklif özet raporu oluşturur (yerleşik — API yok)
  String teklifOzetiOlustur(Map<String, dynamic> hesapSonucu) {
    final f = NumberFormat('#,###', 'tr_TR');
    final senaryo = hesapSonucu['senaryo'] as int;
    final insaatSuresi = hesapSonucu['insaatSuresi'];
    final yillikEnflasyon = (hesapSonucu['yillikEnflasyon'] as double).toStringAsFixed(1);
    final guncelM2 = f.format((hesapSonucu['guncelM2Maliyet'] as double).round());
    final enflasyonluM2 = f.format((hesapSonucu['enflasyonluM2Maliyet'] as double).round());
    final karliM2 = f.format((hesapSonucu['karliM2Fiyat'] as double).round());
    final karOrani = hesapSonucu['karOrani'];
    final toplamM2 = f.format((hesapSonucu['toplamInsaatM2'] as double).round());
    final toplamMaliyet = f.format((hesapSonucu['toplamMaliyet'] as double).round());

    final sb = StringBuffer();

    sb.writeln('İnşaat Teklif Analiz Raporu');
    sb.writeln('══════════════════════════════════');
    sb.writeln();
    sb.writeln('Bu analiz, TÜİK/TCMB İnşaat Maliyet Endeksine dayalı yerleşik veriler '
        'kullanılarak hazırlanmıştır. Toplam $toplamM2 m² inşaat alanı için tahmini '
        'inşaat süresi $insaatSuresi ay olarak hesaplanmıştır.');
    sb.writeln();
    sb.writeln('Güncel m² imalat maliyeti $guncelM2 ₺ olup, yıllık %$yillikEnflasyon '
        'inşaat enflasyonu dikkate alındığında, inşaat süresince ortalama m² maliyetin '
        '$enflasyonluM2 ₺ seviyesine ulaşması öngörülmektedir. %$karOrani kar oranı '
        'eklenmesiyle kar dahil m² fiyat $karliM2 ₺ olarak belirlenmiştir.');
    sb.writeln();

    if (senaryo == 1) {
      sb.writeln('Senaryo 1 (Müteahhit Daire Almıyor): Toplam inşaat maliyeti '
          '$toplamMaliyet ₺ olarak hesaplanmış olup, bu tutar mal sahibi daireleri '
          'arasında metrekare oranlarına göre paylaştırılmıştır. Hibe ve kredi '
          'imkanları olan dairelerde bu tutarlar net ödemeden düşülmüştür.');
    } else {
      final mutSatis = f.format((hesapSonucu['muteahhitSatisGeliri'] as double).round());
      final kalan = f.format((hesapSonucu['kalanMaliyet'] as double).round());
      final mutDaireler = hesapSonucu['muteahhitDaireleri'] as List;
      final malDaireler = hesapSonucu['malSahibiDaireleri'] as List;

      sb.writeln('Senaryo 2 (Müteahhit Daire Alıyor): Müteahhite ${mutDaireler.length} '
          'daire tahsis edilmiş olup, bu dairelerin tahmini toplam satış geliri '
          '$mutSatis ₺ olarak hesaplanmıştır. Toplam inşaat maliyeti $toplamMaliyet ₺\'den '
          'müteahhit daire satış geliri düşüldüğünde, mal sahiplerine kalan maliyet '
          '$kalan ₺\'dir. Bu tutar ${malDaireler.length} mal sahibi dairesi arasında '
          'm² oranlarına göre paylaştırılmıştır.');
    }

    sb.writeln();
    sb.writeln('⚠️ Not: Bu hesaplamalar tahmini değerlerdir. Gerçek maliyetler piyasa '
        'koşullarına, malzeme fiyatlarına ve işçilik ücretlerine göre değişiklik '
        'gösterebilir. Daire satış fiyat tahminleri il bazlı ortalama verilere '
        'dayalı olup, gerçek fiyatlar konum, bina kalitesi ve piyasa koşullarına '
        'göre farklılık gösterebilir.');

    return sb.toString();
  }
}
