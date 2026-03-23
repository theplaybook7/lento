import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:typed_data';
import '../models/payment_model.dart';
import '../services/firebase_service.dart';
import '../utils/image_utils.dart';
import '../theme/app_theme.dart';

class PaymentPlanDetailsScreen extends StatefulWidget {
  final String paymentPlanId;
  final String planName;

  const PaymentPlanDetailsScreen({
    required this.paymentPlanId,
    required this.planName,
    super.key,
  });

  @override
  State<PaymentPlanDetailsScreen> createState() => _PaymentPlanDetailsScreenState();
}

class _PaymentPlanDetailsScreenState extends State<PaymentPlanDetailsScreen> {
  final _firebase = FirebaseService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text(widget.planName),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        elevation: 1,
      ),
      body: FutureBuilder<List<PaymentInstallment>>(
        future: _firebase.getPaymentInstallments(widget.paymentPlanId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Hata: ${snapshot.error}'));
          }

          final installments = snapshot.data ?? [];

          if (installments.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.receipt_long_outlined, size: 48, color: Colors.grey.shade400),
                  const SizedBox(height: 12),
                  Text(
                    'Taksit bulunamadı',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: installments.length,
            itemBuilder: (context, index) {
              final inst = installments[index];
              final isOverdue = inst.isOverdue();

              return StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('payment_installments')
                    .doc(inst.id)
                    .collection('payment_records')
                    .snapshots(),
                builder: (context, paymentSnap) {
                  final paymentRecords = paymentSnap.data?.docs ?? [];
                  
                  // Kısmen ödenmiş mi kontrol et
                  double totalPaid = 0;
                  for (var record in paymentRecords) {
                    final recordData = record.data() as Map<String, dynamic>;
                    // tlAmount varsa onu, yoksa paidAmount'ı kullan
                    final tlAmount = (recordData['tlAmount'] ?? recordData['paidAmount']) as num?;
                    if (tlAmount != null) {
                      totalPaid += tlAmount.toDouble();
                    }
                  }
                  
                  print('DEBUG: Taksit ${inst.installmentNumber} - Toplam Ödenmiş: $totalPaid / ${inst.amount}');
                  
                  final isPartiallyPaid = totalPaid > 0 && totalPaid < inst.amount && !inst.isPaid;
                  
                  // Arka plan rengini belirle
                  Color cardColor = Colors.transparent;
                  if (isPartiallyPaid) {
                    cardColor = Colors.yellow.shade50;
                  }
                  return Card(
                    elevation: 1,
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Colors.grey.shade200),
                    ),
                    color: cardColor,
                    child: StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('payment_installments')
                          .doc(inst.id)
                          .collection('payment_records')
                          .orderBy('createdAt', descending: true)
                          .snapshots(),
                      builder: (context, paymentSnap) {
                        final paymentRecords = paymentSnap.data?.docs ?? [];

                        return ExpansionTile(
                      leading: Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: inst.isPaid
                              ? AppTheme.successColor
                              : (isOverdue ? Colors.red : AppTheme.warningColor),
                          boxShadow: [
                            BoxShadow(
                              color: inst.isPaid
                                  ? AppTheme.successColor.withValues(alpha: 0.3)
                                  : (isOverdue ? Colors.red.withValues(alpha: 0.3) : AppTheme.warningColor.withValues(alpha: 0.3)),
                              blurRadius: 8,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            '${inst.installmentNumber}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                      title: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '₺${NumberFormat('#,##0.00', 'tr_TR').format(inst.amount)}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: inst.isPaid ? Colors.green : Colors.black,
                            ),
                          ),
                          Text(
                            '${inst.installmentPercentage.toStringAsFixed(1)}% - ${DateFormat('dd.MM.yyyy').format(inst.dueDate)}',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                      subtitle: Text(
                        inst.isPaid ? 'Ödendi' : 'Beklemede',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: inst.isPaid ? Colors.green : Colors.orange,
                        ),
                      ),
                      trailing: inst.isPaid
                          ? const Icon(Icons.check_circle, color: Colors.green, size: 20)
                          : PopupMenuButton<String>(
                              onSelected: (value) {
                                if (value == 'mark_paid') {
                                  _markAsPaid(inst);
                                }
                              },
                              itemBuilder: (BuildContext context) {
                                return [
                                  const PopupMenuItem(
                                    value: 'mark_paid',
                                    child: Row(
                                      children: [
                                        Icon(Icons.check, color: Colors.green),
                                        SizedBox(width: 8),
                                        Text('Ödeme Kaydet'),
                                      ],
                                    ),
                                  ),
                                ];
                              },
                            ),
                      children: [
                        if (totalPaid > 0)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('Toplam Ödenen:', style: TextStyle(color: Colors.grey.shade700)),
                                    Text(
                                      '₺${NumberFormat('#,##0.00', 'tr_TR').format(totalPaid)}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.green,
                                      ),
                                    ),
                                  ],
                                ),
                                if (totalPaid < inst.amount) ...[
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text('Kalan:', style: TextStyle(color: Colors.grey.shade700)),
                                      Text(
                                        '₺${NumberFormat('#,##0.00', 'tr_TR').format(inst.amount - totalPaid)}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.red,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                                const Divider(height: 16),
                              ],
                            ),
                          ),
                        if (paymentRecords.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              'Henüz ödeme yapılmadı',
                              style: TextStyle(color: Colors.grey.shade600),
                            ),
                          )
                        else
                          ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            itemCount: paymentRecords.length,
                            itemBuilder: (context, idx) {
                              final record = paymentRecords[idx].data() as Map<String, dynamic>;
                              // tlAmount varsa onu göster (dönüştürülmüş tutar), yoksa paidAmount'ı göster
                              final amount = ((record['tlAmount'] ?? record['paidAmount']) as num?)?.toDouble() ?? 0;
                              final originalCurrency = record['currency'] as String? ?? 'TL';
                              final originalAmount = (record['paidAmount'] as num?)?.toDouble() ?? 0;
                              final date = record['createdAt'] as Timestamp?;
                              final photos = List<String>.from(record['photoUrls'] ?? []);
                              
                              // Başlık: eğer orijinal para birimi TL değilse, ikisini de göster
                              String amountDisplay = '';
                              if (originalCurrency != 'TL' && originalAmount > 0) {
                                amountDisplay = '$originalAmount $originalCurrency = ₺${NumberFormat('#,##0.00', 'tr_TR').format(amount)}';
                              } else {
                                amountDisplay = '₺${NumberFormat('#,##0.00', 'tr_TR').format(amount)}';
                              }

                              return Column(
                                children: [
                                  ListTile(
                                    dense: true,
                                    leading: const Icon(Icons.check, color: Colors.green, size: 20),
                                    title: Text(
                                      amountDisplay,
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                    subtitle: date != null
                                        ? Text(DateFormat('dd.MM.yyyy HH:mm').format(date.toDate()))
                                        : null,
                                    trailing: photos.isNotEmpty
                                        ? Icon(Icons.image, color: Colors.blue.shade400, size: 18)
                                        : null,
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16),
                                    child: Align(
                                      alignment: Alignment.centerRight,
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(20),
                                        onTap: () => _editPaymentRecord(inst, paymentRecords[idx].id, record),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: Colors.orange.shade50,
                                            borderRadius: BorderRadius.circular(20),
                                            border: Border.all(color: Colors.orange.shade300),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.edit, color: Colors.orange.shade700, size: 16),
                                              const SizedBox(width: 4),
                                              Text('Düzenle', style: TextStyle(color: Colors.orange.shade700, fontSize: 12, fontWeight: FontWeight.w600)),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (photos.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 16),
                                      child: Wrap(
                                        spacing: 8,
                                        children: photos.map((photoUrl) {
                                          return GestureDetector(
                                            onTap: () => _showImagePreview(photoUrl),
                                            child: Container(
                                              width: 50,
                                              height: 50,
                                              decoration: BoxDecoration(
                                                borderRadius: BorderRadius.circular(4),
                                                border: Border.all(color: Colors.grey.shade300),
                                              ),
                                              child: ClipRRect(
                                                borderRadius: BorderRadius.circular(4),
                                                child: Image.network(
                                                  photoUrl,
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (context, error, stackTrace) =>
                                                      const Icon(Icons.broken_image, size: 20),
                                                ),
                                              ),
                                            ),
                                          );
                                        }).toList(),
                                      ),
                                    ),
                                ],
                              );
                            },
                          ),
                      ],
                    );
                      },
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  void _markAsPaid(PaymentInstallment installment) async {
    final paidAmountCtrl = TextEditingController(text: installment.amount.toString());
    final List<XFile> selectedImages = [];
    DateTime selectedDate = DateTime.now();
    final tarihCtrl = TextEditingController(text: DateFormat('dd.MM.yyyy').format(selectedDate));
    
    // Dialog içinde kullanılacak değişkenler
    late String selectedCurrencyForSaving;
    late double calculatedTlAmount;
    
    String paraBirimi = 'TL';
    final kurUSDCtrl = TextEditingController();
    final kurEURCtrl = TextEditingController();
    final kurGBPCtrl = TextEditingController();
    final altinKurCtrl = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Ödeme Kaydı'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: paraBirimi,
                    decoration: const InputDecoration(
                      labelText: 'Para Birimi',
                      border: OutlineInputBorder(),
                    ),
                    items: ['TL', 'USD', 'EUR', 'GBP', 'ALTIN']
                        .map((pb) => DropdownMenuItem(value: pb, child: Text(pb)))
                        .toList(),
                    onChanged: (v) => setState(() => paraBirimi = v!),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: paidAmountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Ödenen Tutar ($paraBirimi)',
                      prefixIcon: const Icon(Icons.monetization_on),
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (val) {
                      if (paraBirimi != 'TL') {
                        setState(() {});
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  if (paraBirimi == 'USD') ...[
                    TextField(
                      controller: kurUSDCtrl,
                      decoration: const InputDecoration(
                        labelText: 'USD Kuru (TL) *',
                        border: OutlineInputBorder(),
                        hintText: 'Örn: 34,50',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (val) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (paraBirimi == 'EUR') ...[
                    TextField(
                      controller: kurEURCtrl,
                      decoration: const InputDecoration(
                        labelText: 'EUR Kuru (TL) *',
                        border: OutlineInputBorder(),
                        hintText: 'Örn: 37,50',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (val) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (paraBirimi == 'GBP') ...[
                    TextField(
                      controller: kurGBPCtrl,
                      decoration: const InputDecoration(
                        labelText: 'GBP Kuru (TL) *',
                        border: OutlineInputBorder(),
                        hintText: 'Örn: 43,50',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (val) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (paraBirimi == 'ALTIN') ...[
                    TextField(
                      controller: altinKurCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Gram Fiyatı (TL) *',
                        border: OutlineInputBorder(),
                        hintText: 'Örn: 2.850,00',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (val) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (paraBirimi != 'TL') ...[
                    Builder(
                      builder: (context) {
                        final tutar = double.tryParse(paidAmountCtrl.text.replaceAll(',', '.')) ?? 0;
                        double kur = 0;
                        if (paraBirimi == 'USD') {
                          kur = double.tryParse(kurUSDCtrl.text.replaceAll(',', '.')) ?? 0;
                        } else if (paraBirimi == 'EUR') {
                          kur = double.tryParse(kurEURCtrl.text.replaceAll(',', '.')) ?? 0;
                        } else if (paraBirimi == 'GBP') {
                          kur = double.tryParse(kurGBPCtrl.text.replaceAll(',', '.')) ?? 0;
                        } else if (paraBirimi == 'ALTIN') {
                          kur = double.tryParse(altinKurCtrl.text.replaceAll(',', '.')) ?? 0;
                        }
                        
                        if (tutar > 0 && kur > 0) {
                          final tlKarsilik = tutar * kur;
                          return Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              border: Border.all(color: Colors.blue.shade200),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'TL Karşılığı: ${tlKarsilik.toStringAsFixed(2)} ₺',
                              style: TextStyle(color: Colors.blue.shade900, fontWeight: FontWeight.w600),
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    controller: tarihCtrl,
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: 'Ödeme Tarihi',
                      prefixIcon: const Icon(Icons.calendar_today),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.calendar_month),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: selectedDate,
                            firstDate: DateTime(2000),
                            lastDate: DateTime.now(),
                          );
                          if (picked != null) {
                            setState(() {
                              selectedDate = picked;
                              tarihCtrl.text = DateFormat('dd.MM.yyyy').format(selectedDate);
                            });
                          }
                        },
                      ),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () async {
                      final picker = ImagePicker();
                      final pickedFile = await picker.pickImage(source: ImageSource.camera);
                      if (pickedFile != null) {
                        setState(() {
                          selectedImages.add(pickedFile);
                        });
                      }
                    },
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Fotoğraf Çek'),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: () async {
                      final picker = ImagePicker();
                      final pickedFiles = await picker.pickMultiImage();
                      if (pickedFiles.isNotEmpty) {
                        setState(() {
                          selectedImages.addAll(pickedFiles);
                        });
                      }
                    },
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Galeriden Seç'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade600),
                  ),
                  if (selectedImages.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      '✓ ${selectedImages.length} fotoğraf seçildi',
                      style: TextStyle(color: Colors.green.shade700, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: selectedImages.asMap().entries.map((entry) {
                        return Stack(
                          children: [
                            FutureBuilder<Widget>(
                              future: _buildImageWidget(entry.value),
                              builder: (context, snapshot) {
                                if (snapshot.hasData) {
                                  return snapshot.data!;
                                }
                                return const SizedBox(
                                  width: 60,
                                  height: 60,
                                  child: Center(child: CircularProgressIndicator()),
                                );
                              },
                            ),
                            Positioned(
                              right: 0,
                              top: 0,
                              child: GestureDetector(
                                onTap: () {
                                  setState(() {
                                    selectedImages.removeAt(entry.key);
                                  });
                                },
                                child: Container(
                                  decoration: const BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.close, size: 16, color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ]
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('İptal'),
              ),
              TextButton(
                onPressed: () {
                  // Dialog kapatmadan önce değerleri kaydet
                  final paidAmount = double.tryParse(paidAmountCtrl.text.replaceAll(',', '.')) ?? 0;
                  
                  if (paidAmount <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Geçerli bir tutar girin')),
                    );
                    return;
                  }
                  
                  // TL karşılığını hesapla
                  double tlTutar = paidAmount;
                  if (paraBirimi != 'TL') {
                    double kur = 0;
                    if (paraBirimi == 'USD') {
                      kur = double.tryParse(kurUSDCtrl.text.replaceAll(',', '.')) ?? 0;
                    } else if (paraBirimi == 'EUR') {
                      kur = double.tryParse(kurEURCtrl.text.replaceAll(',', '.')) ?? 0;
                    } else if (paraBirimi == 'GBP') {
                      kur = double.tryParse(kurGBPCtrl.text.replaceAll(',', '.')) ?? 0;
                    } else if (paraBirimi == 'ALTIN') {
                      kur = double.tryParse(altinKurCtrl.text.replaceAll(',', '.')) ?? 0;
                    }
                    
                    if (kur <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('$paraBirimi kuru giriniz')),
                      );
                      return;
                    }
                    
                    tlTutar = paidAmount * kur;
                  }
                  
                  selectedCurrencyForSaving = paraBirimi;
                  calculatedTlAmount = tlTutar;
                  Navigator.pop(c, true);
                },
                child: const Text('Kaydet'),
              ),
            ],
          );
        },
      ),
    );

    if (result != true) return;

    final paidAmount = double.tryParse(paidAmountCtrl.text.replaceAll(',', '.')) ?? 0;
    if (paidAmount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Geçerli bir tutar girin')),
      );
      return;
    }
    
    // Daha önceden hesaplanmış TL tutarını kullan
    final tlTutar = calculatedTlAmount;
    final finalCurrency = selectedCurrencyForSaving;
    
    print('DEBUG SAVE: paidAmount=$paidAmount, currency=$finalCurrency, tlTutar=$tlTutar');

    try {
      final List<String> photoUrls = [];

      // Fotoğrafları yükle ve sıkıştır
      if (selectedImages.isNotEmpty) {
        for (var i = 0; i < selectedImages.length; i++) {
          final fileName = 'payment_${installment.id}_${DateTime.now().millisecondsSinceEpoch}_$i.jpg';
          final storageRef = FirebaseService().getStorageRef('payment_proofs/$fileName');
          
          // Resmi sıkıştır
          final compressedList = await compressImage(selectedImages[i]);
          final compressedBytes = Uint8List.fromList(compressedList);
          
          await storageRef.putData(compressedBytes);
          
          final url = await storageRef.getDownloadURL();
          photoUrls.add(url);
        }
      }

      // Ödeme kaydını payment_records subcollection'a ekle
      await FirebaseFirestore.instance
          .collection('payment_installments')
          .doc(installment.id)
          .collection('payment_records')
          .add({
        'paidAmount': paidAmount,
        'currency': finalCurrency,
        'tlAmount': tlTutar,
        'createdAt': selectedDate,
        'photoUrls': photoUrls,
        'notes': '',
      });

      // Loading dialog'ı göster
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => const Center(
            child: CircularProgressIndicator(),
          ),
        );
      }

      // Taksit bilgilerini güncelle
      try {
        await _firebase.markInstallmentAsPaid(
          installmentId: installment.id,
          paymentPlanId: widget.paymentPlanId,
          projectId: installment.projectId,
          paidAmount: paidAmount,
          photoUrls: photoUrls,
        );

        if (mounted) {
          Navigator.pop(context);
          setState(() {});
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${tlTutar.toStringAsFixed(2)} ₺ ödeme kaydedildi')),
          );
        }
      } catch (e) {
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Firebase hatası: $e')),
          );
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Dosya yükleme hatası: $e')),
      );
    }
  }

  void _editPaymentRecord(PaymentInstallment installment, String recordId, Map<String, dynamic> record) async {
    final originalPaidAmount = (record['paidAmount'] as num?)?.toDouble() ?? 0;
    final originalCurrency = record['currency'] as String? ?? 'TL';
    final originalTlAmount = (record['tlAmount'] as num?)?.toDouble() ?? originalPaidAmount;
    final originalDate = record['createdAt'] as Timestamp?;
    final existingPhotos = List<String>.from(record['photoUrls'] ?? []);

    final paidAmountCtrl = TextEditingController(text: originalPaidAmount.toString());
    DateTime selectedDate = originalDate?.toDate() ?? DateTime.now();
    final tarihCtrl = TextEditingController(text: DateFormat('dd.MM.yyyy').format(selectedDate));
    String paraBirimi = originalCurrency;
    final kurUSDCtrl = TextEditingController();
    final kurEURCtrl = TextEditingController();
    final kurGBPCtrl = TextEditingController();
    final altinKurCtrl = TextEditingController();
    final List<XFile> selectedImages = [];
    final List<String> keptPhotos = List<String>.from(existingPhotos);

    // Eğer orijinal kur bilgisi varsa, ters hesaplamayla kuru bul
    if (originalCurrency != 'TL' && originalPaidAmount > 0) {
      final kur = originalTlAmount / originalPaidAmount;
      final kurStr = kur.toStringAsFixed(4);
      if (originalCurrency == 'USD') kurUSDCtrl.text = kurStr;
      if (originalCurrency == 'EUR') kurEURCtrl.text = kurStr;
      if (originalCurrency == 'GBP') kurGBPCtrl.text = kurStr;
      if (originalCurrency == 'ALTIN') altinKurCtrl.text = kurStr;
    }

    late String selectedCurrencyForSaving;
    late double calculatedTlAmount;

    final result = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Ödeme Düzenle'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: paraBirimi,
                    decoration: const InputDecoration(
                      labelText: 'Para Birimi',
                      border: OutlineInputBorder(),
                    ),
                    items: ['TL', 'USD', 'EUR', 'GBP', 'ALTIN']
                        .map((pb) => DropdownMenuItem(value: pb, child: Text(pb)))
                        .toList(),
                    onChanged: (v) => setState(() => paraBirimi = v!),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: paidAmountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Ödenen Tutar ($paraBirimi)',
                      prefixIcon: const Icon(Icons.monetization_on),
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (val) {
                      if (paraBirimi != 'TL') setState(() {});
                    },
                  ),
                  const SizedBox(height: 12),
                  if (paraBirimi == 'USD') ...[TextField(controller: kurUSDCtrl, decoration: const InputDecoration(labelText: 'USD Kuru (TL) *', border: OutlineInputBorder(), hintText: 'Örn: 34,50'), keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (val) => setState(() {})), const SizedBox(height: 12)],
                  if (paraBirimi == 'EUR') ...[TextField(controller: kurEURCtrl, decoration: const InputDecoration(labelText: 'EUR Kuru (TL) *', border: OutlineInputBorder(), hintText: 'Örn: 37,50'), keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (val) => setState(() {})), const SizedBox(height: 12)],
                  if (paraBirimi == 'GBP') ...[TextField(controller: kurGBPCtrl, decoration: const InputDecoration(labelText: 'GBP Kuru (TL) *', border: OutlineInputBorder(), hintText: 'Örn: 43,50'), keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (val) => setState(() {})), const SizedBox(height: 12)],
                  if (paraBirimi == 'ALTIN') ...[TextField(controller: altinKurCtrl, decoration: const InputDecoration(labelText: 'Gram Fiyatı (TL) *', border: OutlineInputBorder(), hintText: 'Örn: 2.850,00'), keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (val) => setState(() {})), const SizedBox(height: 12)],
                  if (paraBirimi != 'TL') ...[Builder(builder: (context) {
                    final tutar = double.tryParse(paidAmountCtrl.text.replaceAll(',', '.')) ?? 0;
                    double kur = 0;
                    if (paraBirimi == 'USD') kur = double.tryParse(kurUSDCtrl.text.replaceAll(',', '.')) ?? 0;
                    else if (paraBirimi == 'EUR') kur = double.tryParse(kurEURCtrl.text.replaceAll(',', '.')) ?? 0;
                    else if (paraBirimi == 'GBP') kur = double.tryParse(kurGBPCtrl.text.replaceAll(',', '.')) ?? 0;
                    else if (paraBirimi == 'ALTIN') kur = double.tryParse(altinKurCtrl.text.replaceAll(',', '.')) ?? 0;
                    if (tutar > 0 && kur > 0) {
                      final tlKarsilik = tutar * kur;
                      return Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.blue.shade50, border: Border.all(color: Colors.blue.shade200), borderRadius: BorderRadius.circular(8)), child: Text('TL Karşılığı: ${tlKarsilik.toStringAsFixed(2)} ₺', style: TextStyle(color: Colors.blue.shade900, fontWeight: FontWeight.w600)));
                    }
                    return const SizedBox.shrink();
                  }), const SizedBox(height: 12)],
                  TextField(
                    controller: tarihCtrl,
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: 'Ödeme Tarihi',
                      prefixIcon: const Icon(Icons.calendar_today),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.calendar_month),
                        onPressed: () async {
                          final picked = await showDatePicker(context: context, initialDate: selectedDate, firstDate: DateTime(2000), lastDate: DateTime.now());
                          if (picked != null) {
                            setState(() { selectedDate = picked; tarihCtrl.text = DateFormat('dd.MM.yyyy').format(selectedDate); });
                          }
                        },
                      ),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Mevcut fotoğraflar
                  if (keptPhotos.isNotEmpty) ...[const Align(alignment: Alignment.centerLeft, child: Text('Mevcut Fotoğraflar:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))), const SizedBox(height: 8), Wrap(spacing: 8, children: keptPhotos.asMap().entries.map((entry) => Stack(children: [GestureDetector(onTap: () => _showImagePreview(entry.value), child: Container(width: 60, height: 60, decoration: BoxDecoration(borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.grey.shade300)), child: ClipRRect(borderRadius: BorderRadius.circular(4), child: Image.network(entry.value, fit: BoxFit.cover, errorBuilder: (c, e, s) => const Icon(Icons.broken_image, size: 20))))), Positioned(right: 0, top: 0, child: GestureDetector(onTap: () => setState(() => keptPhotos.removeAt(entry.key)), child: Container(decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle), child: const Icon(Icons.close, size: 16, color: Colors.white))))],)).toList()), const SizedBox(height: 12)],
                  ElevatedButton.icon(onPressed: () async { final picker = ImagePicker(); final pickedFile = await picker.pickImage(source: ImageSource.camera); if (pickedFile != null) setState(() => selectedImages.add(pickedFile)); }, icon: const Icon(Icons.camera_alt), label: const Text('Fotoğraf Çek')),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(onPressed: () async { final picker = ImagePicker(); final pickedFiles = await picker.pickMultiImage(); if (pickedFiles.isNotEmpty) setState(() => selectedImages.addAll(pickedFiles)); }, icon: const Icon(Icons.photo_library), label: const Text('Galeriden Seç'), style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade600)),
                  if (selectedImages.isNotEmpty) ...[const SizedBox(height: 12), Text('✓ ${selectedImages.length} yeni fotoğraf seçildi', style: TextStyle(color: Colors.green.shade700, fontWeight: FontWeight.bold))],
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c), child: const Text('İptal')),
              TextButton(
                onPressed: () {
                  final paidAmount = double.tryParse(paidAmountCtrl.text.replaceAll(',', '.')) ?? 0;
                  if (paidAmount <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Geçerli bir tutar girin')));
                    return;
                  }
                  double tlTutar = paidAmount;
                  if (paraBirimi != 'TL') {
                    double kur = 0;
                    if (paraBirimi == 'USD') kur = double.tryParse(kurUSDCtrl.text.replaceAll(',', '.')) ?? 0;
                    else if (paraBirimi == 'EUR') kur = double.tryParse(kurEURCtrl.text.replaceAll(',', '.')) ?? 0;
                    else if (paraBirimi == 'GBP') kur = double.tryParse(kurGBPCtrl.text.replaceAll(',', '.')) ?? 0;
                    else if (paraBirimi == 'ALTIN') kur = double.tryParse(altinKurCtrl.text.replaceAll(',', '.')) ?? 0;
                    if (kur <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$paraBirimi kuru giriniz')));
                      return;
                    }
                    tlTutar = paidAmount * kur;
                  }
                  selectedCurrencyForSaving = paraBirimi;
                  calculatedTlAmount = tlTutar;
                  Navigator.pop(c, true);
                },
                child: const Text('Güncelle'),
              ),
            ],
          );
        },
      ),
    );

    if (result != true) return;

    final paidAmount = double.tryParse(paidAmountCtrl.text.replaceAll(',', '.')) ?? 0;
    if (paidAmount <= 0) return;
    final tlTutar = calculatedTlAmount;
    final finalCurrency = selectedCurrencyForSaving;

    try {
      // Yeni fotoğrafları yükle
      final List<String> newPhotoUrls = [];
      if (selectedImages.isNotEmpty) {
        for (var i = 0; i < selectedImages.length; i++) {
          final fileName = 'payment_${installment.id}_${DateTime.now().millisecondsSinceEpoch}_$i.jpg';
          final storageRef = FirebaseService().getStorageRef('payment_proofs/$fileName');
          final compressedList = await compressImage(selectedImages[i]);
          final compressedBytes = Uint8List.fromList(compressedList);
          await storageRef.putData(compressedBytes);
          final url = await storageRef.getDownloadURL();
          newPhotoUrls.add(url);
        }
      }

      final allPhotos = [...keptPhotos, ...newPhotoUrls];

      // Ödeme kaydını güncelle
      await FirebaseFirestore.instance
          .collection('payment_installments')
          .doc(installment.id)
          .collection('payment_records')
          .doc(recordId)
          .update({
        'paidAmount': paidAmount,
        'currency': finalCurrency,
        'tlAmount': tlTutar,
        'createdAt': selectedDate,
        'photoUrls': allPhotos,
      });

      // Taksit ve plan toplamlarını yeniden hesapla
      await _recalculateInstallmentTotals(installment);

      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ödeme güncellendi')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Güncelleme hatası: $e')),
        );
      }
    }
  }

  Future<void> _recalculateInstallmentTotals(PaymentInstallment installment) async {
    // payment_records'dan toplam TL tutarını hesapla
    final records = await FirebaseFirestore.instance
        .collection('payment_installments')
        .doc(installment.id)
        .collection('payment_records')
        .get();

    double totalPaid = 0;
    for (var r in records.docs) {
      final d = r.data();
      totalPaid += ((d['tlAmount'] ?? d['paidAmount'] ?? 0) as num).toDouble();
    }

    final isPaidComplete = totalPaid >= installment.amount;

    // Taksiti güncelle
    await FirebaseFirestore.instance.collection('payment_installments').doc(installment.id).update({
      'isPaid': isPaidComplete,
      'paidAmount': totalPaid,
      'paidDate': isPaidComplete ? DateTime.now() : null,
    });

    // Plan toplamlarını güncelle
    final installments = await FirebaseFirestore.instance
        .collection('payment_installments')
        .where('paymentPlanId', isEqualTo: widget.paymentPlanId)
        .get();

    double planTotalPaid = 0;
    for (var doc in installments.docs) {
      planTotalPaid += (doc.data()['paidAmount'] as num?)?.toDouble() ?? 0;
    }

    final plan = await FirebaseFirestore.instance.collection('payment_plans').doc(widget.paymentPlanId).get();
    final planData = plan.data() as Map<String, dynamic>;
    final totalAmount = (planData['totalAmount'] as num?)?.toDouble() ?? 0;
    final newStatus = planTotalPaid >= totalAmount ? 'completed' : 'partialPaid';

    await FirebaseFirestore.instance.collection('payment_plans').doc(widget.paymentPlanId).update({
      'paidAmount': planTotalPaid,
      'status': newStatus,
    });
  }

  void _showImagePreview(String imageUrl) {
    showDialog(
      context: context,
      builder: (c) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBar(
              title: const Text('Fotoğraf Önizleme'),
              automaticallyImplyLeading: false,
              actions: [
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(c),
                ),
              ],
            ),
            Expanded(
              child: InteractiveViewer(
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Center(
                      child: CircularProgressIndicator(
                        value: loadingProgress.expectedTotalBytes != null
                            ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                            : null,
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<Widget> _buildImageWidget(XFile imageFile) async {
    final bytes = await imageFile.readAsBytes();

    return Image.memory(
      bytes,
      width: 60,
      height: 60,
      fit: BoxFit.cover,
    );
  }
}
