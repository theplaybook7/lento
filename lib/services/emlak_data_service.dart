/// Emlak piyasa verileri servisi
/// İlçe bazında SIFIR BİNA m² satış fiyatları, kat ve tip çarpanları
/// 2025-2026 güncel sıfır bina fiyatları baz alınmıştır
class EmlakDataService {
  // ── Kat Çarpanları ──
  static double katCarpani(int kat, {int toplamKat = 5}) {
    if (kat <= -1) return 0.78; // Bodrum
    if (kat == 0) return 0.90; // Zemin
    if (kat == 1) return 1.0; // 1. kat (referans)
    if (kat == 2) return 1.03;
    if (kat == 3) return 1.05;
    if (kat == 4) return 1.07;
    if (kat == 5) return 1.09;
    if (kat >= toplamKat && kat >= 6) return 1.15; // Çatı katı / penthouse
    return 1.0 + ((kat - 1) * 0.02);
  }

  // ── Daire Tipi Çarpanları ──
  static double tipCarpani(String tip) {
    switch (tip) {
      case 'Dubleks':
        return 1.20;
      case 'Ters Dubleks':
        return 1.10;
      case 'Depolu Dükkan':
        return 1.40;
      case 'Dükkan':
        return 1.35;
      case 'Ofis':
        return 1.12;
      case 'Daire':
      default:
        return 1.0;
    }
  }

  /// İlçe listesini döner
  static List<String> ilListesi() {
    final iller = _ilVerileri.keys.toList();
    iller.sort((a, b) => a.compareTo(b));
    return iller.map((il) => _capitalize(il)).toList();
  }

  /// Belirli bir il için ilçe listesini döner
  static List<String> ilceListesi(String il) {
    final normalIl = _normalize(il);
    final ilceler = <String>[];
    for (final key in _ilceVerileri.keys) {
      if (key.startsWith('$normalIl/')) {
        final ilce = key.substring(normalIl.length + 1);
        ilceler.add(_capitalize(ilce));
      }
    }
    ilceler.sort();
    return ilceler;
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

    // İnşaat süresi boyunca değer artışı (yıllık ~%15 konut değer artışı)
    final artis = 1.0 + (0.15 * insaatSuresi / 12);

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
    sb.writeln('Bölge Sıfır Bina m² Satış Fiyatları:');
    sb.writeln('  En Düşük: ${_fmtN(fiyat['min']!)} ₺/m²');
    sb.writeln('  Ortalama: ${_fmtN(fiyat['avg']!)} ₺/m²');
    sb.writeln('  En Yüksek: ${_fmtN(fiyat['max']!)} ₺/m²');
    sb.writeln();

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

      sb.writeln('  $tip ${m2.round()} m² (${_katAdi(kat)}): ${_fmtN(tahmin['minToplam']!)} ₺ - ${_fmtN(tahmin['maxToplam']!)} ₺');
    }

    sb.writeln();
    sb.writeln('Kat Etkileri:');
    sb.writeln('  Bodrum: -%22  |  Zemin: -%10  |  1. Kat: Referans');
    sb.writeln('  2. Kat: +%3  |  3. Kat: +%5  |  4. Kat: +%7  |  5+ Kat: +%9-15');
    sb.writeln();
    sb.writeln('Tip Etkileri:');
    sb.writeln('  Daire: Referans  |  Dubleks: +%20  |  Ters Dubleks: +%10');
    sb.writeln('  Dükkan: +%35  |  Depolu Dükkan: +%40  |  Ofis: +%12');
    sb.writeln();
    sb.writeln('⚠️ Fiyatlar sıfır bina bölge ortalamasına dayalı tahminlerdir.');

