import 'dart:convert';
import 'package:http/http.dart' as http;

class TcmbService {
  static const String _apiKey = 'HwmQnhrbFH';
  static const String _baseUrl = 'https://evds2.tcmb.gov.tr/service/evds';

  /// İnşaat Maliyet Endeksi verilerini çeker (son N ay)
  /// Seri: TP.INSAATMALIYET2015.Q2 (İnşaat maliyet endeksi, yıllık değişim)
  Future<List<Map<String, dynamic>>> getInsaatMaliyetEndeksi({int sonKacAy = 36}) async {
    final now = DateTime.now();
    final baslangic = DateTime(now.year - (sonKacAy ~/ 12) - 1, now.month, 1);
    final startDate = '${_pad(baslangic.day)}-${_pad(baslangic.month)}-${baslangic.year}';
    final endDate = '${_pad(now.day)}-${_pad(now.month)}-${now.year}';

    // İnşaat maliyet endeksi serileri
    final seriler = [
      'TP.INSAATMALIYET2015.Q2', // Genel inşaat maliyet endeksi yıllık değişim
    ];

    try {
      final uri = Uri.parse('$_baseUrl/series=${seriler.join("-")}'
          '&startDate=$startDate&endDate=$endDate'
          '&type=json&key=$_apiKey&frequency=5');

      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['items'] != null) {
          return List<Map<String, dynamic>>.from(data['items']);
        }
      }
    } catch (e) {
      // API hatası durumunda fallback verileri kullanılacak
    }
    return [];
  }

  /// Son 3 yıllık inşaat maliyet endeksinden yıllık ortalama artış oranı hesaplar
  Future<double> getYillikInsaatEnflasyonu() async {
    final veriler = await getInsaatMaliyetEndeksi(sonKacAy: 36);

    if (veriler.isEmpty) {
      // Fallback: TCMB'den veri alınamazsa varsayılan %45
      return 45.0;
    }

    // Son 12 aylık verilerin ortalamasını al
    final son12 = veriler.length > 12 ? veriler.sublist(veriler.length - 12) : veriler;
    double toplam = 0;
    int sayac = 0;

    for (final veri in son12) {
      final deger = _parseValue(veri['TP_INSAATMALIYET2015_Q2']);
      if (deger != null) {
        toplam += deger;
        sayac++;
      }
    }

    if (sayac > 0) {
      return toplam / sayac;
    }

    return 45.0; // Fallback
  }

  /// Belirli bir süre sonrası için maliyet projeksiyonu yapar
  /// [guncelMaliyet]: Bugünkü m² maliyeti
  /// [aySayisi]: İnşaat süresi (ay)
  /// Dönen değer: Tahmini ortalama maliyet (süre boyunca)
  Future<Map<String, dynamic>> maliyetProjeksiyonu({
    required double guncelMaliyet,
    required int aySayisi,
  }) async {
    final yillikEnflasyon = await getYillikInsaatEnflasyonu();
    final aylikEnflasyon = yillikEnflasyon / 12;

    // İnşaat süresinin ortalamasını al (başlangıç ve bitiş maliyetinin ortası)
    final baslangicMaliyet = guncelMaliyet;
    final bitisMaliyet = guncelMaliyet * (1 + (yillikEnflasyon / 100) * (aySayisi / 12));
    final ortalamaMaliyet = (baslangicMaliyet + bitisMaliyet) / 2;

    return {
      'yillikEnflasyon': yillikEnflasyon,
      'aylikEnflasyon': aylikEnflasyon,
      'baslangicMaliyet': baslangicMaliyet,
      'bitisMaliyet': bitisMaliyet,
      'ortalamaMaliyet': ortalamaMaliyet,
      'aySayisi': aySayisi,
      'kaynak': 'TCMB İnşaat Maliyet Endeksi',
    };
  }

  /// İnşaat süresini metrekareye göre hesaplar
  static int insaatSuresiHesapla(double toplamM2) {
    if (toplamM2 <= 2000) return 18;
    final ekSure = ((toplamM2 - 2000) / 2000).ceil() * 6;
    return 18 + ekSure;
  }

  double? _parseValue(dynamic val) {
    if (val == null) return null;
    if (val is num) return val.toDouble();
    if (val is String) {
      return double.tryParse(val.replaceAll(',', '.'));
    }
    return null;
  }

  String _pad(int n) => n.toString().padLeft(2, '0');
}
