import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';

String _fmt(double n) {
  if (n == n.roundToDouble()) {
    return n.toStringAsFixed(0).replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');
  }
  final parts = n.toStringAsFixed(2).split('.');
  final intPart = parts[0].replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');
  return '$intPart,${parts[1]}';
}

Future<Uint8List> generateAiTeklifPdf({
  required Map<String, dynamic> hesapSonucu,
  required String aiOzet,
  required String il,
  required String ilce,
  required String mahalle,
  required String firmaAdi,
  Uint8List? firmaLogosu,
}) async {
  final pdf = pw.Document();
  final font = await PdfGoogleFonts.notoSansRegular();
  final fontBold = await PdfGoogleFonts.notoSansBold();

  final senaryo = hesapSonucu['senaryo'] as int;
  final tarih = DateFormat('dd.MM.yyyy').format(DateTime.now());

  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      theme: pw.ThemeData.withFont(base: font, bold: fontBold),
      header: (context) => _buildHeader(firmaAdi, firmaLogosu, tarih, font, fontBold),
      footer: (context) => pw.Container(
        alignment: pw.Alignment.centerRight,
        margin: const pw.EdgeInsets.only(top: 10),
        child: pw.Text('Sayfa ${context.pageNumber} / ${context.pagesCount}',
            style: pw.TextStyle(font: font, fontSize: 9, color: PdfColors.grey600)),
      ),
      build: (context) {
        final widgets = <pw.Widget>[];

        // Başlık
        widgets.add(pw.Center(
          child: pw.Text(
            'AI DESTEKLİ İNŞAAT TEKLİF ANALİZİ',
            style: pw.TextStyle(font: fontBold, fontSize: 16, color: PdfColors.blue900),
          ),
        ));
        widgets.add(pw.SizedBox(height: 4));
        widgets.add(pw.Center(
          child: pw.Text(
            'Senaryo ${senaryo}: ${senaryo == 1 ? "Müteahhit Daire Almıyor" : "Müteahhit Daire Alıyor"}',
            style: pw.TextStyle(font: font, fontSize: 11, color: PdfColors.grey700),
          ),
        ));
        widgets.add(pw.SizedBox(height: 16));

        // Konum ve Temel Bilgiler
        widgets.add(_sectionTitle('PROJE BİLGİLERİ', fontBold));
        widgets.add(_buildInfoTable([
          ['Konum', '$il / $ilce / $mahalle'],
          ['Toplam İnşaat Alanı', '${_fmt(hesapSonucu['toplamInsaatM2'])} m²'],
          ['İnşaat Süresi', '${hesapSonucu['insaatSuresi']} ay'],
          ['Kar Oranı', '%${_fmt(hesapSonucu['karOrani'])}'],
        ], font, fontBold));
        widgets.add(pw.SizedBox(height: 12));

        // Maliyet Analizi
        widgets.add(_sectionTitle('MALİYET ANALİZİ (TCMB İnşaat Maliyet Endeksine Dayalı)', fontBold));
        widgets.add(_buildInfoTable([
          ['Güncel m² Maliyeti', '${_fmt(hesapSonucu['guncelM2Maliyet'])} ₺'],
          ['Yıllık İnşaat Enflasyonu', '%${(hesapSonucu['yillikEnflasyon'] as double).toStringAsFixed(1)}'],
          ['Enflasyonlu m² Maliyeti', '${_fmt(hesapSonucu['enflasyonluM2Maliyet'])} ₺'],
          ['Kar Dahil m² Fiyat', '${_fmt(hesapSonucu['karliM2Fiyat'])} ₺'],
          ['Toplam Proje Maliyeti', '${_fmt(hesapSonucu['toplamMaliyet'])} ₺'],
        ], font, fontBold));
        widgets.add(pw.SizedBox(height: 12));

        // Senaryo 2: Müteahhit daireleri
        if (senaryo == 2 && hesapSonucu['muteahhitDaireleri'] != null) {
          widgets.add(_sectionTitle('MÜTEAHHİT DAİRELERİ', fontBold));
          final mutRows = <List<String>>[
            ['Tip', 'm²', 'Kat', 'Tahmini Satış'],
          ];
          for (final d in (hesapSonucu['muteahhitDaireleri'] as List)) {
            mutRows.add([
              d['tip'] ?? 'Daire',
              '${_fmt((d['m2'] as num).toDouble())}',
              '${d['kat']}',
              '${_fmt((d['tahminiSatisFiyati'] as num).toDouble())} ₺',
            ]);
          }
          widgets.add(_buildTable(mutRows, font, fontBold));
          widgets.add(pw.SizedBox(height: 4));
          widgets.add(pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            children: [
              pw.Text('Müteahhit Satış Geliri: ${_fmt((hesapSonucu['muteahhitSatisGeliri'] as num).toDouble())} ₺',
                  style: pw.TextStyle(font: fontBold, fontSize: 10)),
              pw.SizedBox(width: 20),
              pw.Text('Kalan Maliyet: ${_fmt((hesapSonucu['kalanMaliyet'] as num).toDouble())} ₺',
                  style: pw.TextStyle(font: fontBold, fontSize: 10, color: PdfColors.red)),
            ],
          ));
          widgets.add(pw.SizedBox(height: 12));
        }

        // Mal Sahibi Daire Ödemeleri
        widgets.add(_sectionTitle('MAL SAHİBİ ÖDEME TABLOSU', fontBold));
        final daireler = senaryo == 1
            ? (hesapSonucu['daireler'] as List)
            : (hesapSonucu['malSahibiDaireleri'] as List);

        final rows = <List<String>>[
          ['No', 'Tip', 'm²', 'Kat', 'Brüt Tutar', 'Hibe', 'Kredi', 'Net Ödeme'],
        ];
        for (int i = 0; i < daireler.length; i++) {
          final d = daireler[i];
          rows.add([
            '${i + 1}',
            d['tip'] ?? 'Daire',
            '${_fmt((d['m2'] as num).toDouble())}',
            '${d['kat']}',
            '${_fmt((d['brutMaliyet'] as num).toDouble())} ₺',
            d['hibeVar'] == true ? '${_fmt((d['hibeTutari'] as num).toDouble())} ₺' : '-',
            d['krediVar'] == true ? '${_fmt((d['krediTutari'] as num).toDouble())} ₺' : '-',
            '${_fmt((d['netOdeme'] as num).toDouble())} ₺',
          ]);
        }
        widgets.add(_buildTable(rows, font, fontBold));
        widgets.add(pw.SizedBox(height: 16));

        // AI Özet
        if (aiOzet.isNotEmpty) {
          widgets.add(_sectionTitle('AI ANALİZ ÖZETİ', fontBold));
          widgets.add(pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey400),
              borderRadius: pw.BorderRadius.circular(4),
              color: PdfColors.grey50,
            ),
            child: pw.Text(aiOzet, style: pw.TextStyle(font: font, fontSize: 9, lineSpacing: 4)),
          ));
          widgets.add(pw.SizedBox(height: 12));
        }

        // Uyarı
        widgets.add(pw.Container(
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.amber),
            color: PdfColors.amber50,
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: pw.Text(
            'NOT: Bu teklif AI destekli tahminler içermektedir. Enflasyon projeksiyonu TCMB İnşaat Maliyet Endeksi\'ne, '
            'daire satış fiyatları AI tahminlerine dayanmaktadır. Gerçek piyasa koşullarına göre değişiklik gösterebilir.',
            style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey800),
          ),
        ));

        return widgets;
      },
    ),
  );

  return pdf.save();
}

