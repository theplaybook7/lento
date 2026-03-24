import 'yerel_ai_service.dart';

/// Yerleşik AI Sohbet Servisi — İnşaat teklif analizi için kural tabanlı motor.
/// İnternet veya API anahtarı gerektirmeden çalışır.
class GeminiService {
  bool get hazir => true;
  bool get yerelModAktif => true;

  /// Servisi başlat — her zaman başarılı
  Future<bool> baslat() async => true;

  /// Sohbeti sıfırla
  void sifirla() {}

  /// Kullanıcı mesajı gönder, yerleşik AI'dan yanıt al
  Future<String> mesajGonder(String mesaj) async {
    return YerelAiService.mesajYanitla(mesaj);
  }
}
