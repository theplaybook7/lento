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

  // Step 1: Temel bilgiler
  final _ilCtrl = TextEditingController();
  final _ilceCtrl = TextEditingController();
  final _mahalleCtrl = TextEditingController();

  // Step 2: İnşaat bilgileri
  final _toplamM2Ctrl = TextEditingController();
  final _katSayisiCtrl = TextEditingController();
  final _katBasiDaireCtrl = TextEditingController(text: '2');
  final _guncelMaliyetCtrl = TextEditingController();
  final _karOraniCtrl = TextEditingController(text: '20');

  // Step 3: Daire bilgileri
  final List<Map<String, dynamic>> _daireler = [];
  int _senaryo = 1; // 1: daire almıyor, 2: daire alıyor

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

  @override
  void dispose() {
    _ilCtrl.dispose();
    _ilceCtrl.dispose();
    _mahalleCtrl.dispose();
    _toplamM2Ctrl.dispose();
    _katSayisiCtrl.dispose();
    _katBasiDaireCtrl.dispose();
    _guncelMaliyetCtrl.dispose();
    _karOraniCtrl.dispose();
    _hibeTutariCtrl.dispose();
    _krediTutariCtrl.dispose();
    for (final d in _daireler) {
      (d['m2Ctrl'] as TextEditingController).dispose();
    }
    super.dispose();
  }

  void _daireleriOlustur() {
    for (final d in _daireler) {
      (d['m2Ctrl'] as TextEditingController).dispose();
    }
    _daireler.clear();

    final katSayisi = int.tryParse(_katSayisiCtrl.text) ?? 1;
    final katBasiDaire = int.tryParse(_katBasiDaireCtrl.text) ?? 2;
    final toplamM2 = _parseN(_toplamM2Ctrl.text);
    final toplamDaire = katSayisi * katBasiDaire;
    final daireM2 = toplamDaire > 0 ? toplamM2 / toplamDaire : 0.0;
    final daireM2Str = daireM2 > 0 ? _formatN(daireM2) : '';

    int no = 1;
    for (int kat = 1; kat <= katSayisi; kat++) {
      for (int i = 0; i < katBasiDaire; i++) {
        _daireler.add({
          'tip': 'Daire',
          'm2Ctrl': TextEditingController(text: daireM2Str),
          'kat': kat,
          'no': no++,
          'sahip': 'malSahibi',
          'hibeVar': false,
          'krediVar': false,
        });
      }
    }
    setState(() {});
  }

  int get _hesaplananSure => TcmbService.insaatSuresiHesapla(_parseN(_toplamM2Ctrl.text));

  bool _validateStep(int step) {
    switch (step) {
      case 0:
        return _ilCtrl.text.trim().isNotEmpty &&
            _ilceCtrl.text.trim().isNotEmpty &&
            _mahalleCtrl.text.trim().isNotEmpty;
      case 1:
        return _parseN(_toplamM2Ctrl.text) > 0 &&
            (int.tryParse(_katSayisiCtrl.text) ?? 0) > 0 &&
            (int.tryParse(_katBasiDaireCtrl.text) ?? 0) > 0 &&
            _parseN(_guncelMaliyetCtrl.text) > 0 &&
            _parseN(_karOraniCtrl.text) > 0;
      case 2:
        if (_daireler.isEmpty) return false;
        if (!_daireler.every((d) => _parseN((d['m2Ctrl'] as TextEditingController).text) > 0)) return false;
        if (_senaryo == 2 && !_daireler.any((d) => d['sahip'] == 'muteahhit')) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Senaryo 2 için en az bir daireyi müteahhite atamalısınız!'),
              backgroundColor: Colors.red,
            ),
          );
          return false;
        }
        return true;
      default:
        return true;
    }
  }

  Future<void> _hesaplaVeAnaliz() async {
    setState(() {
      _isLoading = true;
      _loadingMessage = 'TCMB verileri alınıyor...';
    });

    try {
      // TCMB verisi çekmeyi dene
      await _aiService.verileriGuncelle();

      setState(() => _loadingMessage = 'İstatistiksel analiz yapılıyor...');

      // 1. Enflasyon projeksiyonu
      final projeksiyon = _aiService.enflasyonProjeksiyonu(
        guncelMaliyet: _parseN(_guncelMaliyetCtrl.text),
        toplamM2: _parseN(_toplamM2Ctrl.text),
      );

      // 2. Min/Max fiyat önerisi
      final minMax = _aiService.minMaxFiyatOnerisi(
        guncelMaliyet: _parseN(_guncelMaliyetCtrl.text),
        toplamM2: _parseN(_toplamM2Ctrl.text),
        karOrani: _parseN(_karOraniCtrl.text),
      );

      // 3. Daire listesini hazırla
      final daireListesi = _daireler.map((d) => {
        'm2': _parseN((d['m2Ctrl'] as TextEditingController).text),
        'kat': d['kat'] as int,
        'tip': d['tip'] as String,
        'sahip': d['sahip'] as String,
        'hibeVar': d['hibeVar'] as bool,
        'krediVar': d['krediVar'] as bool,
      }).toList();

      // 4. Pazar analizi
      setState(() => _loadingMessage = 'Pazar verileri analiz ediliyor...');
      final pazarMetni = _aiService.pazarAnalizi(
        il: _ilCtrl.text.trim(),
        ilce: _ilceCtrl.text.trim(),
        mahalle: _mahalleCtrl.text.trim(),
        insaatSuresi: _hesaplananSure,
        daireler: daireListesi,
      );

      // 5. Senaryo hesapla
      Map<String, dynamic> sonuc;

      if (_senaryo == 2) {
        sonuc = _aiService.senaryo2Hesapla(
          guncelM2Maliyet: _parseN(_guncelMaliyetCtrl.text),
          toplamInsaatM2: _parseN(_toplamM2Ctrl.text),
          karOrani: _parseN(_karOraniCtrl.text),
          daireler: daireListesi,
          hibeTutari: _parseN(_hibeTutariCtrl.text),
          krediTutari: _parseN(_krediTutariCtrl.text),
          il: _ilCtrl.text.trim(),
          ilce: _ilceCtrl.text.trim(),
          insaatSuresi: _hesaplananSure,
        );
      } else {
        sonuc = _aiService.senaryo1Hesapla(
          guncelM2Maliyet: _parseN(_guncelMaliyetCtrl.text),
          toplamInsaatM2: _parseN(_toplamM2Ctrl.text),
          karOrani: _parseN(_karOraniCtrl.text),
          daireler: daireListesi,
          hibeTutari: _parseN(_hibeTutariCtrl.text),
          krediTutari: _parseN(_krediTutariCtrl.text),
        );
      }

      // 6. Özet rapor
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
          SnackBar(content: Text('Hata: $e')),
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
        'il': _ilCtrl.text.trim(),
        'ilce': _ilceCtrl.text.trim(),
        'mahalle': _mahalleCtrl.text.trim(),
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
      final pdfBytes = await _generateAiTeklifPdf();
      if (mounted) {
        await Printing.layoutPdf(onLayout: (format) async => pdfBytes);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('PDF hatası: $e')));
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Teklif Asistanı'),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'TCMB API Ayarları',
            onPressed: _tcmbApiKeyDialog,
          ),
          IconButton(
            icon: Icon(_showSavedList ? Icons.calculate : Icons.list),
            tooltip: _showSavedList ? 'Yeni Teklif' : 'Kayıtlı Teklifler',
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
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return const Center(child: Text('Kayıtlı AI teklif bulunamadı.'));
        }
        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (_, i) {
            final data = docs[i].data() as Map<String, dynamic>;
            final tarih = (data['tarih'] as Timestamp?)?.toDate();
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: data['senaryo'] == 1 ? Colors.blue : Colors.orange,
                  child: Text('S${data['senaryo']}', style: const TextStyle(color: Colors.white)),
                ),
                title: Text('${data['il']} / ${data['ilce']} / ${data['mahalle']}'),
                subtitle: Text(
                  tarih != null ? DateFormat('dd.MM.yyyy HH:mm').format(tarih) : '',
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () => docs[i].reference.delete(),
                ),
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
      controlsBuilder: (context, details) {
        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Row(
            children: [
              if (_currentStep < 4)
                ElevatedButton(
                  onPressed: () {
                    if (_currentStep == 3) {
                      _hesaplaVeAnaliz();
                    } else if (_validateStep(_currentStep)) {
                      if (_currentStep == 1) {
                        _daireleriOlustur();
                      }
                      setState(() => _currentStep++);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Lütfen tüm alanları doldurun')),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor),
                  child: Text(
                    _currentStep == 3 ? 'AI ile Hesapla' : 'Devam',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              if (_currentStep == 4) ...[
                ElevatedButton.icon(
                  onPressed: _pdfOlusturVeGoster,
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('PDF Oluştur'),
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
              ? Text('${_ilCtrl.text} / ${_ilceCtrl.text} / ${_mahalleCtrl.text}')
              : null,
          isActive: _currentStep >= 0,
          state: _currentStep > 0 ? StepState.complete : StepState.indexed,
          content: _buildStep1(),
        ),
        Step(
          title: const Text('İnşaat Bilgileri'),
          subtitle: _currentStep > 1
              ? Text('${_formatN(_parseN(_toplamM2Ctrl.text))} m² • ${_hesaplananSure} ay • %${_karOraniCtrl.text} kar')
              : null,
          isActive: _currentStep >= 1,
          state: _currentStep > 1 ? StepState.complete : StepState.indexed,
          content: _buildStep2(),
        ),
        Step(
          title: const Text('Daire Bilgileri'),
          subtitle: _currentStep > 2
              ? Text('${_daireler.length} daire • Senaryo ${_senaryo}')
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
          title: const Text('AI Analiz Sonucu'),
          isActive: _currentStep >= 4,
          state: _currentStep >= 4 ? StepState.complete : StepState.indexed,
          content: _hesapSonucu != null ? _buildStep5() : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _buildStep1() {
    return Column(
      children: [
        TextField(
          controller: _ilCtrl,
          decoration: const InputDecoration(labelText: 'İl', border: OutlineInputBorder(), prefixIcon: Icon(Icons.location_city)),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _ilceCtrl,
          decoration: const InputDecoration(labelText: 'İlçe', border: OutlineInputBorder(), prefixIcon: Icon(Icons.location_on)),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _mahalleCtrl,
          decoration: const InputDecoration(labelText: 'Mahalle', border: OutlineInputBorder(), prefixIcon: Icon(Icons.map)),
        ),
      ],
    );
  }

  Widget _buildStep2() {
    return Column(
      children: [
        TextField(
          controller: _toplamM2Ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [_TBinlikFormatter()],
          decoration: const InputDecoration(
            labelText: 'Toplam İnşaat Alanı (m²)',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.square_foot),
          ),
          onChanged: (_) => setState(() {}),
        ),
        if (_parseN(_toplamM2Ctrl.text) > 0) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.timer, color: Colors.blue.shade700, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Tahmini İnşaat Süresi: $_hesaplananSure ay',
                  style: TextStyle(color: Colors.blue.shade700, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _katSayisiCtrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Kat Sayısı',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.layers),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _katBasiDaireCtrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Kat Başı Daire Sayısı',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.door_front_door),
            hintText: 'Örn: 2',
          ),
        ),
        const SizedBox(height: 12),
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

  Widget _buildStep3() {
    final katSayisi = int.tryParse(_katSayisiCtrl.text) ?? 1;
    final katBasiDaire = int.tryParse(_katBasiDaireCtrl.text) ?? 2;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Senaryo seçimi
        Card(
          color: Colors.amber.shade50,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Senaryo Seçin:', style: TextStyle(fontWeight: FontWeight.bold)),
                RadioListTile<int>(
                  title: const Text('Müteahhit daire almıyor'),
                  subtitle: const Text('Saf m² fiyatı ile hesaplama'),
                  value: 1,
                  groupValue: _senaryo,
                  onChanged: (v) => setState(() => _senaryo = v!),
                  dense: true,
                ),
                RadioListTile<int>(
                  title: const Text('Müteahhit daire alıyor'),
                  subtitle: const Text('Daire satış geliri düşülerek hesaplama'),
                  value: 2,
                  groupValue: _senaryo,
                  onChanged: (v) => setState(() => _senaryo = v!),
                  dense: true,
                ),
              ],
            ),
          ),
        ),

        // Senaryo 2 uyarı
        if (_senaryo == 2) ...[
          const SizedBox(height: 8),
          Card(
            color: Colors.orange.shade100,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: Colors.orange.shade400, width: 2),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(Icons.touch_app, color: Colors.orange.shade800, size: 24),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Krokide dairelere tıklayarak müteahhitin alacağı daireleri seçin.\n'
                      'Müteahhit: ${_daireler.where((d) => d['sahip'] == 'muteahhit').length}  •  '
                      'Mal Sahibi: ${_daireler.where((d) => d['sahip'] == 'malSahibi').length}',
                      style: TextStyle(color: Colors.orange.shade900, fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],

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
                      'Bina Krokisi — $katSayisi Kat, ${katSayisi * katBasiDaire} Daire',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ],
                ),
              ),
              // Katlar (üstten alta)
              for (int kat = katSayisi; kat >= 1; kat--)
                _buildKatSatiri(kat, katBasiDaire),
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
            '📝 Dairenin detaylarını düzenlemek için üzerine uzun basın',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
          ),
        ),
      ],
    );
  }

  Widget _buildKatSatiri(int kat, int daireSayisi) {
    final katDaireleri = _daireler.where((d) => d['kat'] == kat).toList();
    if (katDaireleri.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.grey.shade500)),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Kat numarası
            Container(
              width: 30,
              color: Colors.grey.shade200,
              child: Center(
                child: Text(
                  '$kat',
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey.shade700, fontSize: 13),
                ),
              ),
            ),
            Container(width: 1, color: Colors.grey.shade500),
            // Daireler
            ...katDaireleri.asMap().entries.map((entry) {
              final isLast = entry.key == katDaireleri.length - 1;
              return Expanded(
                child: Container(
                  decoration: isLast
                      ? null
                      : BoxDecoration(border: Border(right: BorderSide(color: Colors.grey.shade400))),
                  child: _buildDaireHucre(entry.value),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildDaireHucre(Map<String, dynamic> daire) {
    final isMuteahhit = daire['sahip'] == 'muteahhit';
    final no = daire['no'] as int;
    final m2Ctrl = daire['m2Ctrl'] as TextEditingController;
    final tip = daire['tip'] as String;
    final hibeVar = daire['hibeVar'] as bool;
    final krediVar = daire['krediVar'] as bool;

    Color bgColor;
    if (_senaryo == 2) {
      bgColor = isMuteahhit ? Colors.orange.shade100 : Colors.blue.shade50;
    } else {
      bgColor = Colors.white;
    }

    return GestureDetector(
      onTap: _senaryo == 2
          ? () => setState(() {
                daire['sahip'] = isMuteahhit ? 'malSahibi' : 'muteahhit';
              })
          : () => _daireDuzenleDialog(daire),
      onLongPress: () => _daireDuzenleDialog(daire),
      child: Container(
        color: bgColor,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('D$no', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                if (_senaryo == 2) ...[
                  const SizedBox(width: 4),
                  Icon(
                    isMuteahhit ? Icons.construction : Icons.home,
                    size: 14,
                    color: isMuteahhit ? Colors.orange.shade700 : Colors.blue.shade700,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 2),
            Text(
              '${m2Ctrl.text} m²',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade800, fontWeight: FontWeight.w500),
            ),
            Text(tip, style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
            if (hibeVar || krediVar)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (hibeVar) Text('H', style: TextStyle(fontSize: 9, color: Colors.green.shade700, fontWeight: FontWeight.bold)),
                  if (hibeVar && krediVar) const Text(' ', style: TextStyle(fontSize: 9)),
                  if (krediVar) Text('K', style: TextStyle(fontSize: 9, color: Colors.purple.shade700, fontWeight: FontWeight.bold)),
                ],
              ),
          ],
        ),
      ),
    );
  }

  void _daireDuzenleDialog(Map<String, dynamic> daire) {
    final m2Ctrl = daire['m2Ctrl'] as TextEditingController;
    final tempM2Ctrl = TextEditingController(text: m2Ctrl.text);
    String tempTip = daire['tip'] as String;
    bool tempHibe = daire['hibeVar'] as bool;
    bool tempKredi = daire['krediVar'] as bool;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Daire ${daire['no']} — ${daire['kat']}. Kat'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: tempM2Ctrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [_TBinlikFormatter()],
                decoration: const InputDecoration(
                  labelText: 'Metrekare (m²)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.square_foot),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: tempTip,
                decoration: const InputDecoration(
                  labelText: 'Tip',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.category),
                ),
                items: ['Daire', 'Dubleks', 'Dükkan', 'Ofis']
                    .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                    .toList(),
                onChanged: (v) => setDialogState(() => tempTip = v!),
              ),
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
          actions: [
            TextButton(
              onPressed: () {
                tempM2Ctrl.dispose();
                Navigator.pop(ctx);
              },
              child: const Text('İptal'),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  m2Ctrl.text = tempM2Ctrl.text;
                  daire['tip'] = tempTip;
                  daire['hibeVar'] = tempHibe;
                  daire['krediVar'] = tempKredi;
                });
                tempM2Ctrl.dispose();
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
              Text('📍 Konum: ${_ilCtrl.text} / ${_ilceCtrl.text} / ${_mahalleCtrl.text}'),
              Text('📐 Toplam Alan: ${_toplamM2Ctrl.text} m²'),
              Text('⏱ Tahmini Süre: $_hesaplananSure ay'),
              Text('💰 Güncel Maliyet: ${_guncelMaliyetCtrl.text} ₺/m²'),
              Text('📈 Kar Oranı: %${_karOraniCtrl.text}'),
              Text('🏠 Daire Sayısı: ${_daireler.length}'),
              Text('📋 Senaryo: ${_senaryo == 1 ? "Müteahhit daire almıyor" : "Müteahhit daire alıyor"}'),
              if (_senaryo == 2)
                Text('🏗 Müteahhit Daire: ${_daireler.where((d) => d['sahip'] == 'muteahhit').length} adet'),
              const SizedBox(height: 8),
              const Text('⚡ "AI ile Hesapla" butonuna basarak analizi başlatın.',
                  style: TextStyle(fontStyle: FontStyle.italic, fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStep5() {
    final sonuc = _hesapSonucu!;
    final senaryo = sonuc['senaryo'] as int;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Veri kaynağı göstergesi
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _aiService.veriKaynagi.contains('canlı')
                  ? Colors.green.shade50
                  : Colors.amber.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _aiService.veriKaynagi.contains('canlı')
                    ? Colors.green.shade300
                    : Colors.amber.shade300,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _aiService.veriKaynagi.contains('canlı') ? Icons.cloud_done : Icons.storage,
                  size: 16,
                  color: _aiService.veriKaynagi.contains('canlı') ? Colors.green.shade700 : Colors.amber.shade800,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Veri: ${_aiService.veriKaynagi}',
                    style: TextStyle(
                      fontSize: 11,
                      color: _aiService.veriKaynagi.contains('canlı') ? Colors.green.shade800 : Colors.amber.shade900,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: _tcmbApiKeyDialog,
                  child: Icon(Icons.settings, size: 16, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // İstatistiksel maliyet tahmini — min/avg/max
          _buildInfoCard(
            'İstatistiksel Maliyet Tahmini',
            Icons.show_chart,
            Colors.blue,
            [
              'Yıllık İnşaat Enflasyonu: %${(sonuc['yillikEnflasyon'] as double).toStringAsFixed(1)}',
              'İnşaat Süresi: ${sonuc['insaatSuresi']} ay',
              'Güncel m² Maliyet: ${_formatN(sonuc['guncelM2Maliyet'])} ₺',
              'Tahmini m² Maliyet (ort): ${_formatN(sonuc['enflasyonluM2Maliyet'])} ₺',
              '  ↳ İyimser: ${_formatN((sonuc['minM2Maliyet'] as num).toDouble())} ₺  |  Kötümser: ${_formatN((sonuc['maxM2Maliyet'] as num).toDouble())} ₺',
            ],
          ),

          // Min/Max m² fiyat önerisi
          if (_minMaxFiyat != null) ...[
            const SizedBox(height: 12),
            _buildInfoCard(
              'Önerilen m² Satış Fiyat Aralığı',
              Icons.price_change,
              Colors.teal,
              [
                'En Düşük (iyimser): ${_formatN(_minMaxFiyat!['minM2Fiyat']!)} ₺/m²',
                'Ortalama: ${_formatN(_minMaxFiyat!['ortM2Fiyat']!)} ₺/m²',
                'En Yüksek (kötümser): ${_formatN(_minMaxFiyat!['maxM2Fiyat']!)} ₺/m²',
                '(%${_karOraniCtrl.text} kar oranı dahil)',
              ],
            ),
          ],

          if (senaryo == 2 && sonuc['muteahhitDaireleri'] != null) ...[
            const SizedBox(height: 12),
            _buildInfoCard(
              'Müteahhit Daireleri — Pazar Satış Tahmini',
              Icons.business,
              Colors.orange,
              [
                ...((sonuc['muteahhitDaireleri'] as List).map((d) {
                  final min = _formatN((d['minSatisFiyati'] as num).toDouble());
                  final avg = _formatN((d['tahminiSatisFiyati'] as num).toDouble());
                  final max = _formatN((d['maxSatisFiyati'] as num).toDouble());
                  return '${d['tip']} ${d['m2']} m² (${d['kat']}. kat)\n  Min: $min ₺  |  Ort: $avg ₺  |  Max: $max ₺';
                })),
                '',
                'Toplam Satış Geliri (ort): ${_formatN((sonuc['muteahhitSatisGeliri'] as num).toDouble())} ₺',
                '  ↳ Min: ${_formatN((sonuc['muteahhitSatisMin'] as num).toDouble())} ₺  |  Max: ${_formatN((sonuc['muteahhitSatisMax'] as num).toDouble())} ₺',
                'Kalan Maliyet: ${_formatN((sonuc['kalanMaliyet'] as num).toDouble())} ₺',
              ],
            ),
          ],

          const SizedBox(height: 12),
          _buildInfoCard(
            'Mal Sahibi Daire Ödemeleri',
            Icons.people,
            Colors.green,
            [..._buildDaireOdemeList(sonuc)],
          ),

          // Pazar Analizi
          if (_pazarAnaliziMetni != null) ...[
            const SizedBox(height: 12),
            Card(
              color: Colors.indigo.shade50,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.analytics, color: Colors.indigo.shade700),
                        const SizedBox(width: 8),
                        Text('Bölge Pazar Analizi',
                            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo.shade700, fontSize: 14)),
                      ],
                    ),
                    const Divider(),
                    Text(_pazarAnaliziMetni!, style: const TextStyle(fontSize: 12, height: 1.6, fontFamily: 'monospace')),
                  ],
                ),
              ),
            ),
          ],

          // Özet Rapor
          if (_aiOzet != null) ...[
            const SizedBox(height: 12),
            Card(
              color: Colors.purple.shade50,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.smart_toy, color: Colors.purple.shade700),
                        const SizedBox(width: 8),
                        Text('Analiz Raporu',
                            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.purple.shade700, fontSize: 15)),
                      ],
                    ),
                    const Divider(),
                    Text(_aiOzet!, style: const TextStyle(fontSize: 13, height: 1.5)),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
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
              await TcmbService.setApiKey(ctrl.text.trim());
              ctrl.dispose();
              if (mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('API anahtarı kaydedildi'), backgroundColor: Colors.green),
                );
              }
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
  }

  List<String> _buildDaireOdemeList(Map<String, dynamic> sonuc) {
    final senaryo = sonuc['senaryo'] as int;
    final daireler = senaryo == 1
        ? (sonuc['daireler'] as List)
        : (sonuc['malSahibiDaireleri'] as List);

    return daireler.map<String>((d) {
      final tip = d['tip'] ?? 'Daire';
      final m2 = _formatN((d['m2'] as num).toDouble());
      final kat = d['kat'];
      final brut = _formatN((d['brutMaliyet'] as num).toDouble());
      final net = _formatN((d['netOdeme'] as num).toDouble());
      final hibe = d['hibeVar'] == true ? ' (-Hibe ${_formatN((d['hibeTutari'] as num).toDouble())} ₺)' : '';
      final kredi = d['krediVar'] == true ? ' (-Kredi ${_formatN((d['krediTutari'] as num).toDouble())} ₺)' : '';
      return '$tip $m2 m² ($kat. kat): Brüt $brut ₺$hibe$kredi → Net: $net ₺';
    }).toList();
  }

  Widget _buildInfoCard(String title, IconData icon, Color color, List<String> items) {
    return Card(
      color: color.withValues(alpha: 0.05),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 14)),
              ],
            ),
            const Divider(),
            ...items.map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(item, style: const TextStyle(fontSize: 13)),
                )),
          ],
        ),
      ),
    );
  }

  // ============ PDF ============

  Future<Uint8List> _generateAiTeklifPdf() async {
    return ai_pdf.generateAiTeklifPdf(
      hesapSonucu: _hesapSonucu!,
      aiOzet: _aiOzet ?? '',
      il: _ilCtrl.text.trim(),
      ilce: _ilceCtrl.text.trim(),
      mahalle: _mahalleCtrl.text.trim(),
      firmaAdi: SistemYoneticisi().aktifSirket?.ad ?? '',
      firmaLogosu: SistemYoneticisi().aktifSirket?.logo,
    );
  }
}
