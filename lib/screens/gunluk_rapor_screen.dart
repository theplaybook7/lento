import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../project_core.dart';
import '../theme/app_theme.dart';
import 'project_details_screen.dart';

/// Sabah 07:00'da Cloud Function tarafından oluşturulan günlük raporu
/// görüntüler. Yazdırma / PDF çıktısı alınabilir.
class GunlukRaporScreen extends StatefulWidget {
  final String? raporId; // Belirli bir rapor
  const GunlukRaporScreen({super.key, this.raporId});

  @override
  State<GunlukRaporScreen> createState() => _GunlukRaporScreenState();
}

class _GunlukRaporScreenState extends State<GunlukRaporScreen> {
  Map<String, dynamic>? _rapor;
  bool _yukleniyor = true;
  String? _hata;

  @override
  void initState() {
    super.initState();
    _raporuYukle();
  }

  Future<void> _raporuYukle() async {
    try {
      final sirketId = SistemYoneticisi().aktifSirket?.id;
      if (sirketId == null) {
        setState(() {
          _hata = 'Aktif şirket yok';
          _yukleniyor = false;
        });
        return;
      }

      DocumentSnapshot? doc;
      if (widget.raporId != null && widget.raporId!.isNotEmpty) {
        doc = await FirebaseFirestore.instance
            .collection('gunluk_raporlar')
            .doc(widget.raporId)
            .get();
      } else {
        // En son raporu bul
        final snap = await FirebaseFirestore.instance
            .collection('gunluk_raporlar')
            .where('sirketId', isEqualTo: sirketId)
            .orderBy('tarih', descending: true)
            .limit(1)
            .get();
        if (snap.docs.isNotEmpty) doc = snap.docs.first;
      }

      if (doc == null || !doc.exists) {
        setState(() {
          _hata = 'Henüz günlük rapor oluşturulmadı. Rapor her sabah 07:00\'da hazırlanır.';
          _yukleniyor = false;
        });
        return;
      }

      setState(() {
        _rapor = doc!.data() as Map<String, dynamic>;
        _yukleniyor = false;
      });
    } catch (e) {
      setState(() {
        _hata = 'Rapor yüklenirken hata: $e';
        _yukleniyor = false;
      });
    }
  }

  Future<Uint8List> _pdfOlustur() async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.notoSansRegular();
    final fontBold = await PdfGoogleFonts.notoSansBold();

