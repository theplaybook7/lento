import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:printing/printing.dart';
import '../project_core.dart';
import '../theme/app_theme.dart';
import '../services/ai_teklif_service.dart';
import '../services/tcmb_service.dart';
import '../services/emlak_data_service.dart';
import '../services/ai_teklif_pdf_service.dart' as ai_pdf;

String _formatN(double n) {
  if (n == n.roundToDouble()) {
    return NumberFormat('#,###', 'tr_TR').format(n.toInt());
  }
  return NumberFormat('#,##0.00', 'tr_TR').format(n);
}

double _parseN(String t) =>
    double.tryParse(t.replaceAll('.', '').replaceAll(',', '.')) ?? 0;

class _TBinlikFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue o, TextEditingValue n) {
    if (n.text.isEmpty) return n;
    final clean = n.text.replaceAll('.', '');
    final parts = clean.split(',');
    final intP = parts[0].replaceAll(RegExp(r'[^0-9]'), '');
    if (intP.isEmpty) return n;
    final fmt = NumberFormat('#,###', 'tr_TR').format(int.parse(intP));
    final r = parts.length > 1 ? '$fmt,${parts[1]}' : fmt;
    return TextEditingValue(text: r, selection: TextSelection.collapsed(offset: r.length));
  }
}

class AiTeklifScreen extends StatefulWidget {
  const AiTeklifScreen({super.key});

  @override
  State<AiTeklifScreen> createState() => _AiTeklifScreenState();
}

class _AiTeklifScreenState extends State<AiTeklifScreen> {
  final _aiService = AiTeklifService();
  int _currentStep = 0;
  bool _isLoading = false;
  String _loadingMessage = '';

  // Step 1: Konum bilgileri
  String? _secilenIl;
  String? _secilenIlce;
  String? _secilenMahalle;
  List<String> _ilListesi = [];
  List<String> _ilceListesi = [];
  List<String> _mahalleListesi = [];

  // Step 2: İnşaat bilgileri — kat tipi bazında m²
  final _bodrumM2Ctrl = TextEditingController();
  final _zeminM2Ctrl = TextEditingController();
  final _normalM2Ctrl = TextEditingController();
  final _bodrumKatSayisiCtrl = TextEditingController(text: '1');
  final _normalKatSayisiCtrl = TextEditingController(text: '5');
  final _guncelMaliyetCtrl = TextEditingController();
  final _karOraniCtrl = TextEditingController(text: '20');

  // Step 3: Kroki + daire bilgileri
  final List<Map<String, dynamic>> _katlar = [];
  int _senaryo = 1;

  // Step 4: Hibe/Kredi
  final _hibeTutariCtrl = TextEditingController(text: '0');
  final _krediTutariCtrl = TextEditingController(text: '0');

  // Step 5: AI tahminleri
  Map<String, dynamic>? _enflasyonProjeksiyonu;
  Map<String, double>? _minMaxFiyat;
  String? _pazarAnaliziMetni;
  Map<String, dynamic>? _hesapSonucu;
  String? _aiOzet;

  // Kayıtlı AI teklifler
  bool _showSavedList = false;

  /// Hesaplanmış toplam m²
  double get _toplamM2 {
    final bodrum = int.tryParse(_bodrumKatSayisiCtrl.text) ?? 0;
    final normal = int.tryParse(_normalKatSayisiCtrl.text) ?? 0;
    final bodrumM2 = _parseN(_bodrumM2Ctrl.text);
    final zeminM2 = _parseN(_zeminM2Ctrl.text);
    final normalM2 = _parseN(_normalM2Ctrl.text);
    double toplam = bodrum * bodrumM2;
    if (normal >= 1) toplam += zeminM2;
    if (normal > 1) toplam += (normal - 1) * normalM2;
    return toplam;
  }

  @override
  void initState() {
    super.initState();
    _ilListesi = EmlakDataService.ilListesi();
  }

  @override
  void dispose() {
    _bodrumM2Ctrl.dispose();
    _zeminM2Ctrl.dispose();
    _normalM2Ctrl.dispose();
    _bodrumKatSayisiCtrl.dispose();
    _normalKatSayisiCtrl.dispose();
    _guncelMaliyetCtrl.dispose();
    _karOraniCtrl.dispose();
    _hibeTutariCtrl.dispose();
    _krediTutariCtrl.dispose();
    for (final k in _katlar) {
      (k['katAlaniCtrl'] as TextEditingController).dispose();
      for (final d in (k['daireler'] as List)) {
        (d['m2Ctrl'] as TextEditingController).dispose();
        if (d['ustM2Ctrl'] != null) (d['ustM2Ctrl'] as TextEditingController).dispose();
        if (d['altM2Ctrl'] != null) (d['altM2Ctrl'] as TextEditingController).dispose();
      }
    }
    super.dispose();
  }

  int get _toplamKatSayisi {
    final bodrum = int.tryParse(_bodrumKatSayisiCtrl.text) ?? 0;
    final normal = int.tryParse(_normalKatSayisiCtrl.text) ?? 0;
    return bodrum + (normal > 0 ? 1 : 0) + (normal > 1 ? normal - 1 : 0);
  }

  void _krokiOlustur() {
    for (final k in _katlar) {
      (k['katAlaniCtrl'] as TextEditingController).dispose();
      for (final d in (k['daireler'] as List)) {
        (d['m2Ctrl'] as TextEditingController).dispose();
        if (d['ustM2Ctrl'] != null) (d['ustM2Ctrl'] as TextEditingController).dispose();
        if (d['altM2Ctrl'] != null) (d['altM2Ctrl'] as TextEditingController).dispose();
      }
    }
    _katlar.clear();

    final bodrum = int.tryParse(_bodrumKatSayisiCtrl.text) ?? 0;
    final normal = int.tryParse(_normalKatSayisiCtrl.text) ?? 0;
    final bodrumM2 = _parseN(_bodrumM2Ctrl.text);
    final zeminM2 = _parseN(_zeminM2Ctrl.text);
    final normalM2 = _parseN(_normalM2Ctrl.text);

    // Bodrum katlar
    for (int i = bodrum; i >= 1; i--) {
      _katlar.add({
        'ad': '$i. Bodrum Kat',
        'kat': -i,
        'katAlaniCtrl': TextEditingController(text: bodrumM2 > 0 ? _formatN(bodrumM2) : ''),
        'daireler': <Map<String, dynamic>>[],
      });
    }
    // Zemin kat
    if (normal >= 1) {
      _katlar.add({
        'ad': 'Zemin Kat',
        'kat': 0,
        'katAlaniCtrl': TextEditingController(text: zeminM2 > 0 ? _formatN(zeminM2) : ''),
        'daireler': <Map<String, dynamic>>[],
      });
    }
    // Normal katlar
    for (int i = 1; i < normal; i++) {
      _katlar.add({
        'ad': '$i. Normal Kat',
        'kat': i,
        'katAlaniCtrl': TextEditingController(text: normalM2 > 0 ? _formatN(normalM2) : ''),
        'daireler': <Map<String, dynamic>>[],
      });
    }

    // Her kata 2 daire
    int no = 1;
    for (final k in _katlar) {
      final daireList = k['daireler'] as List<Map<String, dynamic>>;
      for (int i = 0; i < 2; i++) {
        daireList.add(_yeniDaire(no: no++, kat: k['kat'] as int));
      }
    }

    setState(() {});
  }

