import 'package:intl/intl.dart';
import 'tcmb_service.dart';
import 'emlak_data_service.dart';

/// Yerleşik mini yapay zeka — Gemini API'ye ihtiyaç duymadan
/// inşaat teklif analizi, maliyet hesabı, pazar bilgisi sunar.
/// Kural tabanlı (rule-based) çalışır, internet gerektirmez.
class YerelAiService {
  static final _f = NumberFormat('#,###', 'tr_TR');
  static final _tcmb = TcmbService();

  /// Kullanıcı mesajını analiz edip yanıt üret
  static String mesajYanitla(String mesaj) {
    final m = mesaj.toLowerCase().replaceAll('İ', 'i').replaceAll('ı', 'i');

    // Selamlama
    if (_eslesiyor(m, ['merhaba', 'selam', 'nasılsın', 'hey', 'günaydın', 'iyi günler'])) {
      return _karsilama();
    }

    // Yardım
    if (_eslesiyor(m, ['ne yapabilirsin', 'yardım', 'help', 'neler biliyorsun', 'komutlar'])) {
      return _yetenekler();
    }

    // Maliyet hesabı
    if (_eslesiyor(m, ['maliyet', 'maliyeti', 'ne kadar tutar', 'kaça mal olur', 'inşaat maliyeti'])) {
      final m2 = _sayiCikar(mesaj);
      final kat = _katSayisiCikar(mesaj);
      if (m2 != null) {
        return _maliyetHesabi(m2, kat);
      }
      return _maliyetBilgi();
    }

    // Kat karşılığı
    if (_eslesiyor(m, ['kat karşılığı', 'kat karsiligi', 'müteahhit daire', 'muteahhit'])) {
      return _katKarsiligi();
    }

    // Enflasyon / maliyet artışı
    if (_eslesiyor(m, ['enflasyon', 'artış', 'zamlanır', 'artis', 'fiyat artışı'])) {
      return _enflasyonBilgi();
    }

    // Bölge / ilçe fiyatları
    if (_eslesiyor(m, ['fiyat', 'm2 fiyat', 'metrekare', 'bölge', 'ilçe', 'mahalle', 'piyasa'])) {
      final ilce = _ilceCikar(mesaj);
      if (ilce != null) {
        return _ilceFiyat(ilce);
      }
      return _genelPiyasa();
    }

    // Sığınak
    if (_eslesiyor(m, ['sığınak', 'siginak', 'barınak'])) {
      return _siginakKurali();
    }

    // Otopark
    if (_eslesiyor(m, ['otopark', 'garaj', 'araç park'])) {
      return _otoparkBilgi();
    }

    // Hibe / kredi
    if (_eslesiyor(m, ['hibe', 'kredi', 'kentsel dönüşüm', 'devlet desteği', 'destek'])) {
      return _hibeBilgi();
    }

    // Kat çarpanı
    if (_eslesiyor(m, ['kat çarpanı', 'kat carpani', 'kat farkı', 'zemin kat', 'penthouse', 'çatı kat'])) {
      return _katCarpanBilgi();
    }

    // Daire tipi
    if (_eslesiyor(m, ['dubleks', 'dükkan', 'ofis', 'daire tipi', 'tip çarpan', 'ters dubleks'])) {
      return _tipCarpanBilgi();
    }

    // İnşaat süresi
    if (_eslesiyor(m, ['süre', 'sure', 'ne kadar sürer', 'kaç ay', 'inşaat süresi'])) {
      final m2 = _sayiCikar(mesaj);
      if (m2 != null) {
        return _sureHesabi(m2);
      }
      return _sureBilgi();
    }

    // Senaryo karşılaştırması
    if (_eslesiyor(m, ['senaryo', 'karşılaştır', 'fark', 'hangisi avantajlı'])) {
      return _senaryoKarsilastirma();
    }

    // KDV / vergi
    if (_eslesiyor(m, ['kdv', 'vergi', 'stopaj', 'damga'])) {
      return _vergiBilgi();
    }

    // Ruhsat / imar
    if (_eslesiyor(m, ['ruhsat', 'imar', 'izin', 'belediye', 'yapı ruhsatı'])) {
      return _ruhsatBilgi();
    }

    // Sayı varsa maliyet hesabı dene
    final m2 = _sayiCikar(mesaj);
    if (m2 != null && m2 > 50 && m2 < 100000) {
      return _maliyetHesabi(m2, null);
    }

    // Genel
    return _genelYanit();
  }