    final rapor = _rapor ?? {};
    final sirketAd = rapor['sirketAd'] ?? SistemYoneticisi().aktifSirket?.ad ?? '';
    final tarihStr = rapor['tarihStr'] ?? '';
    final baslik = rapor['baslik'] ?? 'Günlük Rapor';
    final pasifProjeler =
        (rapor['pasifProjeler'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        theme: pw.ThemeData.withFont(base: font, bold: fontBold),
        build: (ctx) => [
          pw.Header(
            level: 0,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(sirketAd,
                    style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 4),
                pw.Text(baslik, style: const pw.TextStyle(fontSize: 14)),
                pw.Text('Tarih: $tarihStr', style: const pw.TextStyle(fontSize: 11)),
                pw.Divider(),
              ],
            ),
          ),
          pw.Paragraph(
            text:
                'Aşağıdaki projelerde 4 gün veya daha uzun süredir ruhsat/akış diyagramı işlemi yapılmamıştır.',
            style: const pw.TextStyle(fontSize: 11),
          ),
          pw.SizedBox(height: 8),
          pw.TableHelper.fromTextArray(
            headers: ['#', 'Proje Adı', 'Gün', 'Son İşlem'],
            data: List.generate(pasifProjeler.length, (i) {
              final p = pasifProjeler[i];
              String sonStr = '-';
              final s = p['sonIslemTarihi'];
              if (s is String && s.isNotEmpty) {
                try {
                  final dt = DateTime.parse(s);
                  sonStr =
                      '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
                } catch (_) {}
              }
              return [
                '${i + 1}',
                p['projeAd']?.toString() ?? '',
                '${p['gun'] ?? ''}',
                sonStr,
              ];
            }),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey700),
            cellAlignment: pw.Alignment.centerLeft,
            cellAlignments: {
              0: pw.Alignment.center,
              2: pw.Alignment.center,
              3: pw.Alignment.center,
            },
            columnWidths: {
              0: const pw.FixedColumnWidth(30),
              1: const pw.FlexColumnWidth(3),
              2: const pw.FixedColumnWidth(50),
              3: const pw.FixedColumnWidth(80),
            },
            cellStyle: const pw.TextStyle(fontSize: 10),
          ),
          pw.SizedBox(height: 12),
          pw.Text('Toplam pasif proje: ${pasifProjeler.length}',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        ],
        footer: (ctx) => pw.Container(
          alignment: pw.Alignment.centerRight,
          margin: const pw.EdgeInsets.only(top: 8),
          child: pw.Text(
            'Sayfa ${ctx.pageNumber} / ${ctx.pagesCount}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey),
          ),
        ),
      ),
    );

    return pdf.save();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Günlük Rapor'),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        actions: [
          if (_rapor != null)
            IconButton(
              icon: const Icon(Icons.print),
              tooltip: 'Yazdır / PDF Çıktı',
              onPressed: () async {
                await Printing.layoutPdf(
                  onLayout: (format) async => _pdfOlustur(),
                  name: 'gunluk_rapor_${_rapor?['tarihStr'] ?? ''}.pdf',
                );
              },
            ),
          if (_rapor != null)
            IconButton(
              icon: const Icon(Icons.share),
              tooltip: 'Paylaş',
              onPressed: () async {
                final bytes = await _pdfOlustur();
                await Printing.sharePdf(
                  bytes: bytes,
                  filename: 'gunluk_rapor_${_rapor?['tarihStr'] ?? ''}.pdf',
                );
              },
            ),
        ],
      ),
      body: _yukleniyor
          ? const Center(child: CircularProgressIndicator())
          : _hata != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.inbox_outlined, size: 64, color: Colors.grey.shade400),
                        const SizedBox(height: 12),
                        Text(
                          _hata!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 15),
                        ),
                      ],
                    ),
                  ),
                )
              : _raporBody(),
    );
  }

  Widget _raporBody() {
    final rapor = _rapor!;
    final sirketAd = rapor['sirketAd'] ?? '';
    final tarihStr = rapor['tarihStr'] ?? '';
    final pasifProjeler =
        (rapor['pasifProjeler'] as List?)?.cast<dynamic>() ?? [];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.report_problem_outlined,
                          color: Colors.red.shade700),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(sirketAd,
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold)),
                          Text('Günlük Rapor - $tarihStr',
                              style: TextStyle(color: Colors.grey.shade600)),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24),
                Text(
                  '4 gün veya daha uzun süredir işlem yapılmayan projeler:',
                  style: TextStyle(color: Colors.grey.shade700),
                ),
                const SizedBox(height: 4),
                Text('Toplam: ${pasifProjeler.length} proje',
                    style: TextStyle(
                        color: Colors.red.shade700,
                        fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        ...pasifProjeler.asMap().entries.map((e) {
          final i = e.key;
          final p = e.value as Map<String, dynamic>;
          final projeAd = p['projeAd']?.toString() ?? '';
          final gun = p['gun'] ?? 0;
          final projeId = p['projeId']?.toString() ?? '';
          String sonIslemStr = '';
          final s = p['sonIslemTarihi'];
          if (s is String && s.isNotEmpty) {
            try {
              final dt = DateTime.parse(s);
              sonIslemStr =
                  'Son işlem: ${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
            } catch (_) {}
          }

          Color renk;
          if (gun is num && gun >= 14) {
            renk = Colors.red;
          } else if (gun is num && gun >= 7) {
            renk = Colors.orange;
          } else {
            renk = Colors.amber;
          }

          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: renk.withValues(alpha: 0.15),
                foregroundColor: renk,
                child: Text('${i + 1}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
              title: Text(projeAd,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(sonIslemStr),
              trailing: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: renk.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('$gun gün',
                    style: TextStyle(
                        color: renk, fontWeight: FontWeight.bold)),
              ),
              onTap: projeId.isEmpty
                  ? null
                  : () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              ProjectDetailsScreen(projectId: projeId),
                        ),
                      );
                    },
            ),
          );
        }),
      ],
    );
  }
}
