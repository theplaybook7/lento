import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import '../models/payment_model.dart';
import '../services/firebase_service.dart';

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

              return Card(
                elevation: 1,
                margin: const EdgeInsets.only(bottom: 10),
                color: inst.isPaid
                    ? Colors.green.shade50
                    : (isOverdue ? Colors.red.shade50 : Colors.white),
                child: ListTile(
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
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                  title: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
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
                            '${inst.installmentPercentage.toStringAsFixed(1)}%',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        inst.isPaid ? 'Ödendi' : 'Beklemede',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: inst.isPaid ? Colors.green : Colors.orange,
                        ),
                      ),
                    ],
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Text(
                        'Tarih: ${DateFormat('dd.MM.yyyy').format(inst.dueDate)}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      if (inst.paidAmount > 0)
                        Text(
                          'Ödenen: ₺${NumberFormat('#,##0.00', 'tr_TR').format(inst.paidAmount)}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.green,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      if (inst.paidDate != null)
                        Text(
                          'Ödeme Tarihi: ${DateFormat('dd.MM.yyyy').format(inst.paidDate!)}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.green,
                          ),
                        ),
                      if (inst.photoUrls.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: inst.photoUrls.map((photoUrl) {
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.blue.shade200),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.photo, size: 14, color: Colors.blue),
                                    const SizedBox(width: 6),
                                    // Önizleme ikonu
                                    InkWell(
                                      onTap: () => _showImagePreview(photoUrl),
                                      child: const Icon(Icons.visibility, size: 18, color: Colors.blue),
                                    ),
                                    const SizedBox(width: 6),
                                    // İndirme ikonu
                                    InkWell(
                                      onTap: () => _downloadImage(photoUrl),
                                      child: const Icon(Icons.download, size: 18, color: Colors.green),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      if (isOverdue && !inst.isPaid)
                        Text(
                          'GECİKMİŞ',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.red.shade700,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                    ],
                  ),
                  trailing: inst.isPaid
                      ? const Icon(Icons.check_circle, color: Colors.green)
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
                ),
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

    await showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Ödeme Kaydı'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: paidAmountCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Ödenen Tutar (₺)',
                      prefixIcon: Icon(Icons.monetization_on),
                      border: OutlineInputBorder(),
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
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Kaydet'),
              ),
            ],
          );
        },
      ),
    ).then((result) async {
      if (result != true) return;

      final paidAmount = double.tryParse(paidAmountCtrl.text) ?? 0;
      if (paidAmount <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Geçerli bir tutar girin')),
        );
        return;
      }

      try {
        final List<String> photoUrls = [];

        // Fotoğrafları yükle
        if (selectedImages.isNotEmpty) {
          for (var i = 0; i < selectedImages.length; i++) {
            final fileName = 'payment_${installment.id}_${DateTime.now().millisecondsSinceEpoch}_$i.jpg';
            final storageRef = FirebaseService().getStorageRef('payment_proofs/$fileName');
            
            // XFile readAsBytes() hem web hem mobilde çalışır
            final bytes = await selectedImages[i].readAsBytes();
            
            if (kIsWeb) {
              // Web için putData
              await storageRef.putData(bytes);
            } else {
              // Mobil/Desktop için File nesnesi oluştur
              final file = File(selectedImages[i].path);
              await storageRef.putFile(file);
            }
            
            final url = await storageRef.getDownloadURL();
            photoUrls.add(url);
          }
        }

        await _firebase.markInstallmentAsPaid(
          installmentId: installment.id,
          paymentPlanId: widget.paymentPlanId,
          projectId: installment.projectId,
          paidAmount: paidAmount,
          photoUrls: photoUrls,
        );

        if (mounted) {
          setState(() {});
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('₺${paidAmount.toStringAsFixed(2)} ödeme kaydedildi')),
          );
          Navigator.pop(context, true);
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e')),
        );
      }
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

  Future<void> _downloadImage(String imageUrl) async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('İndiriliyor...')),
      );

      if (kIsWeb) {
        // Web için - tarayıcı indirmesi
        // ignore: unused_local_variable
        final anchor = html.document.createElement('a') as html.AnchorElement
          ..href = imageUrl
          ..download = 'payment_${DateTime.now().millisecondsSinceEpoch}.jpg'
          ..click();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('İndirme başlatıldı')),
          );
        }
      } else {
        // Mobil ve desktop için
        final response = await http.get(Uri.parse(imageUrl));
        if (response.statusCode == 200) {
          final dir = await getApplicationDocumentsDirectory();
          final fileName = 'payment_${DateTime.now().millisecondsSinceEpoch}.jpg';
          final file = File('${dir.path}/$fileName');
          await file.writeAsBytes(response.bodyBytes);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('İndirildi: $fileName')),
            );
          }
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('İndirme hatası: $e')),
      );
    }
  }

  Future<Widget> _buildImageWidget(XFile imageFile) async {
    // Web ve mobil için XFile.readAsBytes() kullan
    final bytes = await imageFile.readAsBytes();
    
    if (kIsWeb) {
      // Web için bytes'dan oluştur
      return Image.memory(
        bytes,
        width: 60,
        height: 60,
        fit: BoxFit.cover,
      );
    } else {
      // Mobil/Desktop için File nesnesi oluştur
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