    return sb.toString();
  }

  static String _katAdi(int kat) {
    if (kat <= -1) return '${kat.abs()}. Bodrum';
    if (kat == 0) return 'Zemin';
    return '$kat. Kat';
  }

  static String _fmtN(double n) {
    return n.round().toString().replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]}.');
  }

  static String _normalize(String s) =>
      s.trim()
          .replaceAll('İ', 'i')
          .replaceAll('I', 'ı')
          .replaceAll('Ü', 'ü')
          .replaceAll('Ö', 'ö')
          .replaceAll('Ç', 'ç')
          .replaceAll('Ş', 'ş')
          .replaceAll('Ğ', 'ğ')
          .toLowerCase();

  static String _capitalize(String s) {
    if (s.isEmpty) return s;
    // Turkish capitalize
    final first = s[0];
    final upper = first == 'i' ? 'İ' : first == 'ı' ? 'I' : first.toUpperCase();
    return '$upper${s.substring(1)}';
  }

  static const Map<String, double> _varsayilan = {
    'min': 30000,
    'avg': 42000,
    'max': 58000,
  };

  // ── İl bazında SIFIR BİNA genel fiyatlar (2025-2026) ──
  static const Map<String, Map<String, double>> _ilVerileri = {
    'istanbul': {'min': 65000, 'avg': 95000, 'max': 200000},
    'ankara': {'min': 35000, 'avg': 52000, 'max': 95000},
    'izmir': {'min': 42000, 'avg': 62000, 'max': 120000},
    'bursa': {'min': 32000, 'avg': 48000, 'max': 85000},
    'antalya': {'min': 45000, 'avg': 68000, 'max': 140000},
    'konya': {'min': 25000, 'avg': 38000, 'max': 60000},
    'adana': {'min': 25000, 'avg': 35000, 'max': 55000},
    'gaziantep': {'min': 25000, 'avg': 38000, 'max': 60000},
    'kayseri': {'min': 22000, 'avg': 32000, 'max': 50000},
    'mersin': {'min': 28000, 'avg': 42000, 'max': 68000},
    'eskişehir': {'min': 28000, 'avg': 42000, 'max': 65000},
    'diyarbakır': {'min': 20000, 'avg': 30000, 'max': 45000},
    'samsun': {'min': 22000, 'avg': 32000, 'max': 50000},
    'denizli': {'min': 24000, 'avg': 35000, 'max': 55000},
    'muğla': {'min': 55000, 'avg': 80000, 'max': 160000},
    'trabzon': {'min': 28000, 'avg': 42000, 'max': 68000},
    'kocaeli': {'min': 35000, 'avg': 50000, 'max': 80000},
    'sakarya': {'min': 28000, 'avg': 42000, 'max': 65000},
    'tekirdağ': {'min': 30000, 'avg': 45000, 'max': 68000},
    'balıkesir': {'min': 24000, 'avg': 35000, 'max': 58000},
    'aydın': {'min': 30000, 'avg': 45000, 'max': 72000},
    'çanakkale': {'min': 32000, 'avg': 48000, 'max': 75000},
    'yalova': {'min': 35000, 'avg': 48000, 'max': 75000},
    'bolu': {'min': 25000, 'avg': 35000, 'max': 55000},
    'düzce': {'min': 22000, 'avg': 32000, 'max': 50000},
    'edirne': {'min': 24000, 'avg': 35000, 'max': 55000},
    'manisa': {'min': 22000, 'avg': 32000, 'max': 50000},
    'hatay': {'min': 20000, 'avg': 30000, 'max': 45000},
    'malatya': {'min': 18000, 'avg': 28000, 'max': 42000},
    'van': {'min': 16000, 'avg': 25000, 'max': 38000},
    'şanlıurfa': {'min': 18000, 'avg': 28000, 'max': 42000},
    'erzurum': {'min': 20000, 'avg': 30000, 'max': 45000},
    'elazığ': {'min': 20000, 'avg': 30000, 'max': 45000},
    'sivas': {'min': 18000, 'avg': 28000, 'max': 42000},
    'zonguldak': {'min': 22000, 'avg': 32000, 'max': 50000},
    'karabük': {'min': 22000, 'avg': 30000, 'max': 46000},
    'bartın': {'min': 20000, 'avg': 28000, 'max': 42000},
    'rize': {'min': 25000, 'avg': 35000, 'max': 55000},
    'ordu': {'min': 22000, 'avg': 32000, 'max': 50000},
    'giresun': {'min': 22000, 'avg': 30000, 'max': 46000},
    'artvin': {'min': 22000, 'avg': 30000, 'max': 46000},
    'isparta': {'min': 22000, 'avg': 30000, 'max': 46000},
    'burdur': {'min': 20000, 'avg': 28000, 'max': 42000},
    'afyonkarahisar': {'min': 20000, 'avg': 28000, 'max': 42000},
    'kütahya': {'min': 18000, 'avg': 26000, 'max': 40000},
    'uşak': {'min': 20000, 'avg': 28000, 'max': 42000},
    'bilecik': {'min': 22000, 'avg': 30000, 'max': 46000},
    'çorum': {'min': 18000, 'avg': 26000, 'max': 40000},
    'amasya': {'min': 20000, 'avg': 28000, 'max': 42000},
    'tokat': {'min': 16000, 'avg': 25000, 'max': 38000},
    'sinop': {'min': 22000, 'avg': 30000, 'max': 46000},
    'kastamonu': {'min': 16000, 'avg': 25000, 'max': 38000},
    'nevşehir': {'min': 20000, 'avg': 28000, 'max': 42000},
    'kırşehir': {'min': 18000, 'avg': 26000, 'max': 40000},
    'aksaray': {'min': 18000, 'avg': 26000, 'max': 40000},
    'niğde': {'min': 16000, 'avg': 25000, 'max': 38000},
    'karaman': {'min': 18000, 'avg': 26000, 'max': 40000},
    'yozgat': {'min': 16000, 'avg': 25000, 'max': 38000},
    'çankırı': {'min': 16000, 'avg': 25000, 'max': 38000},
    'kırıkkale': {'min': 18000, 'avg': 26000, 'max': 40000},
    'osmaniye': {'min': 18000, 'avg': 26000, 'max': 40000},
    'kahramanmaraş': {'min': 18000, 'avg': 26000, 'max': 40000},
    'adıyaman': {'min': 16000, 'avg': 25000, 'max': 38000},
    'batman': {'min': 16000, 'avg': 25000, 'max': 38000},
    'mardin': {'min': 16000, 'avg': 25000, 'max': 38000},
    'şırnak': {'min': 14000, 'avg': 22000, 'max': 34000},
    'siirt': {'min': 14000, 'avg': 22000, 'max': 34000},
    'bingöl': {'min': 14000, 'avg': 22000, 'max': 34000},
    'bitlis': {'min': 12000, 'avg': 20000, 'max': 32000},
    'muş': {'min': 12000, 'avg': 20000, 'max': 32000},
    'hakkari': {'min': 12000, 'avg': 20000, 'max': 32000},
    'tunceli': {'min': 16000, 'avg': 25000, 'max': 38000},
    'ağrı': {'min': 12000, 'avg': 20000, 'max': 32000},
    'iğdır': {'min': 12000, 'avg': 20000, 'max': 32000},
    'kars': {'min': 12000, 'avg': 20000, 'max': 32000},
    'ardahan': {'min': 12000, 'avg': 20000, 'max': 32000},
    'bayburt': {'min': 14000, 'avg': 22000, 'max': 34000},
    'gümüşhane': {'min': 16000, 'avg': 25000, 'max': 38000},
    'kilis': {'min': 16000, 'avg': 25000, 'max': 38000},
    'erzincan': {'min': 18000, 'avg': 28000, 'max': 42000},
    'kırklareli': {'min': 24000, 'avg': 35000, 'max': 55000},
  };

  // ── İlçe bazında SIFIR BİNA detaylı fiyatlar {min, avg, max} TL/m² (2025-2026) ──
  static const Map<String, Map<String, double>> _ilceVerileri = {
    // İSTANBUL — Sıfır Bina Fiyatları
    'istanbul/kadıköy': {'min': 110000, 'avg': 155000, 'max': 250000},
    'istanbul/beşiktaş': {'min': 140000, 'avg': 200000, 'max': 350000},
    'istanbul/şişli': {'min': 100000, 'avg': 150000, 'max': 270000},
    'istanbul/beyoğlu': {'min': 90000, 'avg': 130000, 'max': 230000},
    'istanbul/üsküdar': {'min': 85000, 'avg': 120000, 'max': 200000},
    'istanbul/ataşehir': {'min': 85000, 'avg': 125000, 'max': 210000},
    'istanbul/maltepe': {'min': 70000, 'avg': 100000, 'max': 165000},
    'istanbul/kartal': {'min': 60000, 'avg': 88000, 'max': 140000},
    'istanbul/pendik': {'min': 52000, 'avg': 78000, 'max': 120000},
    'istanbul/tuzla': {'min': 48000, 'avg': 70000, 'max': 108000},
    'istanbul/bakırköy': {'min': 100000, 'avg': 145000, 'max': 250000},
    'istanbul/bahçelievler': {'min': 65000, 'avg': 92000, 'max': 140000},
    'istanbul/bağcılar': {'min': 52000, 'avg': 75000, 'max': 110000},
    'istanbul/güngören': {'min': 55000, 'avg': 78000, 'max': 115000},
    'istanbul/zeytinburnu': {'min': 70000, 'avg': 100000, 'max': 155000},
    'istanbul/fatih': {'min': 78000, 'avg': 110000, 'max': 175000},
    'istanbul/eyüpsultan': {'min': 55000, 'avg': 82000, 'max': 130000},
    'istanbul/beylikdüzü': {'min': 48000, 'avg': 70000, 'max': 108000},
    'istanbul/esenyurt': {'min': 35000, 'avg': 52000, 'max': 78000},
    'istanbul/avcılar': {'min': 48000, 'avg': 70000, 'max': 100000},
    'istanbul/küçükçekmece': {'min': 48000, 'avg': 70000, 'max': 100000},
    'istanbul/başakşehir': {'min': 58000, 'avg': 92000, 'max': 148000},
    'istanbul/sarıyer': {'min': 100000, 'avg': 165000, 'max': 320000},
    'istanbul/beykoz': {'min': 85000, 'avg': 128000, 'max': 240000},
    'istanbul/çekmeköy': {'min': 52000, 'avg': 78000, 'max': 120000},
    'istanbul/sancaktepe': {'min': 42000, 'avg': 65000, 'max': 95000},
    'istanbul/sultanbeyli': {'min': 35000, 'avg': 52000, 'max': 78000},
    'istanbul/ümraniye': {'min': 65000, 'avg': 95000, 'max': 148000},
    'istanbul/kağıthane': {'min': 70000, 'avg': 100000, 'max': 155000},
    'istanbul/gaziosmanpaşa': {'min': 48000, 'avg': 70000, 'max': 100000},
    'istanbul/esenler': {'min': 42000, 'avg': 60000, 'max': 88000},
    'istanbul/bayrampaşa': {'min': 58000, 'avg': 82000, 'max': 120000},
    'istanbul/sultangazi': {'min': 42000, 'avg': 60000, 'max': 88000},
    'istanbul/arnavutköy': {'min': 30000, 'avg': 48000, 'max': 72000},
    'istanbul/silivri': {'min': 30000, 'avg': 42000, 'max': 65000},
    'istanbul/çatalca': {'min': 25000, 'avg': 35000, 'max': 52000},
    'istanbul/büyükçekmece': {'min': 42000, 'avg': 65000, 'max': 100000},
    'istanbul/adalar': {'min': 75000, 'avg': 120000, 'max': 220000},
    // ANKARA — Sıfır Bina Fiyatları
    'ankara/çankaya': {'min': 58000, 'avg': 92000, 'max': 175000},
    'ankara/keçiören': {'min': 30000, 'avg': 42000, 'max': 65000},
    'ankara/yenimahalle': {'min': 38000, 'avg': 55000, 'max': 90000},
    'ankara/etimesgut': {'min': 35000, 'avg': 52000, 'max': 78000},
    'ankara/mamak': {'min': 25000, 'avg': 35000, 'max': 52000},
    'ankara/sincan': {'min': 25000, 'avg': 35000, 'max': 52000},
    'ankara/altındağ': {'min': 25000, 'avg': 35000, 'max': 52000},
    'ankara/pursaklar': {'min': 28000, 'avg': 42000, 'max': 60000},
    'ankara/gölbaşı': {'min': 38000, 'avg': 58000, 'max': 95000},
    'ankara/beypazarı': {'min': 18000, 'avg': 25000, 'max': 38000},
    'ankara/polatlı': {'min': 18000, 'avg': 25000, 'max': 38000},
    // İZMİR — Sıfır Bina Fiyatları
    'izmir/konak': {'min': 52000, 'avg': 78000, 'max': 128000},
    'izmir/bornova': {'min': 48000, 'avg': 65000, 'max': 100000},
    'izmir/karşıyaka': {'min': 55000, 'avg': 82000, 'max': 138000},
    'izmir/buca': {'min': 38000, 'avg': 52000, 'max': 78000},
    'izmir/bayraklı': {'min': 42000, 'avg': 60000, 'max': 92000},
    'izmir/çiğli': {'min': 35000, 'avg': 48000, 'max': 75000},
    'izmir/gaziemir': {'min': 38000, 'avg': 55000, 'max': 82000},
    'izmir/narlıdere': {'min': 65000, 'avg': 100000, 'max': 175000},
    'izmir/balçova': {'min': 55000, 'avg': 88000, 'max': 148000},
    'izmir/çeşme': {'min': 85000, 'avg': 138000, 'max': 275000},
    'izmir/urla': {'min': 65000, 'avg': 100000, 'max': 175000},
    'izmir/seferihisar': {'min': 52000, 'avg': 78000, 'max': 128000},
    'izmir/karabağlar': {'min': 35000, 'avg': 48000, 'max': 75000},
    'izmir/torbalı': {'min': 28000, 'avg': 38000, 'max': 58000},
    'izmir/menemen': {'min': 28000, 'avg': 38000, 'max': 58000},
    // ANTALYA — Sıfır Bina Fiyatları
    'antalya/muratpaşa': {'min': 65000, 'avg': 95000, 'max': 165000},
    'antalya/konyaaltı': {'min': 75000, 'avg': 110000, 'max': 200000},
    'antalya/kepez': {'min': 35000, 'avg': 52000, 'max': 78000},
    'antalya/döşemealtı': {'min': 38000, 'avg': 55000, 'max': 88000},
    'antalya/aksu': {'min': 35000, 'avg': 48000, 'max': 72000},
    'antalya/alanya': {'min': 55000, 'avg': 82000, 'max': 155000},
    'antalya/manavgat': {'min': 35000, 'avg': 52000, 'max': 82000},
    'antalya/kaş': {'min': 65000, 'avg': 100000, 'max': 185000},
    // BURSA — Sıfır Bina Fiyatları
    'bursa/osmangazi': {'min': 35000, 'avg': 52000, 'max': 88000},
    'bursa/nilüfer': {'min': 48000, 'avg': 72000, 'max': 120000},
    'bursa/yıldırım': {'min': 28000, 'avg': 38000, 'max': 60000},
    'bursa/görükle': {'min': 35000, 'avg': 52000, 'max': 78000},
    'bursa/mudanya': {'min': 42000, 'avg': 60000, 'max': 100000},
    'bursa/gemlik': {'min': 28000, 'avg': 38000, 'max': 60000},
    // KOCAELİ — Sıfır Bina Fiyatları
    'kocaeli/izmit': {'min': 38000, 'avg': 55000, 'max': 88000},
    'kocaeli/gebze': {'min': 42000, 'avg': 60000, 'max': 92000},
    'kocaeli/darıca': {'min': 35000, 'avg': 48000, 'max': 75000},
    'kocaeli/körfez': {'min': 30000, 'avg': 42000, 'max': 65000},
    'kocaeli/derince': {'min': 30000, 'avg': 45000, 'max': 70000},
    // GAZİANTEP — Sıfır Bina Fiyatları
    'gaziantep/şahinbey': {'min': 25000, 'avg': 38000, 'max': 58000},
    'gaziantep/şehitkamil': {'min': 28000, 'avg': 42000, 'max': 68000},
    // KONYA — Sıfır Bina Fiyatları
    'konya/selçuklu': {'min': 28000, 'avg': 42000, 'max': 68000},
    'konya/meram': {'min': 25000, 'avg': 35000, 'max': 58000},
    'konya/karatay': {'min': 22000, 'avg': 30000, 'max': 48000},
    // MERSİN — Sıfır Bina Fiyatları
    'mersin/yenişehir': {'min': 35000, 'avg': 52000, 'max': 82000},
    'mersin/mezitli': {'min': 38000, 'avg': 55000, 'max': 88000},
    'mersin/akdeniz': {'min': 25000, 'avg': 35000, 'max': 52000},
    'mersin/toroslar': {'min': 28000, 'avg': 38000, 'max': 58000},
    // ADANA — Sıfır Bina Fiyatları
    'adana/seyhan': {'min': 28000, 'avg': 38000, 'max': 60000},
    'adana/çukurova': {'min': 32000, 'avg': 45000, 'max': 72000},
    'adana/yüreğir': {'min': 22000, 'avg': 28000, 'max': 42000},
    'adana/sarıçam': {'min': 25000, 'avg': 35000, 'max': 52000},
    // ESKİŞEHİR — Sıfır Bina Fiyatları
    'eskişehir/tepebaşı': {'min': 32000, 'avg': 45000, 'max': 70000},
    'eskişehir/odunpazarı': {'min': 28000, 'avg': 38000, 'max': 60000},
    // KAYSERİ — Sıfır Bina Fiyatları
    'kayseri/melikgazi': {'min': 25000, 'avg': 35000, 'max': 52000},
    'kayseri/kocasinan': {'min': 22000, 'avg': 30000, 'max': 48000},
    'kayseri/talas': {'min': 28000, 'avg': 42000, 'max': 65000},
    // TRABZON — Sıfır Bina Fiyatları
    'trabzon/ortahisar': {'min': 32000, 'avg': 45000, 'max': 72000},
    'trabzon/akçaabat': {'min': 25000, 'avg': 35000, 'max': 52000},
    'trabzon/yomra': {'min': 25000, 'avg': 35000, 'max': 52000},
    // SAMSUN — Sıfır Bina Fiyatları
    'samsun/atakum': {'min': 28000, 'avg': 42000, 'max': 65000},
    'samsun/ilkadım': {'min': 25000, 'avg': 35000, 'max': 52000},
    'samsun/canik': {'min': 22000, 'avg': 30000, 'max': 48000},
    // MUĞLA — Sıfır Bina Fiyatları
    'muğla/bodrum': {'min': 95000, 'avg': 148000, 'max': 320000},
    'muğla/fethiye': {'min': 65000, 'avg': 100000, 'max': 200000},
    'muğla/marmaris': {'min': 65000, 'avg': 95000, 'max': 185000},
    'muğla/dalaman': {'min': 38000, 'avg': 55000, 'max': 92000},
    'muğla/milas': {'min': 35000, 'avg': 48000, 'max': 75000},
    'muğla/menteşe': {'min': 42000, 'avg': 60000, 'max': 95000},
    // DİYARBAKIR — Sıfır Bina Fiyatları
    'diyarbakır/kayapınar': {'min': 25000, 'avg': 35000, 'max': 52000},
    'diyarbakır/bağlar': {'min': 18000, 'avg': 25000, 'max': 38000},
    'diyarbakır/yenişehir': {'min': 22000, 'avg': 32000, 'max': 48000},
    // DENİZLİ — Sıfır Bina Fiyatları
    'denizli/merkezefendi': {'min': 28000, 'avg': 38000, 'max': 60000},
    'denizli/pamukkale': {'min': 25000, 'avg': 35000, 'max': 52000},
    // AYDIN — Sıfır Bina Fiyatları
    'aydın/efeler': {'min': 32000, 'avg': 45000, 'max': 70000},
    'aydın/kuşadası': {'min': 52000, 'avg': 78000, 'max': 138000},
    'aydın/didim': {'min': 48000, 'avg': 72000, 'max': 120000},
    'aydın/söke': {'min': 25000, 'avg': 35000, 'max': 52000},
    // TEKİRDAĞ — Sıfır Bina Fiyatları
    'tekirdağ/süleymanpaşa': {'min': 35000, 'avg': 48000, 'max': 78000},
    'tekirdağ/çorlu': {'min': 35000, 'avg': 48000, 'max': 75000},
    'tekirdağ/çerkezköy': {'min': 32000, 'avg': 42000, 'max': 65000},
    // SAKARYA — Sıfır Bina Fiyatları
    'sakarya/serdivan': {'min': 35000, 'avg': 52000, 'max': 78000},
    'sakarya/adapazarı': {'min': 28000, 'avg': 38000, 'max': 60000},
    'sakarya/erenler': {'min': 25000, 'avg': 35000, 'max': 52000},
    // BALIKESİR — Sıfır Bina Fiyatları
    'balıkesir/altıeylül': {'min': 28000, 'avg': 38000, 'max': 60000},
    'balıkesir/karesi': {'min': 25000, 'avg': 35000, 'max': 52000},
    'balıkesir/ayvalık': {'min': 42000, 'avg': 60000, 'max': 100000},
    'balıkesir/edremit': {'min': 35000, 'avg': 52000, 'max': 82000},
    'balıkesir/bandırma': {'min': 28000, 'avg': 38000, 'max': 60000},
  };
}
