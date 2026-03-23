/// Emlak piyasa verileri servisi
/// İlçe bazında m² satış fiyatları, kat ve tip çarpanları
class EmlakDataService {
  // ── Kat Çarpanları ──
  // Zemin altı ve üstü katlar için fiyat çarpanları
  static double katCarpani(int kat, {int toplamKat = 5}) {
    if (kat <= -1) return 0.75; // Bodrum
    if (kat == 0) return 0.88; // Zemin
    if (kat == 1) return 1.0; // 1. kat (referans)
    if (kat == 2) return 1.03;
    if (kat == 3) return 1.05;
    if (kat == 4) return 1.07;
    if (kat == 5) return 1.08;
    if (kat >= toplamKat && kat >= 6) return 1.15; // Çatı katı / penthouse
    return 1.0 + ((kat - 1) * 0.02); // Yüksek katlar
  }

  // ── Daire Tipi Çarpanları ──
  static double tipCarpani(String tip) {
    switch (tip) {
      case 'Dubleks':
        return 1.18;
      case 'Dükkan':
        return 1.35;
      case 'Ofis':
        return 1.12;
      case 'Daire':
      default:
        return 1.0;
    }
  }

  /// İlçe bazında m² fiyat verisini döner {min, avg, max}
  static Map<String, double> ilceM2Fiyat(String il, String ilce) {
    final key = '${_normalize(il)}/${_normalize(ilce)}';
    return _ilceVerileri[key] ?? _ilVerileri[_normalize(il)] ?? _varsayilan;
  }

  /// Tam daire satış fiyatı tahmini (min / avg / max)
  static Map<String, double> daireSatisTahmini({
    required String il,
    required String ilce,
    required double m2,
    required int kat,
    required String tip,
    required int insaatSuresi,
    int toplamKat = 5,
  }) {
    final bazFiyat = ilceM2Fiyat(il, ilce);
    final kc = katCarpani(kat, toplamKat: toplamKat);
    final tc = tipCarpani(tip);

    // İnşaat süresi boyunca değer artışı (yıllık ~%20 konut değer artışı)
    final artis = 1.0 + (0.20 * insaatSuresi / 12);

    return {
      'minM2': bazFiyat['min']! * kc * tc * artis,
      'avgM2': bazFiyat['avg']! * kc * tc * artis,
      'maxM2': bazFiyat['max']! * kc * tc * artis,
      'minToplam': bazFiyat['min']! * kc * tc * artis * m2,
      'avgToplam': bazFiyat['avg']! * kc * tc * artis * m2,
      'maxToplam': bazFiyat['max']! * kc * tc * artis * m2,
      'katCarpani': kc,
      'tipCarpani': tc,
      'degerArtisi': artis,
    };
  }

