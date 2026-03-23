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
  Map<String, dynamic>? _satisFiyatTahmini;
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
    _guncelMaliyetCtrl.dispose();
    _karOraniCtrl.dispose();
    _hibeTutariCtrl.dispose();
    _krediTutariCtrl.dispose();
    for (final d in _daireler) {
      (d['m2Ctrl'] as TextEditingController).dispose();
      (d['katCtrl'] as TextEditingController).dispose();
    }
    super.dispose();
  }

  void _daireBolumEkle() {
    setState(() {
      _daireler.add({
        'tip': 'Daire',
        'm2Ctrl': TextEditingController(),
        'katCtrl': TextEditingController(text: '${_daireler.length + 1}'),
        'sahip': 'malSahibi',
        'hibeVar': false,
        'krediVar': false,
      });
    });
  }

  void _daireSil(int index) {
    setState(() {
      (_daireler[index]['m2Ctrl'] as TextEditingController).dispose();
      (_daireler[index]['katCtrl'] as TextEditingController).dispose();
      _daireler.removeAt(index);
    });
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
            _parseN(_guncelMaliyetCtrl.text) > 0 &&
            _parseN(_karOraniCtrl.text) > 0;
      case 2:
        return _daireler.isNotEmpty &&
            _daireler.every((d) => _parseN((d['m2Ctrl'] as TextEditingController).text) > 0);
      default:
        return true;
    }
  }

  Future<void> _hesaplaVeAnaliz() async {
    setState(() {
      _isLoading = true;
      _loadingMessage = 'TCMB\'den inşaat maliyet endeksi alınıyor...';
    });

    try {
      // 1. Enflasyon projeksiyonu
      final projeksiyon = await _aiService.enflasyonProjeksiyonu(
        guncelMaliyet: _parseN(_guncelMaliyetCtrl.text),
        toplamM2: _parseN(_toplamM2Ctrl.text),
      );
      setState(() {
        _enflasyonProjeksiyonu = projeksiyon;
        _loadingMessage = 'Hesaplamalar yapılıyor...';
      });

      // 2. Daire listesini hazırla
      final daireListesi = _daireler.map((d) => {
        'm2': _parseN((d['m2Ctrl'] as TextEditingController).text),
        'kat': int.tryParse((d['katCtrl'] as TextEditingController).text) ?? 1,
        'tip': d['tip'] as String,
        'sahip': d['sahip'] as String,
        'hibeVar': d['hibeVar'] as bool,
        'krediVar': d['krediVar'] as bool,
      }).toList();

      Map<String, dynamic> sonuc;

      if (_senaryo == 2) {
        // Müteahhit daire alıyorsa: önce satış fiyatı tahmin et
        final muteahhitDaireler = daireListesi
            .where((d) => d['sahip'] == 'muteahhit')
            .toList();

        if (muteahhitDaireler.isNotEmpty) {
          setState(() => _loadingMessage = 'AI daire satış fiyatları tahmin ediliyor...');
          _satisFiyatTahmini = await _aiService.daireSatisFiyatiTahminEt(
            il: _ilCtrl.text.trim(),
            ilce: _ilceCtrl.text.trim(),
            mahalle: _mahalleCtrl.text.trim(),
            daireler: muteahhitDaireler,
            insaatSuresi: _hesaplananSure,
          );
        }

        // Satış fiyatlarını map'e dönüştür
        final satisFiyatlari = <String, double>{};
        if (_satisFiyatTahmini != null) {
          final tahminler = _satisFiyatTahmini!['tahminler'] as List? ?? [];
          int mutIndex = 0;
          for (int i = 0; i < daireListesi.length; i++) {
            if (daireListesi[i]['sahip'] == 'muteahhit') {
              if (mutIndex < tahminler.length) {
                satisFiyatlari[i.toString()] =
                    (tahminler[mutIndex]['fiyat'] as num).toDouble();
              }
              mutIndex++;
            }
          }
        }

        sonuc = await _aiService.senaryo2Hesapla(
          guncelM2Maliyet: _parseN(_guncelMaliyetCtrl.text),
          toplamInsaatM2: _parseN(_toplamM2Ctrl.text),
          karOrani: _parseN(_karOraniCtrl.text),
          daireler: daireListesi,
          hibeTutari: _parseN(_hibeTutariCtrl.text),
          krediTutari: _parseN(_krediTutariCtrl.text),
          konum: '${_ilCtrl.text}/${_ilceCtrl.text}/${_mahalleCtrl.text}',
          muteahhitDaireSatisFiyatlari: satisFiyatlari,
        );
      } else {
        sonuc = await _aiService.senaryo1Hesapla(
          guncelM2Maliyet: _parseN(_guncelMaliyetCtrl.text),
          toplamInsaatM2: _parseN(_toplamM2Ctrl.text),
          karOrani: _parseN(_karOraniCtrl.text),
          daireler: daireListesi,
          hibeTutari: _parseN(_hibeTutariCtrl.text),
          krediTutari: _parseN(_krediTutariCtrl.text),
        );
      }

      setState(() {
        _hesapSonucu = sonuc;
        _loadingMessage = 'AI özet rapor hazırlanıyor...';
      });

      // 3. AI özet
      final ozet = await _aiService.teklifOzetiOlustur(sonuc);
      setState(() {
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
                    _satisFiyatTahmini = null;
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
        const SizedBox(height: 12),

        // Daire listesi
        ..._daireler.asMap().entries.map((entry) {
          final i = entry.key;
          final d = entry.value;
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    children: [
                      Text('Daire ${i + 1}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      const Spacer(),
                      if (_senaryo == 2)
                        DropdownButton<String>(
                          value: d['sahip'] as String,
                          items: const [
                            DropdownMenuItem(value: 'malSahibi', child: Text('Mal Sahibi')),
                            DropdownMenuItem(value: 'muteahhit', child: Text('Müteahhit')),
                          ],
                          onChanged: (v) => setState(() => d['sahip'] = v),
                          underline: const SizedBox.shrink(),
                        ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                        onPressed: () => _daireSil(i),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: DropdownButtonFormField<String>(
                          value: d['tip'] as String,
                          decoration: const InputDecoration(
                            labelText: 'Tip',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: ['Daire', 'Dubleks', 'Dükkan', 'Ofis']
                              .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                              .toList(),
                          onChanged: (v) => setState(() => d['tip'] = v),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: d['m2Ctrl'] as TextEditingController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [_TBinlikFormatter()],
                          decoration: const InputDecoration(
                            labelText: 'm²',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: d['katCtrl'] as TextEditingController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Kat',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: CheckboxListTile(
                          title: const Text('Hibe', style: TextStyle(fontSize: 13)),
                          value: d['hibeVar'] as bool,
                          onChanged: (v) => setState(() => d['hibeVar'] = v),
                          dense: true,
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      Expanded(
                        child: CheckboxListTile(
                          title: const Text('Kredi', style: TextStyle(fontSize: 13)),
                          value: d['krediVar'] as bool,
                          onChanged: (v) => setState(() => d['krediVar'] = v),
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
          );
        }),

        Center(
          child: ElevatedButton.icon(
            onPressed: _daireBolumEkle,
            icon: const Icon(Icons.add),
            label: const Text('Daire Ekle'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade600, foregroundColor: Colors.white),
          ),
        ),
      ],
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
          // Enflasyon bilgisi
          _buildInfoCard(
            'TCMB İnşaat Maliyet Endeksi',
            Icons.show_chart,
            Colors.blue,
            [
              'Yıllık İnşaat Enflasyonu: %${(sonuc['yillikEnflasyon'] as double).toStringAsFixed(1)}',
              'İnşaat Süresi: ${sonuc['insaatSuresi']} ay',
              'Güncel m² Maliyet: ${_formatN(sonuc['guncelM2Maliyet'])} ₺',
              'Enflasyonlu m² Maliyet: ${_formatN(sonuc['enflasyonluM2Maliyet'])} ₺',
              'Kar Dahil m² Fiyat: ${_formatN(sonuc['karliM2Fiyat'])} ₺',
            ],
          ),

          if (senaryo == 2 && sonuc['muteahhitDaireleri'] != null) ...[
            const SizedBox(height: 12),
            _buildInfoCard(
              'Müteahhit Daireleri',
              Icons.business,
              Colors.orange,
              [
                ...((sonuc['muteahhitDaireleri'] as List).map((d) {
                  return '${d['tip']} ${d['m2']} m² (${d['kat']}. kat) → Tahmini: ${_formatN((d['tahminiSatisFiyati'] as num).toDouble())} ₺';
                })),
                'Toplam Satış Geliri: ${_formatN((sonuc['muteahhitSatisGeliri'] as num).toDouble())} ₺',
                'Kalan Maliyet: ${_formatN((sonuc['kalanMaliyet'] as num).toDouble())} ₺',
              ],
            ),
          ],

          const SizedBox(height: 12),
          // Daire bazlı hesap tablosu
          _buildInfoCard(
            'Mal Sahibi Daire Ödemeleri',
            Icons.people,
            Colors.green,
            [
              ..._buildDaireOdemeList(sonuc),
            ],
          ),

          // AI Özet
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
                        Text('AI Analiz Özeti',
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

          // Satış fiyat tahmini onay/düzenleme
          if (_satisFiyatTahmini != null) ...[
            const SizedBox(height: 12),
            Card(
              color: Colors.amber.shade50,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.amber.shade800),
                        const SizedBox(width: 8),
                        const Text('Daire Satış Tahminleri (AI)',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _satisFiyatTahmini!['aciklama'] ?? '',
                      style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'ℹ️ Bu tahmini fiyatları onaylayın veya düzenleyip yeniden hesaplatın.',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
          ],
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
