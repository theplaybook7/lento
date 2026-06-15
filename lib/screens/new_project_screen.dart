import 'package:flutter/material.dart';
import '../services/firebase_service.dart';
import '../payment_service.dart';
import '../project_core.dart';
import 'paywall_screen.dart';
import '../theme/app_theme.dart';
import '../utils/error_handler.dart';

class NewProjectScreen extends StatefulWidget {
  final String companyId;
  const NewProjectScreen({super.key, required this.companyId});

  @override
  State<NewProjectScreen> createState() => _NewProjectScreenState();
}

class _NewProjectScreenState extends State<NewProjectScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _descCtrl;
  late TextEditingController _budgetCtrl;
  late TextEditingController _malSahibiCtrl;
  late TextEditingController _adaParselCtrl;
  late TextEditingController _muteahhitCtrl;
  DateTime _startDate = DateTime.now();
  DateTime? _endDate;
  bool _isLoading = false;

  bool _isPlanLimitError(String message) {
    final m = message.toLowerCase();
    return m.contains('ucretsiz planda') ||
        m.contains('planinizi yukseltin') ||
        m.contains('yukseltme yaparak');
  }

  bool _canOfferUpgrade() {
    final activePlan = SistemYoneticisi().aktifSirket?.aktifPlan ?? PlanTier.free;
    return PaymentService().isPaymentSupported && activePlan != PlanTier.enterprise;
  }

  @override
  void initState() {
    super.initState();
    _descCtrl = TextEditingController();
    _budgetCtrl = TextEditingController();
    _malSahibiCtrl = TextEditingController();
    _adaParselCtrl = TextEditingController();
    _muteahhitCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    _budgetCtrl.dispose();
    _malSahibiCtrl.dispose();
    _adaParselCtrl.dispose();
    _muteahhitCtrl.dispose();
    super.dispose();
  }

  Future<void> _selectDate(bool isStart) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _startDate : (_endDate ?? DateTime.now().add(const Duration(days: 30))),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
        } else {
          _endDate = picked;
        }
      });
    }
  }

  Future<void> _createProject() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      final firebase = FirebaseService();
      final budget = parseFormatted(_budgetCtrl.text);

      final projectId = await firebase.createProject(
        companyId: widget.companyId,
        name: '${_malSahibiCtrl.text.trim()} / ${_adaParselCtrl.text.trim()} / ${_muteahhitCtrl.text.trim()}',
        description: _descCtrl.text.trim(),
        startDate: _startDate,
        endDate: _endDate,
        totalBudget: budget,
        malSahibi: _malSahibiCtrl.text.trim(),
        adaParsel: _adaParselCtrl.text.trim(),
        muteahhit: _muteahhitCtrl.text.trim(),
      );

      if (!mounted) return;
      Navigator.pop(context, projectId);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Proje başarıyla oluşturuldu')),
      );
    } catch (e) {
      if (!mounted) return;
      final mesaj = hataCevir(e);
      final showUpgrade = _isPlanLimitError(mesaj) && _canOfferUpgrade();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(mesaj),
          backgroundColor: Colors.red,
          action: showUpgrade
              ? SnackBarAction(
                  label: 'Aboneligi Yukselt',
                  textColor: Colors.white,
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const PaywallScreen(mode: PaywallMode.subscription),
                      ),
                    );
                  },
                )
              : null,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Yeni Proje Oluştur'),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        elevation: 1,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Mal Sahibi
              TextFormField(
                controller: _malSahibiCtrl,
                decoration: InputDecoration(
                  labelText: 'Mal Sahibi *',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  prefixIcon: Icon(Icons.person, color: AppTheme.primaryColor),
                  filled: true,
                  fillColor: Colors.white,
                ),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Mal sahibi gerekli' : null,
              ),
              const SizedBox(height: 16),

              // Ada Parsel
              TextFormField(
                controller: _adaParselCtrl,
                decoration: InputDecoration(
                  labelText: 'Ada / Parsel *',
                  hintText: 'Örn: 1234 / 56',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  prefixIcon: Icon(Icons.grid_on, color: AppTheme.primaryColor),
                  filled: true,
                  fillColor: Colors.white,
                ),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Ada / parsel gerekli' : null,
              ),
              const SizedBox(height: 16),

              // Müteahhit
              TextFormField(
                controller: _muteahhitCtrl,
                decoration: InputDecoration(
                  labelText: 'Müteahhit *',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  prefixIcon: Icon(Icons.engineering, color: AppTheme.primaryColor),
                  filled: true,
                  fillColor: Colors.white,
                ),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Müteahhit gerekli' : null,
              ),
              const SizedBox(height: 16),

              // Açıklama
              TextFormField(
                controller: _descCtrl,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'Açıklama',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  prefixIcon: const Icon(Icons.description),
                ),
              ),
              const SizedBox(height: 16),

              // Başlangıç Tarihi
              GestureDetector(
                onTap: () => _selectDate(true),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today, color: Colors.grey),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Başlangıç Tarihi *', style: TextStyle(fontSize: 12, color: Colors.grey)),
                            Text(
                              '${_startDate.day}.${_startDate.month}.${_startDate.year}',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios, size: 16),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Bitiş Tarihi
              GestureDetector(
                onTap: () => _selectDate(false),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today, color: Colors.grey),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Bitiş Tarihi', style: TextStyle(fontSize: 12, color: Colors.grey)),
                            Text(
                              _endDate != null
                                  ? '${_endDate!.day}.${_endDate!.month}.${_endDate!.year}'
                                  : 'Seçilmedi',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios, size: 16),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Toplam Bütçe
              TextFormField(
                controller: _budgetCtrl,
                inputFormatters: [BinlikInputFormatter()],
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Toplam Bütçe (₺)',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  prefixIcon: const Icon(Icons.attach_money),
                ),
              ),
              const SizedBox(height: 24),

              // Oluştur Butonu
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _createProject,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 2,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation(Colors.white),
                          ),
                        )
                      : const Text('Proje Oluştur', style: TextStyle(fontSize: 16, color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
