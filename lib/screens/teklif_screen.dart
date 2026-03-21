import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../audit_log_servisi.dart';
import '../pdf_service.dart';
import '../pdf_viewer.dart';
import '../project_core.dart';
import '../theme/app_theme.dart';
import 'arsiv_screen.dart';

class TeklifSayfasi extends StatefulWidget {
  final Map<String, dynamic>? mevcutTeklifData;
  final String? mevcutDocId;

  const TeklifSayfasi({super.key, this.mevcutTeklifData, this.mevcutDocId});

  @override
  State<TeklifSayfasi> createState() => _TeklifSayfasiState();
}

class _TeklifSayfasiState extends State<TeklifSayfasi> {
  final ilceCtrl = TextEditingController();
  final mahalleCtrl = TextEditingController();
  final adaCtrl = TextEditingController();
  final parselCtrl = TextEditingController();
  final eskiDaireSayisiCtrl = TextEditingController(text: '0');
  final eskiDukkanSayisiCtrl = TextEditingController(text: '0');

  final daireHibeLimitCtrl = TextEditingController(text: '875.000');
  final daireKrediLimitCtrl = TextEditingController(text: '875.000');
  final dukkanHibeLimitCtrl = TextEditingController(text: '437.500');
  final dukkanKrediLimitCtrl = TextEditingController(text: '437.500');

  final bodrumKatSayisiCtrl = TextEditingController(text: '1');
  final normalKatSayisiCtrl = TextEditingController(text: '5');

  final daireMaliyetCtrl = TextEditingController(text: '15.000');
  final dukkanMaliyetCtrl = TextEditingController(text: '15.000');
  final ortakAlanMaliyetCtrl = TextEditingController(text: '10.000');

  @override
  void initState() {
    super.initState();
    _mevcutlariYukle();
  }

  void _mevcutlariYukle() {
    final d = widget.mevcutTeklifData;
    if (d == null) return;
    ilceCtrl.text = d['ilce'] ?? '';
    mahalleCtrl.text = d['mahalle'] ?? '';
    adaCtrl.text = d['ada'] ?? '';
    parselCtrl.text = d['parsel'] ?? '';
    eskiDaireSayisiCtrl.text = d['eskiDaireSayisi']?.toString() ?? '0';
    eskiDukkanSayisiCtrl.text = d['eskiDukkanSayisi']?.toString() ?? '0';
    bodrumKatSayisiCtrl.text = d['bodrumKatSayisi']?.toString() ?? '0';
    normalKatSayisiCtrl.text = d['normalKatSayisi']?.toString() ?? '0';
    daireMaliyetCtrl.text = formatNumber(d['daireBirimMaliyet']);
    dukkanMaliyetCtrl.text = formatNumber(d['dukkanBirimMaliyet']);
    ortakAlanMaliyetCtrl.text = formatNumber(d['ortakAlanBirimMaliyet']);
    daireHibeLimitCtrl.text = formatNumber(d['daireHibeLim']);
    daireKrediLimitCtrl.text = formatNumber(d['daireKrediLim']);
    dukkanHibeLimitCtrl.text = formatNumber(d['dukkanHibeLim']);
    dukkanKrediLimitCtrl.text = formatNumber(d['dukkanKrediLim']);
  }

  int _bodrumKatSayisiDegeri() => int.tryParse(bodrumKatSayisiCtrl.text) ?? 0;

  int _normalKatSayisiDegeri() => int.tryParse(normalKatSayisiCtrl.text) ?? 0;

  List<KatModel> _bosKatListesiOlustur({required int bodrum, required int normal}) {
    final katlar = <KatModel>[];
    for (int i = bodrum; i >= 1; i--) {
      katlar.add(KatModel(ad: '$i. Bodrum Kat', katBrutAlanCtrl: TextEditingController(), bolumler: []));
    }
    if (normal >= 1) {
      katlar.add(KatModel(ad: 'Zemin Kat', katBrutAlanCtrl: TextEditingController(), bolumler: []));
    }
    for (int i = 1; i < normal; i++) {
      katlar.add(KatModel(ad: '$i. Normal Kat', katBrutAlanCtrl: TextEditingController(), bolumler: []));
    }
    return katlar;
  }

  List<KatModel> _mevcutKatListesiyleBirlestir(
    List<KatModel> mevcutKatlar, {
    required int bodrum,
    required int normal,
  }) {
    final hedef = _bosKatListesiOlustur(bodrum: bodrum, normal: normal);
    final mevcutByAd = <String, KatModel>{for (final kat in mevcutKatlar) kat.ad: kat};
    return hedef.map((kat) => mevcutByAd[kat.ad] ?? kat).toList();
  }