  // ── Yanıt üreticileri ──

  static String _karsilama() {
    return 'Merhaba! Ben Lento yerleşik yapay zeka asistanıyım.\n\n'
        'İnşaat teklif analizi, maliyet hesabı, bölge fiyatları ve '
        'kat karşılığı konularında size yardımcı olabilirim.\n\n'
        'İnternet bağlantısı veya API anahtarı gerektirmeden çalışıyorum.\n\n'
        'Birkaç örnek soru:\n'
        '• "3.000 m² inşaatın maliyeti ne olur?"\n'
        '• "Kadıköy\'de m² fiyatları ne?"\n'
        '• "Kat karşılığı nasıl hesaplanır?"\n'
        '• "Sığınak gereklilikleri nelerdir?"';
  }

  static String _yetenekler() {
    return 'Şu konularda bilgi verebilirim:\n\n'
        '📊 Maliyet Hesabı\n'
        '• m² bazında inşaat maliyeti hesaplama\n'
        '• Enflasyon projeksiyonu (iyimser/orta/kötümser)\n'
        '• İnşaat süresi tahmini\n\n'
        '🏠 Piyasa Bilgisi\n'
        '• İstanbul 39 ilçe + 250+ mahalle m² fiyatları\n'
        '• Kat ve daire tipi çarpanları\n'
        '• Satış fiyat tahminleri\n\n'
        '📋 İnşaat Kuralları\n'
        '• Sığınak gereklilikleri\n'
        '• Otopark düzenlemeleri\n'
        '• Kat karşılığı hesabı\n'
        '• Senaryo karşılaştırması\n\n'
        '💰 Finansal\n'
        '• Hibe ve kredi bilgisi\n'
        '• KDV/vergi bilgileri\n'
        '• Kentsel dönüşüm destekleri';
  }

  static String _maliyetHesabi(double m2, int? katSayisi) {
    final sure = TcmbService.insaatSuresiHesapla(m2);
    final guncelM2 = 35000.0; // 2025-2026 ortalama ₺/m²

    final proj = _tcmb.maliyetProjeksiyonuDetayli(
      guncelMaliyet: guncelM2,
      aySayisi: sure,
    );

    final minM = proj['minMaliyet'] as double;
    final ortM = proj['ortalamaMaliyet'] as double;
    final maxM = proj['maxMaliyet'] as double;
    final enfl = proj['yillikEnflasyon'] as double;

    final minT = (m2 * minM).round();
    final ortT = (m2 * ortM).round();
    final maxT = (m2 * maxM).round();

    final ks = katSayisi != null ? '$katSayisi katlı, ' : '';

    return '${ks}${_f.format(m2.round())} m² inşaat için tahmini hesaplama:\n\n'
        '📐 Toplam alan: ${_f.format(m2.round())} m²\n'
        '🕐 Tahmini süre: $sure ay\n'
        '📈 Yıllık inşaat enflasyonu: %${enfl.toStringAsFixed(1)}\n\n'
        'Maliyet Tahminleri (m² birim):\n'
        '• İyimser:  ${_f.format(minM.round())} ₺/m²\n'
        '• Ortalama: ${_f.format(ortM.round())} ₺/m²\n'
        '• Kötümser: ${_f.format(maxM.round())} ₺/m²\n\n'
        'Toplam Maliyet:\n'
        '• İyimser:  ${_f.format(minT)} ₺\n'
        '• Ortalama: ${_f.format(ortT)} ₺\n'
        '• Kötümser: ${_f.format(maxT)} ₺\n\n'
        '⚠️ Bu tahminler TÜİK inşaat maliyet endeksine dayalıdır.\n'
        'Gerçek maliyet arsa, konum ve inşaat kalitesine göre değişir.\n\n'
        '💡 Kar oranı eklemek için AI Teklif ekranını kullanabilirsiniz.';
  }

