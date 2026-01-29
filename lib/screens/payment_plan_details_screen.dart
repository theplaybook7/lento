import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:typed_data';
import '../models/payment_model.dart';
import '../services/firebase_service.dart';
import '../utils/image_utils.dart';

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
      appBar: AppBar(
        title: Text(widget.planName),
        backgroundColor: Colors.blueGrey.shade800,
        foregroundColor: Colors.white,
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
            return const Center(child: Text('Taksit bulunamadı'));
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
                    margin: const EdgeInsets.only(bottom: 10),
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
                              ? Colors.green
                              : (isOverdue ? Colors.red : Colors.orange),
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
                        if (inst.paidAmount > 0)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('Toplam Ödenen:', style: TextStyle(color: Colors.grey.shade700)),
                                    Text(
                                      '₺${NumberFormat('#,##0.00', 'tr_TR').format(inst.paidAmount)}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.green,
                                      ),
                                    ),
                                  ],
                                ),
                                if (inst.paidAmount < inst.amount) ...[
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text('Kalan:', style: TextStyle(color: Colors.grey.shade700)),
                                      Text(
                                        '₺${NumberFormat('#,##0.00', 'tr_TR').format(inst.amount - inst.paidAmount)}',
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
                              final amount = (record['paidAmount'] as num?)?.toDouble() ?? 0;
                              final date = record['createdAt'] as Timestamp?;
                              final photos = List<String>.from(record['photoUrls'] ?? []);

                              return Column(
                                children: [
                                  ListTile(
                                    dense: true,
                                    leading: const Icon(Icons.check, color: Colors.green, size: 20),
                                    title: Text(
                                      '₺${NumberFormat('#,##0.00', 'tr_TR').format(amount)}',
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                    subtitle: date != null
                                        ? Text(DateFormat('dd.MM.yyyy HH:mm').format(date.toDate()))
                                        : null,
                                    trailing: photos.isNotEmpty
                                        ? Icon(Icons.image, color: Colors.blue.shade400, size: 18)
                                        : null,
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
    
    if (kIsWeb) {
      return Image.memory(
        bytes,
        width: 60,
        height: 60,
        fit: BoxFit.cover,
      );
    } else {
      final file = File(imageFile.path);
      return Image.file(
        file,
        width: 60,
        height: 60,
        fit: BoxFit.cover,
      );
    }
  }
}