  /// Pazar analizi metni oluşturur
  static String pazarAnalizi({
    required String il,
    required String ilce,
    required String mahalle,
    required int insaatSuresi,
    required List<Map<String, dynamic>> daireler,
  }) {
    final fiyat = ilceM2Fiyat(il, ilce);
    final sb = StringBuffer();

    sb.writeln('Pazar Analizi: $il / $ilce / $mahalle');
    sb.writeln('─' * 40);
    sb.writeln();
    sb.writeln('Bölge m² Satış Fiyatları (güncel):');
    sb.writeln('  En Düşük: ${fiyat['min']!.round().toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]}.')} ₺/m²');
    sb.writeln('  Ortalama: ${fiyat['avg']!.round().toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]}.')} ₺/m²');
    sb.writeln('  En Yüksek: ${fiyat['max']!.round().toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]}.')} ₺/m²');
    sb.writeln();

    // Daire bazlı tahminler
    sb.writeln('Daire Bazlı Satış Tahminleri ($insaatSuresi ay sonrası):');
    for (int i = 0; i < daireler.length; i++) {
      final d = daireler[i];
      final m2 = (d['m2'] as num).toDouble();
      final kat = d['kat'] as int;
      final tip = d['tip'] as String? ?? 'Daire';

      final tahmin = daireSatisTahmini(
        il: il,
        ilce: ilce,
        m2: m2,
        kat: kat,
        tip: tip,
        insaatSuresi: insaatSuresi,
      );

      final minF = tahmin['minToplam']!.round().toString().replaceAllMapped(
          RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]}.');
      final maxF = tahmin['maxToplam']!.round().toString().replaceAllMapped(
          RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]}.');

      sb.writeln('  $tip ${m2.round()} m² (${kat}. kat): $minF ₺ - $maxF ₺');
    }

    sb.writeln();
    sb.writeln('Kat Etkileri:');
    sb.writeln('  Bodrum: -%25  |  Zemin: -%12  |  1. Kat: Referans');
    sb.writeln('  2. Kat: +%3  |  3. Kat: +%5  |  4. Kat: +%7  |  5+ Kat: +%8-15');
    sb.writeln();
    sb.writeln('⚠️ Fiyatlar bölge ortalamasına dayalı tahminlerdir. Gerçek fiyatlar');
    sb.writeln('   binanın kalitesi, konumu ve piyasa koşullarına göre değişir.');

    return sb.toString();
  }

  static String _normalize(String s) =>
      s.toLowerCase().trim()
          .replaceAll('İ', 'i')
          .replaceAll('I', 'ı')
          .replaceAll('Ü', 'ü')
          .replaceAll('Ö', 'ö')
          .replaceAll('Ç', 'ç')
          .replaceAll('Ş', 'ş')
          .replaceAll('Ğ', 'ğ');

  static const Map<String, double> _varsayilan = {
    'min': 15000,
    'avg': 20000,
    'max': 28000,
  };

  // ── İl bazında genel fiyatlar ──
  static const Map<String, Map<String, double>> _ilVerileri = {
    'istanbul': {'min': 35000, 'avg': 55000, 'max': 120000},
    'ankara': {'min': 18000, 'avg': 28000, 'max': 55000},
    'izmir': {'min': 22000, 'avg': 32000, 'max': 65000},
    'bursa': {'min': 16000, 'avg': 25000, 'max': 45000},
    'antalya': {'min': 25000, 'avg': 35000, 'max': 80000},
    'konya': {'min': 12000, 'avg': 18000, 'max': 30000},
    'adana': {'min': 12000, 'avg': 17000, 'max': 28000},
    'gaziantep': {'min': 12000, 'avg': 18000, 'max': 30000},
    'kayseri': {'min': 10000, 'avg': 16000, 'max': 25000},
    'mersin': {'min': 14000, 'avg': 20000, 'max': 35000},
    'eskişehir': {'min': 14000, 'avg': 20000, 'max': 32000},
    'diyarbakır': {'min': 9000, 'avg': 14000, 'max': 22000},
    'samsun': {'min': 10000, 'avg': 16000, 'max': 25000},
    'denizli': {'min': 12000, 'avg': 17000, 'max': 28000},
    'muğla': {'min': 28000, 'avg': 40000, 'max': 90000},
    'trabzon': {'min': 14000, 'avg': 20000, 'max': 35000},
    'kocaeli': {'min': 18000, 'avg': 26000, 'max': 42000},
    'sakarya': {'min': 15000, 'avg': 22000, 'max': 35000},
    'tekirdağ': {'min': 15000, 'avg': 22000, 'max': 35000},
    'balıkesir': {'min': 12000, 'avg': 18000, 'max': 30000},
    'aydın': {'min': 15000, 'avg': 22000, 'max': 38000},
    'çanakkale': {'min': 16000, 'avg': 24000, 'max': 40000},
    'yalova': {'min': 18000, 'avg': 25000, 'max': 40000},
    'bolu': {'min': 12000, 'avg': 18000, 'max': 28000},
    'düzce': {'min': 10000, 'avg': 16000, 'max': 25000},
    'edirne': {'min': 12000, 'avg': 18000, 'max': 28000},
    'manisa': {'min': 10000, 'avg': 16000, 'max': 25000},
    'hatay': {'min': 9000, 'avg': 14000, 'max': 22000},
    'malatya': {'min': 8000, 'avg': 13000, 'max': 20000},
    'van': {'min': 7000, 'avg': 12000, 'max': 18000},
    'şanlıurfa': {'min': 8000, 'avg': 13000, 'max': 20000},
    'erzurum': {'min': 9000, 'avg': 14000, 'max': 22000},
    'elazığ': {'min': 9000, 'avg': 14000, 'max': 22000},
    'sivas': {'min': 8000, 'avg': 13000, 'max': 20000},
    'zonguldak': {'min': 10000, 'avg': 16000, 'max': 25000},
    'karabük': {'min': 10000, 'avg': 15000, 'max': 23000},
    'bartın': {'min': 9000, 'avg': 14000, 'max': 22000},
    'rize': {'min': 12000, 'avg': 18000, 'max': 28000},
    'ordu': {'min': 10000, 'avg': 16000, 'max': 25000},
    'giresun': {'min': 10000, 'avg': 15000, 'max': 23000},
    'artvin': {'min': 10000, 'avg': 15000, 'max': 23000},
    'isparta': {'min': 10000, 'avg': 15000, 'max': 23000},
    'burdur': {'min': 9000, 'avg': 14000, 'max': 22000},
    'afyonkarahisar': {'min': 9000, 'avg': 14000, 'max': 22000},
    'kütahya': {'min': 8000, 'avg': 13000, 'max': 20000},
    'uşak': {'min': 9000, 'avg': 14000, 'max': 22000},
    'bilecik': {'min': 10000, 'avg': 15000, 'max': 23000},
    'çorum': {'min': 8000, 'avg': 13000, 'max': 20000},
    'amasya': {'min': 9000, 'avg': 14000, 'max': 22000},
    'tokat': {'min': 7000, 'avg': 12000, 'max': 18000},
    'sinop': {'min': 10000, 'avg': 15000, 'max': 23000},
    'kastamonu': {'min': 7000, 'avg': 12000, 'max': 18000},
    'nevşehir': {'min': 9000, 'avg': 14000, 'max': 22000},
    'kırşehir': {'min': 8000, 'avg': 13000, 'max': 20000},
    'aksaray': {'min': 8000, 'avg': 13000, 'max': 20000},
    'niğde': {'min': 7000, 'avg': 12000, 'max': 18000},
    'karaman': {'min': 8000, 'avg': 13000, 'max': 20000},
    'yozgat': {'min': 7000, 'avg': 12000, 'max': 18000},
    'çankırı': {'min': 7000, 'avg': 12000, 'max': 18000},
    'kırıkkale': {'min': 8000, 'avg': 13000, 'max': 20000},
    'osmaniye': {'min': 8000, 'avg': 13000, 'max': 20000},
    'kahramanmaraş': {'min': 8000, 'avg': 13000, 'max': 20000},
    'adıyaman': {'min': 7000, 'avg': 12000, 'max': 18000},
    'batman': {'min': 7000, 'avg': 12000, 'max': 18000},
    'mardin': {'min': 7000, 'avg': 12000, 'max': 18000},
    'şırnak': {'min': 6000, 'avg': 11000, 'max': 16000},
    'siirt': {'min': 6000, 'avg': 11000, 'max': 16000},
    'bingöl': {'min': 6000, 'avg': 11000, 'max': 16000},
    'bitlis': {'min': 5000, 'avg': 10000, 'max': 15000},
    'muş': {'min': 5000, 'avg': 10000, 'max': 15000},
    'hakkari': {'min': 5000, 'avg': 10000, 'max': 15000},
    'tunceli': {'min': 7000, 'avg': 12000, 'max': 18000},
    'ağrı': {'min': 5000, 'avg': 10000, 'max': 15000},
    'iğdır': {'min': 5000, 'avg': 10000, 'max': 15000},
    'kars': {'min': 5000, 'avg': 10000, 'max': 15000},
    'ardahan': {'min': 5000, 'avg': 10000, 'max': 15000},
    'bayburt': {'min': 6000, 'avg': 11000, 'max': 16000},
    'gümüşhane': {'min': 7000, 'avg': 12000, 'max': 18000},
    'kilis': {'min': 7000, 'avg': 12000, 'max': 18000},
  };

  // ── İlçe bazında detaylı fiyatlar {min, avg, max} TL/m² ──
  static const Map<String, Map<String, double>> _ilceVerileri = {
    // İSTANBUL
    'istanbul/kadıköy': {'min': 60000, 'avg': 85000, 'max': 140000},
    'istanbul/beşiktaş': {'min': 75000, 'avg': 110000, 'max': 200000},
    'istanbul/şişli': {'min': 55000, 'avg': 80000, 'max': 150000},
    'istanbul/beyoğlu': {'min': 50000, 'avg': 70000, 'max': 130000},
    'istanbul/üsküdar': {'min': 45000, 'avg': 65000, 'max': 110000},
    'istanbul/ataşehir': {'min': 45000, 'avg': 68000, 'max': 115000},
    'istanbul/maltepe': {'min': 38000, 'avg': 55000, 'max': 90000},
    'istanbul/kartal': {'min': 32000, 'avg': 48000, 'max': 75000},
    'istanbul/pendik': {'min': 28000, 'avg': 42000, 'max': 65000},
    'istanbul/tuzla': {'min': 25000, 'avg': 38000, 'max': 58000},
    'istanbul/bakırköy': {'min': 55000, 'avg': 80000, 'max': 140000},
    'istanbul/bahçelievler': {'min': 35000, 'avg': 50000, 'max': 75000},
    'istanbul/bağcılar': {'min': 28000, 'avg': 40000, 'max': 60000},
    'istanbul/güngören': {'min': 30000, 'avg': 42000, 'max': 62000},
    'istanbul/zeytinburnu': {'min': 38000, 'avg': 55000, 'max': 85000},
    'istanbul/fatih': {'min': 42000, 'avg': 60000, 'max': 95000},
    'istanbul/eyüpsultan': {'min': 30000, 'avg': 45000, 'max': 70000},
    'istanbul/beylikdüzü': {'min': 25000, 'avg': 38000, 'max': 58000},
    'istanbul/esenyurt': {'min': 18000, 'avg': 28000, 'max': 42000},
    'istanbul/avcılar': {'min': 25000, 'avg': 38000, 'max': 55000},
    'istanbul/küçükçekmece': {'min': 25000, 'avg': 38000, 'max': 55000},
    'istanbul/başakşehir': {'min': 30000, 'avg': 50000, 'max': 80000},
    'istanbul/sarıyer': {'min': 55000, 'avg': 90000, 'max': 180000},
    'istanbul/beykoz': {'min': 45000, 'avg': 70000, 'max': 130000},
    'istanbul/çekmeköy': {'min': 28000, 'avg': 42000, 'max': 65000},
    'istanbul/sancaktepe': {'min': 22000, 'avg': 35000, 'max': 52000},
    'istanbul/sultanbeyli': {'min': 18000, 'avg': 28000, 'max': 42000},
    'istanbul/ümraniye': {'min': 35000, 'avg': 52000, 'max': 80000},
    'istanbul/kağıthane': {'min': 38000, 'avg': 55000, 'max': 85000},
    'istanbul/gaziosmanpaşa': {'min': 25000, 'avg': 38000, 'max': 55000},
    'istanbul/esenler': {'min': 22000, 'avg': 32000, 'max': 48000},
    'istanbul/bayrampaşa': {'min': 32000, 'avg': 45000, 'max': 65000},
    'istanbul/sultangazi': {'min': 22000, 'avg': 32000, 'max': 48000},
    'istanbul/arnavutköy': {'min': 15000, 'avg': 25000, 'max': 38000},
    'istanbul/silivri': {'min': 15000, 'avg': 22000, 'max': 35000},
    'istanbul/çatalca': {'min': 12000, 'avg': 18000, 'max': 28000},
    'istanbul/büyükçekmece': {'min': 22000, 'avg': 35000, 'max': 55000},
    'istanbul/adalar': {'min': 40000, 'avg': 65000, 'max': 120000},
    // ANKARA
    'ankara/çankaya': {'min': 30000, 'avg': 50000, 'max': 95000},
    'ankara/keçiören': {'min': 15000, 'avg': 22000, 'max': 35000},
    'ankara/yenimahalle': {'min': 20000, 'avg': 30000, 'max': 50000},
    'ankara/etimesgut': {'min': 18000, 'avg': 28000, 'max': 42000},
    'ankara/mamak': {'min': 12000, 'avg': 18000, 'max': 28000},
    'ankara/sincan': {'min': 12000, 'avg': 18000, 'max': 28000},
    'ankara/altındağ': {'min': 12000, 'avg': 18000, 'max': 28000},
    'ankara/pursaklar': {'min': 14000, 'avg': 22000, 'max': 32000},
    'ankara/gölbaşı': {'min': 20000, 'avg': 32000, 'max': 52000},
    'ankara/beypazarı': {'min': 8000, 'avg': 12000, 'max': 18000},
    'ankara/polatlı': {'min': 8000, 'avg': 12000, 'max': 18000},
    // İZMİR
    'izmir/konak': {'min': 28000, 'avg': 42000, 'max': 70000},
    'izmir/bornova': {'min': 25000, 'avg': 35000, 'max': 55000},
    'izmir/karşıyaka': {'min': 30000, 'avg': 45000, 'max': 75000},
    'izmir/buca': {'min': 20000, 'avg': 28000, 'max': 42000},
    'izmir/bayraklı': {'min': 22000, 'avg': 32000, 'max': 50000},
    'izmir/çiğli': {'min': 18000, 'avg': 26000, 'max': 40000},
    'izmir/gaziemir': {'min': 20000, 'avg': 30000, 'max': 45000},
    'izmir/narlıdere': {'min': 35000, 'avg': 55000, 'max': 95000},
    'izmir/balçova': {'min': 30000, 'avg': 48000, 'max': 80000},
    'izmir/çeşme': {'min': 45000, 'avg': 75000, 'max': 150000},
    'izmir/urla': {'min': 35000, 'avg': 55000, 'max': 95000},
    'izmir/seferihisar': {'min': 28000, 'avg': 42000, 'max': 70000},
    'izmir/karabağlar': {'min': 18000, 'avg': 26000, 'max': 40000},
    'izmir/torbalı': {'min': 14000, 'avg': 20000, 'max': 30000},
    'izmir/menemen': {'min': 14000, 'avg': 20000, 'max': 30000},
    // ANTALYA
    'antalya/muratpaşa': {'min': 35000, 'avg': 52000, 'max': 90000},
    'antalya/konyaaltı': {'min': 40000, 'avg': 60000, 'max': 110000},
    'antalya/kepez': {'min': 18000, 'avg': 28000, 'max': 42000},
    'antalya/döşemealtı': {'min': 20000, 'avg': 30000, 'max': 48000},
    'antalya/aksu': {'min': 18000, 'avg': 25000, 'max': 38000},
    'antalya/alanya': {'min': 30000, 'avg': 45000, 'max': 85000},
    'antalya/manavgat': {'min': 18000, 'avg': 28000, 'max': 45000},
    'antalya/kaş': {'min': 35000, 'avg': 55000, 'max': 100000},
    // BURSA
    'bursa/osmangazi': {'min': 18000, 'avg': 28000, 'max': 48000},
    'bursa/nilüfer': {'min': 25000, 'avg': 38000, 'max': 65000},
    'bursa/yıldırım': {'min': 14000, 'avg': 20000, 'max': 32000},
    'bursa/görükle': {'min': 18000, 'avg': 28000, 'max': 42000},
    'bursa/mudanya': {'min': 22000, 'avg': 32000, 'max': 55000},
    'bursa/gemlik': {'min': 14000, 'avg': 20000, 'max': 32000},
    // KOCAELİ
    'kocaeli/izmit': {'min': 20000, 'avg': 30000, 'max': 48000},
    'kocaeli/gebze': {'min': 22000, 'avg': 32000, 'max': 50000},
    'kocaeli/darıca': {'min': 18000, 'avg': 26000, 'max': 40000},
    'kocaeli/körfez': {'min': 16000, 'avg': 22000, 'max': 35000},
    'kocaeli/derince': {'min': 16000, 'avg': 24000, 'max': 38000},
    // GAZİANTEP
    'gaziantep/şahinbey': {'min': 12000, 'avg': 18000, 'max': 30000},
    'gaziantep/şehitkamil': {'min': 14000, 'avg': 22000, 'max': 38000},
    // KONYA
    'konya/selçuklu': {'min': 14000, 'avg': 22000, 'max': 38000},
    'konya/meram': {'min': 12000, 'avg': 18000, 'max': 30000},
    'konya/karatay': {'min': 10000, 'avg': 15000, 'max': 24000},
    // MERSİN
    'mersin/yenişehir': {'min': 18000, 'avg': 28000, 'max': 45000},
    'mersin/mezitli': {'min': 20000, 'avg': 30000, 'max': 48000},
    'mersin/akdeniz': {'min': 12000, 'avg': 18000, 'max': 28000},
    'mersin/toroslar': {'min': 14000, 'avg': 20000, 'max': 30000},
    // ADANA
    'adana/seyhan': {'min': 14000, 'avg': 20000, 'max': 32000},
    'adana/çukurova': {'min': 16000, 'avg': 24000, 'max': 40000},
    'adana/yüreğir': {'min': 10000, 'avg': 14000, 'max': 22000},
    'adana/sarıçam': {'min': 12000, 'avg': 18000, 'max': 28000},
    // ESKİŞEHİR
    'eskişehir/tepebaşı': {'min': 16000, 'avg': 24000, 'max': 38000},
    'eskişehir/odunpazarı': {'min': 14000, 'avg': 20000, 'max': 32000},
    // KAYSERİ
    'kayseri/melikgazi': {'min': 12000, 'avg': 18000, 'max': 28000},
    'kayseri/kocasinan': {'min': 10000, 'avg': 15000, 'max': 24000},
    'kayseri/talas': {'min': 14000, 'avg': 22000, 'max': 35000},
    // TRABZON
    'trabzon/ortahisar': {'min': 16000, 'avg': 24000, 'max': 40000},
    'trabzon/akçaabat': {'min': 12000, 'avg': 18000, 'max': 28000},
    'trabzon/yomra': {'min': 12000, 'avg': 18000, 'max': 28000},
    // SAMSUN
    'samsun/atakum': {'min': 14000, 'avg': 22000, 'max': 35000},
    'samsun/ilkadım': {'min': 12000, 'avg': 18000, 'max': 28000},
    'samsun/canik': {'min': 10000, 'avg': 15000, 'max': 24000},
    // MUĞLA
    'muğla/bodrum': {'min': 50000, 'avg': 80000, 'max': 180000},
    'muğla/fethiye': {'min': 35000, 'avg': 55000, 'max': 110000},
    'muğla/marmaris': {'min': 35000, 'avg': 52000, 'max': 100000},
    'muğla/dalaman': {'min': 20000, 'avg': 30000, 'max': 50000},
    'muğla/milas': {'min': 18000, 'avg': 25000, 'max': 40000},
    'muğla/menteşe': {'min': 22000, 'avg': 32000, 'max': 52000},
    // DİYARBAKIR
    'diyarbakır/kayapınar': {'min': 12000, 'avg': 18000, 'max': 28000},
    'diyarbakır/bağlar': {'min': 8000, 'avg': 12000, 'max': 18000},
    'diyarbakır/yenişehir': {'min': 10000, 'avg': 16000, 'max': 25000},
    // DENİZLİ
    'denizli/merkezefendi': {'min': 14000, 'avg': 20000, 'max': 32000},
    'denizli/pamukkale': {'min': 12000, 'avg': 18000, 'max': 28000},
    // AYDIN
    'aydın/efeler': {'min': 16000, 'avg': 24000, 'max': 38000},
    'aydın/kuşadası': {'min': 28000, 'avg': 42000, 'max': 75000},
    'aydın/didim': {'min': 25000, 'avg': 38000, 'max': 65000},
    'aydın/söke': {'min': 12000, 'avg': 18000, 'max': 28000},
    // TEKİRDAĞ
    'tekirdağ/süleymanpaşa': {'min': 18000, 'avg': 26000, 'max': 42000},
    'tekirdağ/çorlu': {'min': 18000, 'avg': 26000, 'max': 40000},
    'tekirdağ/çerkezköy': {'min': 16000, 'avg': 22000, 'max': 35000},
    // SAKARYA
    'sakarya/serdivan': {'min': 18000, 'avg': 28000, 'max': 42000},
    'sakarya/adapazarı': {'min': 14000, 'avg': 20000, 'max': 32000},
    'sakarya/erenler': {'min': 12000, 'avg': 18000, 'max': 28000},
    // BALIKESİR
    'balıkesir/altıeylül': {'min': 14000, 'avg': 20000, 'max': 32000},
    'balıkesir/karesi': {'min': 12000, 'avg': 18000, 'max': 28000},
    'balıkesir/ayvalık': {'min': 22000, 'avg': 32000, 'max': 55000},
    'balıkesir/edremit': {'min': 18000, 'avg': 28000, 'max': 45000},
    'balıkesir/bandırma': {'min': 14000, 'avg': 20000, 'max': 32000},
  };
}