  static String _maliyetBilgi() {
    return 'Maliyet hesabı yapabilmem için toplam inşaat alanını (m²) belirtin.\n\n'
        'Örnek: "5.000 m² inşaatın maliyeti ne olur?"\n\n'
        '2025-2026 güncel ortalama değerler:\n'
        '• Konut inşaatı: 30.000 - 40.000 ₺/m²\n'
        '• Lüks konut: 45.000 - 65.000 ₺/m²\n'
        '• Ticari inşaat: 35.000 - 55.000 ₺/m²\n\n'
        'Bu rakamlar kaba + ince işçilik dahil, arsa hariçtir.\n'
        'İnşaat enflasyonu yıllık yaklaşık %${_tcmb.yillikInsaatEnflasyonu().toStringAsFixed(0)} civarındadır.';
  }

  static String _katKarsiligi() {
    return 'Kat Karşılığı İnşaat Sözleşmesi Bilgileri:\n\n'
        '📌 Nedir?\n'
        'Arsa sahibi arsasını, müteahhit inşaatı yapar. Karşılığında '
        'müteahhit bazı daireleri alır.\n\n'
        '📊 Tipik Paylaşım Oranları (İstanbul):\n'
        '• Merkezi ilçeler (Kadıköy, Beşiktaş): %40-50 arsa sahibine\n'
        '• Orta segment (Ataşehir, Maltepe): %45-55 arsa sahibine\n'
        '• Dış ilçeler (Esenyurt, Silivri): %50-65 arsa sahibine\n\n'
        '⚖️ İki Senaryo:\n'
        '1️⃣ Müteahhit daire almıyor → Tüm maliyet mal sahibine\n'
        '2️⃣ Müteahhit daire alıyor → Müteahhit daire satışından kazanır, '
        'kalan maliyet mal sahibi dairelerine dağıtılır\n\n'
        '💡 Detaylı analiz için AI Teklif ekranından her iki senaryoyu '
        'hesaplayabilirsiniz.\n\n'
        '⚠️ Sözleşme öncesi mutlaka hukuki danışmanlık alın.';
  }

  static String _enflasyonBilgi() {
    final enfl = _tcmb.yillikInsaatEnflasyonu();
    return 'İnşaat Sektörü Enflasyon Bilgileri:\n\n'
        '📈 Mevcut yıllık inşaat enflasyonu: %${enfl.toStringAsFixed(1)}\n'
        '(TÜİK İnşaat Maliyet Endeksi, 2015=100)\n\n'
        'Son 6 Yıllık Seyir (Endeks):\n'
        '• 2020 Q1: 142,3  →  2020 Q4: 178,5\n'
        '• 2021 Q1: 195,2  →  2021 Q4: 289,7\n'
        '• 2022 Q1: 342,1  →  2022 Q4: 512,6\n'
        '• 2023 Q1: 548,3  →  2023 Q4: 742,8\n'
        '• 2024 Q1: 798,5  →  2024 Q4: 978,2\n'
        '• 2025 Q1: 1.032,5 → 2025 Q4: 1.198,6\n\n'
        '📊 Projeksiyon Yöntemi:\n'
        '• Doğrusal regresyon (trend çizgisi)\n'
        '• Üstel düzeltme (son verilere ağırlık)\n'
        '• 3 senaryo: iyimser / ortalama / kötümser\n\n'
        '💡 Detaylı projeksiyon için m² ve alan girerek AI Teklif hesabı yapın.';
  }