  Map<String, dynamic> _yeniDaire({required int no, required int kat}) {
    return {
      'tip': 'Daire',
      'm2Ctrl': TextEditingController(),
      'ustM2Ctrl': TextEditingController(),
      'altM2Ctrl': TextEditingController(),
      'kat': kat,
      'no': no,
      'sahip': 'malSahibi',
      'hibeVar': false,
      'krediVar': false,
    };
  }

  int get _toplamDaireSayisi {
    int count = 0;
    for (final k in _katlar) {
      count += (k['daireler'] as List).length;
    }
    return count;
  }

  int get _hesaplananSure => TcmbService.insaatSuresiHesapla(_toplamM2);

  List<String> _tiplerForKat(int katIndex) {
    final enAlt = katIndex == 0;
    final enUst = katIndex == _katlar.length - 1;
    final tipler = ['Daire', 'Ofis', 'Dükkan'];
    if (!enAlt) tipler.addAll(['Ters Dubleks', 'Depolu Dükkan']);
    if (!enUst) tipler.add('Dubleks');
    return tipler;
  }

  // ── Cross-floor phantom hücreleri ──

  /// Belirli bir kat için diğer katlardan gelen phantom hücreleri toplar
  List<Map<String, dynamic>> _phantomCellsForFloor(int katIndex) {
    final targetKat = _katlar[katIndex]['kat'] as int;
    final phantoms = <Map<String, dynamic>>[];

    for (int i = 0; i < _katlar.length; i++) {
      if (i == katIndex) continue;
      final sourceKat = _katlar[i]['kat'] as int;
      final daireler = _katlar[i]['daireler'] as List;

      for (final d in daireler) {
        final tip = d['tip'] as String;
        final no = d['no'] as int;

        if (tip == 'Dubleks' && sourceKat + 1 == targetKat) {
          final ustM2 = _parseN((d['ustM2Ctrl'] as TextEditingController).text);
          if (ustM2 > 0) {
            phantoms.add({
              'tip': 'Dubleks Üst',
              'label': 'D$no Üst',
              'm2': ustM2,
              'sourceNo': no,
              'sourceKatIndex': i,
            });
          }
        } else if (tip == 'Ters Dubleks' && sourceKat - 1 == targetKat) {
          final altM2 = _parseN((d['altM2Ctrl'] as TextEditingController).text);
          if (altM2 > 0) {
            phantoms.add({
              'tip': 'TD Alt',
              'label': 'D$no Alt',
              'm2': altM2,
              'sourceNo': no,
              'sourceKatIndex': i,
            });
          }
        } else if (tip == 'Depolu Dükkan' && sourceKat - 1 == targetKat) {
          final altM2 = _parseN((d['altM2Ctrl'] as TextEditingController).text);
          if (altM2 > 0) {
            phantoms.add({
              'tip': 'Depo',
              'label': 'D$no Depo',
              'm2': altM2,
              'sourceNo': no,
              'sourceKatIndex': i,
            });
          }
        }
      }
    }
    return phantoms;
  }

  /// Cross-floor m² toplamı (phantom hücreler)
  double _crossFloorM2ForFloor(int katIndex) {
    double total = 0;
    for (final p in _phantomCellsForFloor(katIndex)) {
      total += p['m2'] as double;
    }
    return total;
  }

  // Sığınak kuralı kontrolü
  Map<String, dynamic> _siginakKontrolu() {
    int konutSayisi = 0;
    double toplamTicariM2 = 0;
    double toplamInsaatAlani = _toplamM2;

    for (final k in _katlar) {
      for (final d in (k['daireler'] as List)) {
        final tip = d['tip'] as String;
        final m2 = _parseN((d['m2Ctrl'] as TextEditingController).text);
        if (tip.contains('Daire') || tip.contains('Dubleks')) {
          konutSayisi++;
        }
        if (tip.contains('Dükkan') || tip.contains('Ofis')) {
          toplamTicariM2 += m2;
        }
      }
    }

    final bool siginakSart = (toplamInsaatAlani >= 1500) || (konutSayisi >= 10);
    double gerekenSiginakM2 = 0;
    if (siginakSart) {
      gerekenSiginakM2 = (konutSayisi * 4.0) + (toplamTicariM2 / 20.0);
    }

    return {
      'gerekli': siginakSart,
      'gerekenM2': gerekenSiginakM2,
      'mevcutM2': 0.0,
      'konutSayisi': konutSayisi,
      'yeterli': !siginakSart,
    };
  }

