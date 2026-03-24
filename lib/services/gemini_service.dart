import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'yerel_ai_service.dart';

/// Gemini AI Sohbet Servisi — İnşaat teklif analizi için doğal dil arayüzü.
/// API anahtarı --dart-define=GEMINI_API_KEY ile build-time'da veya
/// SharedPreferences üzerinden runtime'da sağlanır.
/// Gemini başarısız olursa yerleşik kural tabanlı AI devreye girer.
class GeminiService {
  static const String _apiKeyPrefKey = 'gemini_api_key';
  static const String _buildTimeKey = String.fromEnvironment('GEMINI_API_KEY');

  GenerativeModel? _model;
  ChatSession? _chat;
  bool _yerelMod = false;

  bool get hazir => _model != null || _yerelMod;
  bool get yerelModAktif => _yerelMod;

  // ── API Key yönetimi ──
  static Future<String?> getApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_apiKeyPrefKey);
    if (saved != null && saved.isNotEmpty) return saved;
    if (_buildTimeKey.isNotEmpty) return _buildTimeKey;
    return null;
  }

  static Future<void> setApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_apiKeyPrefKey, key);
  }

  /// Servisi başlat — API anahtarı yoksa yerleşik moda geçer
  Future<bool> baslat() async {
    final key = await getApiKey();
    if (key == null || key.isEmpty) {
      _yerelMod = true;
      return true; // Yerleşik modda çalışır
    }

    _model = GenerativeModel(
      model: 'gemini-2.0-flash',
      apiKey: key,
      systemInstruction: Content.text(_sistemTalimati),
    );
    _chat = _model!.startChat();
    _yerelMod = false;
    return true;
  }

  /// Sohbeti sıfırla
  void sifirla() {
    if (!_yerelMod) {
      _chat = _model?.startChat();
    }
  }

  /// Kullanıcı mesajı gönder, AI cevabını al
  /// Gemini başarısız olursa otomatik olarak yerleşik AI'ya geçer
  Future<String> mesajGonder(String mesaj) async {
    // Yerleşik mod aktifse doğrudan yerleşik AI'yı kullan
    if (_yerelMod) {
      return YerelAiService.mesajYanitla(mesaj);
    }

    if (_chat == null) {
      // Gemini yok ama yerleşik kullanılabilir
      _yerelMod = true;
      return YerelAiService.mesajYanitla(mesaj);
    }

    try {
      final response = await _chat!.sendMessage(Content.text(mesaj));
      return response.text ?? 'Yanıt alınamadı.';
    } on GenerativeAIException catch (e) {
      final msg = e.message.toLowerCase();
      if (msg.contains('quota') || msg.contains('rate') || msg.contains('limit') || msg.contains('429')) {
        // Kota doldu → yerleşik moda geç
        _yerelMod = true;
        final yerelCevap = YerelAiService.mesajYanitla(mesaj);
        return '⚠️ Gemini API kotası doldu — yerleşik AI moduna geçildi.\n\n$yerelCevap';
      }
      if (msg.contains('api key') || msg.contains('invalid') || msg.contains('permission')) {
        _yerelMod = true;
        final yerelCevap = YerelAiService.mesajYanitla(mesaj);
        return '⚠️ API anahtarı geçersiz — yerleşik AI moduna geçildi.\n\n$yerelCevap';
      }
      // Bilinmeyen hata → yerleşik
      _yerelMod = true;
      return YerelAiService.mesajYanitla(mesaj);
    } catch (e) {
      // Herhangi bir hata → yerleşik moda geç
      _yerelMod = true;
      final yerelCevap = YerelAiService.mesajYanitla(mesaj);
      return '⚠️ Bağlantı hatası — yerleşik AI moduna geçildi.\n\n$yerelCevap';
    }
  }

  /// Hesaplama sonuçlarını AI'ya yorumlatır
  Future<String> sonucYorumla(Map<String, dynamic> hesapSonucu) async {
    final mesaj = '''
Aşağıdaki inşaat teklif hesaplama sonuçlarını analiz et ve mal sahibine 
yönelik kısa, anlaşılır bir değerlendirme yaz.
Olumlu ve riskli noktaları belirt. Türkçe yaz.

Hesap sonuçları:
$hesapSonucu
''';
    return mesajGonder(mesaj);
  }

  static const String _sistemTalimati = '''
Sen "Lento" inşaat yönetim uygulamasının yapay zeka asistanısın.
Türkiye'de inşaat sektörü, müteahhitlik, kat karşılığı inşaat ve 
kentsel dönüşüm konularında uzmansın.

Görevlerin:
1. İnşaat teklif analizi yapmak — maliyet, kâr oranı, süre tahmini
2. Senaryo karşılaştırması — müteahhit daire alıyor vs almıyor
3. Hibe ve kredi hesaplamaları
4. Bölge pazar analizi — İstanbul ilçe/mahalle bazında
5. Sığınak, otopark gibi yasal gereklilikleri hatırlatmak
6. Mal sahibine ve müteahhite yönelik önerilerde bulunmak

Kurallar:
- Her zaman Türkçe yanıt ver
- Sayıları Türk formatında yaz (nokta binlik, virgül ondalık: 1.250.000,50 ₺)
- Karmaşık konuları basit anlatmaya çalış
- Kesin bilgi veremediğinde "yaklaşık" veya "tahmini" ifadeleri kullan
- Yasal tavsiye verme, "hukuki danışmanlık alın" de
- Kısa ve öz yanıtlar ver, gereksiz uzatma
''';
}