  static String _ilceFiyat(String ilce) {
    // Normalize
    final normalized = EmlakDataService.normalize(ilce);
    final veri = EmlakDataService.ilceFiyatBilgisi('istanbul', normalized);

    if (veri == null) {
      return '$ilce için veri bulunamadı.\n\n'
          'İstanbul\'un 39 ilçesi için fiyat bilgisi mevcuttur.\n'
          'Örnek: "Kadıköy fiyatları", "Beşiktaş m² fiyat"';
    }

    final min = _f.format(veri['min']!.round());
    final avg = _f.format(veri['avg']!.round());
    final max = _f.format(veri['max']!.round());

    // Mahalle listesi
    final mahalleler = EmlakDataService.mahalleListesi('istanbul', normalized);
    final mahalleStr = mahalleler.isNotEmpty
        ? '\n\nKayıtlı Mahalleler (${mahalleler.length}):\n${mahalleler.map((m) => '• $m').join('\n')}'
        : '';

    return '${ilce.toUpperCase()} - Sıfır Bina m² Satış Fiyatları:\n\n'
        '• Minimum: $min ₺/m²\n'
        '• Ortalama: $avg ₺/m²\n'
        '• Maksimum: $max ₺/m²\n'
        '$mahalleStr\n\n'
        'Kat Çarpanları uygulanır:\n'
        '• Zemin kat: x0,90 | 3. kat: x1,05 | Çatı: x1,15\n\n'
        'Tip Çarpanları:\n'
        '• Dükkan: x1,35 | Dubleks: x1,20 | Ofis: x1,12\n\n'
        '⚠️ Fiyatlar sıfır bina (yeni inşaat) içindir, ikinci el değil.';
  }

  static String _genelPiyasa() {
    return 'İstanbul Genel Piyasa Bilgileri (Sıfır Bina m²):\n\n'
        '🏆 En Pahalı İlçeler:\n'
        '• Beşiktaş: 140.000 - 350.000 ₺/m²\n'
        '• Sarıyer: 105.000 - 280.000 ₺/m²\n'
        '• Kadıköy: 110.000 - 250.000 ₺/m²\n'
        '• Bakırköy: 100.000 - 230.000 ₺/m²\n\n'
        '📊 Orta Segment:\n'
        '• Ataşehir: 85.000 - 210.000 ₺/m²\n'
        '• Üsküdar: 85.000 - 200.000 ₺/m²\n'
        '• Maltepe: 72.000 - 160.000 ₺/m²\n'
        '• Kartal: 65.000 - 140.000 ₺/m²\n\n'
        '💰 Uygun Fiyatlı:\n'
        '• Esenyurt: 28.000 - 62.000 ₺/m²\n'
        '• Sultanbeyli: 28.000 - 60.000 ₺/m²\n'
        '• Çatalca: 18.000 - 58.000 ₺/m²\n\n'
        '💡 Belirli bir ilçe için soru sorun:\n'
        '"Kadıköy fiyatları" veya "Maltepe m² fiyat"';
  }

  static String _siginakKurali() {
    return 'Sığınak Gereklilikleri (Türkiye Mevzuatı):\n\n'
        '📌 Ne Zaman Zorunlu?\n'
        '• Toplam inşaat alanı ≥ 1.500 m² VEYA\n'
        '• Konut sayısı ≥ 10 adet\n\n'
        '📐 Minimum Sığınak Alanı Hesabı:\n'
        'Alan = (Konut sayısı × 4 m²) + (Ticari alan / 20)\n\n'
        'Sınırlar: Minimum 30 m², Maksimum 120 m²\n\n'
        '📍 Konumu:\n'
        '• Genellikle en alt katta (bodrum)\n'
        '• Bina girişine yakın olmalı\n'
        '• Uygulama: Binada 15 daire + 200 m² dükkan varsa:\n'
        '  → (15 × 4) + (200 / 20) = 60 + 10 = 70 m² sığınak\n\n'
        '⚠️ Lento uygulaması sığınağı otomatik hesaplar ve binaya ekler.';
  }

  static String _otoparkBilgi() {
    return 'Otopark Düzenlemeleri:\n\n'
        '📌 Genel Kurallar:\n'
        '• Her bağımsız bölüm için en az 1 otopark yeri\n'
        '• Dükkan: Her 30 m² için 1 otopark\n'
        '• Ofis: Her 40 m² için 1 otopark\n\n'
        '📐 Standart Boyutlar:\n'
        '• Normal otopark: 2,5 × 5,0 m (12,5 m²)\n'
        '• Engelli otopark: 3,5 × 5,0 m (17,5 m²)\n\n'
        '📍 Uygulama:\n'
        '• Açık otopark veya kapalı garaj olabilir\n'
        '• Bodrum kat tercihen garaj olarak planlanır\n'
        '• İmar planına göre değişiklik gösterebilir\n\n'
        '⚠️ Belediye imar yönetmeliğini kontrol edin — ilçeye göre farklılık gösterir.';
  }

