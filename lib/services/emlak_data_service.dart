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
      case 'Çatı Katı Daire':
        return 1.18;
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
    final normalIlce = _normalize(ilce);
    if (_normalize(il) == 'istanbul' && _istanbulMahalleleri.containsKey(normalIlce)) {
      return List<String>.from(_istanbulMahalleleri[normalIlce]!)..sort();
    }
    final prefix = '${_normalize(il)}/$normalIlce/';
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
    sb.writeln('Bölge Sıfır Bina m² Satış Fiyatı:');
    sb.writeln('  Ortalama: yaklaşık ${_fmtN(fiyat['avg']!)} ₺/m²');
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

      sb.writeln('  $tip ${m2.round()} m² (${_katAdi(kat)}): yaklaşık ${_fmtN(tahmin['avgToplam']!)} ₺');
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
          .replaceAll('Â', 'a')
          .replaceAll('â', 'a')
          .toLowerCase();

  /// Public normalize — dışarıdan erişim için
  static String normalize(String s) => _normalize(s);

  /// İlçe bazında fiyat bilgisi döner (null: bulunamadı)
  static Map<String, double>? ilceFiyatBilgisi(String il, String ilce) {
    final key = '${_normalize(il)}/${_normalize(ilce)}';
    if (_ilceVerileri.containsKey(key)) return _ilceVerileri[key]!;
    return null;
  }

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
  // ── İlçe bazında m² birim fiyatları (endeksa.com Şub 2025) ──
  static const Map<String, Map<String, double>> _ilceVerileri = {
    'istanbul/kadıköy': {'min': 69000, 'avg': 148000, 'max': 226000},
    'istanbul/beşiktaş': {'min': 77000, 'avg': 202000, 'max': 327000},
    'istanbul/şişli': {'min': 35000, 'avg': 158000, 'max': 281000},
    'istanbul/beyoğlu': {'min': 27000, 'avg': 107000, 'max': 188000},
    'istanbul/üsküdar': {'min': 55000, 'avg': 110000, 'max': 165000},
    'istanbul/ataşehir': {'min': 37000, 'avg': 88000, 'max': 138000},
    'istanbul/maltepe': {'min': 34000, 'avg': 74000, 'max': 113000},
    'istanbul/kartal': {'min': 51000, 'avg': 78000, 'max': 106000},
    'istanbul/pendik': {'min': 22000, 'avg': 55000, 'max': 88000},
    'istanbul/tuzla': {'min': 38000, 'avg': 80000, 'max': 122000},
    'istanbul/bakırköy': {'min': 54000, 'avg': 122000, 'max': 191000},
    'istanbul/bahçelievler': {'min': 39000, 'avg': 74000, 'max': 109000},
    'istanbul/bağcılar': {'min': 28000, 'avg': 48000, 'max': 69000},
    'istanbul/güngören': {'min': 36000, 'avg': 63000, 'max': 90000},
    'istanbul/zeytinburnu': {'min': 53000, 'avg': 128000, 'max': 203000},
    'istanbul/fatih': {'min': 38000, 'avg': 52000, 'max': 66000},
    'istanbul/eyüpsultan': {'min': 39000, 'avg': 96000, 'max': 153000},
    'istanbul/beylikdüzü': {'min': 17000, 'avg': 37000, 'max': 58000},
    'istanbul/esenyurt': {'min': 21000, 'avg': 31000, 'max': 41000},
    'istanbul/avcılar': {'min': 38000, 'avg': 48000, 'max': 58000},
    'istanbul/küçükçekmece': {'min': 29000, 'avg': 57000, 'max': 84000},
    'istanbul/başakşehir': {'min': 37000, 'avg': 64000, 'max': 90000},
    'istanbul/sarıyer': {'min': 46000, 'avg': 188000, 'max': 330000},
    'istanbul/beykoz': {'min': 50000, 'avg': 126000, 'max': 201000},
    'istanbul/çekmeköy': {'min': 54000, 'avg': 111000, 'max': 168000},
    'istanbul/sancaktepe': {'min': 44000, 'avg': 56000, 'max': 69000},
    'istanbul/sultanbeyli': {'min': 42000, 'avg': 49000, 'max': 56000},
    'istanbul/ümraniye': {'min': 31000, 'avg': 86000, 'max': 142000},
    'istanbul/kağıthane': {'min': 43000, 'avg': 73000, 'max': 102000},
    'istanbul/gaziosmanpaşa': {'min': 37000, 'avg': 60000, 'max': 82000},
    'istanbul/esenler': {'min': 29000, 'avg': 58000, 'max': 87000},
    'istanbul/bayrampaşa': {'min': 42000, 'avg': 70000, 'max': 98000},
    'istanbul/sultangazi': {'min': 34000, 'avg': 45000, 'max': 56000},
    'istanbul/arnavutköy': {'min': 12000, 'avg': 48000, 'max': 85000},
    'istanbul/silivri': {'min': 28000, 'avg': 61000, 'max': 93000},
    'istanbul/şile': {'min': 57000, 'avg': 85000, 'max': 112000},
    'istanbul/çatalca': {'min': 42000, 'avg': 71000, 'max': 100000},
    'istanbul/büyükçekmece': {'min': 35000, 'avg': 100000, 'max': 164000},
    'istanbul/adalar': {'min': 78000, 'avg': 99000, 'max': 119000},
  };

  // ── Mahalle bazında m² birim fiyatları (endeksa.com Şub 2025 oranlanmış) ──
  static const Map<String, Map<String, double>> _mahalleVerileri = {
    // KADIKÖY (×0.955)
    'istanbul/kadıköy/caferağa': {'min': 134000, 'avg': 172000, 'max': 267000},
    'istanbul/kadıköy/moda': {'min': 153000, 'avg': 191000, 'max': 296000},
    'istanbul/kadıköy/fenerbahçe': {'min': 148000, 'avg': 186000, 'max': 287000},
    'istanbul/kadıköy/suadiye': {'min': 139000, 'avg': 182000, 'max': 267000},
    'istanbul/kadıköy/bostancı': {'min': 115000, 'avg': 153000, 'max': 229000},
    'istanbul/kadıköy/kozyatağı': {'min': 100000, 'avg': 139000, 'max': 210000},
    'istanbul/kadıköy/göztepe': {'min': 105000, 'avg': 143000, 'max': 220000},
    'istanbul/kadıköy/erenköy': {'min': 124000, 'avg': 162000, 'max': 248000},
    'istanbul/kadıköy/acıbadem': {'min': 115000, 'avg': 158000, 'max': 239000},
    'istanbul/kadıköy/fikirtepe': {'min': 86000, 'avg': 119000, 'max': 186000},
    'istanbul/kadıköy/rasimpaşa': {'min': 124000, 'avg': 158000, 'max': 244000},
    // BEŞİKTAŞ (×1.01)
    'istanbul/beşiktaş/etiler': {'min': 202000, 'avg': 283000, 'max': 424000},
    'istanbul/beşiktaş/levent': {'min': 187000, 'avg': 263000, 'max': 404000},
    'istanbul/beşiktaş/bebek': {'min': 232000, 'avg': 323000, 'max': 505000},
    'istanbul/beşiktaş/ulus': {'min': 182000, 'avg': 253000, 'max': 384000},
    'istanbul/beşiktaş/ortaköy': {'min': 162000, 'avg': 222000, 'max': 343000},
    'istanbul/beşiktaş/akatlar': {'min': 152000, 'avg': 202000, 'max': 303000},
    'istanbul/beşiktaş/türkali': {'min': 131000, 'avg': 177000, 'max': 273000},
    'istanbul/beşiktaş/sinanpaşa': {'min': 141000, 'avg': 187000, 'max': 293000},
    'istanbul/beşiktaş/arnavutköy': {'min': 167000, 'avg': 232000, 'max': 364000},
    // ŞİŞLİ (×1.053)
    'istanbul/şişli/nişantaşı': {'min': 168000, 'avg': 232000, 'max': 369000},
    'istanbul/şişli/teşvikiye': {'min': 158000, 'avg': 221000, 'max': 347000},
    'istanbul/şişli/osmanbey': {'min': 137000, 'avg': 190000, 'max': 295000},
    'istanbul/şişli/bomonti': {'min': 111000, 'avg': 158000, 'max': 247000},
    'istanbul/şişli/mecidiyeköy': {'min': 100000, 'avg': 142000, 'max': 226000},
    'istanbul/şişli/esentepe': {'min': 105000, 'avg': 147000, 'max': 232000},
    'istanbul/şişli/feriköy': {'min': 95000, 'avg': 137000, 'max': 216000},
    'istanbul/şişli/kuştepe': {'min': 68000, 'avg': 95000, 'max': 153000},
    'istanbul/şişli/halaskargazi': {'min': 116000, 'avg': 163000, 'max': 258000},
    // BEYOĞLU (×0.823)
    'istanbul/beyoğlu/cihangir': {'min': 107000, 'avg': 144000, 'max': 230000},
    'istanbul/beyoğlu/galata': {'min': 99000, 'avg': 136000, 'max': 218000},
    'istanbul/beyoğlu/taksim': {'min': 86000, 'avg': 119000, 'max': 193000},
    'istanbul/beyoğlu/tarlabaşı': {'min': 58000, 'avg': 78000, 'max': 128000},
    'istanbul/beyoğlu/kasımpaşa': {'min': 62000, 'avg': 86000, 'max': 140000},
    'istanbul/beyoğlu/piyalepaşa': {'min': 70000, 'avg': 99000, 'max': 156000},
    // ÜSKÜDAR (×0.917)
    'istanbul/üsküdar/kuzguncuk': {'min': 110000, 'avg': 147000, 'max': 234000},
    'istanbul/üsküdar/çengelköy': {'min': 119000, 'avg': 156000, 'max': 248000},
    'istanbul/üsküdar/beylerbeyi': {'min': 105000, 'avg': 142000, 'max': 225000},
    'istanbul/üsküdar/altunizade': {'min': 92000, 'avg': 128000, 'max': 202000},
    'istanbul/üsküdar/acıbadem': {'min': 87000, 'avg': 119000, 'max': 188000},
    'istanbul/üsküdar/bulgurlu': {'min': 69000, 'avg': 96000, 'max': 151000},
    'istanbul/üsküdar/ünalan': {'min': 64000, 'avg': 90000, 'max': 142000},
    // ATAŞEHİR (×0.704)
    'istanbul/ataşehir/küçükbakkalköy': {'min': 63000, 'avg': 92000, 'max': 141000},
    'istanbul/ataşehir/içerenköy': {'min': 56000, 'avg': 81000, 'max': 127000},
    'istanbul/ataşehir/yenisahra': {'min': 51000, 'avg': 74000, 'max': 116000},
    'istanbul/ataşehir/kayışdağı': {'min': 49000, 'avg': 70000, 'max': 111000},
    'istanbul/ataşehir/barbaros': {'min': 60000, 'avg': 88000, 'max': 137000},
    'istanbul/ataşehir/ferhatpaşa': {'min': 46000, 'avg': 67000, 'max': 106000},
    'istanbul/ataşehir/esatpaşa': {'min': 55000, 'avg': 77000, 'max': 123000},
    'istanbul/ataşehir/atatürk': {'min': 67000, 'avg': 95000, 'max': 148000},
    // MALTEPE (×0.74)
    'istanbul/maltepe/altıntepe': {'min': 59000, 'avg': 85000, 'max': 130000},
    'istanbul/maltepe/cevizli': {'min': 56000, 'avg': 80000, 'max': 122000},
    'istanbul/maltepe/idealtepe': {'min': 61000, 'avg': 87000, 'max': 133000},
    'istanbul/maltepe/küçükyalı': {'min': 58000, 'avg': 81000, 'max': 126000},
    'istanbul/maltepe/zümrütevler': {'min': 44000, 'avg': 63000, 'max': 100000},
    'istanbul/maltepe/fındıklı': {'min': 41000, 'avg': 59000, 'max': 93000},
    'istanbul/maltepe/aydınevler': {'min': 48000, 'avg': 68000, 'max': 107000},
    // KARTAL (×0.886)
    'istanbul/kartal/yakacık': {'min': 49000, 'avg': 71000, 'max': 113000},
    'istanbul/kartal/kordonboyu': {'min': 60000, 'avg': 84000, 'max': 133000},
    'istanbul/kartal/soğanlık': {'min': 44000, 'avg': 64000, 'max': 102000},
    'istanbul/kartal/uğurmumcu': {'min': 55000, 'avg': 80000, 'max': 124000},
    'istanbul/kartal/topselvi': {'min': 46000, 'avg': 66000, 'max': 106000},
    'istanbul/kartal/hürriyet': {'min': 49000, 'avg': 69000, 'max': 111000},
    // PENDİK (×0.705)
    'istanbul/pendik/kaynarca': {'min': 41000, 'avg': 58000, 'max': 90000},
    'istanbul/pendik/yenişehir': {'min': 37000, 'avg': 53000, 'max': 83000},
    'istanbul/pendik/kurtköy': {'min': 42000, 'avg': 62000, 'max': 97000},
    'istanbul/pendik/esenyalı': {'min': 32000, 'avg': 46000, 'max': 71000},
    'istanbul/pendik/velibaba': {'min': 30000, 'avg': 42000, 'max': 67000},
    'istanbul/pendik/batı': {'min': 35000, 'avg': 51000, 'max': 79000},
    // TUZLA (×1.143)
    'istanbul/tuzla/aydınlı': {'min': 57000, 'avg': 82000, 'max': 126000},
    'istanbul/tuzla/içmeler': {'min': 51000, 'avg': 74000, 'max': 114000},
    'istanbul/tuzla/postane': {'min': 63000, 'avg': 89000, 'max': 137000},
    'istanbul/tuzla/mimar sinan': {'min': 48000, 'avg': 71000, 'max': 109000},
    'istanbul/tuzla/orhanlı': {'min': 46000, 'avg': 66000, 'max': 103000},
    'istanbul/tuzla/şifa': {'min': 50000, 'avg': 72000, 'max': 112000},
    // BAKIRKÖY (×0.841)
    'istanbul/bakırköy/ataköy': {'min': 109000, 'avg': 156000, 'max': 244000},
    'istanbul/bakırköy/florya': {'min': 118000, 'avg': 164000, 'max': 261000},
    'istanbul/bakırköy/yeşilköy': {'min': 101000, 'avg': 147000, 'max': 231000},
    'istanbul/bakırköy/zuhuratbaba': {'min': 71000, 'avg': 101000, 'max': 160000},
    'istanbul/bakırköy/osmaniye': {'min': 67000, 'avg': 97000, 'max': 151000},
    'istanbul/bakırköy/kartaltepe': {'min': 77000, 'avg': 109000, 'max': 172000},
    'istanbul/bakırköy/cevizlik': {'min': 76000, 'avg': 108000, 'max': 168000},
    // BAHÇELİEVLER (×0.804)
    'istanbul/bahçelievler/bahçelievler': {'min': 58000, 'avg': 80000, 'max': 125000},
    'istanbul/bahçelievler/soğanlı': {'min': 48000, 'avg': 68000, 'max': 107000},
    'istanbul/bahçelievler/kocasinan': {'min': 52000, 'avg': 72000, 'max': 113000},
    'istanbul/bahçelievler/çobançeşme': {'min': 47000, 'avg': 66000, 'max': 103000},
    'istanbul/bahçelievler/hürriyet': {'min': 44000, 'avg': 63000, 'max': 96000},
    'istanbul/bahçelievler/yenibosna': {'min': 47000, 'avg': 66000, 'max': 103000},
    'istanbul/bahçelievler/şirinevler': {'min': 52000, 'avg': 74000, 'max': 114000},
    // BAĞCILAR (×0.64)
    'istanbul/bağcılar/güneşli': {'min': 37000, 'avg': 52000, 'max': 80000},
    'istanbul/bağcılar/mahmutbey': {'min': 33000, 'avg': 48000, 'max': 74000},
    'istanbul/bağcılar/kirazlı': {'min': 31000, 'avg': 44000, 'max': 69000},
    'istanbul/bağcılar/barbaros': {'min': 29000, 'avg': 42000, 'max': 64000},
    'istanbul/bağcılar/yıldıztepe': {'min': 27000, 'avg': 40000, 'max': 61000},
    'istanbul/bağcılar/kazım karabekir': {'min': 27000, 'avg': 38000, 'max': 59000},
    'istanbul/bağcılar/inönü': {'min': 26000, 'avg': 37000, 'max': 58000},
    // GÜNGÖREN (×0.808)
    'istanbul/güngören/merkez': {'min': 48000, 'avg': 69000, 'max': 105000},
    'istanbul/güngören/tozkoparan': {'min': 44000, 'avg': 63000, 'max': 97000},
    'istanbul/güngören/haznedar': {'min': 40000, 'avg': 58000, 'max': 91000},
    'istanbul/güngören/gençosman': {'min': 39000, 'avg': 55000, 'max': 85000},
    'istanbul/güngören/akıncılar': {'min': 40000, 'avg': 57000, 'max': 87000},
    'istanbul/güngören/güneştepe': {'min': 42000, 'avg': 59000, 'max': 90000},
    'istanbul/güngören/sanayi': {'min': 37000, 'avg': 53000, 'max': 81000},
    // ZEYTİNBURNU (×1.28)
    'istanbul/zeytinburnu/merkezefendi': {'min': 100000, 'avg': 141000, 'max': 218000},
    'istanbul/zeytinburnu/beştelsiz': {'min': 87000, 'avg': 122000, 'max': 192000},
    'istanbul/zeytinburnu/nuripaşa': {'min': 79000, 'avg': 113000, 'max': 177000},
    'istanbul/zeytinburnu/telsiz': {'min': 74000, 'avg': 105000, 'max': 164000},
    'istanbul/zeytinburnu/sümer': {'min': 70000, 'avg': 100000, 'max': 154000},
    'istanbul/zeytinburnu/veliemine': {'min': 92000, 'avg': 128000, 'max': 202000},
    // FATİH (×0.6)
    'istanbul/fatih/sultanahmet': {'min': 60000, 'avg': 84000, 'max': 132000},
    'istanbul/fatih/vefa': {'min': 49000, 'avg': 69000, 'max': 108000},
    'istanbul/fatih/balat': {'min': 47000, 'avg': 65000, 'max': 102000},
    'istanbul/fatih/çarşamba': {'min': 43000, 'avg': 60000, 'max': 95000},
    'istanbul/fatih/karagümrük': {'min': 41000, 'avg': 57000, 'max': 90000},
    'istanbul/fatih/aksaray': {'min': 45000, 'avg': 63000, 'max': 99000},
    'istanbul/fatih/zeyrek': {'min': 42000, 'avg': 59000, 'max': 93000},
    // EYÜPSULTAN (×1.171)
    'istanbul/eyüpsultan/göktürk': {'min': 100000, 'avg': 146000, 'max': 228000},
    'istanbul/eyüpsultan/kemerburgaz': {'min': 88000, 'avg': 129000, 'max': 201000},
    'istanbul/eyüpsultan/alibeyköy': {'min': 68000, 'avg': 96000, 'max': 152000},
    'istanbul/eyüpsultan/rami': {'min': 59000, 'avg': 84000, 'max': 131000},
    'istanbul/eyüpsultan/yeşilpınar': {'min': 53000, 'avg': 76000, 'max': 119000},
    'istanbul/eyüpsultan/silahtarağa': {'min': 61000, 'avg': 88000, 'max': 138000},
    // BEYLİKDÜZÜ (×0.6)
    'istanbul/beylikdüzü/adnan kahveci': {'min': 33000, 'avg': 47000, 'max': 72000},
    'istanbul/beylikdüzü/barış': {'min': 30000, 'avg': 43000, 'max': 67000},
    'istanbul/beylikdüzü/büyükşehir': {'min': 28000, 'avg': 39000, 'max': 60000},
    'istanbul/beylikdüzü/cumhuriyet': {'min': 29000, 'avg': 41000, 'max': 63000},
    'istanbul/beylikdüzü/yakuplu': {'min': 27000, 'avg': 39000, 'max': 60000},
    'istanbul/beylikdüzü/kavaklı': {'min': 27000, 'avg': 38000, 'max': 59000},
    // ESENYURT (×0.6)
    'istanbul/esenyurt/ardıçlı': {'min': 23000, 'avg': 33000, 'max': 51000},
    'istanbul/esenyurt/fatih': {'min': 21000, 'avg': 30000, 'max': 47000},
    'istanbul/esenyurt/inönü': {'min': 19000, 'avg': 29000, 'max': 43000},
    'istanbul/esenyurt/mehterçeşme': {'min': 18000, 'avg': 27000, 'max': 41000},
    'istanbul/esenyurt/saadetdere': {'min': 17000, 'avg': 25000, 'max': 39000},
    'istanbul/esenyurt/yeşilkent': {'min': 20000, 'avg': 29000, 'max': 45000},
    'istanbul/esenyurt/namık kemal': {'min': 18000, 'avg': 27000, 'max': 42000},
    // AVCILAR (×0.686)
    'istanbul/avcılar/cihangir': {'min': 36000, 'avg': 51000, 'max': 79000},
    'istanbul/avcılar/merkez': {'min': 33000, 'avg': 48000, 'max': 74000},
    'istanbul/avcılar/ambarlı': {'min': 31000, 'avg': 45000, 'max': 69000},
    'istanbul/avcılar/firuzköy': {'min': 29000, 'avg': 41000, 'max': 63000},
    'istanbul/avcılar/denizköşkler': {'min': 30000, 'avg': 43000, 'max': 67000},
    'istanbul/avcılar/gümüşpala': {'min': 32000, 'avg': 45000, 'max': 69000},
    'istanbul/avcılar/yeşilkent': {'min': 30000, 'avg': 43000, 'max': 65000},
    // KÜÇÜKÇEKMECE (×0.814)
    'istanbul/küçükçekmece/atakent': {'min': 45000, 'avg': 64000, 'max': 98000},
    'istanbul/küçükçekmece/cennet': {'min': 41000, 'avg': 59000, 'max': 90000},
    'istanbul/küçükçekmece/halkalı': {'min': 47000, 'avg': 67000, 'max': 104000},
    'istanbul/küçükçekmece/inönü': {'min': 37000, 'avg': 53000, 'max': 81000},
    'istanbul/küçükçekmece/kanarya': {'min': 33000, 'avg': 47000, 'max': 73000},
    'istanbul/küçükçekmece/söğütlüçeşme': {'min': 34000, 'avg': 49000, 'max': 75000},
    // BAŞAKŞEHİR (×0.696)
    'istanbul/başakşehir/bahçeşehir 1. kısım': {'min': 54000, 'avg': 77000, 'max': 118000},
    'istanbul/başakşehir/bahçeşehir 2. kısım': {'min': 50000, 'avg': 71000, 'max': 110000},
    'istanbul/başakşehir/kayabaşı': {'min': 40000, 'avg': 57000, 'max': 89000},
    'istanbul/başakşehir/başak': {'min': 45000, 'avg': 64000, 'max': 99000},
    'istanbul/başakşehir/güvercintepe': {'min': 31000, 'avg': 45000, 'max': 70000},
    'istanbul/başakşehir/ziya gökalp': {'min': 36000, 'avg': 52000, 'max': 80000},
    // SARIYER (×1.139)
    'istanbul/sarıyer/istinye': {'min': 177000, 'avg': 245000, 'max': 410000},
    'istanbul/sarıyer/tarabya': {'min': 159000, 'avg': 222000, 'max': 364000},
    'istanbul/sarıyer/maslak': {'min': 148000, 'avg': 205000, 'max': 342000},
    'istanbul/sarıyer/emirgan': {'min': 165000, 'avg': 234000, 'max': 387000},
    'istanbul/sarıyer/yeniköy': {'min': 177000, 'avg': 251000, 'max': 416000},
    'istanbul/sarıyer/bahçeköy': {'min': 97000, 'avg': 137000, 'max': 222000},
    'istanbul/sarıyer/zekeriyaköy': {'min': 114000, 'avg': 159000, 'max': 256000},
    'istanbul/sarıyer/rumelihisarı': {'min': 159000, 'avg': 222000, 'max': 364000},
    // BEYKOZ (×0.984)
    'istanbul/beykoz/anadoluhisarı': {'min': 108000, 'avg': 152000, 'max': 246000},
    'istanbul/beykoz/çubuklu': {'min': 98000, 'avg': 138000, 'max': 221000},
    'istanbul/beykoz/kavacık': {'min': 93000, 'avg': 130000, 'max': 212000},
    'istanbul/beykoz/paşabahçe': {'min': 84000, 'avg': 116000, 'max': 187000},
    'istanbul/beykoz/riva': {'min': 67000, 'avg': 93000, 'max': 152000},
    'istanbul/beykoz/acarlar': {'min': 74000, 'avg': 103000, 'max': 167000},
    // ÇEKMEKÖY (×1.423)
    'istanbul/çekmeköy/merkez': {'min': 85000, 'avg': 121000, 'max': 188000},
    'istanbul/çekmeköy/alemdağ': {'min': 78000, 'avg': 111000, 'max': 171000},
    'istanbul/çekmeköy/hamidiye': {'min': 71000, 'avg': 102000, 'max': 159000},
    'istanbul/çekmeköy/ömerli': {'min': 64000, 'avg': 92000, 'max': 142000},
    'istanbul/çekmeköy/nişantepe': {'min': 71000, 'avg': 100000, 'max': 154000},
    'istanbul/çekmeköy/mehmet akif': {'min': 74000, 'avg': 105000, 'max': 164000},
    'istanbul/çekmeköy/mimar sinan': {'min': 68000, 'avg': 97000, 'max': 149000},
    // SANCAKTEPE (×0.862)
    'istanbul/sancaktepe/sarıgazi': {'min': 41000, 'avg': 60000, 'max': 93000},
    'istanbul/sancaktepe/samandıra': {'min': 39000, 'avg': 56000, 'max': 86000},
    'istanbul/sancaktepe/yenidoğan': {'min': 34000, 'avg': 50000, 'max': 78000},
    'istanbul/sancaktepe/inönü': {'min': 36000, 'avg': 52000, 'max': 79000},
    'istanbul/sancaktepe/akpınar': {'min': 38000, 'avg': 53000, 'max': 82000},
    'istanbul/sancaktepe/abdurrahman gazi': {'min': 34000, 'avg': 50000, 'max': 76000},
    'istanbul/sancaktepe/osmangazi': {'min': 40000, 'avg': 57000, 'max': 86000},
    // SULTANBEYLİ (×0.942)
    'istanbul/sultanbeyli/battalgazi': {'min': 36000, 'avg': 52000, 'max': 80000},
    'istanbul/sultanbeyli/fatih': {'min': 33000, 'avg': 49000, 'max': 75000},
    'istanbul/sultanbeyli/mehmet akif': {'min': 30000, 'avg': 45000, 'max': 71000},
    'istanbul/sultanbeyli/necip fazıl': {'min': 28000, 'avg': 42000, 'max': 68000},
    'istanbul/sultanbeyli/hasanpaşa': {'min': 33000, 'avg': 47000, 'max': 73000},
    'istanbul/sultanbeyli/orhangazi': {'min': 31000, 'avg': 45000, 'max': 71000},
    'istanbul/sultanbeyli/yavuz selim': {'min': 30000, 'avg': 43000, 'max': 68000},
    // ÜMRANİYE (×0.905)
    'istanbul/ümraniye/atatürk': {'min': 65000, 'avg': 95000, 'max': 147000},
    'istanbul/ümraniye/çakmak': {'min': 59000, 'avg': 83000, 'max': 131000},
    'istanbul/ümraniye/hekimbaşı': {'min': 54000, 'avg': 77000, 'max': 122000},
    'istanbul/ümraniye/istiklal': {'min': 52000, 'avg': 74000, 'max': 116000},
    'istanbul/ümraniye/site': {'min': 62000, 'avg': 89000, 'max': 138000},
    'istanbul/ümraniye/tantavi': {'min': 52000, 'avg': 74000, 'max': 116000},
    'istanbul/ümraniye/parseller': {'min': 50000, 'avg': 71000, 'max': 109000},
    // KAĞITHANE (×0.73)
    'istanbul/kağıthane/çağlayan': {'min': 55000, 'avg': 79000, 'max': 123000},
    'istanbul/kağıthane/gültepe': {'min': 47000, 'avg': 69000, 'max': 108000},
    'istanbul/kağıthane/hamidiye': {'min': 51000, 'avg': 73000, 'max': 113000},
    'istanbul/kağıthane/seyrantepe': {'min': 58000, 'avg': 84000, 'max': 130000},
    'istanbul/kağıthane/hürriyet': {'min': 42000, 'avg': 60000, 'max': 93000},
    'istanbul/kağıthane/yahya kemal': {'min': 40000, 'avg': 57000, 'max': 88000},
    // GAZİOSMANPAŞA (×0.857)
    'istanbul/gaziosmanpaşa/bağlarbaşı': {'min': 43000, 'avg': 62000, 'max': 96000},
    'istanbul/gaziosmanpaşa/merkez': {'min': 47000, 'avg': 67000, 'max': 103000},
    'istanbul/gaziosmanpaşa/karlıtepe': {'min': 39000, 'avg': 56000, 'max': 86000},
    'istanbul/gaziosmanpaşa/karayolları': {'min': 41000, 'avg': 58000, 'max': 90000},
    'istanbul/gaziosmanpaşa/yıldıztabya': {'min': 39000, 'avg': 56000, 'max': 86000},
    'istanbul/gaziosmanpaşa/sarıgöl': {'min': 36000, 'avg': 51000, 'max': 79000},
    'istanbul/gaziosmanpaşa/pazariçi': {'min': 39000, 'avg': 57000, 'max': 87000},
    // ESENLER (×0.967)
    'istanbul/esenler/davutpaşa': {'min': 44000, 'avg': 63000, 'max': 97000},
    'istanbul/esenler/fevzi çakmak': {'min': 39000, 'avg': 56000, 'max': 87000},
    'istanbul/esenler/oruçreis': {'min': 37000, 'avg': 53000, 'max': 82000},
    'istanbul/esenler/kazım karabekir': {'min': 37000, 'avg': 53000, 'max': 82000},
    'istanbul/esenler/havaalanı': {'min': 34000, 'avg': 48000, 'max': 75000},
    'istanbul/esenler/menderes': {'min': 35000, 'avg': 50000, 'max': 77000},
    'istanbul/esenler/tuna': {'min': 36000, 'avg': 51000, 'max': 79000},
    // BAYRAMPAŞA (×0.854)
    'istanbul/bayrampaşa/yıldırım': {'min': 53000, 'avg': 75000, 'max': 118000},
    'istanbul/bayrampaşa/kocatepe': {'min': 47000, 'avg': 67000, 'max': 102000},
    'istanbul/bayrampaşa/muratpaşa': {'min': 43000, 'avg': 61000, 'max': 96000},
    'istanbul/bayrampaşa/ismetpaşa': {'min': 48000, 'avg': 68000, 'max': 107000},
    'istanbul/bayrampaşa/vatan': {'min': 44000, 'avg': 64000, 'max': 101000},
    'istanbul/bayrampaşa/altıntepsi': {'min': 46000, 'avg': 65000, 'max': 101000},
    'istanbul/bayrampaşa/cevatpaşa': {'min': 44000, 'avg': 63000, 'max': 98000},
    // SULTANGAZİ (×0.75)
    'istanbul/sultangazi/esentepe': {'min': 34000, 'avg': 49000, 'max': 75000},
    'istanbul/sultangazi/cebeci': {'min': 30000, 'avg': 41000, 'max': 64000},
    'istanbul/sultangazi/habipler': {'min': 29000, 'avg': 39000, 'max': 62000},
    'istanbul/sultangazi/50. yıl': {'min': 32000, 'avg': 44000, 'max': 69000},
    'istanbul/sultangazi/ismetpaşa': {'min': 30000, 'avg': 42000, 'max': 66000},
    'istanbul/sultangazi/zübeyde hanım': {'min': 33000, 'avg': 47000, 'max': 71000},
    // ARNAVUTKÖY (×1.0)
    'istanbul/arnavutköy/hadımköy': {'min': 38000, 'avg': 55000, 'max': 85000},
    'istanbul/arnavutköy/bolluca': {'min': 35000, 'avg': 50000, 'max': 78000},
    'istanbul/arnavutköy/merkez': {'min': 32000, 'avg': 48000, 'max': 75000},
    'istanbul/arnavutköy/taşoluk': {'min': 30000, 'avg': 45000, 'max': 72000},
    'istanbul/arnavutköy/dursunköy': {'min': 28000, 'avg': 42000, 'max': 65000},
    'istanbul/arnavutköy/yeşilbayır': {'min': 28000, 'avg': 40000, 'max': 62000},
    // SİLİVRİ (×1.452)
    'istanbul/silivri/merkez': {'min': 46000, 'avg': 65000, 'max': 102000},
    'istanbul/silivri/selimpaşa': {'min': 51000, 'avg': 70000, 'max': 109000},
    'istanbul/silivri/gümüşyaka': {'min': 44000, 'avg': 61000, 'max': 94000},
    'istanbul/silivri/kavaklı': {'min': 41000, 'avg': 55000, 'max': 87000},
    'istanbul/silivri/değirmenköy': {'min': 36000, 'avg': 51000, 'max': 80000},
    'istanbul/silivri/alipaşa': {'min': 41000, 'avg': 58000, 'max': 90000},
    'istanbul/silivri/piri mehmet paşa': {'min': 44000, 'avg': 62000, 'max': 97000},
    // ŞİLE (×1.8)
    'istanbul/şile/merkez': {'min': 54000, 'avg': 76000, 'max': 117000},
    'istanbul/şile/ağva': {'min': 63000, 'avg': 90000, 'max': 140000},
    'istanbul/şile/kumbaba': {'min': 45000, 'avg': 65000, 'max': 99000},
    'istanbul/şile/doğancalı': {'min': 40000, 'avg': 58000, 'max': 86000},
    'istanbul/şile/balıbey': {'min': 50000, 'avg': 72000, 'max': 108000},
    'istanbul/şile/karamandere': {'min': 43000, 'avg': 61000, 'max': 94000},
    'istanbul/şile/üvezli': {'min': 41000, 'avg': 59000, 'max': 90000},
    // ÇATALCA (×1.8)
    'istanbul/çatalca/merkez': {'min': 49000, 'avg': 68000, 'max': 104000},
    'istanbul/çatalca/ferhatpaşa': {'min': 40000, 'avg': 58000, 'max': 90000},
    'istanbul/çatalca/kaleiçi': {'min': 45000, 'avg': 63000, 'max': 99000},
    'istanbul/çatalca/inceğiz': {'min': 36000, 'avg': 50000, 'max': 81000},
    'istanbul/çatalca/yalıköy': {'min': 41000, 'avg': 59000, 'max': 94000},
    'istanbul/çatalca/karacaköy': {'min': 32000, 'avg': 47000, 'max': 76000},
    'istanbul/çatalca/elbasan': {'min': 34000, 'avg': 49000, 'max': 77000},
    // BÜYÜKÇEKMECE (×1.538)
    'istanbul/büyükçekmece/mimaroba': {'min': 74000, 'avg': 105000, 'max': 161000},
    'istanbul/büyükçekmece/kumburgaz': {'min': 77000, 'avg': 111000, 'max': 172000},
    'istanbul/büyükçekmece/merkez': {'min': 74000, 'avg': 105000, 'max': 161000},
    'istanbul/büyükçekmece/batıköy': {'min': 69000, 'avg': 97000, 'max': 151000},
    'istanbul/büyükçekmece/bahçelievler': {'min': 65000, 'avg': 92000, 'max': 141000},
    'istanbul/büyükçekmece/pınartepe': {'min': 68000, 'avg': 95000, 'max': 148000},
    'istanbul/büyükçekmece/fatih': {'min': 71000, 'avg': 100000, 'max': 154000},
    // ADALAR (×0.825)
    'istanbul/adalar/büyükada': {'min': 91000, 'avg': 136000, 'max': 223000},
    'istanbul/adalar/heybeliada': {'min': 74000, 'avg': 111000, 'max': 182000},
    'istanbul/adalar/burgazada': {'min': 68000, 'avg': 103000, 'max': 165000},
    'istanbul/adalar/kınalıada': {'min': 64000, 'avg': 97000, 'max': 157000},
    'istanbul/adalar/sedefadası': {'min': 87000, 'avg': 128000, 'max': 206000},
  };

  // ── İstanbul ilçe-mahalle tam listesi (Wikipedia kaynaklı) ──
  static final Map<String, List<String>> _istanbulMahalleleri = _buildMahalleler();

  static Map<String, List<String>> _buildMahalleler() {
    const v = <String, String>{
      'adalar': 'Burgazada|Heybeliada|Kınalıada|Maden|Nizam',
      'arnavutköy': 'Adnan Menderes|Anadolu|Arnavutköy Merkez|Atatürk|Baklalı|Balaban|Boğazköy İstiklal|Bolluca|Boyalık|Çilingir|Deliklikaya|Dursunköy|Durusu|Fatih|Hacımaşlı|Hadımköy|Haraççı|Hastane|Hicret|İmrahor|İslambey|Karaburun|Karlıbayır|Mareşal Fevzi Çakmak|Mavigöl|Mehmet Akif Ersoy|Mustafa Kemal Paşa|Nene Hatun|Ömerli|Sazlıbosna|Taşoluk|Tayakadın|Terkos|Yassıören|Yavuz Selim|Yeniköy|Yeşilbayır|Yunus Emre',
      'ataşehir': 'Aşıkveysel|Atatürk|Barbaros|Esatpaşa|Ferhatpaşa|Fetih|İçerenköy|İnönü|Kayışdağı|Küçükbakkalköy|Mevlana|Mimarsinan|Mustafa Kemal|Örnek|Yeniçamlıca|Yenişehir|Yenisahra',
      'avcılar': 'Ambarlı|Cihangir|Denizköşkler|Firuzköy|Gümüşpala|Merkez|Mustafa Kemal Paşa|Tahtakale|Üniversite|Yeşilkent',
      'bağcılar': '15 Temmuz|Bağlar|Barbaros|Çınar|Demirkapı|Fatih|Fevzi Çakmak|Göztepe|Güneşli|Hürriyet|İnönü|Kâzım Karabekir|Kemalpaşa|Kirazlı|Mahmutbey|Merkez|Sancaktepe|Yavuzselim|Yenigün|Yenimahalle|Yıldıztepe|Yüzyıl',
      'bahçelievler': 'Bahçelievler|Cumhuriyet|Çobançeşme|Fevzi Çakmak|Hürriyet|Kocasinan|Siyavuşpaşa|Soğanlı|Şirinevler|Yenibosna|Zafer',
      'bakırköy': 'Ataköy 1. Kısım|Ataköy 2-5-6. Kısım|Ataköy 3-4-11. Kısım|Ataköy 7-8-9-10. Kısım|Basınköy|Cevizlik|Kartaltepe|Osmaniye|Sakızağacı|Şenlikköy|Yenimahalle|Yeşilköy|Yeşilyurt|Zeytinlik|Zuhuratbaba',
      'başakşehir': 'Altınşehir|Bahçeşehir 1. Kısım|Bahçeşehir 2. Kısım|Başak|Başakşehir|Güvercintepe|Kayabaşı|Şahintepe|Şamlar|Ziya Gökalp',
      'bayrampaşa': 'Altıntepsi|Cevatpaşa|İsmetpaşa|Kartaltepe|Kocatepe|Muratpaşa|Orta|Terazidere|Vatan|Yenidoğan|Yıldırım',
      'beşiktaş': 'Abbasağa|Akat|Arnavutköy|Balmumcu|Bebek|Cihannüma|Dikilitaş|Etiler|Gayrettepe|Konaklar|Kuruçeşme|Kültür|Levazım|Levent|Mecidiye|Muradiye|Nisbetiye|Ortaköy|Sinanpaşa|Türkali|Ulus|Vişnezade|Yıldız',
      'beykoz': 'Acarlar|Akbaba|Alibahadır|Anadolufeneri|Anadoluhisarı|Anadolukavağı|Baklacı|Bozhane|Cumhuriyet|Çamlıbahçe|Çengeldere|Çiftlik|Çiğdem|Çubuklu|Dereseki|Elmalı|Fatih|Göksu|Göllü|Görele|Göztepe|Gümüşsuyu|İncirköy|İshaklı|Kanlıca|Kavacık|Kaynarca|Kılıçlı|Mahmutşevketpaşa|Merkez|Ortaçeşme|Öğümce|Örnekköy|Paşabahçe|Paşamandıra|Polonezköy|Poyrazköy|Riva|Rüzgarlıbahçe|Soğuksu|Tokatköy|Yalıköy|Yavuzselim|Yenimahalle|Zerzevatçı',
      'beylikdüzü': 'Adnan Kahveci|Barış|Büyükşehir|Cumhuriyet|Dereağzı|Gürpınar|Kavaklı|Marmara|Sahil|Yakuplu',
      'beyoğlu': 'Arapcami|Asmalımescit|Bedrettin|Bereketzade|Bostan|Bülbül|Camiikebir|Cihangir|Çatmamescit|Çukur|Emekyemez|Evliya Çelebi|Fetihtepe|Firuzağa|Gümüşsuyu|Hacıahmet|Hacımimi|Halıcıoğlu|Hüseyinağa|İstiklal|Kadı Mehmet Efendi|Kamerhatun|Kalyoncukulluğu|Kaptanpaşa|Katip Mustafa Çelebi|Keçecipiri|Kemankeş Kara Mustafa Paşa|Kılıçalipaşa|Kocatepe|Kulaksız|Kuloğlu|Küçükpiyale|Müeyyetzade|Ömeravni|Örnektepe|Piripaşa|Piyalepaşa|Pürtelaş|Sururi|Sütlüce|Şahkulu|Şehit Muhtar|Tomtom|Yahya Kahya|Yenişehir',
      'büyükçekmece': '19 Mayıs|Ahmediye|Alkent 2000|Atatürk|Bahçelievler|Celaliye|Cumhuriyet|Çakmaklı|Dizdariye|Ekinoba|Fatih|Güzelce|Hürriyet|Kamiloba|Karaağaç|Kumburgaz|Mimaroba|Mimarsinan|Muratçeşme|Pınartepe|Sinanoba|Türkoba|Ulus|Yenimahalle',
      'çatalca': 'Akalan|Atatürk|Aydınlar|Bahşayiş|Başak|Belgrat|Celepköy|Çakıl|Çanakça|Çiftlikköy|Dağyenice|Elbasan|Fatih|Ferhatpaşa|Gökçeali|Gümüşpınar|Hallaçlı|Hisarbeyli|İhsaniye|İnceğiz|İzzettin|Kabakça|Kaleiçi|Kalfa|Karacaköy|Karamandere|Kestanelik|Kızılcaali|Muratbey|Nakkaş|Oklalı|Ormanlı|Ovayenice|Örcünlü|Örencik|Subaşı|Yalıköy|Yaylacık|Yazlık',
      'çekmeköy': 'Alemdağ|Aydınlar|Cumhuriyet|Çamlık|Çatalmeşe|Ekşioğlu|Güngören|Hamidiye|Hüseyinli|Kirazlıdere|Koçullu|Mehmet Akif|Merkez|Mimar Sinan|Nişantepe|Ömerli|Reşadiye|Sırapınar|Soğukpınar|Sultançiftliği|Taşdelen',
      'esenler': '15 Temmuz|Birlik|Çiftehavuzlar|Davutpaşa|Fatih|Fevzi Çakmak|Havaalanı|Kazım Karabekir|Kemer|Menderes|Mimar Sinan|Namık Kemal|Nenehatun|Oruçreis|Tuna|Turgutreis|Yavuz Selim',
      'esenyurt': 'Akçaburgaz|Akevler|Akşemseddin|Ardıçlı|Aşık Veysel|Atatürk|Bağlarçeşme|Balık Yolu|Barbaros Hayrettin Paşa|Battalgazi|Cumhuriyet|Çınar|Esenkent|Fatih|Gökevler|Güzelyurt|Hürriyet|İncirtepe|İnönü|İstiklal|Koza|Mehmet Akif Ersoy|Mehterçeşme|Mevlana|Namık Kemal|Necip Fazıl Kısakürek|Orhan Gazi|Osmangazi|Örnek|Pınar|Piri Reis|Saadetdere|Selahaddin Eyyubi|Sultaniye|Süleymaniye|Şehitler|Talatpaşa|Turgut Özal|Üçevler|Yenikent|Yeşilkent|Yunus Emre|Zafer',
      'eyüpsultan': '5. Levent|Akşemsettin|Alibeyköy|Çırçır|Defterdar|Düğmeciler|Emniyettepe|Esentepe|Göktürk|Güzeltepe|İslambey|Karadolap|Merkez|Mimarsinan|Mithatpaşa|Nişanca|Rami Cuma|Rami Yeni|Sakarya|Silahtarağa|Topçular|Yeşilpınar',
      'fatih': 'Aksaray|Akşemsettin|Alemdar|Ali Kuşçu|Atikali|Ayvansaray|Balabanağa|Balat|Beyazıt|Binbirdirek|Cankurtaran|Cerrahpaşa|Cibali|Demirtaş|Derviş Ali|Eminsinan|Hacıkadın|Hasekisultan|Hırkaişerif|Hobyar|Hoca Giyasettin|Hocapaşa|İskenderpaşa|Kalenderhane|Karagümrük|Katip Kasım|Kemalpaşa|Kocamustafapaşa|Küçükayasofya|Mercan|Mesihpaşa|Mevlanakapı|Mimar Hayrettin|Mimar Kemalettin|Mollafenari|Mollagürani|Mollahüsrev|Muhsinehatun|Nişanca|Rüstempaşa|Saraçishak|Sarıdemir|Seyyid Ömer|Silivrikapı|Sultanahmet|Sururi|Süleymaniye|Sümbülefendi|Şehremini|Şehsuvarbey|Tahtakale|Tayahatun|Topkapı|Yavuzsinan|Yavuz Sultan Selim|Yedikule|Zeyrek',
      'gaziosmanpaşa': 'Bağlarbaşı|Barbaros Hayrettin Paşa|Fevzi Çakmak|Hürriyet|Karadeniz|Karayolları|Karlıtepe|Kâzım Karabekir|Merkez|Mevlana|Pazariçi|Sarıgöl|Şemsipaşa|Yenidoğan|Yenimahalle|Yıldıztabya',
      'güngören': 'Abdurrahman Nafiz Gürman|Akıncılar|Gençosman|Güneştepe|Güven|Haznedar|Mareşal Fevzi Çakmak|Mehmet Nezih Özmen|Merkez|Sanayi|Tozkoparan',
      'kadıköy': '19 Mayıs|Acıbadem|Bostancı|Caddebostan|Caferağa|Dumlupınar|Eğitim|Erenköy|Fenerbahçe|Feneryolu|Fikirtepe|Göztepe|Hasanpaşa|Koşuyolu|Kozyatağı|Merdivenköy|Osmanağa|Rasimpaşa|Sahrayıcedid|Suadiye|Zühtüpaşa',
      'kağıthane': 'Çağlayan|Çeliktepe|Emniyet Evleri|Gültepe|Gürsel|Hamidiye|Harmantepe|Hürriyet|Mehmet Akif Ersoy|Merkez|Nurtepe|Ortabayır|Seyrantepe|Sultan Selim|Şirintepe|Talatpaşa|Telsizler|Yahya Kemal|Yeşilce',
      'kartal': 'Atalar|Cevizli|Cumhuriyet|Çavuşoğlu|Esentepe|Gümüşpınar|Hürriyet|Karlıktepe|Kordonboyu|Orhantepe|Ortamahalle|Petrol-İş|Soğanlık|Topselvi|Uğur Mumcu|Yakacık Çarşı|Yakacık Yeni|Yalı|Yukarımahalle|Yunus',
      'küçükçekmece': 'Atakent|Atatürk|Beşyol|Cennet|Cumhuriyet|Fatih|Fevzi Çakmak|Gültepe|Halkalı|İnönü|İstasyon|Kanarya|Kartaltepe|Kemalpaşa|Mehmet Akif|Söğütlüçeşme|Sultanmurat|Tevfikbey|Yarımburgaz|Yenimahalle|Yeşilova',
      'maltepe': 'Altayçeşme|Altıntepe|Aydınevler|Bağlarbaşı|Başıbüyük|Büyükbakkalköy|Cevizli|Çınar|Esenkent|Feyzullah|Fındıklı|Girne|Gülensu|Gülsuyu|İdealtepe|Küçükyalı|Yalı|Zümrütevler',
      'pendik': 'Ahmet Yesevi|Bahçelievler|Batı|Çamçeşme|Çamlık|Çınardere|Doğu|Dumlupınar|Ertuğrulgazi|Esenler|Esenyalı|Fatih|Fevzi Çakmak|Güllübağlar|Güzelyalı|Harmandere|Kavakpınar|Kaynarca|Kurtköy|Orhangazi|Orta|Ramazanoğlu|Sanayi|Sapanbağları|Sülüntepe|Şeyhli|Velibaba|Yayalar|Yenimahalle|Yenişehir|Yeşilbağlar',
      'sancaktepe': 'Abdurrahmangazi|Akpınar|Atatürk|Emek|Eyüp Sultan|Fatih|Hilal|İnönü|Kemal Türkler|Meclis|Merve|Mevlana|Osmangazi|Safa|Sarıgazi|Veysel Karani|Yenidoğan|Yunus Emre',
      'sarıyer': 'Ayazağa|Bahçeköy|Bahçeköy Kemer|Bahçeköy Yenimahalle|Baltalimanı|Büyükdere|Cumhuriyet|Çayırbaşı|Darüşşafaka|Demirciköy|Derbent|Emirgân|Fatih Sultan Mehmet|Ferahevler|Garipçe|İstinye|Kâzım Karabekir|Kireçburnu|Kocataş|Kumköy|Maden|Maslak|Merkez|Pınar|Poligon|PTT Evleri|Reşitpaşa|Rumelihisarı|Rumelifeneri|Rumelikavağı|Tarabya|Uskumruköy|Yeniköy|Yenimahalle|Zekeriyaköy',
      'silivri': 'Alibey|Alipaşa|Büyük Çavuşlu|Cumhuriyet|Çanta Fatih|Çanta Mimarsinan|Değirmenköy Fevzipaşa|Değirmenköy İsmetpaşa|Fatih|Gazitepe|Gümüşyaka|Kadıköy|Kavaklı Cumhuriyet|Kavaklı Hürriyet|Küçük Kılıçlı|Mimar Sinan|Ortaköy|Piri Mehmet Paşa|Selimpaşa|Semizkumlar|Yenimahalle|Yolçatı',
      'sultanbeyli': 'Abdurrahmangazi|Adil|Ahmet Yesevi|Akşemsettin|Battalgazi|Fatih|Hamidiye|Hasanpaşa|Mecidiye|Mehmet Akif|Mimarsinan|Necip Fazıl|Orhangazi|Turgutreis|Yavuz Selim',
      'sultangazi': '50. Yıl|75. Yıl|Cebeci|Cumhuriyet|Esentepe|Eski Habibler|Gazi|Habibler|İsmetpaşa|Malkoçoğlu|Sultançiftliği|Uğur Mumcu|Yayla|Yunusemre|Zübeydehanım',
      'şile': 'Ağva|Balibey|Çavuş|Hacıkasım|Kumbaba',
      'şişli': '19 Mayıs|Bozkurt|Cumhuriyet|Duatepe|Ergenekon|Esentepe|Eskişehir|Feriköy|Fulya|Gülbahar|Halaskargazi|Halide Edip Adıvar|Halil Rıfat Paşa|Harbiye|İnönü|İzzetpaşa|Kaptanpaşa|Kuştepe|Mahmut Şevket Paşa|Mecidiyeköy|Merkez|Meşrutiyet|Paşa|Teşvikiye|Yayla',
      'tuzla': 'Akfırat|Anadolu|Aydınlı|Aydıntepe|Cami|Evliya Çelebi|Fatih|İçmeler|İstasyon|Mescit|Mimar Sinan|Orhanlı|Orta|Postane|Şifa|Tepeören|Yayla',
      'ümraniye': 'Adem Yavuz|Altınşehir|Armağanevler|Aşağıdudullu|Atakent|Atatürk|Cemil Meriç|Çakmak|Çamlık|Dumlupınar|Elmalıkent|Esenevler|Esenkent|Esenşehir|Fatih Sultan Mehmet|Finanskent|Hekimbaşı|Huzur|Ihlamurkuyu|İnkılap|İstiklal|Kâzım Karabekir|Madenler|Mehmet Akif|Namık Kemal|Necip Fazıl|Parseller|Site|Şerifali|Tantavi|Tatlısu|Tepeüstü|Topağacı|Yamanevler|Yukarıdudullu',
      'üsküdar': 'Acıbadem|Ahmediye|Altunizade|Aziz Mahmud Hüdayi|Bahçelievler|Barbaros|Beylerbeyi|Bulgurlu|Burhaniye|Cumhuriyet|Çengelköy|Ferah|Güzeltepe|İcadiye|Kandilli|Kirazlıtepe|Kısıklı|Kuleli|Kuzguncuk|Küçük Çamlıca|Küçüksu|Küplüce|Mehmet Akif Ersoy|Mimar Sinan|Murat Reis|Salacak|Selami Ali|Selimiye|Sultantepe|Ünalan|Valide-i Atik|Yavuztürk|Zeynep Kamil',
      'zeytinburnu': 'Beştelsiz|Çırpıcı|Gökalp|Kazlıçeşme|Maltepe|Merkezefendi|Nuripaşa|Seyitnizam|Sümer|Telsiz|Veliefendi|Yenidoğan|Yeşiltepe',
    };
    return v.map((k, val) => MapEntry(k, val.split('|')));
  }
}