pw.Widget _buildHeader(String firmaAdi, Uint8List? logo, String tarih, pw.Font font, pw.Font fontBold) {
  return pw.Container(
    margin: const pw.EdgeInsets.only(bottom: 10),
    padding: const pw.EdgeInsets.only(bottom: 8),
    decoration: const pw.BoxDecoration(
      border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey400, width: 1)),
    ),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Row(
          children: [
            if (logo != null)
              pw.Container(
                width: 40,
                height: 40,
                margin: const pw.EdgeInsets.only(right: 10),
                child: pw.Image(pw.MemoryImage(logo), fit: pw.BoxFit.contain),
              ),
            pw.Text(firmaAdi, style: pw.TextStyle(font: fontBold, fontSize: 14)),
          ],
        ),
        pw.Text('Tarih: $tarih', style: pw.TextStyle(font: font, fontSize: 9, color: PdfColors.grey600)),
      ],
    ),
  );
}

pw.Widget _sectionTitle(String title, pw.Font fontBold) {
  return pw.Container(
    margin: const pw.EdgeInsets.only(bottom: 6),
    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: pw.BoxDecoration(
      color: PdfColors.blue50,
      borderRadius: pw.BorderRadius.circular(2),
    ),
    child: pw.Text(title, style: pw.TextStyle(font: fontBold, fontSize: 11, color: PdfColors.blue900)),
  );
}

pw.Widget _buildInfoTable(List<List<String>> rows, pw.Font font, pw.Font fontBold) {
  return pw.Table(
    columnWidths: {0: const pw.FlexColumnWidth(2), 1: const pw.FlexColumnWidth(3)},
    children: rows.map((row) {
      return pw.TableRow(
        children: [
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 4),
            child: pw.Text(row[0], style: pw.TextStyle(font: fontBold, fontSize: 9)),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 4),
            child: pw.Text(row[1], style: pw.TextStyle(font: font, fontSize: 9)),
          ),
        ],
      );
    }).toList(),
  );
}

pw.Widget _buildTable(List<List<String>> rows, pw.Font font, pw.Font fontBold) {
  return pw.TableHelper.fromTextArray(
    headerCount: 1,
    headerStyle: pw.TextStyle(font: fontBold, fontSize: 9),
    headerDecoration: const pw.BoxDecoration(color: PdfColors.blue50),
    cellStyle: pw.TextStyle(font: font, fontSize: 8),
    cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
    cellAlignment: pw.Alignment.centerLeft,
    border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
    data: rows.sublist(1),
    headers: rows[0],
  );
}