  static String _hibeBilgi() {
    return 'Hibe ve Kredi Seçenekleri:\n\n'
        '🏗️ Kentsel Dönüşüm Desteği:\n'
        '• TOKI/Çevre Bakanlığı kira yardımı\n'
        '• Taşınma yardımı (2025: yaklaşık 15.000-25.000 ₺)\n'
        '• Faiz desteği (kredi faizinin bir kısmı devlet tarafından)\n\n'
        '💰 Kredi İmkanları:\n'
        '• Kentsel dönüşüm kredisi (düşük faizli)\n'
        '• Konut inşaat kredisi (bankalardan)\n'
        '• TOKI konut kredisi\n\n'
        '📋 Başvuru Şartları:\n'
        '• Riskli yapı raporu (kentsel dönüşüm için)\n'
        '• İmar durumu belgesi\n'
        '• 2/3 kat maliki onayı (kentsel dönüşüm)\n\n'
        '⚙️ Lento\'da Kullanım:\n'
        'AI Teklif ekranında her daire için hibe ve kredi '
        'tutarlarını ayrı ayrı girebilirsiniz. Sistem bunları '
        'net ödemeden düşer.\n\n'
        '⚠️ Güncel tutarlar için Çevre, Şehircilik ve İklim '
        'Değişikliği Bakanlığı\'na başvurun.';
  }

  static String _katCarpanBilgi() {
    return 'Kat Çarpanları (Fiyat Etkisi):\n\n'
        'Satış fiyatına uygulanan çarpanlar (1. kat = 1,00):\n\n'
        '🏢 Kat Bazında:\n'
        '• Bodrum (kat ≤ -1): × 0,78  → %22 düşük\n'
        '• Zemin kat (0):     × 0,90  → %10 düşük\n'
        '• 1. kat:            × 1,00  → Baz fiyat\n'
        '• 2. kat:            × 1,03  → %3 primli\n'
        '• 3. kat:            × 1,05  → %5 primli\n'
        '• 4. kat:            × 1,07  → %7 primli\n'
        '• 5. kat:            × 1,09  → %9 primli\n'
        '• Çatı/Penthouse (≥6): × 1,15 → %15 primli\n\n'
        '📌 Örnek:\n'
        'Ortalama m² fiyat 100.000 ₺ ise:\n'
        '• Zemin kat daire: 90.000 ₺/m²\n'
        '• 5. kat daire: 109.000 ₺/m²\n'
        '• Çatı dubleks: 115.000 ₺/m²';
  }

  static String _tipCarpanBilgi() {
    return 'Daire Tipi Çarpanları (Fiyat Etkisi):\n\n'
        'Satış fiyatına uygulanan çarpanlar (Daire = 1,00):\n\n'
        '🏠 Tip Bazında:\n'
        '• Daire:           × 1,00 → Baz fiyat\n'
        '• Ters Dubleks:    × 1,10 → %10 primli\n'
        '• Ofis:            × 1,12 → %12 primli\n'
        '• Dubleks:         × 1,20 → %20 primli\n'
        '• Dükkan:          × 1,35 → %35 primli\n'
        '• Depolu Dükkan:   × 1,40 → %40 primli\n\n'
        '📌 Çapraz Katlı Birimler:\n'
        '• Dubleks: Alt kat + üst kat (bir üst kata uzanır)\n'
        '• Ters Dubleks: Ana kat + alt kat (bir alt kata iner)\n'
        '• Depolu Dükkan: Dükkan + depo (bir alt kata iner)\n\n'
        '📌 Örnek:\n'
        'Ortalama m² fiyat 100.000 ₺, 3. kat:\n'
        '• Daire: 100.000 × 1,05 = 105.000 ₺/m²\n'
        '• Dükkan (zemin): 100.000 × 0,90 × 1,35 = 121.500 ₺/m²';
  }

