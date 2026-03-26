import 'dart:typed_data';
import 'dart:developer' as developer;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

String _formatNumber(double num) {
  final rounded = num.ceilToDouble();
  return rounded.toStringAsFixed(0).replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]}.',
  );
}

double _parseFormatted(String text) {
  if (text.isEmpty) return 0.0;
  final cleaned = text.replaceAll('.', '').replaceAll(',', '.');
  return double.tryParse(cleaned) ?? 0.0;
}

Future<Uint8List> generateSimplePdf({
  required String sirket,
  required String ilce,
  required String mahalle,
  required String ada,
  required String parsel,
  required double toplamInsaatAlani,
  required double daireBirimMaliyet,
  required double dukkanBirimMaliyet,
  required double ortakAlanBirimMaliyet,
  required double toplamOrtakAlanM2,
  required double daireBasiDusenOrtakM2,
  required double daireBasiOrtakMaliyet,
  required double daireHibeLim,
  required double daireKrediLim,
  required double dukkanHibeLim,
  required double dukkanKrediLim,
  required double hibeTutari,
  required double krediTutari,
  required List<dynamic> katListesi,
  Uint8List? firmaLogosu,
}) async {
  final pdf = pw.Document();
  final format = PdfPageFormat.a4.landscape;

  // Font yükle - printing paketinden
  final font = await PdfGoogleFonts.notoSansRegular();
  final fontBold = await PdfGoogleFonts.notoSansBold();

  developer.log('PDF oluşturma başladı', name: 'pdf_service_simple',
      error: {'kat_sayisi': katListesi.length});

  double toplamToprakParasi = 0;
  double muteahhitToplamMaliyet = 0;
  int malSahibiSayisi = 0;
  bool muteahhitVar = false;
  final ortakAlanIsimleri = <String>['Asansör Kulesi (25 m²)'];

  final visualFloors = <int, List<Map<String, dynamic>>>{
    for (int i = 0; i < katListesi.length; i++) i: <Map<String, dynamic>>[],
  };

  for (int i = 0; i < katListesi.length; i++) {
    final kat = katListesi[i];
    for (final b in kat.bolumler) {
      if (b.isOrtakAlan) {
        ortakAlanIsimleri.add('${b.tip} (${_formatNumber(b.girilenM2)} m²)');
      } else {
        final birimMaliyet = b.tip.contains('Dükkan') ? dukkanBirimMaliyet : daireBirimMaliyet;
        final insaatMaliyeti = b.toplamMetrekare * birimMaliyet;
        final toplamMaliyet = insaatMaliyeti + daireBasiOrtakMaliyet;
        if (b.sahip == 'Müteahhit') {
          muteahhitVar = true;
          toplamToprakParasi += b.girilenToprakParasi;
          muteahhitToplamMaliyet += toplamMaliyet;
        } else {
          malSahibiSayisi++;
        }
      }

      final isMut = b.sahip == 'Müteahhit';
      final isOrt = b.isOrtakAlan;
      final tipKisa = b.tip.length > 7 ? b.tip.substring(0, 7) : b.tip;
      double area = 0;
      String labelEk = '';

      if (b.tip == 'Dubleks') {
        area = _parseFormatted(b.m2Ctrl.text);
        labelEk = '(Alt)';
        if (i < katListesi.length - 1) {
          final ustM2 = _parseFormatted(b.ustKatM2Ctrl.text);
          visualFloors[i + 1]?.add({
            'label': '$tipKisa (Üst)',
            'sub': isMut ? 'MÜT' : (isOrt ? 'ORT' : 'MAL'),
            'm2': ustM2,
            'flex': ustM2.round(),
            'bg': isOrt ? PdfColors.grey300 : (isMut ? PdfColors.white : PdfColors.green50),
            'border': isMut ? PdfColors.red : PdfColors.black,
            'textCol': isMut ? PdfColors.red : PdfColors.black,
          });
        }
      } else if (b.tip == 'Ters Dubleks' || b.tip == 'Depolu Dükkan') {
        area = _parseFormatted(b.m2Ctrl.text);
        labelEk = '(Giriş)';
        if (i > 0) {
          final altM2 = _parseFormatted(b.altKatM2Ctrl.text);
          visualFloors[i - 1]?.add({
            'label': '$tipKisa (Alt)',
            'sub': isMut ? 'MÜT' : (isOrt ? 'ORT' : 'MAL'),
            'm2': altM2,
            'flex': altM2.round(),
            'bg': isOrt ? PdfColors.grey300 : (isMut ? PdfColors.white : PdfColors.green50),
            'border': isMut ? PdfColors.red : PdfColors.black,
            'textCol': isMut ? PdfColors.red : PdfColors.black,
          });
        }
      } else {
        area = _parseFormatted(b.m2Ctrl.text);
      }

      visualFloors[i]?.add({
        'label': '$tipKisa $labelEk',
        'sub': isMut ? 'MÜT' : (isOrt ? 'ORT' : 'MAL'),
        'm2': area,
        'flex': area.round(),
        'bg': isOrt ? PdfColors.grey300 : (isMut ? PdfColors.white : PdfColors.green50),
        'border': isMut ? PdfColors.red : PdfColors.black,
        'textCol': isMut ? PdfColors.red : PdfColors.black,
      });
    }
  }

  final ortakAlanAciklamasi = ortakAlanIsimleri.join(', ');
  final kisiBasiToprakIadesi = (malSahibiSayisi > 0 && toplamToprakParasi > 0)
      ? (toplamToprakParasi / malSahibiSayisi)
      : 0;
  final toprakSutunuVar = toplamToprakParasi > 0;

  final satirSayisi = katListesi.fold<int>(0, (sum, kat) {
    final katSatirSayisi = kat.bolumler.where((b) => !b.isOrtakAlan).length;
    return sum + katSatirSayisi as int;
  });
  const binaAyriSayfa = true;

  developer.log('Toplam satır sayısı', name: 'pdf_service_simple', error: satirSayisi);

  double malSahibiNetToplam = 0;

  pw.Widget cell(
    String text, {
    pw.TextAlign align = pw.TextAlign.center,
    PdfColor color = PdfColors.black,
    bool isBold = false,
    double fontSize = 7,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(2),
      child: pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(
          fontSize: fontSize,
          color: color,
          fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
          font: isBold ? fontBold : font,
        ),
      ),
    );
  }

  pw.Widget headerCell(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(2),
      child: pw.Text(
        text,
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(
          fontSize: 7,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.white,
          font: fontBold,
        ),
      ),
    );
  }

  pw.Widget bulletText(String text, PdfColor color, {double fontSize = 7}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(left: 8, top: 2),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            margin: const pw.EdgeInsets.only(top: 2, right: 4),
            width: 3,
            height: 3,
            decoration: pw.BoxDecoration(color: color, shape: pw.BoxShape.circle),
          ),
          pw.Expanded(
            child: pw.Text(
              text,
              style: pw.TextStyle(fontSize: fontSize, color: color, font: font),
            ),
          ),
        ],
      ),
    );
  }

  final tumSatirlar = <pw.TableRow>[];
  for (final kat in katListesi) {
    for (final b in kat.bolumler.where((b) => !b.isOrtakAlan)) {
      final birimMaliyet = b.tip.contains('Dükkan') ? dukkanBirimMaliyet : daireBirimMaliyet;
      final insaatMaliyeti = b.toplamMetrekare * birimMaliyet;
      final hibeTL = (b.daireHibeSayisi * daireHibeLim) + (b.dukkanHibeSayisi * dukkanHibeLim);
      final krediTL = (b.daireKrediSayisi * daireKrediLim) + (b.dukkanKrediSayisi * dukkanKrediLim);

      String netTutarStr;
      PdfColor netColor;
      bool isBold = false;

      if (b.sahip == 'Müteahhit') {
        netTutarStr = '0';
        netColor = PdfColors.black;
      } else {
        final netHesap = (insaatMaliyeti + daireBasiOrtakMaliyet) - hibeTL - krediTL - kisiBasiToprakIadesi;
        netTutarStr = _formatNumber(netHesap);
        netColor = netHesap <= 0 ? PdfColors.green900 : PdfColors.black;
        isBold = true;

        if (b.sahip == 'Mal Sahibi') {
          malSahibiNetToplam += netHesap;
        }
      }

      tumSatirlar.add(
        pw.TableRow(
          decoration: pw.BoxDecoration(color: b.sahip == 'Müteahhit' ? PdfColors.red50 : PdfColors.white),
          children: [
            cell('${kat.ad} - ${b.tip}\n(${b.sahip})', align: pw.TextAlign.left, fontSize: 6),
            cell(_formatNumber(b.toplamMetrekare), fontSize: 6),
            cell(_formatNumber(insaatMaliyeti), fontSize: 6),
            cell(_formatNumber(daireBasiOrtakMaliyet), fontSize: 6),
            cell(hibeTL > 0 ? '-${_formatNumber(hibeTL)}' : '-', color: PdfColors.green700, fontSize: 6),
            cell(krediTL > 0 ? '-${_formatNumber(krediTL)}' : '-', color: PdfColors.blue700, fontSize: 6),
            if (toprakSutunuVar)
              cell(b.sahip == 'Mal Sahibi' ? '-${_formatNumber(kisiBasiToprakIadesi.toDouble())}' : '-', color: PdfColors.orange800, fontSize: 6),
            cell(netTutarStr, color: netColor, isBold: isBold, fontSize: 6),
          ],
        ),
      );
    }
  }

  const int satirPerPage = 18;
  final int toplamSayfaSayisi = (tumSatirlar.length / satirPerPage).ceil().clamp(1, 9999);

  pw.Widget ozetSatir(String baslik, String deger) {
    return pw.Column(
      children: [
        pw.Text(baslik, style: pw.TextStyle(fontSize: 7, color: PdfColors.grey700, font: font)),
        pw.Text(deger, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, font: fontBold)),
      ],
    );
  }

  developer.log('Basit PDF oluşturma başladı', name: 'pdf_service_simple');

  for (int sayfaNo = 0; sayfaNo < toplamSayfaSayisi; sayfaNo++) {
    final baslangic = sayfaNo * satirPerPage;
    final bitis = (baslangic + satirPerPage).clamp(0, tumSatirlar.length);
    final sayfaSatirlari = tumSatirlar.sublist(baslangic, bitis);

    final ilkSayfa = sayfaNo == 0;
    final sonSayfa = sayfaNo == toplamSayfaSayisi - 1;

    developer.log('Sayfa oluşturuluyor', name: 'pdf_service_simple', error: {
      'sayfa': sayfaNo + 1,
      'toplam': toplamSayfaSayisi,
      'satir_araligi': '$baslangic-$bitis'
    });

    pdf.addPage(
      pw.Page(
        pageFormat: format,
        margin: const pw.EdgeInsets.all(15),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            if (ilkSayfa) ...[
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      if (firmaLogosu != null)
                        pw.Image(pw.MemoryImage(firmaLogosu), width: 120, height: 120)
                      else
                        pw.Text(
                          sirket.toUpperCase(),
                          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, font: fontBold),
                        ),
                      pw.SizedBox(height: 2),
                      pw.Text('MALİYET DAĞILIM VE TEKLİF RAPORU', style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700, font: font)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('PROJE BİLGİLERİ', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, font: fontBold)),
                      pw.Text('İlçe: $ilce', style: pw.TextStyle(fontSize: 7, font: font)),
                      pw.Text('Mahalle: $mahalle', style: pw.TextStyle(fontSize: 7, font: font)),
                      pw.Text('Ada: $ada - Parsel: $parsel', style: pw.TextStyle(fontSize: 7, font: font)),
                    ],
                  ),
                ],
              ),
              pw.Divider(color: PdfColors.blueGrey, thickness: 0.5),
              pw.SizedBox(height: 3),
            ] else ...[
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('MALİYET DAĞILIM TABLOSU (Devam)', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, font: fontBold)),
                  pw.Text('Sayfa ${sayfaNo + 1}/$toplamSayfaSayisi', style: pw.TextStyle(fontSize: 7, color: PdfColors.grey600, font: font)),
                ],
              ),
              pw.SizedBox(height: 5),
            ],

            pw.Container(
              padding: const pw.EdgeInsets.symmetric(vertical: 3),
              decoration: const pw.BoxDecoration(color: PdfColors.grey200),
              child: pw.Center(
                child: pw.Text(
                  ilkSayfa ? 'MALİYET DAĞILIM TABLOSU' : 'MALİYET DAĞILIM TABLOSU (Devam)',
                  style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, font: fontBold),
                ),
              ),
            ),

            pw.Expanded(
              child: pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                columnWidths: {
                  0: const pw.FlexColumnWidth(2.5),
                  1: const pw.FlexColumnWidth(0.7),
                  2: const pw.FlexColumnWidth(1),
                  3: const pw.FlexColumnWidth(1),
                  4: const pw.FlexColumnWidth(1),
                  5: const pw.FlexColumnWidth(1),
                  if (toprakSutunuVar) 6: const pw.FlexColumnWidth(1),
                  if (toprakSutunuVar) 7: const pw.FlexColumnWidth(1.2) else 6: const pw.FlexColumnWidth(1.2),
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
                    children: [
                      headerCell('Bölüm'),
                      headerCell('m²'),
                      headerCell('İnş.'),
                      headerCell('Ort.'),
                      headerCell('Hibe'),
                      headerCell('Kredi'),
                      if (toprakSutunuVar) headerCell('Top. iade'),
                      headerCell('NET'),
                    ],
                  ),
                  ...sayfaSatirlari,
                ],
              ),
            ),

            if (sonSayfa) ...[
              pw.SizedBox(height: 5),
              pw.Container(
                padding: const pw.EdgeInsets.all(4),
                decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400), color: PdfColors.grey100),
                child: pw.Column(
                  children: [
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                      children: [
                        ozetSatir('Toplam İnşaat', '${_formatNumber(toplamInsaatAlani)} m²'),
                        ozetSatir('Toplam Ortak', '${_formatNumber(toplamOrtakAlanM2)} m²'),
                        ozetSatir('BB Ortak Payı', '${_formatNumber(daireBasiDusenOrtakM2)} m²'),
                      ],
                    ),
                    pw.SizedBox(height: 5),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 10),
                      decoration: pw.BoxDecoration(color: PdfColors.blue100, borderRadius: pw.BorderRadius.circular(4)),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.center,
                        children: [
                          pw.Row(
                            mainAxisAlignment: pw.MainAxisAlignment.center,
                            children: [
                              pw.Text('MAL SAHİPLERİ TOPLAM ÖDEME (Net): ', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, font: fontBold)),
                              pw.Text('${_formatNumber(malSahibiNetToplam)} TL', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900, font: fontBold)),
                            ],
                          ),
                          pw.SizedBox(height: 4),
                          pw.Row(
                            mainAxisAlignment: pw.MainAxisAlignment.center,
                            children: [
                              pw.Text('Hibe/Kredi Toplamı: ', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey800, font: fontBold)),
                              pw.Text('${_formatNumber(hibeTutari + krediTutari)} TL', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey900, font: fontBold)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 5),
              pw.Container(
                padding: const pw.EdgeInsets.all(5),
                decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.blueGrey200), color: PdfColors.blue50),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('FİNANSAL VE TEKNİK AÇIKLAMA:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7, decoration: pw.TextDecoration.underline, font: fontBold)),
                    bulletText('Dahil edilen ortak alanlar: $ortakAlanAciklamasi.', PdfColors.black, fontSize: 6),
                    if (muteahhitVar)
                      bulletText('Müteahhit, kendi dairelerinin maliyeti olan ${_formatNumber(muteahhitToplamMaliyet)} TL tutarını kendi karşılayacaktır.', PdfColors.red, fontSize: 6),
                    if (toprakSutunuVar)
                      bulletText('Müteahhit tarafından ödenen ${_formatNumber(toplamToprakParasi)} TL toprak parası, mal sahiplerinden düşülmüştür.', PdfColors.red, fontSize: 6),
                    if (binaAyriSayfa) bulletText('Bina kesit görünümü bir sonraki sayfada.', PdfColors.blue, fontSize: 6),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  developer.log('Tablo sayfaları eklendi', name: 'pdf_service_simple');

  if (binaAyriSayfa) {
    final reversedIndices = List.generate(katListesi.length, (index) => index).reversed.toList();

    pdf.addPage(
      pw.Page(
        pageFormat: format,
        margin: const pw.EdgeInsets.all(15),
        build: (context) => pw.Column(
          children: [
            pw.Text('BİNA KESİT GÖRÜNÜMÜ', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, font: fontBold)),
            pw.SizedBox(height: 10),
            pw.Expanded(
              child: pw.Column(
                mainAxisAlignment: pw.MainAxisAlignment.center,
                children: [
                  pw.CustomPaint(
                    size: const PdfPoint(400, 30),
                    painter: (canvas, size) {
                      canvas
                        ..setFillColor(PdfColors.red700)
                        ..moveTo(0, 0)
                        ..lineTo(size.x * 0.5, size.y)
                        ..lineTo(size.x, 0)
                        ..closePath()
                        ..fillPath();
                    },
                  ),
                  ...reversedIndices.map((idx) {
                    final floor = visualFloors[idx] ?? [];
                    if (floor.isEmpty) return pw.SizedBox();

                    return pw.Container(
                      margin: const pw.EdgeInsets.symmetric(vertical: 1),
                      child: pw.Row(
                        children: [
                          pw.Container(
                            width: 60,
                            padding: const pw.EdgeInsets.all(3),
                            decoration: pw.BoxDecoration(border: pw.Border.all(), color: PdfColors.grey200),
                            child: pw.Center(child: pw.Text(katListesi[idx].ad, style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, font: fontBold))),
                          ),
                          pw.SizedBox(width: 5),
                          pw.Expanded(
                            child: pw.Row(
                              children: floor.map<pw.Widget>((room) {
                                return pw.Expanded(
                                  flex: room['flex'] as int,
                                  child: pw.Container(
                                    height: 40,
                                    decoration: pw.BoxDecoration(color: room['bg'] as PdfColor, border: pw.Border.all(color: room['border'] as PdfColor, width: 1)),
                                    child: pw.Column(
                                      mainAxisAlignment: pw.MainAxisAlignment.center,
                                      children: [
                                        pw.Text(room['label'] as String, style: pw.TextStyle(fontSize: 5, color: room['textCol'] as PdfColor, font: font), textAlign: pw.TextAlign.center),
                                        pw.Text('${_formatNumber(room['m2'] as double)} m²', style: pw.TextStyle(fontSize: 5, fontWeight: pw.FontWeight.bold, color: room['textCol'] as PdfColor, font: fontBold)),
                                        pw.Text(room['sub'] as String, style: pw.TextStyle(fontSize: 4, color: room['textCol'] as PdfColor, font: font)),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  pw.Container(height: 3, color: PdfColors.brown),
                ],
              ),
            ),
            pw.SizedBox(height: 10),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                pw.Row(children: [pw.Container(width: 15, height: 15, decoration: pw.BoxDecoration(color: PdfColors.green50, border: pw.Border.all(color: PdfColors.black, width: 1))), pw.SizedBox(width: 5), pw.Text('MAL SAHİBİ', style: pw.TextStyle(fontSize: 7, font: font))]),
                pw.SizedBox(width: 20),
                pw.Row(children: [pw.Container(width: 15, height: 15, decoration: pw.BoxDecoration(color: PdfColors.white, border: pw.Border.all(color: PdfColors.red, width: 1))), pw.SizedBox(width: 5), pw.Text('MÜTEAHHİT', style: pw.TextStyle(fontSize: 7, font: font))]),
                pw.SizedBox(width: 20),
                pw.Row(children: [pw.Container(width: 15, height: 15, decoration: pw.BoxDecoration(color: PdfColors.grey300, border: pw.Border.all(color: PdfColors.black, width: 1))), pw.SizedBox(width: 5), pw.Text('ORTAK ALAN', style: pw.TextStyle(fontSize: 7, font: font))]),
              ],
            ),
          ],
        ),
      ),
    );

    developer.log('İkinci sayfa (bina krokisi) eklendi', name: 'pdf_service_simple');
  }

  final bytes = await pdf.save();
  developer.log('PDF kaydedildi', name: 'pdf_service_simple', error: bytes.length);
  return bytes;
}