  Future<void> _teklifTemelVerileriniGuncelle() async {
    if (widget.mevcutDocId == null) return;

    try {
      final bodrum = _bodrumKatSayisiDegeri();
      final normal = _normalKatSayisiDegeri();

      List<KatModel>? guncelKatListesi;
      if (widget.mevcutTeklifData?['katListesi'] != null) {
        final ham = widget.mevcutTeklifData!['katListesi'] as List<dynamic>;
        final mevcutKatlar = ham.map((e) => KatModel.fromMap(e as Map<String, dynamic>)).toList();
        guncelKatListesi = _mevcutKatListesiyleBirlestir(mevcutKatlar, bodrum: bodrum, normal: normal);
      }

      await FirebaseFirestore.instance.collection('teklifler').doc(widget.mevcutDocId).update({
        'ilce': ilceCtrl.text,
        'mahalle': mahalleCtrl.text,
        'ada': adaCtrl.text,
        'parsel': parselCtrl.text,
        'eskiDaireSayisi': parseFormatted(eskiDaireSayisiCtrl.text).toInt(),
        'eskiDukkanSayisi': parseFormatted(eskiDukkanSayisiCtrl.text).toInt(),
        'bodrumKatSayisi': bodrum,
        'normalKatSayisi': normal,
        'daireBirimMaliyet': parseFormatted(daireMaliyetCtrl.text),
        'dukkanBirimMaliyet': parseFormatted(dukkanMaliyetCtrl.text),
        'ortakAlanBirimMaliyet': parseFormatted(ortakAlanMaliyetCtrl.text),
        'daireHibeLim': parseFormatted(daireHibeLimitCtrl.text),
        'daireKrediLim': parseFormatted(daireKrediLimitCtrl.text),
        'dukkanHibeLim': parseFormatted(dukkanHibeLimitCtrl.text),
        'dukkanKrediLim': parseFormatted(dukkanKrediLimitCtrl.text),
        if (guncelKatListesi != null) 'katListesi': guncelKatListesi.map((k) => k.toMap()).toList(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Teklif güncellendi')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Güncelleme hatası: $e')));
    }
  }