  static String _sureHesabi(double m2) {
    final sure = TcmbService.insaatSuresiHesapla(m2);
    return '${_f.format(m2.round())} m² inşaat için tahmini süre: $sure ay\n\n'
        '📐 Hesaplama yöntemi:\n'
        '• ≤ 2.000 m²: Sabit 18 ay\n'
        '• > 2.000 m²: 18 + (fazladan her 2.000 m² için +6 ay)\n\n'
        '⚠️ Gerçek süre şunlara bağlıdır:\n'
        '• İmar izin süreçleri\n'
        '• Mevsimsel koşullar\n'
        '• İşçi ve malzeme tedariği\n'
        '• Kat sayısı ve mimari karmaşıklık';
  }

  static String _sureBilgi() {
    return 'İnşaat Süresi Tahmini:\n\n'
        '📐 Formül:\n'
        '• ≤ 2.000 m²: 18 ay\n'
        '• > 2.000 m²: 18 + (fazladan 2.000 m² başına +6 ay)\n\n'
        'Örnek Süreler:\n'
        '• 1.000 m² → 18 ay\n'
        '• 3.000 m² → 24 ay\n'
        '• 5.000 m² → 30 ay\n'
        '• 10.000 m² → 42 ay\n\n'
        '💡 Belirli bir alan için sorabilirsiniz:\n'
        '"4.000 m² inşaat ne kadar sürer?"';
  }

  static String _senaryoKarsilastirma() {
    return 'Senaryo Karşılaştırması:\n\n'
        '1️⃣ Senaryo 1 — Müteahhit Daire Almıyor:\n'
        '• Tüm inşaat maliyeti mal sahibine\n'
        '• Her dairenin maliyeti: m² × birim fiyat\n'
        '• Hibe/kredi tek tek düşülebilir\n'
        '• Avantaj: Tüm daireler mal sahibinde kalır\n'
        '• Dezavantaj: Yüksek toplam maliyet\n\n'
        '2️⃣ Senaryo 2 — Müteahhit Daire Alıyor:\n'
        '• Müteahhit belirli daireleri alır, satıştan kazanır\n'
        '• Müteahhit dairelerinin piyasa değeri hesaplanır\n'
        '• Kalan maliyet = Toplam − Müteahhit satış geliri\n'
        '• Kalan, mal sahibi daireleri arasında m² oranında paylaştırılır\n'
        '• Avantaj: Birim başı maliyet düşer\n'
        '• Dezavantaj: Bölünen daireler\n\n'
        '📊 Müteahhit Daire Değerleme:\n'
        '• Bölge piyasa fiyatı kullanılır\n'
        '• Kat ve tip çarpanları uygulanır\n'
        '• İnşaat süresince %15 yıllık değer artışı\n\n'
        '💡 Her iki senaryoyu AI Teklif ekranından hesaplayabilirsiniz.';
  }

  static String _vergiBilgi() {
    return 'İnşaat Vergi ve Kesintiler:\n\n'
        '📌 KDV Oranları:\n'
        '• Konut (≤ 150 m²): %1 (kentsel dönüşüm)\n'
        '• Konut (> 150 m²): %20\n'
        '• Konut (normal): %10\n'
        '• Ticari (dükkan/ofis): %20\n\n'
        '📌 Diğer Vergiler:\n'
        '• Tapu harcı: %4 (alıcı+satıcı toplam)\n'
        '• Damga vergisi: Sözleşme bedelinin binde 9,48\'i\n'
        '• Yapı denetim harcı: İnşaat maliyetinin yaklaşık %3\'ü\n\n'
        '⚠️ Vergi oranları yıldan yıla değişebilir.\n'
        'Güncel oranlar için mali müşavirinize danışın.';
  }