  bool _validateStep(int step) {
    switch (step) {
      case 0:
        return _secilenIl != null && _secilenIlce != null;
      case 1:
        return _toplamM2 > 0 &&
            (int.tryParse(_normalKatSayisiCtrl.text) ?? 0) > 0 &&
            _parseN(_guncelMaliyetCtrl.text) > 0 &&
            _parseN(_karOraniCtrl.text) > 0;
      case 2:
        if (_katlar.isEmpty) return false;
        for (final k in _katlar) {
          final daireler = k['daireler'] as List;
          if (daireler.isEmpty) return false;
          for (final d in daireler) {
            if (_parseN((d['m2Ctrl'] as TextEditingController).text) <= 0) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Tüm dairelerin m² bilgisini girin'), backgroundColor: Colors.red),
              );
              return false;
            }
          }
        }
        // Cross-floor alan kontrolü
        for (int i = 0; i < _katlar.length; i++) {
          final katAlani = _parseN((_katlar[i]['katAlaniCtrl'] as TextEditingController).text);
          final crossM2 = _crossFloorM2ForFloor(i);
          final daireler = _katlar[i]['daireler'] as List;
          double daireM2 = 0;
          for (final d in daireler) {
            daireM2 += _parseN((d['m2Ctrl'] as TextEditingController).text);
          }
          if (katAlani > 0 && (daireM2 + crossM2) > katAlani * 1.1) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('${_katlar[i]['ad']}: Toplam alan (${_formatN(daireM2 + crossM2)} m²) kat alanını (${_formatN(katAlani)} m²) aşıyor!'),
                backgroundColor: Colors.red,
              ),
            );
            return false;
          }
        }
        if (_senaryo == 2) {
          bool hasMuteahhit = false;
          for (final k in _katlar) {
            for (final d in (k['daireler'] as List)) {
              if (d['sahip'] == 'muteahhit') hasMuteahhit = true;
            }
          }
          if (!hasMuteahhit) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Senaryo 2 için en az bir daireyi müteahhite atayın!'), backgroundColor: Colors.red),
            );
            return false;
          }
        }
        return true;
      default:
        return true;
    }
  }

  List<Map<String, dynamic>> _daireListesiHazirla() {
    final list = <Map<String, dynamic>>[];
    for (final k in _katlar) {
      for (final d in (k['daireler'] as List)) {
        final tip = d['tip'] as String;
        double m2 = _parseN((d['m2Ctrl'] as TextEditingController).text);
        if (tip == 'Dubleks') {
          m2 += _parseN((d['ustM2Ctrl'] as TextEditingController).text);
        } else if (tip == 'Ters Dubleks' || tip == 'Depolu Dükkan') {
          m2 += _parseN((d['altM2Ctrl'] as TextEditingController).text);
        }
        list.add({
          'm2': m2,
          'kat': d['kat'] as int,
          'tip': tip,
          'sahip': d['sahip'] as String,
          'hibeVar': d['hibeVar'] as bool,
          'krediVar': d['krediVar'] as bool,
        });
      }
    }
    return list;
  }

  Future<void> _hesaplaVeAnaliz() async {
    setState(() {
      _isLoading = true;
      _loadingMessage = 'TCMB verileri alınıyor...';
    });

    try {
      final tcmbBasarili = await _aiService.verileriGuncelle();

      if (!tcmbBasarili && _aiService.tcmbHataMesaji != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('TCMB: ${_aiService.tcmbHataMesaji}\nYerleşik veriler kullanılacak.'),
            backgroundColor: Colors.orange.shade700,
            duration: const Duration(seconds: 4),
          ),
        );
      }

      setState(() => _loadingMessage = 'İstatistiksel analiz yapılıyor...');

      final il = _secilenIl ?? '';
      final ilce = _secilenIlce ?? '';
      final mahalle = _secilenMahalle ?? '';
      final toplamM2 = _toplamM2;
      final daireListesi = _daireListesiHazirla();

      final projeksiyon = _aiService.enflasyonProjeksiyonu(
        guncelMaliyet: _parseN(_guncelMaliyetCtrl.text),
        toplamM2: toplamM2,
      );

      final minMax = _aiService.minMaxFiyatOnerisi(
        guncelMaliyet: _parseN(_guncelMaliyetCtrl.text),
        toplamM2: toplamM2,
        karOrani: _parseN(_karOraniCtrl.text),
      );

      setState(() => _loadingMessage = 'Pazar verileri analiz ediliyor...');
      final pazarMetni = _aiService.pazarAnalizi(
        il: il,
        ilce: ilce,
        mahalle: mahalle,
        insaatSuresi: _hesaplananSure,
        daireler: daireListesi,
      );

      final siginak = _siginakKontrolu();

      Map<String, dynamic> sonuc;

      if (_senaryo == 2) {
        sonuc = _aiService.senaryo2Hesapla(
          guncelM2Maliyet: _parseN(_guncelMaliyetCtrl.text),
          toplamInsaatM2: toplamM2,
          karOrani: _parseN(_karOraniCtrl.text),
          daireler: daireListesi,
          hibeTutari: _parseN(_hibeTutariCtrl.text),
          krediTutari: _parseN(_krediTutariCtrl.text),
          il: il,
          ilce: ilce,
          insaatSuresi: _hesaplananSure,
          mahalle: mahalle,
        );
      } else {
        sonuc = _aiService.senaryo1Hesapla(
          guncelM2Maliyet: _parseN(_guncelMaliyetCtrl.text),
          toplamInsaatM2: toplamM2,
          karOrani: _parseN(_karOraniCtrl.text),
          daireler: daireListesi,
          hibeTutari: _parseN(_hibeTutariCtrl.text),
          krediTutari: _parseN(_krediTutariCtrl.text),
        );
      }

      sonuc['siginak'] = siginak;

      final ozet = _aiService.teklifOzetiOlustur(sonuc);
      setState(() {
        _enflasyonProjeksiyonu = projeksiyon;
        _minMaxFiyat = minMax;
        _pazarAnaliziMetni = pazarMetni;
        _hesapSonucu = sonuc;
        _aiOzet = ozet;
        _currentStep = 4;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _kaydet() async {
    if (_hesapSonucu == null) return;
    final sirketId = SistemYoneticisi().aktifSirket?.id ?? '';
    final sirketAd = SistemYoneticisi().aktifSirket?.ad ?? '';

    try {
      await FirebaseFirestore.instance.collection('ai_teklifler').add({
        'sirketId': sirketId,
        'sirket': sirketAd,
        'il': _secilenIl ?? '',
        'ilce': _secilenIlce ?? '',
        'mahalle': _secilenMahalle ?? '',
        'senaryo': _senaryo,
        'hesapSonucu': _hesapSonucu,
        'aiOzet': _aiOzet,
        'tarih': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('AI Teklif kaydedildi'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Kayıt hatası: $e')));
      }
    }
  }

  Future<void> _pdfOlusturVeGoster() async {
    if (_hesapSonucu == null) return;
    setState(() {
      _isLoading = true;
      _loadingMessage = 'PDF oluşturuluyor...';
    });

    try {
      final pdfData = await _generateAiTeklifPdf();
      setState(() => _isLoading = false);
      if (!mounted) return;

      await Printing.layoutPdf(
        onLayout: (_) async => pdfData,
        name: 'AI_Teklif_${DateTime.now().millisecondsSinceEpoch}',
      );
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF hatası: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ═══════════════ BUILD ═══════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Teklif Analizi'),
        actions: [
          IconButton(
            icon: const Icon(Icons.list_alt),
            tooltip: 'Kayıtlı Teklifler',
            onPressed: () => setState(() => _showSavedList = !_showSavedList),
          ),
        ],
      ),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(_loadingMessage, style: const TextStyle(fontSize: 14)),
                ],
              ),
            )
          : _showSavedList
              ? _buildSavedList()
              : _buildStepContent(),
    );
  }

  Widget _buildSavedList() {
    final sirketId = SistemYoneticisi().aktifSirket?.id ?? '';
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('ai_teklifler')
          .where('sirketId', isEqualTo: sirketId)
          .orderBy('tarih', descending: true)
          .limit(20)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) return const Center(child: Text('Kayıtlı teklif yok'));
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            return Card(
              child: ListTile(
                title: Text('${data['il']} / ${data['ilce']}'),
                subtitle: Text('Senaryo ${data['senaryo']} — ${data['mahalle'] ?? ''}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  setState(() {
                    _hesapSonucu = data['hesapSonucu'] as Map<String, dynamic>?;
                    _aiOzet = data['aiOzet'] as String?;
                    _showSavedList = false;
                    _currentStep = 4;
                  });
                },
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildStepContent() {
    return Stepper(
      currentStep: _currentStep,
      type: StepperType.vertical,
      physics: const ClampingScrollPhysics(),
      onStepContinue: () {
        if (_currentStep == 3) {
          _hesaplaVeAnaliz();
        } else if (_validateStep(_currentStep)) {
          if (_currentStep == 1 && _katlar.isEmpty) _krokiOlustur();
          setState(() => _currentStep++);
        }
      },
      controlsBuilder: (context, details) {
        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Row(
            children: [
              if (_currentStep < 4)
                ElevatedButton(
                  onPressed: details.onStepContinue,
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white),
                  child: Text(_currentStep == 3 ? 'Hesapla ve Analiz Et' : 'Devam'),
                ),
              if (_currentStep == 4) ...[
                ElevatedButton.icon(
                  onPressed: _pdfOlusturVeGoster,
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('PDF'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade600, foregroundColor: Colors.white),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _kaydet,
                  icon: const Icon(Icons.save),
                  label: const Text('Kaydet'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade600, foregroundColor: Colors.white),
                ),
              ],
              if (_currentStep > 0 && _currentStep < 4) ...[
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => setState(() => _currentStep--),
                  child: const Text('Geri'),
                ),
              ],
              if (_currentStep == 4) ...[
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => setState(() {
                    _currentStep = 0;
                    _hesapSonucu = null;
                    _aiOzet = null;
                    _enflasyonProjeksiyonu = null;
                    _minMaxFiyat = null;
                    _pazarAnaliziMetni = null;
                  }),
                  child: const Text('Yeni Teklif'),
                ),
              ],
            ],
          ),
        );
      },
      steps: [
        Step(
          title: const Text('Konum Bilgileri'),
          subtitle: _currentStep > 0
              ? Text('${_secilenIl ?? ""} / ${_secilenIlce ?? ""} / ${_secilenMahalle ?? ""}')
              : null,
          isActive: _currentStep >= 0,
          state: _currentStep > 0 ? StepState.complete : StepState.indexed,
          content: _buildStep1(),
        ),
        Step(
          title: const Text('İnşaat Bilgileri'),
          subtitle: _currentStep > 1
              ? Text('${_formatN(_toplamM2)} m² • ${_hesaplananSure} ay • %${_karOraniCtrl.text} kar')
              : null,
          isActive: _currentStep >= 1,
          state: _currentStep > 1 ? StepState.complete : StepState.indexed,
          content: _buildStep2(),
        ),
        Step(
          title: const Text('Bina Krokisi & Daireler'),
          subtitle: _currentStep > 2
              ? Text('${_toplamDaireSayisi} daire • Senaryo $_senaryo')
              : null,
          isActive: _currentStep >= 2,
          state: _currentStep > 2 ? StepState.complete : StepState.indexed,
          content: _buildStep3(),
        ),
        Step(
          title: const Text('Hibe & Kredi'),
          isActive: _currentStep >= 3,
          state: _currentStep > 3 ? StepState.complete : StepState.indexed,
          content: _buildStep4(),
        ),
        Step(
          title: const Text('Analiz Sonucu'),
          isActive: _currentStep >= 4,
          state: _currentStep >= 4 ? StepState.complete : StepState.indexed,
          content: _hesapSonucu != null ? _buildStep5() : const SizedBox.shrink(),
        ),
      ],
    );
  }

  // ═══════════════ STEP 1: Konum (İstanbul + Mahalle Dropdown) ═══════════════

  Widget _buildStep1() {
    return Column(
      children: [
        // İl dropdown
        DropdownButtonFormField<String>(
          value: _secilenIl,
          decoration: const InputDecoration(
            labelText: 'İl',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.location_city),
          ),
          isExpanded: true,
          items: _ilListesi
              .map((il) => DropdownMenuItem(value: il, child: Text(il)))
              .toList(),
          onChanged: (v) {
            setState(() {
              _secilenIl = v;
              _secilenIlce = null;
              _secilenMahalle = null;
              _ilceListesi = v != null ? EmlakDataService.ilceListesi(v) : [];
              _mahalleListesi = [];
            });
          },
        ),
        const SizedBox(height: 12),
        // İlçe dropdown
        DropdownButtonFormField<String>(
          value: _secilenIlce,
          decoration: const InputDecoration(
            labelText: 'İlçe',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.location_on),
          ),
          isExpanded: true,
          items: _ilceListesi.isNotEmpty
              ? _ilceListesi.map((ilce) => DropdownMenuItem(value: ilce, child: Text(ilce))).toList()
              : [const DropdownMenuItem(value: null, child: Text('Önce il seçin'))],
          onChanged: _ilceListesi.isNotEmpty
              ? (v) {
                  setState(() {
                    _secilenIlce = v;
                    _secilenMahalle = null;
                    _mahalleListesi = (v != null && _secilenIl != null)
                        ? EmlakDataService.mahalleListesi(_secilenIl!, v)
                        : [];
                  });
                }
              : null,
        ),
        const SizedBox(height: 12),
        // Mahalle dropdown
        DropdownButtonFormField<String>(
          value: _secilenMahalle,
          decoration: const InputDecoration(
            labelText: 'Mahalle',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.map),
          ),
          isExpanded: true,
          items: _mahalleListesi.isNotEmpty
              ? _mahalleListesi.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList()
              : [const DropdownMenuItem(value: null, child: Text('Önce ilçe seçin'))],
          onChanged: _mahalleListesi.isNotEmpty
              ? (v) => setState(() => _secilenMahalle = v)
              : null,
        ),
        // Bölge fiyat bilgisi
        if (_secilenIl != null && _secilenIlce != null) ...[
          const SizedBox(height: 12),
          Builder(builder: (_) {
            final fiyat = EmlakDataService.ilceM2Fiyat(_secilenIl!, _secilenIlce!, mahalle: _secilenMahalle);
            final kaynakLabel = _secilenMahalle != null ? 'Mahalle' : 'İlçe';
            return Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.teal.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.teal.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, size: 16, color: Colors.teal.shade700),
                      const SizedBox(width: 6),
                      Text('$kaynakLabel Bazında Sıfır Bina m² Fiyatları',
                          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal.shade700, fontSize: 13)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'En Düşük: ${_formatN(fiyat['min']!)} ₺  •  Ortalama: ${_formatN(fiyat['avg']!)} ₺  •  En Yüksek: ${_formatN(fiyat['max']!)} ₺',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            );
          }),
        ],
      ],
    );
  }

  // ═══════════════ STEP 2: İnşaat Bilgileri (Kat bazında m²) ═══════════════

  Widget _buildStep2() {
    return Column(
      children: [
        // Kat sayıları
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _bodrumKatSayisiCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Bodrum Kat Sayısı',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.vertical_align_bottom),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _normalKatSayisiCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Normal Kat Sayısı',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.layers),
                  hintText: 'Zemin dahil',
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Kat bazında m² girişleri
        if ((int.tryParse(_bodrumKatSayisiCtrl.text) ?? 0) > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TextField(
              controller: _bodrumM2Ctrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [_TBinlikFormatter()],
              decoration: InputDecoration(
                labelText: 'Bodrum Kat m² (her bir bodrum)',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.vertical_align_bottom),
                suffixText: '× ${_bodrumKatSayisiCtrl.text} kat',
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
        if ((int.tryParse(_normalKatSayisiCtrl.text) ?? 0) >= 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TextField(
              controller: _zeminM2Ctrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [_TBinlikFormatter()],
              decoration: const InputDecoration(
                labelText: 'Zemin Kat m²',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.home_work),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
        if ((int.tryParse(_normalKatSayisiCtrl.text) ?? 0) > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TextField(
              controller: _normalM2Ctrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [_TBinlikFormatter()],
              decoration: InputDecoration(
                labelText: 'Normal Kat m² (her bir kat)',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.layers),
                suffixText: '× ${(int.tryParse(_normalKatSayisiCtrl.text) ?? 0) - 1} kat',
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),

        // Toplam m² ve süre göstergesi
        if (_toplamM2 > 0) ...[
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(Icons.square_foot, color: Colors.blue.shade700, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'Toplam İnşaat Alanı: ${_formatN(_toplamM2)} m²',
                      style: TextStyle(color: Colors.blue.shade700, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.timer, color: Colors.blue.shade700, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'Tahmini İnşaat Süresi: $_hesaplananSure ay',
                      style: TextStyle(color: Colors.blue.shade700, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        TextField(
          controller: _guncelMaliyetCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [_TBinlikFormatter()],
          decoration: const InputDecoration(
            labelText: 'Güncel m² İmalat Maliyeti (₺)',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.monetization_on),
            hintText: 'Örn: 25.000',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _karOraniCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'İstenen Kar Oranı (%)',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.trending_up),
            hintText: 'Örn: 20',
          ),
        ),
      ],
    );
  }

  // ═══════════════ STEP 3: Kroki + Daire Bilgileri ═══════════════

  Widget _buildStep3() {
    // Senaryo seçimi
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: RadioListTile<int>(
                title: const Text('Senaryo 1', style: TextStyle(fontSize: 13)),
                subtitle: const Text('Müteahhit daire almıyor', style: TextStyle(fontSize: 11)),
                value: 1,
                groupValue: _senaryo,
                onChanged: (v) => setState(() => _senaryo = v!),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
            Expanded(
              child: RadioListTile<int>(
                title: const Text('Senaryo 2', style: TextStyle(fontSize: 13)),
                subtitle: const Text('Müteahhit daire alıyor', style: TextStyle(fontSize: 11)),
                value: 2,
                groupValue: _senaryo,
                onChanged: (v) => setState(() => _senaryo = v!),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),

        if (_senaryo == 2)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              border: Border.all(color: Colors.orange.shade200),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Dairelere tıklayarak müteahhit/mal sahibi atayın',
              style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
            ),
          ),

        // Sığınak uyarısı
        Builder(builder: (_) {
          final s = _siginakKontrolu();
          if (!s['gerekli']) return const SizedBox.shrink();
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: s['yeterli'] ? Colors.green.shade50 : Colors.amber.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: s['yeterli'] ? Colors.green.shade300 : Colors.amber.shade300),
            ),
            child: Row(
              children: [
                Icon(Icons.shield, color: s['yeterli'] ? Colors.green : Colors.amber.shade700, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Sığınak gerekli: ${(s['gerekenM2'] as double).toStringAsFixed(0)} m²',
                  style: TextStyle(fontWeight: FontWeight.w600, color: s['yeterli'] ? Colors.green.shade800 : Colors.amber.shade900, fontSize: 12),
                ),
              ],
            ),
          );
        }),

        const SizedBox(height: 12),

        // Bina Krokisi
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade700, width: 2),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            children: [
              // Çatı
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.brown.shade400,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.roofing, color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Bina Krokisi — ${_katlar.length} Kat, $_toplamDaireSayisi Bölüm',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ],
                ),
              ),
              // Katlar (üstten alta)
              for (int i = _katlar.length - 1; i >= 0; i--)
                _buildKatSatiri(i),
            ],
          ),
        ),

        if (_senaryo == 2) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(width: 16, height: 16, decoration: BoxDecoration(color: Colors.orange.shade200, border: Border.all(color: Colors.orange.shade400))),
              const SizedBox(width: 4),
              const Text('Müteahhit', style: TextStyle(fontSize: 11)),
              const SizedBox(width: 16),
              Container(width: 16, height: 16, decoration: BoxDecoration(color: Colors.blue.shade50, border: Border.all(color: Colors.blue.shade200))),
              const SizedBox(width: 4),
              const Text('Mal Sahibi', style: TextStyle(fontSize: 11)),
            ],
          ),
        ],

        const SizedBox(height: 8),
        Center(
          child: Text(
            'Dairenin detaylarını düzenlemek için üzerine uzun basın\n'
            'Her bölüm için × butonuyla çıkarma yapabilirsiniz',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
          ),
        ),
      ],
    );
  }

  Widget _buildKatSatiri(int katIndex) {
    final katData = _katlar[katIndex];
    final ad = katData['ad'] as String;
    final kat = katData['kat'] as int;
    final katAlaniCtrl = katData['katAlaniCtrl'] as TextEditingController;
    final daireler = katData['daireler'] as List<Map<String, dynamic>>;
    final phantoms = _phantomCellsForFloor(katIndex);

    // Renk
    Color katBg;
    if (kat < 0) {
      katBg = Colors.grey.shade100;
    } else if (kat == 0) {
      katBg = Colors.amber.shade50;
    } else {
      katBg = Colors.white;
    }

    // Alan kullanımı
    final katAlani = _parseN(katAlaniCtrl.text);
    double daireM2 = 0;
    for (final d in daireler) {
      daireM2 += _parseN((d['m2Ctrl'] as TextEditingController).text);
    }
    final crossM2 = _crossFloorM2ForFloor(katIndex);
    final toplam = daireM2 + crossM2;
    final alanAsimi = katAlani > 0 && toplam > katAlani;

    return Container(
      decoration: BoxDecoration(
        color: katBg,
        border: Border(top: BorderSide(color: Colors.grey.shade500)),
      ),
      child: Column(
        children: [
          // Kat başlığı
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            color: kat < 0 ? Colors.grey.shade200 : (kat == 0 ? Colors.amber.shade100 : Colors.blue.shade50),
            child: Row(
              children: [
                SizedBox(
                  width: 100,
                  child: Text(ad, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                ),
                const SizedBox(width: 4),
                SizedBox(
                  width: 80,
                  child: TextField(
                    controller: katAlaniCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [_TBinlikFormatter()],
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 11),
                    decoration: const InputDecoration(
                      hintText: 'Kat m²',
                      isDense: true,
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 4),
                Text('m²', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                const Spacer(),
                // Alan kullanımı göstergesi
                if (katAlani > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      color: alanAsimi ? Colors.red.shade50 : Colors.green.shade50,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: alanAsimi ? Colors.red.shade300 : Colors.green.shade300),
                    ),
                    child: Text(
                      'Kalan: ${_formatN(katAlani - toplam)}',
                      style: TextStyle(fontSize: 9, color: alanAsimi ? Colors.red.shade700 : Colors.green.shade700, fontWeight: FontWeight.bold),
                    ),
                  ),
                const SizedBox(width: 4),
                // Daire ekle
                SizedBox(
                  height: 28,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    icon: Icon(Icons.add_circle, color: Colors.green.shade600, size: 22),
                    tooltip: 'Bölüm Ekle',
                    onPressed: () {
                      setState(() {
                        int maxNo = 0;
                        for (final k in _katlar) {
                          for (final d in (k['daireler'] as List)) {
                            if ((d['no'] as int) > maxNo) maxNo = d['no'] as int;
                          }
                        }
                        daireler.add(_yeniDaire(no: maxNo + 1, kat: kat));
                      });
                    },
                  ),
                ),
              ],
            ),
          ),
          // Daireler + phantom hücreler
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...daireler.asMap().entries.map((entry) {
                  return Expanded(
                    child: Container(
                      decoration: entry.key < daireler.length - 1 || phantoms.isNotEmpty
                          ? BoxDecoration(border: Border(right: BorderSide(color: Colors.grey.shade400)))
                          : null,
                      child: _buildDaireHucre(entry.value, katIndex),
                    ),
                  );
                }),
                ...phantoms.asMap().entries.map((entry) {
                  final isLast = entry.key == phantoms.length - 1;
                  return Expanded(
                    child: Container(
                      decoration: !isLast
                          ? BoxDecoration(border: Border(right: BorderSide(color: Colors.grey.shade400)))
                          : null,
                      child: _buildPhantomHucre(entry.value),
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDaireHucre(Map<String, dynamic> daire, int katIndex) {
    final isMuteahhit = daire['sahip'] == 'muteahhit';
    final no = daire['no'] as int;
    final m2Ctrl = daire['m2Ctrl'] as TextEditingController;
    final tip = daire['tip'] as String;
    final hibeVar = daire['hibeVar'] as bool;
    final krediVar = daire['krediVar'] as bool;
    final daireler = _katlar[katIndex]['daireler'] as List;

    Color bgColor;
    if (_senaryo == 2) {
      bgColor = isMuteahhit ? Colors.orange.shade100 : Colors.blue.shade50;
    } else {
      bgColor = Colors.transparent;
    }

    String tipGosterge = '';
    if (tip == 'Dubleks') tipGosterge = 'D↑';
    else if (tip == 'Ters Dubleks') tipGosterge = 'D↓';
    else if (tip == 'Depolu Dükkan') tipGosterge = 'DD';
    else if (tip == 'Dükkan') tipGosterge = 'Dk';
    else if (tip == 'Ofis') tipGosterge = 'Of';

    return GestureDetector(
      onTap: _senaryo == 2
          ? () => setState(() {
                daire['sahip'] = isMuteahhit ? 'malSahibi' : 'muteahhit';
              })
          : () => _daireDuzenleDialog(daire, katIndex),
      onLongPress: () => _daireDuzenleDialog(daire, katIndex),
      child: Stack(
        children: [
          Container(
            color: bgColor,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('D$no', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    if (_senaryo == 2) ...[
                      const SizedBox(width: 3),
                      Icon(
                        isMuteahhit ? Icons.construction : Icons.home,
                        size: 12,
                        color: isMuteahhit ? Colors.orange.shade700 : Colors.blue.shade700,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                SizedBox(
                  width: 55,
                  height: 24,
                  child: TextField(
                    controller: m2Ctrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [_TBinlikFormatter()],
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
                    decoration: InputDecoration(
                      hintText: 'm²',
                      hintStyle: TextStyle(fontSize: 9, color: Colors.grey.shade400),
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                if (tipGosterge.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 2),
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: tip.contains('Dükkan') ? Colors.purple.shade50 : Colors.indigo.shade50,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(tipGosterge, style: TextStyle(fontSize: 9, color: Colors.indigo.shade700, fontWeight: FontWeight.bold)),
                  )
                else
                  Text(tip, style: TextStyle(fontSize: 9, color: Colors.grey.shade500)),
                if (hibeVar || krediVar)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (hibeVar) Text('H', style: TextStyle(fontSize: 8, color: Colors.green.shade700, fontWeight: FontWeight.bold)),
                      if (hibeVar && krediVar) const Text(' ', style: TextStyle(fontSize: 8)),
                      if (krediVar) Text('K', style: TextStyle(fontSize: 8, color: Colors.purple.shade700, fontWeight: FontWeight.bold)),
                    ],
                  ),
              ],
            ),
          ),
          // Bölüm çıkarma butonu (Task 1)
          if (daireler.length > 1)
            Positioned(
              top: 0,
              right: 0,
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    daireler.remove(daire);
                    (daire['m2Ctrl'] as TextEditingController).dispose();
                    (daire['ustM2Ctrl'] as TextEditingController).dispose();
                    (daire['altM2Ctrl'] as TextEditingController).dispose();
                  });
                },
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.close, size: 12, color: Colors.red.shade400),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Phantom hücre — cross-floor birim gösterimi (Tasks 2-4)
  Widget _buildPhantomHucre(Map<String, dynamic> phantom) {
    final label = phantom['label'] as String;
    final tip = phantom['tip'] as String;
    final m2 = phantom['m2'] as double;

    Color bgColor;
    IconData icon;
    if (tip == 'Depo') {
      bgColor = Colors.brown.shade50;
      icon = Icons.warehouse;
    } else if (tip == 'TD Alt') {
      bgColor = Colors.indigo.shade50;
      icon = Icons.arrow_downward;
    } else {
      bgColor = Colors.deepPurple.shade50;
      icon = Icons.arrow_upward;
    }

    return Container(
      color: bgColor,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 14, color: Colors.grey.shade600),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.grey.shade700),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          Text(
            '${_formatN(m2)} m²',
            style: TextStyle(fontSize: 10, color: Colors.grey.shade600, fontWeight: FontWeight.w600),
          ),
          Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(tip, style: TextStyle(fontSize: 8, color: Colors.grey.shade600)),
          ),
        ],
      ),
    );
  }

  void _daireDuzenleDialog(Map<String, dynamic> daire, int katIndex) {
    final m2Ctrl = daire['m2Ctrl'] as TextEditingController;
    final ustM2Ctrl = daire['ustM2Ctrl'] as TextEditingController;
    final altM2Ctrl = daire['altM2Ctrl'] as TextEditingController;
    final tempM2Ctrl = TextEditingController(text: m2Ctrl.text);
    final tempUstM2Ctrl = TextEditingController(text: ustM2Ctrl.text);
    final tempAltM2Ctrl = TextEditingController(text: altM2Ctrl.text);
    String tempTip = daire['tip'] as String;
    bool tempHibe = daire['hibeVar'] as bool;
    bool tempKredi = daire['krediVar'] as bool;

    final tipler = _tiplerForKat(katIndex);
    if (!tipler.contains(tempTip)) tempTip = 'Daire';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Daire ${daire['no']} — ${(_katlar[katIndex]['ad'])}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: tempTip,
                  decoration: const InputDecoration(
                    labelText: 'Tip',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.category),
                  ),
                  items: tipler
                      .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                      .toList(),
                  onChanged: (v) => setDialogState(() => tempTip = v!),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: tempM2Ctrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [_TBinlikFormatter()],
                  decoration: InputDecoration(
                    labelText: tempTip == 'Dubleks'
                        ? 'Ana Kat m²'
                        : (tempTip == 'Ters Dubleks' || tempTip == 'Depolu Dükkan')
                            ? 'Ana Kat m²'
                            : 'Metrekare (m²)',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.square_foot),
                  ),
                ),
                if (tempTip == 'Dubleks') ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: tempUstM2Ctrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [_TBinlikFormatter()],
                    decoration: const InputDecoration(
                      labelText: 'Üst Kat m²',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.arrow_upward),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('Üst kat m² bir üst kattan düşülür ve krokide görünür',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontStyle: FontStyle.italic)),
                ],
                if (tempTip == 'Ters Dubleks' || tempTip == 'Depolu Dükkan') ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: tempAltM2Ctrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [_TBinlikFormatter()],
                    decoration: InputDecoration(
                      labelText: tempTip == 'Depolu Dükkan' ? 'Depo m²' : 'Alt Kat m²',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.arrow_downward),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    tempTip == 'Depolu Dükkan'
                        ? 'Depo m² alt kattan düşülür ve krokide görünür'
                        : 'Alt kat m² alt kattan düşülür ve krokide görünür',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: CheckboxListTile(
                        title: const Text('Hibe', style: TextStyle(fontSize: 13)),
                        value: tempHibe,
                        onChanged: (v) => setDialogState(() => tempHibe = v!),
                        dense: true,
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    Expanded(
                      child: CheckboxListTile(
                        title: const Text('Kredi', style: TextStyle(fontSize: 13)),
                        value: tempKredi,
                        onChanged: (v) => setDialogState(() => tempKredi = v!),
                        dense: true,
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                tempM2Ctrl.dispose();
                tempUstM2Ctrl.dispose();
                tempAltM2Ctrl.dispose();
                Navigator.pop(ctx);
              },
              child: const Text('İptal'),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  m2Ctrl.text = tempM2Ctrl.text;
                  ustM2Ctrl.text = tempUstM2Ctrl.text;
                  altM2Ctrl.text = tempAltM2Ctrl.text;
                  daire['tip'] = tempTip;
                  daire['hibeVar'] = tempHibe;
                  daire['krediVar'] = tempKredi;
                });
                tempM2Ctrl.dispose();
                tempUstM2Ctrl.dispose();
                tempAltM2Ctrl.dispose();
                Navigator.pop(ctx);
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white),
              child: const Text('Tamam'),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════ STEP 4: Hibe & Kredi ═══════════════

  Widget _buildStep4() {
    return Column(
      children: [
        TextField(
          controller: _hibeTutariCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [_TBinlikFormatter()],
          decoration: const InputDecoration(
            labelText: 'Daire Başı Hibe Tutarı (₺)',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.card_giftcard),
            hintText: 'Yoksa 0',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _krediTutariCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [_TBinlikFormatter()],
          decoration: const InputDecoration(
            labelText: 'Daire Başı Kredi Tutarı (₺)',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.account_balance),
            hintText: 'Yoksa 0',
          ),
        ),
        const SizedBox(height: 16),
        // Sığınak bilgisi
        Builder(builder: (_) {
          final s = _siginakKontrolu();
          if (!s['gerekli']) return const SizedBox.shrink();
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: s['yeterli'] ? Colors.green.shade50 : Colors.red.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: s['yeterli'] ? Colors.green.shade300 : Colors.red.shade300),
            ),
            child: Row(
              children: [
                Icon(Icons.shield, color: s['yeterli'] ? Colors.green : Colors.red, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Sığınak: ${(s['gerekenM2'] as double).toStringAsFixed(0)} m² gerekli',
                  style: TextStyle(fontWeight: FontWeight.w600, color: s['yeterli'] ? Colors.green.shade800 : Colors.red.shade800),
                ),
              ],
            ),
          );
        }),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            border: Border.all(color: Colors.orange.shade200),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Özet:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('Konum: ${_secilenIl ?? ""} / ${_secilenIlce ?? ""} / ${_secilenMahalle ?? ""}'),
              Text('Toplam Alan: ${_formatN(_toplamM2)} m²'),
              Text('Süre: $_hesaplananSure ay'),
              Text('Maliyet: ${_guncelMaliyetCtrl.text} ₺/m²  •  Kar: %${_karOraniCtrl.text}'),
              Text('Bölüm: $_toplamDaireSayisi  •  Senaryo ${_senaryo == 1 ? "1 (daire almıyor)" : "2 (daire alıyor)"}'),
              if (_senaryo == 2)
                Builder(builder: (_) {
                  int mc = 0;
                  for (final k in _katlar) {
                    for (final d in (k['daireler'] as List)) {
                      if (d['sahip'] == 'muteahhit') mc++;
                    }
                  }
                  return Text('Müteahhit Daire: $mc adet');
                }),
              const SizedBox(height: 8),
              const Text('"Hesapla ve Analiz Et" butonuna basarak başlatın.',
                  style: TextStyle(fontStyle: FontStyle.italic, fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }

  // ═══════════════ STEP 5: Sonuçlar ═══════════════

  Widget _buildStep5() {
    final sonuc = _hesapSonucu!;
    final senaryo = sonuc['senaryo'] as int;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildVeriKaynagiWidget(),
          const SizedBox(height: 12),

          // Maliyet Analizi
          _buildGradientCard(
            title: 'Maliyet Analizi',
            icon: Icons.show_chart,
            gradient: [Colors.blue.shade600, Colors.blue.shade400],
            child: Column(
              children: [
                _buildAnalysisRow('Yıllık İnşaat Enflasyonu', '%${(sonuc['yillikEnflasyon'] as double).toStringAsFixed(1)}'),
                _buildAnalysisRow('İnşaat Süresi', '${sonuc['insaatSuresi']} ay'),
                const Divider(color: Colors.white24),
                _buildAnalysisRow('Güncel m² Maliyet', '${_formatN(sonuc['guncelM2Maliyet'])} ₺'),
                _buildTripleRow(
                  'Tahmini m² Maliyet',
                  _formatN((sonuc['minM2Maliyet'] as num).toDouble()),
                  _formatN(sonuc['enflasyonluM2Maliyet']),
                  _formatN((sonuc['maxM2Maliyet'] as num).toDouble()),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Fiyat Önerisi
          if (_minMaxFiyat != null)
            _buildGradientCard(
              title: 'Önerilen m² Satış Fiyatı',
              icon: Icons.price_change,
              gradient: [Colors.teal.shade600, Colors.teal.shade400],
              child: Column(
                children: [
                  _buildTripleRow(
                    '%${_karOraniCtrl.text} kar ile',
                    _formatN(_minMaxFiyat!['minM2Fiyat']!),
                    _formatN(_minMaxFiyat!['ortM2Fiyat']!),
                    _formatN(_minMaxFiyat!['maxM2Fiyat']!),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Toplam: ${_formatN((sonuc['toplamInsaatM2'] as double) * _minMaxFiyat!['ortM2Fiyat']!)} ₺',
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 10),

          // Sığınak
          if (sonuc['siginak'] != null) ...[
            Builder(builder: (_) {
              final s = sonuc['siginak'] as Map<String, dynamic>;
              if (!(s['gerekli'] as bool)) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Card(
                  color: (s['yeterli'] as bool) ? Colors.green.shade50 : Colors.red.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Icon(Icons.shield, color: (s['yeterli'] as bool) ? Colors.green : Colors.red),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Sığınak Gereksinimi: ${(s['gerekenM2'] as double).toStringAsFixed(0)} m² '
                            '(${s['konutSayisi']} konut × 4 m²)\n'
                            '${(s['yeterli'] as bool) ? "Yeterli" : "Yetersiz — Binaya sığınak ekleyin"}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: (s['yeterli'] as bool) ? Colors.green.shade800 : Colors.red.shade800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ],

          // Müteahhit Daireleri
          if (senaryo == 2 && sonuc['muteahhitDaireleri'] != null) ...[
            _buildGradientCard(
              title: 'Müteahhit Daireleri — Satış Tahmini',
              icon: Icons.business,
              gradient: [Colors.orange.shade600, Colors.orange.shade400],
              child: Column(
                children: [
                  ...((sonuc['muteahhitDaireleri'] as List).map((d) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${d['tip']} ${d['m2']} m² (${_katAdiFromInt(d['kat'] as int)})',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _miniLabel('Min', _formatN((d['minSatisFiyati'] as num).toDouble())),
                              _miniLabel('Ort', _formatN((d['tahminiSatisFiyati'] as num).toDouble())),
                              _miniLabel('Max', _formatN((d['maxSatisFiyati'] as num).toDouble())),
                            ],
                          ),
                        ],
                      ),
                    );
                  })),
                  const Divider(color: Colors.white24),
                  _buildTripleRow(
                    'Toplam Satış',
                    _formatN((sonuc['muteahhitSatisMin'] as num).toDouble()),
                    _formatN((sonuc['muteahhitSatisGeliri'] as num).toDouble()),
                    _formatN((sonuc['muteahhitSatisMax'] as num).toDouble()),
                  ),
                  _buildAnalysisRow('Kalan Maliyet', '${_formatN((sonuc['kalanMaliyet'] as num).toDouble())} ₺'),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],

          // Mal Sahibi Daire Ödemeleri
          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.people, color: Colors.green.shade700, size: 20),
                      const SizedBox(width: 8),
                      Text('Mal Sahibi Daire Ödemeleri',
                          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green.shade700, fontSize: 14)),
                    ],
                  ),
                  const Divider(),
                  ..._buildDaireOdemeWidgets(sonuc),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Pazar Analizi
          if (_pazarAnaliziMetni != null)
            Card(
              elevation: 2,
              child: ExpansionTile(
                leading: Icon(Icons.analytics, color: Colors.indigo.shade700),
                title: Text('Bölge Pazar Analizi', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo.shade700, fontSize: 14)),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(_pazarAnaliziMetni!, style: const TextStyle(fontSize: 12, height: 1.6, fontFamily: 'monospace')),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 10),

          // Özet Rapor
          if (_aiOzet != null)
            Card(
              elevation: 2,
              child: ExpansionTile(
                leading: Icon(Icons.smart_toy, color: Colors.purple.shade700),
                title: Text('Detaylı Rapor', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.purple.shade700, fontSize: 14)),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(_aiOzet!, style: const TextStyle(fontSize: 12, height: 1.5)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ══════════ UI Helpers ══════════

  Widget _buildVeriKaynagiWidget() {
    final canli = _aiService.veriKaynagi.contains('canlı');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: canli
              ? [Colors.green.shade400, Colors.green.shade600]
              : [Colors.amber.shade400, Colors.amber.shade600],
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(canli ? Icons.cloud_done : Icons.storage, size: 18, color: Colors.white),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Veri: ${_aiService.veriKaynagi}',
              style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ),
          GestureDetector(
            onTap: _tcmbApiKeyDialog,
            child: const Icon(Icons.settings, size: 18, color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _buildGradientCard({
    required String title,
    required IconData icon,
    required List<Color> gradient,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: gradient[0].withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 14)),
            ],
          ),
          const Divider(color: Colors.white24),
          child,
        ],
      ),
    );
  }

  Widget _buildAnalysisRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildTripleRow(String label, String min, String ort, String max) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _miniLabel('Min', '$min ₺'),
              _miniLabel('Ort', '$ort ₺'),
              _miniLabel('Max', '$max ₺'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniLabel(String label, String value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10)),
        Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
      ],
    );
  }

  String _katAdiFromInt(int kat) {
    if (kat < 0) return '${kat.abs()}. Bodrum';
    if (kat == 0) return 'Zemin';
    return '$kat. Kat';
  }

  List<Widget> _buildDaireOdemeWidgets(Map<String, dynamic> sonuc) {
    final senaryo = sonuc['senaryo'] as int;
    final daireler = senaryo == 1
        ? (sonuc['daireler'] as List)
        : (sonuc['malSahibiDaireleri'] as List);

    return daireler.map<Widget>((d) {
      final tip = d['tip'] ?? 'Daire';
      final m2 = _formatN((d['m2'] as num).toDouble());
      final kat = d['kat'] as int;
      final brut = _formatN((d['brutMaliyet'] as num).toDouble());
      final net = _formatN((d['netOdeme'] as num).toDouble());
      final hibe = d['hibeVar'] == true;
      final kredi = d['krediVar'] == true;

      return Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('$tip $m2 m² (${_katAdiFromInt(kat)})',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.green.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('Net: $net ₺', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.green.shade800)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Brüt: $brut ₺${hibe ? '  •  Hibe düşüldü' : ''}${kredi ? '  •  Kredi düşüldü' : ''}',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }).toList();
  }

  void _tcmbApiKeyDialog() async {
    final currentKey = await TcmbService.getApiKey() ?? '';
    final ctrl = TextEditingController(text: currentKey);

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('TCMB EVDS API Anahtarı'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Canlı veri almak için TCMB EVDS API anahtarı girin.\n'
              'evds2.tcmb.gov.tr adresinden ücretsiz alabilirsiniz.\n\n'
              'Anahtar girilmezse yerleşik veriler kullanılır.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(
                labelText: 'API Key',
                border: OutlineInputBorder(),
                hintText: 'TCMB EVDS API anahtarınız',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              ctrl.dispose();
              Navigator.pop(ctx);
            },
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () async {
              final key = ctrl.text.trim();
              await TcmbService.setApiKey(key);
              ctrl.dispose();
              if (!ctx.mounted) return;
              Navigator.pop(ctx);

              if (key.isNotEmpty && mounted) {
                setState(() {
                  _isLoading = true;
                  _loadingMessage = 'API bağlantısı test ediliyor...';
                });
                final basarili = await _aiService.verileriGuncelle();
                setState(() => _isLoading = false);

                if (mounted) {
                  if (basarili) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('API bağlantısı başarılı! Canlı veri aktif.'), backgroundColor: Colors.green),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('API bağlantısı başarısız: ${_aiService.tcmbHataMesaji ?? "Bilinmeyen hata"}'),
                        backgroundColor: Colors.red,
                        duration: const Duration(seconds: 5),
                      ),
                    );
                  }
                }
              } else if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('API anahtarı temizlendi. Yerleşik veriler kullanılacak.'), backgroundColor: Colors.orange),
                );
              }
            },
            child: const Text('Kaydet ve Test Et'),
          ),
        ],
      ),
    );
  }

  // ============ PDF ============

  Future<Uint8List> _generateAiTeklifPdf() async {
    return ai_pdf.generateAiTeklifPdf(
      hesapSonucu: _hesapSonucu!,
      aiOzet: _aiOzet ?? '',
      il: _secilenIl ?? '',
      ilce: _secilenIlce ?? '',
      mahalle: _secilenMahalle ?? '',
      firmaAdi: SistemYoneticisi().aktifSirket?.ad ?? '',
      firmaLogosu: SistemYoneticisi().aktifSirket?.logo,
    );
  }
}