  void _olusturVeGec() {
    final bodrum = _bodrumKatSayisiDegeri();
    final normal = _normalKatSayisiDegeri();

    List<KatModel> katlar = _bosKatListesiOlustur(bodrum: bodrum, normal: normal);
    if (widget.mevcutTeklifData != null && widget.mevcutTeklifData!['katListesi'] != null) {
      final ham = widget.mevcutTeklifData!['katListesi'] as List<dynamic>;
      final mevcutKatlar = ham.map((e) => KatModel.fromMap(e as Map<String, dynamic>)).toList();
      katlar = _mevcutKatListesiyleBirlestir(mevcutKatlar, bodrum: bodrum, normal: normal);
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TeklifDetaySayfasi(
          katListesi: katlar,
          ilce: ilceCtrl.text,
          mahalle: mahalleCtrl.text,
          ada: adaCtrl.text,
          parsel: parselCtrl.text,
          eskiDaire: parseFormatted(eskiDaireSayisiCtrl.text).toInt(),
          eskiDukkan: parseFormatted(eskiDukkanSayisiCtrl.text).toInt(),
          daireHibeLim: parseFormatted(daireHibeLimitCtrl.text),
          daireKrediLim: parseFormatted(daireKrediLimitCtrl.text),
          dukkanHibeLim: parseFormatted(dukkanHibeLimitCtrl.text),
          dukkanKrediLim: parseFormatted(dukkanKrediLimitCtrl.text),
          daireMaliyet: parseFormatted(daireMaliyetCtrl.text),
          dukkanMaliyet: parseFormatted(dukkanMaliyetCtrl.text),
          ortakMaliyet: parseFormatted(ortakAlanMaliyetCtrl.text),
          bodrumKatSayisi: bodrum,
          normalKatSayisi: normal,
          mevcutDocId: widget.mevcutDocId,
          mevcutTeklifData: widget.mevcutTeklifData,
        ),
      ),
    );
  }

  Widget _input(TextEditingController c, String label, {bool isNumber = false}) {
    return TextField(
      controller: c,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      inputFormatters: isNumber ? [BinlikInputFormatter()] : [],
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.transparent),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppTheme.primaryColor, width: 2),
        ),
        isDense: true,
        filled: true,
        fillColor: Colors.white,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editMod = widget.mevcutDocId != null;
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text(editMod ? 'Teklif Düzenle' : 'Yeni Proje Teklifi'),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        elevation: 1,
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Teklif Arşivi',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ArsivSayfasi())),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _bolumBaslik('Proje Konumu'),
            Row(children: [Expanded(child: _input(ilceCtrl, 'İlçe')), const SizedBox(width: 10), Expanded(child: _input(mahalleCtrl, 'Mahalle'))]),
            const SizedBox(height: 10),
            Row(children: [Expanded(child: _input(adaCtrl, 'Ada')), const SizedBox(width: 10), Expanded(child: _input(parselCtrl, 'Parsel'))]),
            const SizedBox(height: 20),
            _bolumBaslik('Mevcut Bina (Hak sınırları için)'),
            Row(children: [Expanded(child: _input(eskiDaireSayisiCtrl, 'Eski Daire Sayısı', isNumber: true)), const SizedBox(width: 10), Expanded(child: _input(eskiDukkanSayisiCtrl, 'Eski Dükkan Sayısı', isNumber: true))]),
            const SizedBox(height: 20),
            _bolumBaslik('Maliyetler (m2 birim)'),
            Row(children: [Expanded(child: _input(daireMaliyetCtrl, 'Daire m2 Fiyatı', isNumber: true)), const SizedBox(width: 10), Expanded(child: _input(dukkanMaliyetCtrl, 'Dükkan m2 Fiyatı', isNumber: true))]),
            const SizedBox(height: 10),
            _input(ortakAlanMaliyetCtrl, 'Ortak Alan m2 Fiyatı', isNumber: true),
            const SizedBox(height: 20),
            _bolumBaslik('Hak Limitleri (Hibe/Kredi)'),
            Row(children: [Expanded(child: _input(daireHibeLimitCtrl, 'Daire Hibe', isNumber: true)), const SizedBox(width: 10), Expanded(child: _input(daireKrediLimitCtrl, 'Daire Kredi', isNumber: true))]),
            const SizedBox(height: 10),
            Row(children: [Expanded(child: _input(dukkanHibeLimitCtrl, 'Dükkan Hibe', isNumber: true)), const SizedBox(width: 10), Expanded(child: _input(dukkanKrediLimitCtrl, 'Dükkan Kredi', isNumber: true))]),
            const SizedBox(height: 20),
            _bolumBaslik('Proje Yapısı'),
            Row(children: [Expanded(child: _input(bodrumKatSayisiCtrl, 'Bodrum Kat Sayısı', isNumber: true)), const SizedBox(width: 10), Expanded(child: _input(normalKatSayisiCtrl, 'Zemin Dahil Kat', isNumber: true))]),
            const SizedBox(height: 30),
            if (editMod) ...[
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: _teklifTemelVerileriniGuncelle,
                  icon: const Icon(Icons.system_update_alt),
                  label: const Text('GÜNCELLE'),
                ),
              ),
              const SizedBox(height: 10),
            ],
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: _olusturVeGec,
                icon: const Icon(Icons.arrow_forward),
                label: Text(editMod ? 'Detaylara Geç' : 'Proje Detaylarına Geç'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            const SizedBox(height: 20),
            _bolumBaslik('Kayıtlı Teklifler'),
            _buildTeklifListesi(),
          ],
        ),
      ),
    );
  }

  Widget _bolumBaslik(String t) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          t,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: AppTheme.primaryColor,
            letterSpacing: 0.3,
          ),
        ),
      );

  Widget _buildTeklifListesi() {
    final sirketAdi = SistemYoneticisi().aktifSirket?.ad ?? '';

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('teklifler')
          .where('sirket', isEqualTo: sirketAdi)
          .orderBy('tarih', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator()));
        }

        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return const Text('Kayıtlı teklif bulunamadı.');
        }

        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: docs.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final data = docs[i].data() as Map<String, dynamic>;
            final il = data['ilce'] ?? '';
            final mah = data['mahalle'] ?? '';
            final durum = data['durum'] ?? 'teklif';
            return ListTile(
              title: Text('$il / $mah'),
              subtitle: Text('Durum: $durum'),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TeklifSayfasi(
                      mevcutTeklifData: data,
                      mevcutDocId: docs[i].id,
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class TeklifDetaySayfasi extends StatefulWidget {
  final List<KatModel> katListesi;
  final String ilce, mahalle, ada, parsel;
  final int eskiDaire, eskiDukkan;
  final double daireHibeLim, daireKrediLim, dukkanHibeLim, dukkanKrediLim;
  final double daireMaliyet, dukkanMaliyet, ortakMaliyet;
  final int bodrumKatSayisi;
  final int normalKatSayisi;
  final String? mevcutDocId;
  final Map<String, dynamic>? mevcutTeklifData;

  const TeklifDetaySayfasi({
    super.key,
    required this.katListesi,
    required this.ilce,
    required this.mahalle,
    required this.ada,
    required this.parsel,
    required this.eskiDaire,
    required this.eskiDukkan,
    required this.daireHibeLim,
    required this.daireKrediLim,
    required this.dukkanHibeLim,
    required this.dukkanKrediLim,
    required this.daireMaliyet,
    required this.dukkanMaliyet,
    required this.ortakMaliyet,
    required this.bodrumKatSayisi,
    required this.normalKatSayisi,
    this.mevcutDocId,
    this.mevcutTeklifData,
  });

  @override
  State<TeklifDetaySayfasi> createState() => _TeklifDetaySayfasiState();
}

class _TeklifDetaySayfasiState extends State<TeklifDetaySayfasi> {
  double toplamInsaatAlani = 0;
  double toplamOrtakAlanM2 = 25;
  double daireBasiDusenOrtakM2 = 0;
  double daireBasiOrtakMaliyet = 0;
  int topKullanilanDaireHibe = 0;
  int topKullanilanDaireKredi = 0;
  int topKullanilanDukkanHibe = 0;
  bool _pdfIslemde = false;
  int topKullanilanDukkanKredi = 0;
  double kullanilanHibeTL = 0;
  double kullanilanKrediTL = 0;
  Map<int, double> katDoluluklari = {};

  @override
  void initState() {
    super.initState();
    _hesapla();
  }

  void _hesapla() {
    double alan = 0;
    double manuelOrtak = 0;
    int bagimsiz = 0;
    int cDH = 0, cDK = 0, cDuH = 0, cDuK = 0;
    double kHibe = 0, kKredi = 0;
    final tempDoluluk = <int, double>{};

    for (int i = 0; i < widget.katListesi.length; i++) {
      // Kat doluluğunu başlat - ama eğer önceki katlardan Dubleks/Ters Dubleks eklendiyse koru
      if (!tempDoluluk.containsKey(i)) {
        tempDoluluk[i] = 0;
      }
      final kat = widget.katListesi[i];
      alan += parseFormatted(kat.katBrutAlanCtrl.text);

      for (final b in kat.bolumler) {
        final adet = b.girilenAdet;
        final m2Ana = b.girilenM2;
        tempDoluluk[i] = (tempDoluluk[i] ?? 0) + m2Ana * adet;

        if (b.tip == 'Dubleks' && i < widget.katListesi.length - 1) {
          final m2Ust = parseFormatted(b.ustKatM2Ctrl.text);
          tempDoluluk[i + 1] = (tempDoluluk[i + 1] ?? 0) + m2Ust * adet;
        }
        if ((b.tip == 'Ters Dubleks' || b.tip == 'Depolu Dükkan') && i > 0) {
          final m2Alt = parseFormatted(b.altKatM2Ctrl.text);
          tempDoluluk[i - 1] = (tempDoluluk[i - 1] ?? 0) + m2Alt * adet;
        }

        if (b.isOrtakAlan) {
          manuelOrtak += b.girilenM2;
        } else {
          bagimsiz++;
          cDH += b.daireHibeSayisi;
          cDK += b.daireKrediSayisi;
          cDuH += b.dukkanHibeSayisi;
          cDuK += b.dukkanKrediSayisi;
          kHibe += (b.daireHibeSayisi * widget.daireHibeLim) + (b.dukkanHibeSayisi * widget.dukkanHibeLim);
          kKredi += (b.daireKrediSayisi * widget.daireKrediLim) + (b.dukkanKrediSayisi * widget.dukkanKrediLim);
        }
      }
    }

    final double genelOrtak = 25.0 + manuelOrtak;
    final double kisiBasi = bagimsiz > 0 ? (genelOrtak / bagimsiz) : 0.0;

    setState(() {
      toplamInsaatAlani = alan;
      toplamOrtakAlanM2 = genelOrtak;
      daireBasiDusenOrtakM2 = kisiBasi;
      daireBasiOrtakMaliyet = kisiBasi * widget.ortakMaliyet;
      topKullanilanDaireHibe = cDH;
      topKullanilanDaireKredi = cDK;
      topKullanilanDukkanHibe = cDuH;
      topKullanilanDukkanKredi = cDuK;
      kullanilanHibeTL = kHibe;
      kullanilanKrediTL = kKredi;
      katDoluluklari = tempDoluluk;
    });
  }

  Future<void> _durumDegistir(String yeni) async {
    if (widget.mevcutDocId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Önce teklifi kaydedin.')));
      return;
    }

    final docRef = FirebaseFirestore.instance.collection('teklifler').doc(widget.mevcutDocId);
    final durumMetin = {
      'teklif': 'Teklif Aşamasında',
      'anlasildi': 'Anlaşıldı - Ruhsat Başlıyor',
      'tamamlandi': 'Proje Tamamlandı',
    };

    try {
      final snap = await docRef.get();
      final eskiDurum = (snap.data() ?? {})['durum'] ?? 'teklif';

      if (yeni == 'anlasildi') {
        final gelirRef = docRef.collection('gelirler');
        final eskiGelir = await gelirRef.get();
        for (final g in eskiGelir.docs) {
          await g.reference.delete();
        }

        final toplamDevlet = kullanilanHibeTL + kullanilanKrediTL;
        if (toplamDevlet > 0) {
          await gelirRef.add({
            'aciklama': 'Devlet (Hibe + Kredi)',
            'tutar': toplamDevlet,
            'odenen': 0,
            'tur': 'Devlet',
            'tarih': FieldValue.serverTimestamp(),
          });
        }

        int malSahibi = 0;
        double toplamToprak = 0;
        for (final k in widget.katListesi) {
          for (final b in k.bolumler) {
            if (b.isOrtakAlan) continue;
            if (b.sahip == 'Muteahhit') {
              toplamToprak += b.girilenToprakParasi;
            } else {
              malSahibi++;
            }
          }
        }
        final kisiToprak = malSahibi > 0 ? (toplamToprak / malSahibi) : 0;

        for (final k in widget.katListesi) {
          for (final b in k.bolumler) {
            if (b.isOrtakAlan || b.sahip == 'Muteahhit') continue;
            final insaat = b.girilenM2 * (b.tip.contains('Dükkan') ? widget.dukkanMaliyet : widget.daireMaliyet);
            final toplam = insaat + daireBasiOrtakMaliyet;
            final hibeKredi = (b.daireHibeSayisi * widget.daireHibeLim) + (b.daireKrediSayisi * widget.daireKrediLim) + (b.dukkanHibeSayisi * widget.dukkanHibeLim) + (b.dukkanKrediSayisi * widget.dukkanKrediLim);
            final net = toplam - hibeKredi - kisiToprak;
            if (net > 0) {
              await gelirRef.add({
                'aciklama': '${b.sahip} (${b.tip} - ${k.ad})',
                'tutar': net,
                'odenen': 0,
                'tur': 'Mal Sahibi',
                'tarih': FieldValue.serverTimestamp(),
              });
            }
          }
        }
      }

      await docRef.update({
        'durum': yeni,
        if (yeni == 'anlasildi') ...{
          'mevcutAsama': 'ruhsat',
          'moduller': ['ruhsat', 'santiye'],
          'sonIslem': 'Teklif Onaylandı - Ruhsat Başlıyor',
          'yuzde': 0.0,
        }
      });

      await AuditLogServisi.aktiviteKaydet(
        projeId: widget.mevcutDocId!,
        islem: 'Durum Değişti',
        detay: '${durumMetin[eskiDurum] ?? eskiDurum} -> ${durumMetin[yeni] ?? yeni}',
      );

      if (!mounted) return;
      
      if (yeni == 'anlasildi') {
        showDialog(
          context: context, 
          builder: (c) => AlertDialog(
            title: const Text('Tebrikler! 🎉'),
            content: const Text('Proje \'Anlaşıldı\' olarak işaretlendi.\n\nRuhsat/Şantiye işlemleri Sol Menü\'den başlatabilirsiniz.'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(c);
                  Navigator.pop(context); // Detaydan çık
                  Navigator.pop(context); // Ana sayfaya dön
                }, 
                child: const Text('TAMAM')
              )
            ],
          )
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Durum: ${durumMetin[yeni] ?? yeni}')));
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e')));
    }
  }

  Future<void> _kaydet(String hedefDurum) async {
    try {
      final teklif = {
        'tarih': FieldValue.serverTimestamp(),
        'ilce': widget.ilce,
        'mahalle': widget.mahalle,
        'ada': widget.ada,
        'parsel': widget.parsel,
        'eskiDaireSayisi': widget.eskiDaire,
        'eskiDukkanSayisi': widget.eskiDukkan,
        'bodrumKatSayisi': widget.bodrumKatSayisi,
        'normalKatSayisi': widget.normalKatSayisi,
        'toplamInsaatAlani': toplamInsaatAlani,
        'toplamOrtakAlanM2': toplamOrtakAlanM2,
        'daireBasiDusenOrtakM2': daireBasiDusenOrtakM2,
        'daireBasiOrtakMaliyet': daireBasiOrtakMaliyet,
        'hibeTutari': kullanilanHibeTL,
        'krediTutari': kullanilanKrediTL,
        'daireBirimMaliyet': widget.daireMaliyet,
        'dukkanBirimMaliyet': widget.dukkanMaliyet,
        'ortakAlanBirimMaliyet': widget.ortakMaliyet,
        'daireHibeLim': widget.daireHibeLim,
        'daireKrediLim': widget.daireKrediLim,
        'dukkanHibeLim': widget.dukkanHibeLim,
        'dukkanKrediLim': widget.dukkanKrediLim,
        'katListesi': widget.katListesi.map((k) => k.toMap()).toList(),
        'sirket': SistemYoneticisi().aktifSirket?.ad ?? '',
        'durum': hedefDurum,
        'kaynak': 'teklif',
        'ruhsatAsama': '',
        'santiyeAsama': '',
      };

      String? docId = widget.mevcutDocId;
      if (docId != null) {
        await FirebaseFirestore.instance.collection('teklifler').doc(docId).update(teklif);
      } else {
        final ref = await FirebaseFirestore.instance.collection('teklifler').add(teklif);
        docId = ref.id;
      }

      if (!mounted) return;

      if (hedefDurum == 'anlasildi') {
        await _durumDegistir('anlasildi');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Taslak kaydedildi')));
        // Düzenleme yapıldıysa ana ekrana dön
        if (widget.mevcutDocId != null) {
          Navigator.pop(context); // TeklifDetaySayfasi'ndan çık
          Navigator.pop(context); // TeklifSayfasi'ndan çık, Dashboard'a dön
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Kayıt hatası: $e')));
    }
  }

  Future<void> _pdfOlusturKontrol() async {
    // Çift tıklamayı engelle
    if (_pdfIslemde) {
      print('PDF üretimi zaten devam ediyor, istek iptal edildi');
      return;
    }
    
    try {
      _pdfIslemde = true;
      setState(() {});
      
      print('===== PDF OLUŞTURMA BAŞLIYOR #${DateTime.now().millisecondsSinceEpoch} =====');
      
      // Validasyon kontrolleri
      final hatalar = <String>[];
      for (int i = 0; i < widget.katListesi.length; i++) {
        final kat = widget.katListesi[i];
        final sinir = kat.girilenKatAlani;
        final dolu = katDoluluklari[i] ?? 0;
        final fark = sinir - dolu;
        if (fark.abs() > 0.5) {
          hatalar.add('${kat.ad}: ${formatNumber(fark)} m2 fark');
        }
      }
      
      if (hatalar.isNotEmpty) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Alan Kontrolü'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: hatalar.map((e) => Text('- $e')).toList(),
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('TAMAM'))],
          ),
        );
        return;
      }

      // Sığınak kontrolleri
      int konutSayisi = 0;
      double toplamTicariM2 = 0;
      double mevcutSiginakM2 = 0;

      for (final k in widget.katListesi) {
        for (final b in k.bolumler) {
          if (b.isOrtakAlan && b.tip.contains('Sığınak')) {
            mevcutSiginakM2 += b.girilenM2;
          } else if (!b.isOrtakAlan) {
            if (b.tip.contains('Daire') || b.tip.contains('Dubleks')) {
              konutSayisi++;
            }
            if (b.tip.contains('Dükkan') || b.tip.contains('Ofis')) {
              toplamTicariM2 += b.girilenM2;
            }
          }
        }
      }

      final bool siginakSart = (toplamInsaatAlani >= 1500) || (konutSayisi >= 10);
      double gerekenSiginakM2 = 0;
      if (siginakSart) {
        gerekenSiginakM2 = (konutSayisi * 4.0) + (toplamTicariM2 / 20.0);
      }

      if (siginakSart && mevcutSiginakM2 < gerekenSiginakM2) {
        final devam = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            icon: const Icon(Icons.warning, color: Colors.orange, size: 50),
            title: const Text('Sığınak Yetersiz'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Sığınak gereksinimi sağlanmıyor.', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                Text('• Gereken: ${formatNumber(gerekenSiginakM2)} m²'),
                Text('• Mevcut: ${formatNumber(mevcutSiginakM2)} m²', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                const SizedBox(height: 10),
                const Text('Devam edilsin mi?'),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('DÖN')),
              TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('YİNE DE OLUŞTUR', style: TextStyle(color: Colors.grey))),
            ],
          ),
        );
        if (devam != true) {
          return;
        }
      }

      if (!mounted) {
        return;
      }

      // Loading dialog göster
      showDialog(
        context: context,
        barrierDismissible: false,
        useRootNavigator: true,
        builder: (_) => const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('PDF oluşturuluyor...'),
                ],
              ),
            ),
          ),
        ),
      );

      print('generateSimplePdf çağrılıyor...');
      final pdf = await generateSimplePdf(
        sirket: SistemYoneticisi().aktifSirket?.ad ?? 'Firma',
        ilce: widget.ilce,
        mahalle: widget.mahalle,
        ada: widget.ada,
        parsel: widget.parsel,
        toplamInsaatAlani: toplamInsaatAlani,
        daireBirimMaliyet: widget.daireMaliyet,
        dukkanBirimMaliyet: widget.dukkanMaliyet,
        ortakAlanBirimMaliyet: widget.ortakMaliyet,
        toplamOrtakAlanM2: toplamOrtakAlanM2,
        daireBasiDusenOrtakM2: daireBasiDusenOrtakM2,
        daireBasiOrtakMaliyet: daireBasiOrtakMaliyet,
        daireHibeLim: widget.daireHibeLim,
        daireKrediLim: widget.daireKrediLim,
        dukkanHibeLim: widget.dukkanHibeLim,
        dukkanKrediLim: widget.dukkanKrediLim,
        hibeTutari: kullanilanHibeTL,
        krediTutari: kullanilanKrediTL,
        katListesi: widget.katListesi,
        firmaLogosu: SistemYoneticisi().aktifSirket?.logo,
      ).timeout(
        const Duration(seconds: 120),
        onTimeout: () {
          print('PDF oluşturma timeout! 120 saniyeyi aştı.');
          throw Exception('PDF oluşturma çok uzun sürüyor (120sn+)');
        },
      );

      print('===== generateSimplePdf RETURN ETTİ, PDF boyutu: ${pdf.length} bytes =====');

      if (!mounted) {
        return;
      }

      // Dialog kapat
      try {
        Navigator.of(context, rootNavigator: true).pop();
      } catch (_) {}

      if (!mounted) {
        return;
      }

      // PDF viewer aç
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PdfViewerWeb(
            pdfBytes: pdf,
            filename: 'teklif_${widget.ada}_${widget.parsel}.pdf',
          ),
        ),
      );

      print('PDF viewer açıldı');
    } catch (e, st) {
      print('PDF hatası: $e');
      print('Stack: $st');

      if (mounted) {
        try {
          Navigator.of(context, rootNavigator: true).pop();
        } catch (_) {}

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('PDF hatası: $e'),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _pdfIslemde = false;
        });
      } else {
        _pdfIslemde = false;
      }
      print('===== PDF işlemi bitti, flag reset edildi =====');
    }
  }

  List<String> _tiplerForKat(int index) {
    final enAlt = index == 0;
    final enUst = index == widget.katListesi.length - 1;
    final tipler = ['Daire', 'Ofis', 'Dükkan'];
    if (!enAlt) {
      tipler.addAll(['Ters Dubleks', 'Depolu Dükkan']);
    }
    if (!enUst) {
      tipler.add('Dubleks');
    }
    return tipler;
  }

  Widget _miniInput(TextEditingController c, String l) => SizedBox(
        width: 70,
        child: TextField(
          controller: c,
          onChanged: (_) => _hesapla(),
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          inputFormatters: [BinlikInputFormatter()],
          decoration: InputDecoration(
            labelText: l,
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
          ),
        ),
      );

  void _hakDuzenle(BolumModel b) {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialog) {
          Widget sayac(String baslik, int deger, int toplamKullanilan, int limit, ValueChanged<int> onChange, Color renk) {
            final izin = limit - (toplamKullanilan - deger);
            final kilit = deger >= izin && izin >= 0;
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(baslik),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: deger > 0
                          ? () {
                              onChange(deger - 1);
                              _hesapla();
                              setDialog(() {});
                            }
                          : null,
                    ),
                    Text('$deger', style: TextStyle(color: renk, fontWeight: FontWeight.bold)),
                    IconButton(
                      icon: Icon(kilit ? Icons.block : Icons.add_circle, color: kilit ? Colors.grey : renk),
                      onPressed: kilit
                          ? null
                          : () {
                              onChange(deger + 1);
                              _hesapla();
                              setDialog(() {});
                            },
                    ),
                  ],
                ),
                Text('Kal: ${izin - deger}', style: const TextStyle(fontSize: 11)),
              ],
            );
          }

          return AlertDialog(
            title: const Text('Hibe/Kredi Hakları'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  sayac('Daire Hibe', b.daireHibeSayisi, topKullanilanDaireHibe, widget.eskiDaire, (v) => b.daireHibeSayisi = v, Colors.green),
                  sayac('Daire Kredi', b.daireKrediSayisi, topKullanilanDaireKredi, widget.eskiDaire, (v) => b.daireKrediSayisi = v, Colors.blue),
                  sayac('Dükkan Hibe', b.dukkanHibeSayisi, topKullanilanDukkanHibe, widget.eskiDukkan, (v) => b.dukkanHibeSayisi = v, Colors.green),
                  sayac('Dükkan Kredi', b.dukkanKrediSayisi, topKullanilanDukkanKredi, widget.eskiDukkan, (v) => b.dukkanKrediSayisi = v, Colors.blue),
                ],
              ),
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('KAPAT'))],
          );
        },
      ),
    );
  }

  void _ortakAlanEkle(KatModel kat) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ortak Alan Ekle'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('Sığınak'),
              onTap: () {
                _bolumEkle(kat, 'Sığınak', ortak: true);
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              title: const Text('Bina Girişi'),
              onTap: () {
                _bolumEkle(kat, 'Bina Girişi', ortak: true);
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              title: const Text('Arka Bahçe'),
              onTap: () {
                _bolumEkle(kat, 'Arka Bahçe', ortak: true);
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              title: const Text('Otopark'),
              onTap: () {
                _bolumEkle(kat, 'Otopark', ortak: true);
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _bolumEkle(KatModel kat, String tip, {bool ortak = false}) {
    setState(() {
      kat.bolumler.add(
        BolumModel(
          tip: tip,
          adetCtrl: TextEditingController(text: '1'),
          m2Ctrl: TextEditingController(text: '10'),
          toprakParasiCtrl: TextEditingController(),
          isOrtakAlan: ortak,
        ),
      );
    });
    _hesapla();
  }

  @override
  Widget build(BuildContext context) {
    final kayitli = widget.mevcutDocId != null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Planlama ve Dağıtım'),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(onPressed: () => _kaydet('teklif'), icon: const Icon(Icons.save, color: Colors.white), tooltip: 'Taslak Kaydet'),
          IconButton(onPressed: _pdfIslemde ? null : _pdfOlusturKontrol, icon: const Icon(Icons.picture_as_pdf, color: Colors.white)),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: widget.katListesi.length,
              itemBuilder: (_, i) {
                final kat = widget.katListesi[i];
                final sinir = kat.girilenKatAlani;
                final dolu = katDoluluklari[i] ?? 0;
                final bos = sinir - dolu;
                final renk = bos < -0.5
                    ? Colors.red
                    : (bos > 0.5 ? Colors.orange.shade800 : Colors.green);
                final durum = bos < -0.5
                    ? 'Taştı: ${formatNumber(bos.abs())} m2'
                    : (bos > 0.5 ? 'Boşluk: ${formatNumber(bos)} m2' : 'Tam Dolu');

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  elevation: 3,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  child: ExpansionTile(
                    initiallyExpanded: true,
                    title: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(kat.ad, style: const TextStyle(fontWeight: FontWeight.bold)),
                            const Spacer(),
                            SizedBox(
                              width: 90,
                              child: TextField(
                                controller: kat.katBrutAlanCtrl,
                                onChanged: (_) => _hesapla(),
                                keyboardType: TextInputType.number,
                                inputFormatters: [BinlikInputFormatter()],
                                decoration: const InputDecoration(
                                  labelText: 'Kat m2',
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(durum, style: TextStyle(color: renk, fontSize: 12, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        child: Column(
                          children: [
                            ...kat.bolumler.map(
                              (b) => Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: b.isOrtakAlan
                                      ? Colors.grey.shade200
                                      : (b.sahip == 'Muteahhit' ? Colors.red.shade50 : Colors.white),
                                  border: Border.all(color: Colors.grey.shade300),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: LayoutBuilder(
                                  builder: (context, constraints) {
                                    final isTight = constraints.maxWidth < 420;

                                    if (!isTight) {
                                      return Row(
                                        children: [
                                          if (b.isOrtakAlan)
                                            Expanded(
                                              child: Row(
                                                children: [
                                                  const Icon(Icons.public, size: 16),
                                                  const SizedBox(width: 6),
                                                  Text(b.tip, style: const TextStyle(fontWeight: FontWeight.bold)),
                                                ],
                                              ),
                                            )
                                          else
                                            Expanded(
                                              child: DropdownButtonHideUnderline(
                                                child: DropdownButton<String>(
                                                  value: _tiplerForKat(i).contains(b.tip) ? b.tip : 'Daire',
                                                  isExpanded: true,
                                                  items: _tiplerForKat(i)
                                                      .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                                                      .toList(),
                                                  onChanged: (v) {
                                                    setState(() => b.tip = v ?? 'Daire');
                                                    _hesapla();
                                                  },
                                                ),
                                              ),
                                            ),
                                          const SizedBox(width: 6),
                                          if (!b.isOrtakAlan && b.tip == 'Dubleks') ...[
                                            _miniInput(b.m2Ctrl, 'Ana'),
                                            const SizedBox(width: 4),
                                            _miniInput(b.ustKatM2Ctrl, 'Üst'),
                                          ] else if (!b.isOrtakAlan && (b.tip == 'Ters Dubleks' || b.tip == 'Depolu Dükkan')) ...[
                                            _miniInput(b.m2Ctrl, 'Ana'),
                                            const SizedBox(width: 4),
                                            _miniInput(b.altKatM2Ctrl, 'Alt'),
                                          ] else ...[
                                            _miniInput(b.m2Ctrl, 'm2'),
                                          ],
                                          const SizedBox(width: 6),
                                          if (!b.isOrtakAlan) ...[
                                            PopupMenuButton<String>(
                                              padding: EdgeInsets.zero,
                                              itemBuilder: (_) => const [
                                                PopupMenuItem(value: 'Mal Sahibi', child: Text('Mal Sahibi')),
                                                PopupMenuItem(value: 'Muteahhit', child: Text('Müteahhit')),
                                              ],
                                              onSelected: (v) {
                                                setState(() => b.sahip = v);
                                                _hesapla();
                                              },
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                                decoration: BoxDecoration(
                                                  color: b.sahip == 'Muteahhit' ? Colors.red.shade100 : Colors.green.shade100,
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: Text(
                                                  b.sahip == 'Muteahhit' ? 'Müteahhit' : b.sahip,
                                                  style: TextStyle(color: b.sahip == 'Muteahhit' ? Colors.red.shade900 : Colors.green.shade900),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            ElevatedButton(
                                              onPressed: () => _hakDuzenle(b),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: b.hakKullanildi ? Colors.blue : Colors.grey.shade300,
                                                foregroundColor: b.hakKullanildi ? Colors.white : Colors.black,
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                                minimumSize: const Size(90, 40),
                                              ),
                                              child: const Text('Hibe/Kredi', textAlign: TextAlign.center, style: TextStyle(fontSize: 11)),
                                            ),
                                          ],
                                          if (b.sahip == 'Muteahhit' && !b.isOrtakAlan) ...[
                                            const SizedBox(width: 6),
                                            SizedBox(
                                              width: 90,
                                              child: TextField(
                                                controller: b.toprakParasiCtrl,
                                                onChanged: (_) => _hesapla(),
                                                keyboardType: TextInputType.number,
                                                inputFormatters: [BinlikInputFormatter()],
                                                decoration: const InputDecoration(
                                                  labelText: 'Toprak',
                                                  isDense: true,
                                                  border: OutlineInputBorder(),
                                                ),
                                              ),
                                            ),
                                          ],
                                          const SizedBox(width: 4),
                                          IconButton(
                                            icon: const Icon(Icons.cancel, color: Colors.red),
                                            onPressed: () {
                                              setState(() => kat.bolumler.remove(b));
                                              _hesapla();
                                            },
                                          )
                                        ],
                                      );
                                    }

                                    final isDubleks = !b.isOrtakAlan && b.tip == 'Dubleks';
                                    final isTers = !b.isOrtakAlan && (b.tip == 'Ters Dubleks' || b.tip == 'Depolu Dükkan');

                                    Widget inputGroup;
                                    if (isDubleks) {
                                      inputGroup = Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          _miniInput(b.m2Ctrl, 'Ana'),
                                          const SizedBox(width: 4),
                                          _miniInput(b.ustKatM2Ctrl, 'Üst'),
                                        ],
                                      );
                                    } else if (isTers) {
                                      inputGroup = Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          _miniInput(b.m2Ctrl, 'Ana'),
                                          const SizedBox(width: 4),
                                          _miniInput(b.altKatM2Ctrl, 'Alt'),
                                        ],
                                      );
                                    } else {
                                      inputGroup = _miniInput(b.m2Ctrl, 'm2');
                                    }

                                    return Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        if (b.isOrtakAlan)
                                          Row(
                                            children: [
                                              const Icon(Icons.public, size: 16),
                                              const SizedBox(width: 6),
                                              Expanded(
                                                child: Text(
                                                  b.tip,
                                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                                ),
                                              ),
                                            ],
                                          )
                                        else
                                          DropdownButtonHideUnderline(
                                            child: DropdownButton<String>(
                                              value: _tiplerForKat(i).contains(b.tip) ? b.tip : 'Daire',
                                              isExpanded: true,
                                              items: _tiplerForKat(i)
                                                  .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                                                  .toList(),
                                              onChanged: (v) {
                                                setState(() => b.tip = v ?? 'Daire');
                                                _hesapla();
                                              },
                                            ),
                                          ),
                                        const SizedBox(height: 8),
                                        Wrap(
                                          spacing: 6,
                                          runSpacing: 6,
                                          crossAxisAlignment: WrapCrossAlignment.center,
                                          children: [
                                            inputGroup,
                                            if (!b.isOrtakAlan)
                                              PopupMenuButton<String>(
                                                padding: EdgeInsets.zero,
                                                itemBuilder: (_) => const [
                                                  PopupMenuItem(value: 'Mal Sahibi', child: Text('Mal Sahibi')),
                                                  PopupMenuItem(value: 'Muteahhit', child: Text('Müteahhit')),
                                                ],
                                                onSelected: (v) {
                                                  setState(() => b.sahip = v);
                                                  _hesapla();
                                                },
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                                  decoration: BoxDecoration(
                                                    color: b.sahip == 'Muteahhit' ? Colors.red.shade100 : Colors.green.shade100,
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  child: Text(
                                                    b.sahip == 'Muteahhit' ? 'Müteahhit' : b.sahip,
                                                    style: TextStyle(color: b.sahip == 'Muteahhit' ? Colors.red.shade900 : Colors.green.shade900),
                                                  ),
                                                ),
                                              ),
                                            if (!b.isOrtakAlan)
                                              ElevatedButton(
                                                onPressed: () => _hakDuzenle(b),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: b.hakKullanildi ? Colors.blue : Colors.grey.shade300,
                                                  foregroundColor: b.hakKullanildi ? Colors.white : Colors.black,
                                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                                  minimumSize: const Size(90, 40),
                                                ),
                                                child: const Text('Hibe/Kredi', textAlign: TextAlign.center, style: TextStyle(fontSize: 11)),
                                              ),
                                            if (b.sahip == 'Muteahhit' && !b.isOrtakAlan)
                                              SizedBox(
                                                width: 90,
                                                child: TextField(
                                                  controller: b.toprakParasiCtrl,
                                                  onChanged: (_) => _hesapla(),
                                                  keyboardType: TextInputType.number,
                                                  inputFormatters: [BinlikInputFormatter()],
                                                  decoration: const InputDecoration(
                                                    labelText: 'Toprak',
                                                    isDense: true,
                                                    border: OutlineInputBorder(),
                                                  ),
                                                ),
                                              ),
                                            IconButton(
                                              icon: const Icon(Icons.cancel, color: Colors.red),
                                              onPressed: () {
                                                setState(() => kat.bolumler.remove(b));
                                                _hesapla();
                                              },
                                            ),
                                          ],
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              ),
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                ElevatedButton.icon(
                                  onPressed: () {
                                    setState(() => kat.bolumler.add(
                                          BolumModel(
                                            tip: 'Daire',
                                            adetCtrl: TextEditingController(text: '1'),
                                            m2Ctrl: TextEditingController(text: '1'),
                                            toprakParasiCtrl: TextEditingController(),
                                          ),
                                        ));
                                    _hesapla();
                                  },
                                  icon: const Icon(Icons.add),
                                  label: const Text('Bağımsız Bölüm'),
                                ),
                                const SizedBox(width: 10),
                                TextButton.icon(
                                  onPressed: () => _ortakAlanEkle(kat),
                                  icon: const Icon(Icons.public),
                                  label: const Text('Ortak Alan'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.grey.withAlpha(76), blurRadius: 10, offset: const Offset(0, -3))],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Kaydetme butonları
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _kaydet('teklif'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 15),
                        ),
                        icon: const Icon(Icons.save, color: Colors.white),
                        label: Text(
                          kayitli ? 'GÜNCELLE' : 'TASLAK KAYDET',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _pdfIslemde ? null : _pdfOlusturKontrol,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade700,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 15),
                        ),
                        icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
                        label: const Text('PDF OLUŞTUR', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
