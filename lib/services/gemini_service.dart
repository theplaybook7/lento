import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Gemini AI Sohbet Servisi — İnşaat teklif analizi için doğal dil arayüzü.
/// API anahtarı --dart-define=GEMINI_API_KEY ile build-time'da veya
/// SharedPreferences üzerinden runtime'da sağlanır.
class GeminiService {
  static const String _apiKeyPrefKey = 'gemini_api_key';
  static const String _buildTimeKey = String.fromEnvironment('GEMINI_API_KEY');

  GenerativeModel? _model;
  ChatSession? _chat;

  bool get hazir => _model != null;

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

  /// Servisi başlat — API anahtarı yoksa false döner
  Future<bool> baslat() async {
    final key = await getApiKey();
    if (key == null || key.isEmpty) return false;

    _model = GenerativeModel(
      model: 'gemini-2.0-flash',
      apiKey: key,
      systemInstruction: Content.text(_sistemTalimati),
    );
    _chat = _model!.startChat();
    return true;
  }

  /// Sohbeti sıfırla
  void sifirla() {
    _chat = _model?.startChat();
  }

  /// Kullanıcı mesajı gönder, AI cevabını al
  Future<String> mesajGonder(String mesaj) async {
    if (_chat == null) {
      return 'AI servisi başlatılmadı. Lütfen Gemini API anahtarını girin.';
    }

    try {
      final response = await _chat!.sendMessage(Content.text(mesaj));
      return response.text ?? 'Yanıt alınamadı.';
    } catch (e) {
      return 'AI hatası: $e';
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