  static String _ruhsatBilgi() {
    return 'Yapı Ruhsatı ve İmar Bilgileri:\n\n'
        '📋 Gerekli Belgeler:\n'
        '• İmar durumu belgesi (belediyeden)\n'
        '• Mimari proje (onaylı)\n'
        '• Statik proje\n'
        '• Mekanik + elektrik projeleri\n'
        '• Zemin etüdü raporu\n'
        '• Yapı denetim sözleşmesi\n\n'
        '🕐 Süreç:\n'
        '1. İmar durumu başvurusu (1-2 hafta)\n'
        '2. Proje hazırlanması (1-3 ay)\n'
        '3. Belediye onayı (2-4 hafta)\n'
        '4. Yapı ruhsatı çıkması (1-2 hafta)\n'
        '5. İnşaat başlangıcı\n\n'
        '⚠️ Kentsel dönüşüm binalarında riskli yapı raporu '
        'ek olarak gereklidir.\n'
        'İlçe belediyesinin imar yönetmeliğini kontrol edin.';
  }

  static String _genelYanit() {
    return 'Sorunuzu tam anlayamadım, ama şu konularda yardımcı olabilirim:\n\n'
        '• "3.000 m² inşaatın maliyeti" → maliyet hesabı\n'
        '• "Kadıköy fiyatları" → bölge piyasa bilgisi\n'
        '• "Kat karşılığı nedir?" → müteahhit anlaşması\n'
        '• "Sığınak kuralları" → yasal gereklilikler\n'
        '• "Enflasyon tahmini" → maliyet artış projeksiyonu\n'
        '• "Kat çarpanı nedir?" → kat bazlı fiyat farkları\n'
        '• "Dükkan fiyat farkı" → tip bazlı çarpanlar\n'
        '• "Hibe ve kredi" → devlet destekleri\n'
        '• "KDV oranları" → vergi bilgileri\n'
        '• "Ruhsat süreci" → yapı ruhsatı\n\n'
        'Sorularınızı Türkçe ve kısa yazın, daha iyi anlayabilirim.';
  }

  // ── Yardımcı metodlar ──

  static bool _eslesiyor(String metin, List<String> kelimeler) {
    for (final k in kelimeler) {
      if (metin.contains(k.toLowerCase().replaceAll('İ', 'i').replaceAll('ı', 'i'))) {
        return true;
      }
    }
    return false;
  }

  static double? _sayiCikar(String metin) {
    // "3.000 m²" veya "3000" veya "5 bin" veya "5.000"
    final binMatch = RegExp(r'(\d+)\s*bin').firstMatch(metin);
    if (binMatch != null) {
      return (int.tryParse(binMatch.group(1)!) ?? 0) * 1000.0;
    }

    final noktaliMatch = RegExp(r'(\d{1,3})\.(\d{3})').firstMatch(metin);
    if (noktaliMatch != null) {
      final sayi = '${noktaliMatch.group(1)}${noktaliMatch.group(2)}';
      return double.tryParse(sayi);
    }

    final match = RegExp(r'(\d{3,6})').firstMatch(metin);
    if (match != null) {
      return double.tryParse(match.group(1)!);
    }

    return null;
  }

  static int? _katSayisiCikar(String metin) {
    final match = RegExp(r'(\d+)\s*kat').firstMatch(metin.toLowerCase());
    if (match != null) {
      final sayi = int.tryParse(match.group(1)!);
      if (sayi != null && sayi >= 1 && sayi <= 50) return sayi;
    }
    return null;
  }

  static String? _ilceCikar(String metin) {
    final ilceler = [
      'kadıköy', 'beşiktaş', 'şişli', 'beyoğlu', 'üsküdar', 'ataşehir',
      'maltepe', 'kartal', 'pendik', 'tuzla', 'beykoz', 'çekmeköy',
      'sancaktepe', 'sultanbeyli', 'ümraniye', 'fatih', 'bakırköy',
      'bahçelievler', 'bağcılar', 'küçükçekmece', 'başakşehir', 'avcılar',
      'esenyurt', 'beylikdüzü', 'büyükçekmece', 'arnavutköy', 'sultangazi',
      'gaziosmanpaşa', 'eyüpsultan', 'kağıthane', 'sarıyer', 'zeytinburnu',
      'güngören', 'esenler', 'bayrampaşa', 'silivri', 'şile', 'çatalca',
      'adalar',
    ];

    final lower = metin.toLowerCase();
    for (final ilce in ilceler) {
      if (lower.contains(ilce)) return ilce;
    }
    return null;
  }
}
