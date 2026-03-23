/// Türkiye inşaat maliyet endeksi ve enflasyon hesaplama servisi.
/// TÜİK / TCMB verilerine dayalı yerleşik parametreler kullanır.
class TcmbService {
  // ── Yerleşik İnşaat Enflasyon Verileri (TÜİK İnşaat Maliyet Endeksi) ──
  // Her yıl/çeyrek ortalaması. Kullanıcı girişiyle birleştirilir.
  // Son güncelleme: 2025-Q4 verilerine göre.
  static const double _insaatEnflasyonu2023 = 42.0; // %42
  static const double _insaatEnflasyonu2024 = 35.0; // %35
  static const double _insaatEnflasyonu2025 = 30.0; // %30 (tahmin)
  static const double _varsayilanEnflasyon = 30.0;

  /// Son 3 yılın ağırlıklı ortalamasını hesaplar (yakın yıla daha çok ağırlık)
  double getYillikInsaatEnflasyonu() {
    // Ağırlıklar: en yakın yıl %50, bir önceki %30, iki önceki %20
    return (_insaatEnflasyonu2025 * 0.50) +
        (_insaatEnflasyonu2024 * 0.30) +
        (_insaatEnflasyonu2023 * 0.20);
    // = 30*0.5 + 35*0.3 + 42*0.2 = 15 + 10.5 + 8.4 = 33.9
  }

  /// Belirli bir süre sonrası için maliyet projeksiyonu yapar
  Map<String, dynamic> maliyetProjeksiyonu({
    required double guncelMaliyet,
    required int aySayisi,
  }) {
    final yillikEnflasyon = getYillikInsaatEnflasyonu();
    final aylikEnflasyon = yillikEnflasyon / 12;

    // İnşaat süresinin başlangıç ve bitiş maliyetini hesapla
    final baslangicMaliyet = guncelMaliyet;
    final bitisMaliyet =
        guncelMaliyet * (1 + (yillikEnflasyon / 100) * (aySayisi / 12));
    final ortalamaMaliyet = (baslangicMaliyet + bitisMaliyet) / 2;

    return {
      'yillikEnflasyon': yillikEnflasyon,
      'aylikEnflasyon': aylikEnflasyon,
      'baslangicMaliyet': baslangicMaliyet,
      'bitisMaliyet': bitisMaliyet,
      'ortalamaMaliyet': ortalamaMaliyet,
      'aySayisi': aySayisi,
      'kaynak': 'TÜİK/TCMB İnşaat Maliyet Endeksi (yerleşik veri)',
    };
  }

  /// İnşaat süresini metrekareye göre hesaplar
  static int insaatSuresiHesapla(double toplamM2) {
    if (toplamM2 <= 2000) return 18;
    final ekSure = ((toplamM2 - 2000) / 2000).ceil() * 6;
    return 18 + ekSure;
  }

  // ── Bölgesel m² Satış Fiyat Tahmini ──
  // İl bazında ortalama m² konut satış fiyatları (TL/m², 2025 tahmini)
  static const Map<String, double> _ilM2Fiyatlari = {
    'istanbul': 55000,
    'ankara': 28000,
    'izmir': 32000,
    'bursa': 25000,
    'antalya': 35000,
    'konya': 18000,
    'adana': 17000,
    'gaziantep': 18000,
    'kayseri': 16000,
    'mersin': 20000,
    'eskişehir': 20000,
    'diyarbakır': 14000,
    'samsun': 16000,
    'denizli': 17000,
    'muğla': 40000,
    'trabzon': 20000,
    'kocaeli': 26000,
    'sakarya': 22000,
    'tekirdağ': 22000,
    'manisa': 16000,
    'malatya': 13000,
    'erzurum': 14000,
    'van': 12000,
    'balıkesir': 18000,
    'elazığ': 14000,
    'sivas': 13000,
    'kahramanmaraş': 13000,
    'hatay': 14000,
    'mardin': 12000,
    'aydın': 22000,
    'çanakkale': 24000,
    'edirne': 18000,
    'ordu': 16000,
    'tokat': 12000,
    'yalova': 25000,
    'düzce': 16000,
    'bolu': 18000,
    'rize': 18000,
    'afyonkarahisar': 14000,
    'uşak': 14000,
    'kütahya': 13000,
    'çorum': 13000,
    'kastamonu': 12000,
    'aksaray': 13000,
    'niğde': 12000,
    'nevşehir': 14000,
    'kırşehir': 13000,
    'karaman': 13000,
    'batman': 12000,
    'şırnak': 11000,
    'ağrı': 10000,
    'iğdır': 10000,
    'bingöl': 11000,
    'bitlis': 10000,
    'hakkari': 10000,
    'muş': 10000,
    'siirt': 11000,
    'tunceli': 12000,
    'artvin': 15000,
    'giresun': 15000,
    'gümüşhane': 12000,
    'bayburt': 11000,
    'ardahan': 10000,
    'ıgdır': 10000,
    'kars': 10000,
    'bartın': 14000,
    'karabük': 15000,
    'zonguldak': 16000,
    'sinop': 15000,
    'amasya': 14000,
    'bilecik': 15000,
    'burdur': 14000,
    'isparta': 15000,
    'çankırı': 12000,
    'yozgat': 12000,
    'kırıkkale': 13000,
    'osmaniye': 13000,
    'şanlıurfa': 13000,
    'adıyaman': 12000,
    'kilis': 12000,
  };

  static const double _varsayilanM2Fiyat = 20000;

  /// İl bazında tahmini m² satış fiyatını döner
  static double ilM2SatisFiyati(String il) {
    final normalizedIl = il.toLowerCase().replaceAll('İ', 'i').replaceAll('I', 'ı');
    return _ilM2Fiyatlari[normalizedIl] ?? _varsayilanM2Fiyat;
  }

  /// Daire satış fiyatı tahmini
  /// [il]: İl adı
  /// [m2]: Daire metrekaresi
  /// [kat]: Kat numarası
  /// [insaatSuresi]: İnşaat süresi (ay)
  static double daireSatisFiyatiTahminEt({
    required String il,
    required double m2,
    required int kat,
    required int insaatSuresi,
    String tip = 'Daire',
  }) {
    double bazM2Fiyat = ilM2SatisFiyati(il);

    // Kat faktörü: üst katlar daha değerli (+%3 her kat için, 1. kattan itibaren)
    final katFaktoru = 1.0 + ((kat - 1) * 0.03);

    // Tip faktörü
    double tipFaktoru = 1.0;
    if (tip == 'Dubleks') tipFaktoru = 1.15;
    if (tip == 'Dükkan') tipFaktoru = 1.30;
    if (tip == 'Ofis') tipFaktoru = 1.10;

    // İnşaat süresi boyunca fiyat artışı (yıllık %25 konut değer artışı)
    final yillikArtis = 0.25;
    final artis = 1.0 + (yillikArtis * insaatSuresi / 12);

    return m2 * bazM2Fiyat * katFaktoru * tipFaktoru * artis;
  }
}
