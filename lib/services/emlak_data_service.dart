/// Emlak piyasa verileri servisi
/// İstanbul ilçe ve mahalle bazında SIFIR BİNA m² satış fiyatları
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

  /// İl listesi (sadece İstanbul)
  static List<String> ilListesi() => ['İstanbul'];

  /// İlçe listesi
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

  /// Mahalle listesi
  static List<String> mahalleListesi(String il, String ilce) {
    final prefix = '${_normalize(il)}/${_normalize(ilce)}/';
    final mahalleler = <String>[];
    for (final key in _mahalleVerileri.keys) {
      if (key.startsWith(prefix)) {
        final mahalle = key.substring(prefix.length);
        mahalleler.add(_capitalize(mahalle));
      }
    }
    mahalleler.sort();
    return mahalleler;
  }

  /// İlçe/mahalle bazında m² fiyat verisini döner {min, avg, max}
  static Map<String, double> ilceM2Fiyat(String il, String ilce, {String? mahalle}) {
    if (mahalle != null && mahalle.isNotEmpty) {
      final mahalleKey = '${_normalize(il)}/${_normalize(ilce)}/${_normalize(mahalle)}';
      if (_mahalleVerileri.containsKey(mahalleKey)) {
        return _mahalleVerileri[mahalleKey]!;
      }
    }
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
    String? mahalle,
  }) {
    final bazFiyat = ilceM2Fiyat(il, ilce, mahalle: mahalle);
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
    final fiyat = ilceM2Fiyat(il, ilce, mahalle: mahalle);
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
        mahalle: mahalle,
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
    final first = s[0];
    final upper = first == 'i' ? 'İ' : first == 'ı' ? 'I' : first.toUpperCase();
    return '$upper${s.substring(1)}';
  }

  static const Map<String, double> _varsayilan = {
    'min': 30000,
    'avg': 42000,
    'max': 58000,
  };

  // ── İl bazında genel fiyatlar ──
  static const Map<String, Map<String, double>> _ilVerileri = {
    'istanbul': {'min': 65000, 'avg': 95000, 'max': 200000},
  };

  // ── İlçe bazında SIFIR BİNA fiyatlar ──
  static const Map<String, Map<String, double>> _ilceVerileri = {
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
  };

  // ── Mahalle bazında SIFIR BİNA fiyatlar (İstanbul) ──
  static const Map<String, Map<String, double>> _mahalleVerileri = {
    // KADIKÖY
    'istanbul/kadıköy/caferağa': {'min': 140000, 'avg': 180000, 'max': 280000},
    'istanbul/kadıköy/moda': {'min': 160000, 'avg': 200000, 'max': 310000},
    'istanbul/kadıköy/fenerbahçe': {'min': 155000, 'avg': 195000, 'max': 300000},
    'istanbul/kadıköy/suadiye': {'min': 145000, 'avg': 190000, 'max': 280000},
    'istanbul/kadıköy/bostancı': {'min': 120000, 'avg': 160000, 'max': 240000},
    'istanbul/kadıköy/kozyatağı': {'min': 105000, 'avg': 145000, 'max': 220000},
    'istanbul/kadıköy/göztepe': {'min': 110000, 'avg': 150000, 'max': 230000},
    'istanbul/kadıköy/erenköy': {'min': 130000, 'avg': 170000, 'max': 260000},
    'istanbul/kadıköy/acıbadem': {'min': 120000, 'avg': 165000, 'max': 250000},
    'istanbul/kadıköy/fikirtepe': {'min': 90000, 'avg': 125000, 'max': 195000},
    'istanbul/kadıköy/rasimpaşa': {'min': 130000, 'avg': 165000, 'max': 255000},
    // BEŞİKTAŞ
    'istanbul/beşiktaş/etiler': {'min': 200000, 'avg': 280000, 'max': 420000},
    'istanbul/beşiktaş/levent': {'min': 185000, 'avg': 260000, 'max': 400000},
    'istanbul/beşiktaş/bebek': {'min': 230000, 'avg': 320000, 'max': 500000},
    'istanbul/beşiktaş/ulus': {'min': 180000, 'avg': 250000, 'max': 380000},
    'istanbul/beşiktaş/ortaköy': {'min': 160000, 'avg': 220000, 'max': 340000},
    'istanbul/beşiktaş/akatlar': {'min': 150000, 'avg': 200000, 'max': 300000},
    'istanbul/beşiktaş/türkali': {'min': 130000, 'avg': 175000, 'max': 270000},
    'istanbul/beşiktaş/sinanpaşa': {'min': 140000, 'avg': 185000, 'max': 290000},
    'istanbul/beşiktaş/arnavutköy': {'min': 165000, 'avg': 230000, 'max': 360000},
    // ŞİŞLİ
    'istanbul/şişli/nişantaşı': {'min': 160000, 'avg': 220000, 'max': 350000},
    'istanbul/şişli/teşvikiye': {'min': 150000, 'avg': 210000, 'max': 330000},
    'istanbul/şişli/osmanbey': {'min': 130000, 'avg': 180000, 'max': 280000},
    'istanbul/şişli/bomonti': {'min': 105000, 'avg': 150000, 'max': 235000},
    'istanbul/şişli/mecidiyeköy': {'min': 95000, 'avg': 135000, 'max': 215000},
    'istanbul/şişli/esentepe': {'min': 100000, 'avg': 140000, 'max': 220000},
    'istanbul/şişli/feriköy': {'min': 90000, 'avg': 130000, 'max': 205000},
    'istanbul/şişli/kuştepe': {'min': 65000, 'avg': 90000, 'max': 145000},
    'istanbul/şişli/halaskargazi': {'min': 110000, 'avg': 155000, 'max': 245000},
    // BEYOĞLU
    'istanbul/beyoğlu/cihangir': {'min': 130000, 'avg': 175000, 'max': 280000},
    'istanbul/beyoğlu/galata': {'min': 120000, 'avg': 165000, 'max': 265000},
    'istanbul/beyoğlu/taksim': {'min': 105000, 'avg': 145000, 'max': 235000},
    'istanbul/beyoğlu/tarlabaşı': {'min': 70000, 'avg': 95000, 'max': 155000},
    'istanbul/beyoğlu/kasımpaşa': {'min': 75000, 'avg': 105000, 'max': 170000},
    'istanbul/beyoğlu/piyalepaşa': {'min': 85000, 'avg': 120000, 'max': 190000},
    // ÜSKÜDAR
    'istanbul/üsküdar/kuzguncuk': {'min': 120000, 'avg': 160000, 'max': 255000},
    'istanbul/üsküdar/çengelköy': {'min': 130000, 'avg': 170000, 'max': 270000},
    'istanbul/üsküdar/beylerbeyi': {'min': 115000, 'avg': 155000, 'max': 245000},
    'istanbul/üsküdar/altunizade': {'min': 100000, 'avg': 140000, 'max': 220000},
    'istanbul/üsküdar/acıbadem': {'min': 95000, 'avg': 130000, 'max': 205000},
    'istanbul/üsküdar/bulgurlu': {'min': 75000, 'avg': 105000, 'max': 165000},
    'istanbul/üsküdar/ünalan': {'min': 70000, 'avg': 98000, 'max': 155000},
    // ATAŞEHİR
    'istanbul/ataşehir/küçükbakkalköy': {'min': 90000, 'avg': 130000, 'max': 200000},
    'istanbul/ataşehir/içerenköy': {'min': 80000, 'avg': 115000, 'max': 180000},
    'istanbul/ataşehir/yenisahra': {'min': 72000, 'avg': 105000, 'max': 165000},
    'istanbul/ataşehir/kayışdağı': {'min': 70000, 'avg': 100000, 'max': 158000},
    'istanbul/ataşehir/barbaros': {'min': 85000, 'avg': 125000, 'max': 195000},
    'istanbul/ataşehir/ferhatpaşa': {'min': 65000, 'avg': 95000, 'max': 150000},
    'istanbul/ataşehir/esatpaşa': {'min': 78000, 'avg': 110000, 'max': 175000},
    'istanbul/ataşehir/atatürk': {'min': 95000, 'avg': 135000, 'max': 210000},
    // MALTEPE
    'istanbul/maltepe/altıntepe': {'min': 80000, 'avg': 115000, 'max': 175000},
    'istanbul/maltepe/cevizli': {'min': 75000, 'avg': 108000, 'max': 165000},
    'istanbul/maltepe/idealtepe': {'min': 82000, 'avg': 118000, 'max': 180000},
    'istanbul/maltepe/küçükyalı': {'min': 78000, 'avg': 110000, 'max': 170000},
    'istanbul/maltepe/zümrütevler': {'min': 60000, 'avg': 85000, 'max': 135000},
    'istanbul/maltepe/fındıklı': {'min': 55000, 'avg': 80000, 'max': 125000},
    'istanbul/maltepe/aydınevler': {'min': 65000, 'avg': 92000, 'max': 145000},
    // KARTAL
    'istanbul/kartal/yakacık': {'min': 55000, 'avg': 80000, 'max': 128000},
    'istanbul/kartal/kordonboyu': {'min': 68000, 'avg': 95000, 'max': 150000},
    'istanbul/kartal/soğanlık': {'min': 50000, 'avg': 72000, 'max': 115000},
    'istanbul/kartal/uğurmumcu': {'min': 62000, 'avg': 90000, 'max': 140000},
    'istanbul/kartal/topselvi': {'min': 52000, 'avg': 75000, 'max': 120000},
    'istanbul/kartal/hürriyet': {'min': 55000, 'avg': 78000, 'max': 125000},
    // PENDİK
    'istanbul/pendik/kaynarca': {'min': 58000, 'avg': 82000, 'max': 128000},
    'istanbul/pendik/yenişehir': {'min': 52000, 'avg': 75000, 'max': 118000},
    'istanbul/pendik/kurtköy': {'min': 60000, 'avg': 88000, 'max': 138000},
    'istanbul/pendik/esenyalı': {'min': 45000, 'avg': 65000, 'max': 100000},
    'istanbul/pendik/velibaba': {'min': 42000, 'avg': 60000, 'max': 95000},
    'istanbul/pendik/batı': {'min': 50000, 'avg': 72000, 'max': 112000},
    // TUZLA
    'istanbul/tuzla/aydınlı': {'min': 50000, 'avg': 72000, 'max': 110000},
    'istanbul/tuzla/içmeler': {'min': 45000, 'avg': 65000, 'max': 100000},
    'istanbul/tuzla/postane': {'min': 55000, 'avg': 78000, 'max': 120000},
    'istanbul/tuzla/mimar sinan': {'min': 42000, 'avg': 62000, 'max': 95000},
    'istanbul/tuzla/orhanlı': {'min': 40000, 'avg': 58000, 'max': 90000},
    'istanbul/tuzla/şifa': {'min': 44000, 'avg': 63000, 'max': 98000},
    // BAKIRKÖY
    'istanbul/bakırköy/ataköy': {'min': 130000, 'avg': 185000, 'max': 290000},
    'istanbul/bakırköy/florya': {'min': 140000, 'avg': 195000, 'max': 310000},
    'istanbul/bakırköy/yeşilköy': {'min': 120000, 'avg': 175000, 'max': 275000},
    'istanbul/bakırköy/zuhuratbaba': {'min': 85000, 'avg': 120000, 'max': 190000},
    'istanbul/bakırköy/osmaniye': {'min': 80000, 'avg': 115000, 'max': 180000},
    'istanbul/bakırköy/kartaltepe': {'min': 92000, 'avg': 130000, 'max': 205000},
    'istanbul/bakırköy/cevizlik': {'min': 90000, 'avg': 128000, 'max': 200000},
    // BAHÇELİEVLER
    'istanbul/bahçelievler/bahçelievler': {'min': 72000, 'avg': 100000, 'max': 155000},
    'istanbul/bahçelievler/soğanlı': {'min': 60000, 'avg': 85000, 'max': 133000},
    'istanbul/bahçelievler/kocasinan': {'min': 65000, 'avg': 90000, 'max': 140000},
    'istanbul/bahçelievler/çobançeşme': {'min': 58000, 'avg': 82000, 'max': 128000},
    'istanbul/bahçelievler/hürriyet': {'min': 55000, 'avg': 78000, 'max': 120000},
    'istanbul/bahçelievler/yenibosna': {'min': 58000, 'avg': 82000, 'max': 128000},
    'istanbul/bahçelievler/şirinevler': {'min': 65000, 'avg': 92000, 'max': 142000},
    // BAĞCILAR
    'istanbul/bağcılar/güneşli': {'min': 58000, 'avg': 82000, 'max': 125000},
    'istanbul/bağcılar/mahmutbey': {'min': 52000, 'avg': 75000, 'max': 115000},
    'istanbul/bağcılar/kirazlı': {'min': 48000, 'avg': 68000, 'max': 108000},
    'istanbul/bağcılar/barbaros': {'min': 45000, 'avg': 65000, 'max': 100000},
    'istanbul/bağcılar/yıldıztepe': {'min': 42000, 'avg': 62000, 'max': 95000},
    'istanbul/bağcılar/kazım karabekir': {'min': 42000, 'avg': 60000, 'max': 92000},
    'istanbul/bağcılar/inönü': {'min': 40000, 'avg': 58000, 'max': 90000},
    // GÜNGÖREN
    'istanbul/güngören/merkez': {'min': 60000, 'avg': 85000, 'max': 130000},
    'istanbul/güngören/tozkoparan': {'min': 55000, 'avg': 78000, 'max': 120000},
    'istanbul/güngören/haznedar': {'min': 50000, 'avg': 72000, 'max': 112000},
    'istanbul/güngören/gençosman': {'min': 48000, 'avg': 68000, 'max': 105000},
    'istanbul/güngören/akıncılar': {'min': 50000, 'avg': 70000, 'max': 108000},
    // ZEYTİNBURNU
    'istanbul/zeytinburnu/merkezefendi': {'min': 78000, 'avg': 110000, 'max': 170000},
    'istanbul/zeytinburnu/beştelsiz': {'min': 68000, 'avg': 95000, 'max': 150000},
    'istanbul/zeytinburnu/nuripaşa': {'min': 62000, 'avg': 88000, 'max': 138000},
    'istanbul/zeytinburnu/telsiz': {'min': 58000, 'avg': 82000, 'max': 128000},
    'istanbul/zeytinburnu/sümer': {'min': 55000, 'avg': 78000, 'max': 120000},
    'istanbul/zeytinburnu/veliemine': {'min': 72000, 'avg': 100000, 'max': 158000},
    // FATİH
    'istanbul/fatih/sultanahmet': {'min': 100000, 'avg': 140000, 'max': 220000},
    'istanbul/fatih/vefa': {'min': 82000, 'avg': 115000, 'max': 180000},
    'istanbul/fatih/balat': {'min': 78000, 'avg': 108000, 'max': 170000},
    'istanbul/fatih/çarşamba': {'min': 72000, 'avg': 100000, 'max': 158000},
    'istanbul/fatih/karagümrük': {'min': 68000, 'avg': 95000, 'max': 150000},
    'istanbul/fatih/aksaray': {'min': 75000, 'avg': 105000, 'max': 165000},
    'istanbul/fatih/zeyrek': {'min': 70000, 'avg': 98000, 'max': 155000},
    // EYÜPSULTAN
    'istanbul/eyüpsultan/göktürk': {'min': 85000, 'avg': 125000, 'max': 195000},
    'istanbul/eyüpsultan/kemerburgaz': {'min': 75000, 'avg': 110000, 'max': 172000},
    'istanbul/eyüpsultan/alibeyköy': {'min': 58000, 'avg': 82000, 'max': 130000},
    'istanbul/eyüpsultan/rami': {'min': 50000, 'avg': 72000, 'max': 112000},
    'istanbul/eyüpsultan/yeşilpınar': {'min': 45000, 'avg': 65000, 'max': 102000},
    'istanbul/eyüpsultan/silahtarağa': {'min': 52000, 'avg': 75000, 'max': 118000},
    // BEYLİKDÜZÜ
    'istanbul/beylikdüzü/adnan kahveci': {'min': 55000, 'avg': 78000, 'max': 120000},
    'istanbul/beylikdüzü/barış': {'min': 50000, 'avg': 72000, 'max': 112000},
    'istanbul/beylikdüzü/büyükşehir': {'min': 46000, 'avg': 65000, 'max': 100000},
    'istanbul/beylikdüzü/cumhuriyet': {'min': 48000, 'avg': 68000, 'max': 105000},
    'istanbul/beylikdüzü/yakuplu': {'min': 45000, 'avg': 65000, 'max': 100000},
    'istanbul/beylikdüzü/kavaklı': {'min': 45000, 'avg': 63000, 'max': 98000},
    // ESENYURT
    'istanbul/esenyurt/ardıçlı': {'min': 38000, 'avg': 55000, 'max': 85000},
    'istanbul/esenyurt/fatih': {'min': 35000, 'avg': 50000, 'max': 78000},
    'istanbul/esenyurt/inönü': {'min': 32000, 'avg': 48000, 'max': 72000},
    'istanbul/esenyurt/mehterçeşme': {'min': 30000, 'avg': 45000, 'max': 68000},
    'istanbul/esenyurt/saadetdere': {'min': 28000, 'avg': 42000, 'max': 65000},
    'istanbul/esenyurt/yeşilkent': {'min': 33000, 'avg': 48000, 'max': 75000},
    'istanbul/esenyurt/namık kemal': {'min': 30000, 'avg': 45000, 'max': 70000},
    // AVCILAR
    'istanbul/avcılar/cihangir': {'min': 52000, 'avg': 75000, 'max': 115000},
    'istanbul/avcılar/merkez': {'min': 48000, 'avg': 70000, 'max': 108000},
    'istanbul/avcılar/ambarlı': {'min': 45000, 'avg': 65000, 'max': 100000},
    'istanbul/avcılar/firuzköy': {'min': 42000, 'avg': 60000, 'max': 92000},
    'istanbul/avcılar/denizköşkler': {'min': 44000, 'avg': 63000, 'max': 98000},
    // KÜÇÜKÇEKMECE
    'istanbul/küçükçekmece/atakent': {'min': 55000, 'avg': 78000, 'max': 120000},
    'istanbul/küçükçekmece/cennet': {'min': 50000, 'avg': 72000, 'max': 110000},
    'istanbul/küçükçekmece/halkalı': {'min': 58000, 'avg': 82000, 'max': 128000},
    'istanbul/küçükçekmece/inönü': {'min': 45000, 'avg': 65000, 'max': 100000},
    'istanbul/küçükçekmece/kanarya': {'min': 40000, 'avg': 58000, 'max': 90000},
    'istanbul/küçükçekmece/söğütlüçeşme': {'min': 42000, 'avg': 60000, 'max': 92000},
    // BAŞAKŞEHİR
    'istanbul/başakşehir/bahçeşehir 1. kısım': {'min': 78000, 'avg': 110000, 'max': 170000},
    'istanbul/başakşehir/bahçeşehir 2. kısım': {'min': 72000, 'avg': 102000, 'max': 158000},
    'istanbul/başakşehir/kayabaşı': {'min': 58000, 'avg': 82000, 'max': 128000},
    'istanbul/başakşehir/başak': {'min': 65000, 'avg': 92000, 'max': 142000},
    'istanbul/başakşehir/güvercintepe': {'min': 45000, 'avg': 65000, 'max': 100000},
    'istanbul/başakşehir/ziya gökalp': {'min': 52000, 'avg': 75000, 'max': 115000},
    // SARIYER
    'istanbul/sarıyer/istinye': {'min': 155000, 'avg': 215000, 'max': 360000},
    'istanbul/sarıyer/tarabya': {'min': 140000, 'avg': 195000, 'max': 320000},
    'istanbul/sarıyer/maslak': {'min': 130000, 'avg': 180000, 'max': 300000},
    'istanbul/sarıyer/emirgan': {'min': 145000, 'avg': 205000, 'max': 340000},
    'istanbul/sarıyer/yeniköy': {'min': 155000, 'avg': 220000, 'max': 365000},
    'istanbul/sarıyer/bahçeköy': {'min': 85000, 'avg': 120000, 'max': 195000},
    'istanbul/sarıyer/zekeriyaköy': {'min': 100000, 'avg': 140000, 'max': 225000},
    'istanbul/sarıyer/rumelihisarı': {'min': 140000, 'avg': 195000, 'max': 320000},
    // BEYKOZ
    'istanbul/beykoz/anadoluhisarı': {'min': 110000, 'avg': 155000, 'max': 250000},
    'istanbul/beykoz/çubuklu': {'min': 100000, 'avg': 140000, 'max': 225000},
    'istanbul/beykoz/kavacık': {'min': 95000, 'avg': 132000, 'max': 215000},
    'istanbul/beykoz/paşabahçe': {'min': 85000, 'avg': 118000, 'max': 190000},
    'istanbul/beykoz/riva': {'min': 68000, 'avg': 95000, 'max': 155000},
    'istanbul/beykoz/acarlar': {'min': 75000, 'avg': 105000, 'max': 170000},
    // ÇEKMEKÖY
    'istanbul/çekmeköy/merkez': {'min': 60000, 'avg': 85000, 'max': 132000},
    'istanbul/çekmeköy/alemdağ': {'min': 55000, 'avg': 78000, 'max': 120000},
    'istanbul/çekmeköy/hamidiye': {'min': 50000, 'avg': 72000, 'max': 112000},
    'istanbul/çekmeköy/ömerli': {'min': 45000, 'avg': 65000, 'max': 100000},
    'istanbul/çekmeköy/nişantepe': {'min': 50000, 'avg': 70000, 'max': 108000},
    // SANCAKTEPE
    'istanbul/sancaktepe/sarıgazi': {'min': 48000, 'avg': 70000, 'max': 108000},
    'istanbul/sancaktepe/samandıra': {'min': 45000, 'avg': 65000, 'max': 100000},
    'istanbul/sancaktepe/yenidoğan': {'min': 40000, 'avg': 58000, 'max': 90000},
    'istanbul/sancaktepe/inönü': {'min': 42000, 'avg': 60000, 'max': 92000},
    'istanbul/sancaktepe/akpınar': {'min': 44000, 'avg': 62000, 'max': 95000},
    // SULTANBEYLİ
    'istanbul/sultanbeyli/battalgazi': {'min': 38000, 'avg': 55000, 'max': 85000},
    'istanbul/sultanbeyli/fatih': {'min': 35000, 'avg': 52000, 'max': 80000},
    'istanbul/sultanbeyli/mehmet akif': {'min': 32000, 'avg': 48000, 'max': 75000},
    'istanbul/sultanbeyli/necip fazıl': {'min': 30000, 'avg': 45000, 'max': 72000},
    'istanbul/sultanbeyli/hasanpaşa': {'min': 35000, 'avg': 50000, 'max': 78000},
    // ÜMRANİYE
    'istanbul/ümraniye/atatürk': {'min': 72000, 'avg': 105000, 'max': 162000},
    'istanbul/ümraniye/çakmak': {'min': 65000, 'avg': 92000, 'max': 145000},
    'istanbul/ümraniye/hekimbaşı': {'min': 60000, 'avg': 85000, 'max': 135000},
    'istanbul/ümraniye/istiklal': {'min': 58000, 'avg': 82000, 'max': 128000},
    'istanbul/ümraniye/site': {'min': 68000, 'avg': 98000, 'max': 152000},
    'istanbul/ümraniye/tantavi': {'min': 58000, 'avg': 82000, 'max': 128000},
    'istanbul/ümraniye/parseller': {'min': 55000, 'avg': 78000, 'max': 120000},
    // KAĞITHANE
    'istanbul/kağıthane/çağlayan': {'min': 75000, 'avg': 108000, 'max': 168000},
    'istanbul/kağıthane/gültepe': {'min': 65000, 'avg': 95000, 'max': 148000},
    'istanbul/kağıthane/hamidiye': {'min': 70000, 'avg': 100000, 'max': 155000},
    'istanbul/kağıthane/seyrantepe': {'min': 80000, 'avg': 115000, 'max': 178000},
    'istanbul/kağıthane/hürriyet': {'min': 58000, 'avg': 82000, 'max': 128000},
    'istanbul/kağıthane/yahya kemal': {'min': 55000, 'avg': 78000, 'max': 120000},
    // GAZİOSMANPAŞA
    'istanbul/gaziosmanpaşa/bağlarbaşı': {'min': 50000, 'avg': 72000, 'max': 112000},
    'istanbul/gaziosmanpaşa/merkez': {'min': 55000, 'avg': 78000, 'max': 120000},
    'istanbul/gaziosmanpaşa/karlıtepe': {'min': 45000, 'avg': 65000, 'max': 100000},
    'istanbul/gaziosmanpaşa/karayolları': {'min': 48000, 'avg': 68000, 'max': 105000},
    'istanbul/gaziosmanpaşa/yıldıztabya': {'min': 45000, 'avg': 65000, 'max': 100000},
    // ESENLER
    'istanbul/esenler/davutpaşa': {'min': 45000, 'avg': 65000, 'max': 100000},
    'istanbul/esenler/fevzi çakmak': {'min': 40000, 'avg': 58000, 'max': 90000},
    'istanbul/esenler/oruçreis': {'min': 38000, 'avg': 55000, 'max': 85000},
    'istanbul/esenler/kazım karabekir': {'min': 38000, 'avg': 55000, 'max': 85000},
    'istanbul/esenler/havaalanı': {'min': 35000, 'avg': 50000, 'max': 78000},
    // BAYRAMPAŞA
    'istanbul/bayrampaşa/yıldırım': {'min': 62000, 'avg': 88000, 'max': 138000},
    'istanbul/bayrampaşa/kocatepe': {'min': 55000, 'avg': 78000, 'max': 120000},
    'istanbul/bayrampaşa/muratpaşa': {'min': 50000, 'avg': 72000, 'max': 112000},
    'istanbul/bayrampaşa/ismetpaşa': {'min': 56000, 'avg': 80000, 'max': 125000},
    'istanbul/bayrampaşa/vatan': {'min': 52000, 'avg': 75000, 'max': 118000},
    // SULTANGAZİ
    'istanbul/sultangazi/esentepe': {'min': 45000, 'avg': 65000, 'max': 100000},
    'istanbul/sultangazi/cebeci': {'min': 40000, 'avg': 55000, 'max': 85000},
    'istanbul/sultangazi/habipler': {'min': 38000, 'avg': 52000, 'max': 82000},
    'istanbul/sultangazi/50. yıl': {'min': 42000, 'avg': 58000, 'max': 92000},
    'istanbul/sultangazi/ismetpaşa': {'min': 40000, 'avg': 56000, 'max': 88000},
    'istanbul/sultangazi/zübeyde hanım': {'min': 44000, 'avg': 62000, 'max': 95000},
    // ARNAVUTKÖY
    'istanbul/arnavutköy/hadımköy': {'min': 38000, 'avg': 55000, 'max': 85000},
    'istanbul/arnavutköy/bolluca': {'min': 35000, 'avg': 50000, 'max': 78000},
    'istanbul/arnavutköy/merkez': {'min': 32000, 'avg': 48000, 'max': 75000},
    'istanbul/arnavutköy/taşoluk': {'min': 30000, 'avg': 45000, 'max': 72000},
    'istanbul/arnavutköy/dursunköy': {'min': 28000, 'avg': 42000, 'max': 65000},
    'istanbul/arnavutköy/yeşilbayır': {'min': 28000, 'avg': 40000, 'max': 62000},
    // SİLİVRİ
    'istanbul/silivri/merkez': {'min': 32000, 'avg': 45000, 'max': 70000},
    'istanbul/silivri/selimpaşa': {'min': 35000, 'avg': 48000, 'max': 75000},
    'istanbul/silivri/gümüşyaka': {'min': 30000, 'avg': 42000, 'max': 65000},
    'istanbul/silivri/kavaklı': {'min': 28000, 'avg': 38000, 'max': 60000},
    'istanbul/silivri/değirmenköy': {'min': 25000, 'avg': 35000, 'max': 55000},
    // ÇATALCA
    'istanbul/çatalca/merkez': {'min': 27000, 'avg': 38000, 'max': 58000},
    'istanbul/çatalca/ferhatpaşa': {'min': 22000, 'avg': 32000, 'max': 50000},
    'istanbul/çatalca/kaleiçi': {'min': 25000, 'avg': 35000, 'max': 55000},
    // BÜYÜKÇEKMECE
    'istanbul/büyükçekmece/mimaroba': {'min': 48000, 'avg': 68000, 'max': 105000},
    'istanbul/büyükçekmece/kumburgaz': {'min': 50000, 'avg': 72000, 'max': 112000},
    'istanbul/büyükçekmece/merkez': {'min': 48000, 'avg': 68000, 'max': 105000},
    'istanbul/büyükçekmece/batıköy': {'min': 45000, 'avg': 63000, 'max': 98000},
    'istanbul/büyükçekmece/bahçelievler': {'min': 42000, 'avg': 60000, 'max': 92000},
    // ADALAR
    'istanbul/adalar/büyükada': {'min': 110000, 'avg': 165000, 'max': 270000},
    'istanbul/adalar/heybeliada': {'min': 90000, 'avg': 135000, 'max': 220000},
    'istanbul/adalar/burgazada': {'min': 82000, 'avg': 125000, 'max': 200000},
    'istanbul/adalar/kınalıada': {'min': 78000, 'avg': 118000, 'max': 190000},
  };
}
