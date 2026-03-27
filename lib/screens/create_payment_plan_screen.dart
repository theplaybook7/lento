import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../services/firebase_service.dart';
import '../theme/app_theme.dart';
import '../utils/error_handler.dart';

class CreatePaymentPlanScreen extends StatefulWidget {
  final String projectId;
  final String projectName;

  const CreatePaymentPlanScreen({
    required this.projectId,
    required this.projectName,
    super.key,
  });

  @override
  State<CreatePaymentPlanScreen> createState() => _CreatePaymentPlanScreenState();
}

class _CreatePaymentPlanScreenState extends State<CreatePaymentPlanScreen> {
  final _firebase = FirebaseService();
  final _formKey = GlobalKey<FormState>();
  
  late TextEditingController _firstNameCtrl;
  late TextEditingController _lastNameCtrl;
  late TextEditingController _totalAmountCtrl;
  late TextEditingController _installmentCountCtrl;

  final List<DateTime> _installmentDates = [];
  final List<double> _installmentPercentages = [];
  final List<TextEditingController> _percentageControllers = [];
  final List<TextEditingController> _amountControllers = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _firstNameCtrl = TextEditingController();
    _lastNameCtrl = TextEditingController();
    _totalAmountCtrl = TextEditingController();
    _installmentCountCtrl = TextEditingController(text: '12');
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _totalAmountCtrl.dispose();
    _installmentCountCtrl.dispose();
    for (var ctrl in _percentageControllers) {
      ctrl.dispose();
    }
    for (var ctrl in _amountControllers) {
      ctrl.dispose();
    }
    super.dispose();
  }

  Future<void> _selectDate(int index) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _installmentDates.isNotEmpty && index < _installmentDates.length
          ? _installmentDates[index]
          : DateTime.now().add(Duration(days: (index + 1) * 30)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );

    if (picked != null) {
      setState(() {
        if (index < _installmentDates.length) {
          _installmentDates[index] = picked;
        } else {
          _installmentDates.add(picked);
        }
      });
    }
  }

  void _generateInstallmentDates() {
    final count = int.tryParse(_installmentCountCtrl.text) ?? 0;
    if (count <= 0) return;

    _installmentDates.clear();
    _installmentPercentages.clear();
    
    // Controllers temizle
    for (var ctrl in _percentageControllers) {
      ctrl.dispose();
    }
    for (var ctrl in _amountControllers) {
      ctrl.dispose();
    }
    _percentageControllers.clear();
    _amountControllers.clear();
    
    final totalAmount = double.tryParse(_totalAmountCtrl.text) ?? 0;
    final equalPercentage = 100.0 / count;
    
    for (int i = 0; i < count; i++) {
      _installmentDates.add(
        DateTime.now().add(Duration(days: (i + 1) * 30)),
      );
      _installmentPercentages.add(equalPercentage);
      
      // Controller'ları oluştur
      _percentageControllers.add(
        TextEditingController(text: equalPercentage.toStringAsFixed(2)),
      );
      final amount = (totalAmount * equalPercentage) / 100;
      _amountControllers.add(
        TextEditingController(text: amount.toStringAsFixed(2)),
      );
    }
    setState(() {});
  }

  void _updateInstallmentPercentage(int index, String value) {
    final percentage = double.tryParse(value) ?? 0;
    if (index >= 0 && index < _installmentPercentages.length) {
      final totalAmount = _parseFormatted(_totalAmountCtrl.text);
      final amount = (totalAmount * percentage) / 100;
      
      setState(() {
        _installmentPercentages[index] = percentage;
        _amountControllers[index].text = _formatAmount(amount);
      });
    }
  }

  void _updateInstallmentAmount(int index, String value) {
    final amount = _parseFormatted(value);
    if (index >= 0 && index < _amountControllers.length) {
      final totalAmount = _parseFormatted(_totalAmountCtrl.text);
      if (totalAmount > 0) {
        final percentage = (amount / totalAmount) * 100;
        setState(() {
          _installmentPercentages[index] = percentage;
          _percentageControllers[index].text = percentage.toStringAsFixed(2);
        });
      }
    }
  }

  double _getTotalPercentage() {
    return _installmentPercentages.fold(0.0, (sum, p) => sum + p);
  }

  Future<void> _createPaymentPlan() async {
    if (!_formKey.currentState!.validate()) return;
    if (_installmentDates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen taksit tarihlerini seçin')),
      );
      return;
    }

    final totalPercentage = _getTotalPercentage();
    if ((totalPercentage - 100.0).abs() > 0.01) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Toplam yüzde %100 olmalı (${totalPercentage.toStringAsFixed(1)}%)')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final firstName = _firstNameCtrl.text.trim();
      final lastName = _lastNameCtrl.text.trim();
      final totalAmount = _parseFormatted(_totalAmountCtrl.text);

      await _firebase.createPaymentPlan(
        projectId: widget.projectId,
        firstName: firstName,
        lastName: lastName,
        totalAmount: totalAmount,
        installmentCount: _installmentDates.length,
        installmentDates: _installmentDates,
        installmentPercentages: _installmentPercentages,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ödeme planı başarıyla oluşturuldu')),
      );
      Navigator.pop(context, true);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(hataCevir(e))),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalPercentage = _getTotalPercentage();
    final percentageColor = (totalPercentage - 100.0).abs() < 0.01
        ? Colors.green
        : (totalPercentage > 100.0 ? Colors.red : Colors.orange);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Yeni Ödeme Planı'),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Proje Bilgisi
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Proje',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                      Text(
                        widget.projectName,
                        style: const TextStyle(fontSize: 16),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Kat Maliki Bilgileri
              TextFormField(
                controller: _firstNameCtrl,
                decoration: const InputDecoration(
                  labelText: 'İsim',
                  prefixIcon: Icon(Icons.person),
                  border: OutlineInputBorder(),
                ),
                validator: (v) => v?.isEmpty ?? true ? 'İsim gerekli' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _lastNameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Soyisim',
                  prefixIcon: Icon(Icons.person_outline),
                  border: OutlineInputBorder(),
                ),
                validator: (v) => v?.isEmpty ?? true ? 'Soyisim gerekli' : null,
              ),
              const SizedBox(height: 20),

              // Ödeme Bilgileri
              TextFormField(
                controller: _totalAmountCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [_ThousandsSeparatorFormatter()],
                decoration: const InputDecoration(
                  labelText: 'Toplam Ödenecek Tutar (₺)',
                  prefixIcon: Icon(Icons.monetization_on),
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  if (v?.isEmpty ?? true) return 'Tutar gerekli';
                  if (_parseFormatted(v!) <= 0) return 'Geçerli tutar girin';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _installmentCountCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Taksit Sayısı',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => _generateInstallmentDates(),
                validator: (v) {
                  if (v?.isEmpty ?? true) return 'Gerekli';
                  if (int.tryParse(v!) == null) return 'Sayı girin';
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // Taksit Tarihleri ve Yüzdeleri
              const Text(
                'Taksit Tarihleri ve Yüzdeleri',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 12),
              if (_installmentDates.isEmpty)
                Center(
                  child: ElevatedButton.icon(
                    onPressed: _generateInstallmentDates,
                    icon: const Icon(Icons.date_range),
                    label: const Text('Tarihleri ve Yüzdeleri Otomatik Oluştur'),
                  ),
                )
              else
                Column(
                  children: [
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _installmentDates.length,
                      itemBuilder: (context, index) {
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Taksit ${index + 1}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.edit, color: Colors.blue),
                                      onPressed: () => _selectDate(index),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Tarih: ${DateFormat('dd.MM.yyyy').format(_installmentDates[index])}',
                                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                                const SizedBox(height: 12),
                                // Yüzde ve Tutar Giriş Alanları
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: _percentageControllers[index],
                                        keyboardType: TextInputType.number,
                                        decoration: const InputDecoration(
                                          labelText: 'Yüzde (%)',
                                          border: OutlineInputBorder(),
                                          isDense: true,
                                        ),
                                        onChanged: (value) => _updateInstallmentPercentage(index, value),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: TextField(
                                        controller: _amountControllers[index],
                                        keyboardType: TextInputType.number,
                                        inputFormatters: [_ThousandsSeparatorFormatter()],
                                        decoration: const InputDecoration(
                                          labelText: 'Tutar (₺)',
                                          border: OutlineInputBorder(),
                                          isDense: true,
                                        ),
                                        onChanged: (value) => _updateInstallmentAmount(index, value),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: percentageColor.withValues(alpha: 0.1),
                        border: Border.all(color: percentageColor),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Toplam Yüzde: ${totalPercentage.toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: percentageColor,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 24),

              // Kaydet Butonu
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _createPaymentPlan,
                  icon: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check),
                  label: Text(_isLoading ? 'Kaydediliyor...' : 'Ödeme Planı Oluştur'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    backgroundColor: Colors.green.shade600,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

double _parseFormatted(String text) {
  return double.tryParse(text.replaceAll('.', '').replaceAll(',', '.')) ?? 0;
}

String _formatAmount(double amount) {
  if (amount == amount.roundToDouble()) {
    return NumberFormat('#,###', 'tr_TR').format(amount.toInt());
  }
  return NumberFormat('#,##0.00', 'tr_TR').format(amount);
}

class _ThousandsSeparatorFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.isEmpty) return newValue;
    final cleanText = newValue.text.replaceAll('.', '');
    final parts = cleanText.split(',');
    final intPart = parts[0].replaceAll(RegExp(r'[^0-9]'), '');
    if (intPart.isEmpty) return newValue;
    final formatted = NumberFormat('#,###', 'tr_TR').format(int.parse(intPart));
    final result = parts.length > 1 ? '$formatted,${parts[1]}' : formatted;
    return TextEditingValue(
      text: result,
      selection: TextSelection.collapsed(offset: result.length),
    );
  }
}
