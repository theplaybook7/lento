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
    // Gün sayısına göre azalan sırala (en pasif proje üstte)
    pasifProjeler.sort((a, b) {
      final ag = (a['gun'] is num) ? (a['gun'] as num).toInt() : 0;
      final bg = (b['gun'] is num) ? (b['gun'] as num).toInt() : 0;
      return bg.compareTo(ag);
    });

    String _sonIslemStr(dynamic s) {
      if (s is String && s.isNotEmpty) {
        try {
          final dt = DateTime.parse(s);
          return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
        } catch (_) {}
      }
      return '-';
    }

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
                'Aşağıdaki projelerde 2 gün veya daha uzun süredir ruhsat/akış diyagramı işlemi yapılmamıştır.',
            style: const pw.TextStyle(fontSize: 11),
          ),
          pw.Text('Toplam pasif proje: ${pasifProjeler.length}',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
          pw.SizedBox(height: 10),
          // Her proje: başlık (sıra, ad, gün, son işlem) + notlar
          ...pasifProjeler.asMap().entries.expand((entry) {
            final i = entry.key;
            final p = entry.value;
            final notlar = (p['akisNotlari'] as List?)?.cast<Map<String, dynamic>>() ?? [];
            final projeAd = p['projeAd']?.toString() ?? '';
            final gun = p['gun'] ?? '';
            final sonStr = _sonIslemStr(p['sonIslemTarihi']);
            return [
              pw.SizedBox(height: i == 0 ? 0 : 10),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: const pw.BoxDecoration(color: PdfColors.blueGrey700),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Expanded(
                      child: pw.Text(
                        '${i + 1}. $projeAd',
                        style: pw.TextStyle(
                          fontSize: 11,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.white,
                        ),
                      ),
                    ),
                    pw.SizedBox(width: 8),
                    pw.Text(
                      '$gun gün  •  Son: $sonStr',
                      style: const pw.TextStyle(fontSize: 10, color: PdfColors.white),
                    ),
                  ],
                ),
              ),
              if (notlar.isEmpty)
                pw.Padding(
                  padding: const pw.EdgeInsets.fromLTRB(8, 4, 8, 0),
                  child: pw.Text(
                    'Akış diyagramı notu bulunmuyor.',
                    style: pw.TextStyle(
                        fontSize: 10,
                        color: PdfColors.grey700,
                        fontStyle: pw.FontStyle.italic),
                  ),
                )
              else
                pw.Padding(
                  padding: const pw.EdgeInsets.fromLTRB(8, 4, 8, 0),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: notlar.map((n) {
                      final sira = n['sira'] ?? 0;
                      final madde = n['madde']?.toString() ?? '';
                      final not = n['not']?.toString() ?? '';
                      return pw.Padding(
                        padding: const pw.EdgeInsets.only(bottom: 3),
                        child: pw.RichText(
                          text: pw.TextSpan(
                            style: const pw.TextStyle(fontSize: 10),
                            children: [
                              pw.TextSpan(
                                text: '$sira. $madde: ',
                                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                              ),
                              pw.TextSpan(text: not),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
            ];
          }),
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
    // Güvence: en uzun süredir pasif olan en üstte
    pasifProjeler.sort((a, b) {
      final ag = (a is Map && a['gun'] is num) ? (a['gun'] as num).toInt() : 0;
      final bg = (b is Map && b['gun'] is num) ? (b['gun'] as num).toInt() : 0;
      return bg.compareTo(ag);
    });

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
                  '2 gün veya daha uzun süredir işlem yapılmayan projeler:',
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
            margin: const EdgeInsets.only(bottom: 10),
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: renk.withValues(alpha: 0.3), width: 1),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ÜST: Büyük gün rozeti + proje adı
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: renk.withValues(alpha: 0.08),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: 64,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: renk,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: renk.withValues(alpha: 0.3),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              Text(
                                '$gun',
                                style: const TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  height: 1.0,
                                ),
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                'GÜN',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                  letterSpacing: 1.0,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '#${i + 1} • $projeAd',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (sonIslemStr.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  sonIslemStr,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // ALT: Notlar (madde başlığı + not metni)
                  if (p['akisNotlari'] is List &&
                      (p['akisNotlari'] as List).isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: ((p['akisNotlari'] as List).cast<dynamic>())
                            .map((n) {
                          final m = n as Map<String, dynamic>;
                          final sira = m['sira'] ?? 0;
                          final madde = m['madde']?.toString() ?? '';
                          final not = m['not']?.toString() ?? '';
                          final durum = m['durum'] ?? 0;
                          final Color dotColor = durum == 2
                              ? Colors.green
                              : (durum == 1 ? Colors.orange : Colors.blueGrey);
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.amber.shade200),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Başlık satırı: madde adı + durum noktası
                                Row(
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: dotColor,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        '$sira. $madde',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.amber.shade900,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                // Not metni
                                Text(
                                  not,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Colors.black87,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}
