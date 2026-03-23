import 'dart:convert';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'tcmb_service.dart';

class AiTeklifService {
  static const String _geminiApiKey = 'AIzaSyCKiWnxhgb2xzby3RD7ZEGvRONphJTHsLs';
  late final GenerativeModel _model;
  final TcmbService _tcmb = TcmbService();

  AiTeklifService() {
    _model = GenerativeModel(
      model: 'gemini-2.0-flash',
      apiKey: _geminiApiKey,
      generationConfig: GenerationConfig(
        temperature: 0.3,
        maxOutputTokens: 4096,
      ),
    );
  }

  /// İnşaat süresini hesaplar
  int insaatSuresiHesapla(double toplamM2) {
    return TcmbService.insaatSuresiHesapla(toplamM2);
  }

  /// TCMB verisiyle enflasyon projeksiyonu yapar
  Future<Map<String, dynamic>> enflasyonProjeksiyonu({
    required double guncelMaliyet,
    required double toplamM2,
  }) async {
    final sure = insaatSuresiHesapla(toplamM2);
    return await _tcmb.maliyetProjeksiyonu(
      guncelMaliyet: guncelMaliyet,
      aySayisi: sure,
    );
  }

  /// Senaryo 1: Müteahhit daire almıyor
  /// Enflasyon + kar dahil m² fiyatı hesaplar
  Future<Map<String, dynamic>> senaryo1Hesapla({
    required double guncelM2Maliyet,
    required double toplamInsaatM2,
    required double karOrani, // yüzde olarak: 20 = %20
    required List<Map<String, dynamic>> daireler, // [{m2, kat, hibeVar, krediVar}]
    required double hibeTutari,
    required double krediTutari,
  }) async {
    final projeksiyon = await enflasyonProjeksiyonu(
      guncelMaliyet: guncelM2Maliyet,
      toplamM2: toplamInsaatM2,
    );

    final enflasyonluMaliyet = projeksiyon['ortalamaMaliyet'] as double;
    final karliM2Fiyat = enflasyonluMaliyet * (1 + karOrani / 100);
    final insaatSuresi = projeksiyon['aySayisi'] as int;
    final yillikEnflasyon = projeksiyon['yillikEnflasyon'] as double;

    // Her daire için maliyet hesapla
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
  Future<Map<String, dynamic>> senaryo2Hesapla({
    required double guncelM2Maliyet,
    required double toplamInsaatM2,
    required double karOrani,
    required List<Map<String, dynamic>> daireler, // [{m2, kat, sahip: 'muteahhit'/'malSahibi', hibeVar, krediVar, tip}]
    required double hibeTutari,
    required double krediTutari,
    required String konum, // il/ilçe/mahalle
    required Map<String, double> muteahhitDaireSatisFiyatlari, // daireIndex -> tahmini satış fiyatı
  }) async {
    final projeksiyon = await enflasyonProjeksiyonu(
      guncelMaliyet: guncelM2Maliyet,
      toplamM2: toplamInsaatM2,
    );

    final enflasyonluMaliyet = projeksiyon['ortalamaMaliyet'] as double;
    final karliM2Fiyat = enflasyonluMaliyet * (1 + karOrani / 100);
    final insaatSuresi = projeksiyon['aySayisi'] as int;
    final yillikEnflasyon = projeksiyon['yillikEnflasyon'] as double;
    final toplamMaliyet = toplamInsaatM2 * karliM2Fiyat;

    // Müteahhit dairelerinin satış geliri
    double muteahhitSatisGeliri = 0;
    final muteahhitDaireleri = <Map<String, dynamic>>[];
    final malSahibiDaireleri = <Map<String, dynamic>>[];
    double malSahibiToplamM2 = 0;

    for (int i = 0; i < daireler.length; i++) {
      final daire = daireler[i];
      final sahip = daire['sahip'] as String? ?? 'malSahibi';
      final m2 = (daire['m2'] as num).toDouble();

      if (sahip == 'muteahhit') {
        final satisFiyati = muteahhitDaireSatisFiyatlari[i.toString()] ?? 0;
        muteahhitSatisGeliri += satisFiyati;
        muteahhitDaireleri.add({
          ...daire,
          'tahminiSatisFiyati': satisFiyati,
        });
      } else {
        malSahibiToplamM2 += m2;
        malSahibiDaireleri.add(daire);
      }
    }

    // Kalan maliyet = toplam maliyet - müteahhit daire satış geliri
    final kalanMaliyet = toplamMaliyet - muteahhitSatisGeliri;
    final kalanMaliyetPozitif = kalanMaliyet < 0 ? 0.0 : kalanMaliyet;

    // Her mal sahibi dairesi için paylaşım
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

  /// Gemini ile daire satış fiyatı tahmini
  Future<Map<String, dynamic>> daireSatisFiyatiTahminEt({
    required String il,
    required String ilce,
    required String mahalle,
    required List<Map<String, dynamic>> daireler, // [{m2, kat, tip}]
    required int insaatSuresi, // ay
  }) async {
    final daireListesi = daireler.asMap().entries.map((e) {
      final d = e.value;
      return '${e.key + 1}. ${d['tip'] ?? 'Daire'} - ${d['m2']} m² - ${d['kat']}. kat';
    }).join('\n');

    final prompt = '''
Sen bir Türkiye emlak piyasası uzmanısın. Aşağıdaki bilgilere göre her dairenin 
$insaatSuresi ay sonraki tahmini satış fiyatını TL olarak belirle.

Konum: $il / $ilce / $mahalle
İnşaat teslim süresi: $insaatSuresi ay

Daireler:
$daireListesi

KURALLAR:
- Türkiye'deki güncel emlak piyasa fiyatlarını baz al
- Konum, m², kat faktörünü göz önüne al (üst katlar genelde daha değerli)
- $insaatSuresi ay sonraki fiyat artışını tahmin et
- Sadece JSON formatında yanıt ver, açıklama yazma

YANIT FORMATI (kesinlikle sadece bu JSON):
{
  "tahminler": [
    {"index": 0, "fiyat": 5000000, "m2Fiyat": 40000},
    {"index": 1, "fiyat": 4500000, "m2Fiyat": 38000}
  ],
  "aciklama": "Bölge ortalaması ve kat faktörüne göre hesaplandı"
}
''';

    try {
      final response = await _model.generateContent([Content.text(prompt)]);
      final text = response.text ?? '';

      // JSON'u çıkar
      final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(text);
      if (jsonMatch != null) {
        final parsed = json.decode(jsonMatch.group(0)!);
        return parsed as Map<String, dynamic>;
      }
    } catch (e) {
      // Gemini hatası
    }

    // Fallback: basit tahmin
    return {
      'tahminler': daireler.asMap().entries.map((e) {
        final m2 = (e.value['m2'] as num).toDouble();
        final kat = e.value['kat'] as int? ?? 1;
        final bazFiyat = 35000.0; // Varsayılan m² fiyat
        final katFaktoru = 1.0 + (kat * 0.02);
        final fiyat = m2 * bazFiyat * katFaktoru;
        return {'index': e.key, 'fiyat': fiyat.round(), 'm2Fiyat': (bazFiyat * katFaktoru).round()};
      }).toList(),
      'aciklama': 'TCMB verisi alınamadı, varsayılan değerler kullanıldı. Lütfen kontrol edin.',
    };
  }

  /// Tam AI teklif analizi - her iki senaryo için özet rapor
  Future<String> teklifOzetiOlustur(Map<String, dynamic> hesapSonucu) async {
    final senaryo = hesapSonucu['senaryo'];
    final prompt = '''
Aşağıdaki inşaat teklif hesaplama sonucunu Türkçe olarak özetleyecek kısa bir analiz yaz.
Müteahhite sunulacak şekilde profesyonel bir dille yaz. 3-4 paragraf olsun.

Hesap Sonucu:
${json.encode(hesapSonucu)}

Senaryo: ${senaryo == 1 ? 'Müteahhit daire almıyor, saf metrekare fiyatı' : 'Müteahhit daire alıyor'}

Önemli noktalar:
- Enflasyon projeksiyonunun TCMB İnşaat Maliyet Endeksine dayandığını belirt
- İnşaat süresinin toplam alana göre hesaplandığını belirt
- Verilerin tahmini olduğunu ve piyasa koşullarına göre değişebileceğini belirt
''';

    try {
      final response = await _model.generateContent([Content.text(prompt)]);
      return response.text ?? 'Özet oluşturulamadı.';
    } catch (e) {
      return 'AI özeti oluşturulurken hata oluştu. Hesap sonuçları tabloda mevcuttur.';
    }
  }
}
