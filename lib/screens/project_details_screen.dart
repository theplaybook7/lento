import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:html' as html;
import 'dart:ui_web' as ui;
import 'dart:developer' as developer;
import '../models/project_model.dart';
import '../services/firebase_service.dart';
import '../utils/format_utils.dart';
import 'payment_plans_screen.dart';
import 'cari_hesap_screen.dart';

class ProjectDetailsScreen extends StatefulWidget {
  final String projectId;
  const ProjectDetailsScreen({super.key, required this.projectId});

  @override
  State<ProjectDetailsScreen> createState() => _ProjectDetailsScreenState();
}

class _ProjectDetailsScreenState extends State<ProjectDetailsScreen> with SingleTickerProviderStateMixin {
  late FirebaseService _firebase;
  late TabController _tabController;
  
  // Ruhsat işlem sırası durum yönetimi
  final Map<int, int> _ruhsatDurumlari = {}; // sıra -> durum (0: başlamadı, 1: devam ediyor, 2: tamamlandı)
  
  // Belgeler
  final List<Map<String, String>> _yuklenenBelgeler = []; // {başlık, tarih, type}

  @override
  void initState() {
    super.initState();
    _firebase = FirebaseService();
    _tabController = TabController(length: 3, vsync: this);
    _ruhsatVerileriniYukle();
    _belgeleriYukle();
  }
  
  void _ruhsatVerileriniYukle() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('ruhsat')
          .doc(widget.projectId)
          .collection('islemler')
          .get();
      
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final sira = data['sira'] as int?;
        final durum = data['durum'] as int?;
        
        if (sira != null && durum != null && mounted) {
          setState(() {
            _ruhsatDurumlari[sira] = durum;
          });
        }
      }
    } catch (e) {
      developer.log('Ruhsat verileri yükleme hatası: $e');
    }
  }
  
  void _belgeleriYukle() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('ruhsat')
          .doc(widget.projectId)
          .collection('belgeler')
          .get();
      
      final belgeler = <Map<String, String>>[];
      for (var doc in snapshot.docs) {
        final data = doc.data();
        belgeler.add({
          'başlık': data['başlık'] ?? '',
          'tarih': data['tarih'] ?? '',
          'firebaseUrl': data['firbaseUrl'] ?? '',
        });
      }
      
      if (mounted) {
        setState(() {
          _yuklenenBelgeler.clear();
          _yuklenenBelgeler.addAll(belgeler);
        });
      }
    } catch (e) {
      developer.log('Belgeler yükleme hatası: $e');
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Proje Detayları'),
        backgroundColor: Colors.blueGrey.shade700,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Muhasebe', icon: Icon(Icons.info_outline, size: 20)),
            Tab(text: 'Ruhsat', icon: Icon(Icons.description_outlined, size: 20)),
            Tab(text: 'Şantiye', icon: Icon(Icons.construction_outlined, size: 20)),
          ],
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'archive') {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Projeyi Arşivle'),
                    content: const Text('Bu projeyi arşivlemek istediğinizden emin misiniz?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('İptal'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Arşivle'),
                      ),
                    ],
                  ),
                );
                if (confirm == true && mounted) {
                  try {
                    await _firebase.archiveProject(widget.projectId);
                    if (!mounted) return;
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Proje arşivlendi')),
                    );
                  } catch (e) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
                    );
                  }
                }
              } else if (value == 'delete') {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Projeyi Sil'),
                    content: const Text('Bu projeyi kalıcı olarak silmek istediğinizden emin misiniz?\n\nBu işlem geri alınamaz!'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('İptal'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: TextButton.styleFrom(foregroundColor: Colors.red),
                        child: const Text('Sil'),
                      ),
                    ],
                  ),
                );
                if (confirm == true && mounted) {
                  try {
                    await _firebase.deleteProject(widget.projectId);
                    if (!mounted) return;
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Proje silindi')),
                    );
                  } catch (e) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
                    );
                  }
                }
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'archive',
                child: Row(
                  children: [
                    Icon(Icons.archive_outlined, color: Colors.orange),
                    SizedBox(width: 8),
                    Text('Arşivle'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Sil', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Muhasebe Tab
          _buildMuhasebeTab(),
          // Ruhsat Tab
          _buildRuhsatTab(),
          // Şantiye Tab
          _buildSantiyeTab(),
        ],
      ),
    );
  }

  Widget _buildMuhasebeTab() {
    return FutureBuilder<Project?>(
      future: _firebase.getProject(widget.projectId),
      builder: (context, projectSnap) {
        if (projectSnap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!projectSnap.hasData || projectSnap.data == null) {
          return const Center(child: Text('Proje bulunamadı'));
        }

        final project = projectSnap.data!;

        return SingleChildScrollView(
            child: Column(
              children: [
                // Hızlı İşlemler Çubuğu
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  color: Colors.blueGrey.shade50,
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (c) => PaymentPlansScreen(
                                  projectId: widget.projectId,
                                  projectName: project.name,
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.receipt_long),
                          label: const Text('Ödeme Planları'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Proje Bilgileri
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.blueGrey.shade50,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  project.name,
                                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 4),
                                if (project.description != null)
                                  Text(
                                    project.description!,
                                    style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                                  ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: _getStatusColor(project.status),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              project.status.name.toUpperCase(),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Başlangıç', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                                Text('${project.startDate.day}.${project.startDate.month}.${project.startDate.year}',
                                    style: const TextStyle(fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                          if (project.endDate != null)
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Bitiş', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                                  Text(
                                    '${project.endDate!.day}.${project.endDate!.month}.${project.endDate!.year}',
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Bütçe', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                                Text(
                                  '${formatNumber(project.totalBudget)} ₺',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Ön Muhasebe Özeti
                FutureBuilder<ProjectFinance>(
                  future: _firebase.getProjectFinance(widget.projectId),
                  builder: (context, financeSnap) {
                    if (financeSnap.connectionState == ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator(),
                      );
                    }

                    if (!financeSnap.hasData) {
                      return const SizedBox();
                    }

                    final finance = financeSnap.data!;

                    return Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              const Text(
                                'Ön Muhasebe Özeti',
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: _FinanceCard(
                                      title: 'Gelir',
                                      amount: finance.totalIncome,
                                      color: Colors.green,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _FinanceCard(
                                      title: 'Gider',
                                      amount: finance.totalExpenses,
                                      color: Colors.red,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _FinanceCard(
                                      title: 'Kâr',
                                      amount: finance.profit,
                                      color: finance.profit >= 0 ? Colors.blue : Colors.orange,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Kâr Marjı', style: TextStyle(color: Colors.grey.shade600)),
                                        Text(
                                          '${finance.profitMargin.toStringAsFixed(1)}%',
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                        ),
                                      ],
                                    ),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Bütçe Kullanımı', style: TextStyle(color: Colors.grey.shade600)),
                                        Text(
                                          '${finance.budgetUsage.toStringAsFixed(1)}%',
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),

                // Cariler Başlığı ve Ekle Butonu
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Cariler',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      ElevatedButton.icon(
                        onPressed: () => _yeniCariDialog(context),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Cari Ekle'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueGrey.shade700,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Cariler Listesi
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('cari_hesaplar')
                      .where('projectId', isEqualTo: widget.projectId)
                      .snapshots(),
                  builder: (context, cariSnap) {
                    if (!cariSnap.hasData) {
                      return const SizedBox();
                    }

                    final cariler = cariSnap.data!.docs;
                    if (cariler.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Center(
                          child: Text(
                            'Henüz cari hesap eklenmedi',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        ),
                      );
                    }

                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 0),
                        itemCount: cariler.length,
                        itemBuilder: (context, index) {
                          final cariDoc = cariler[index];
                          final cariData = cariDoc.data() as Map<String, dynamic>;
                          final ad = cariData['ad'] ?? 'İsimsiz';
                          final tip = cariData['tip'] ?? 'musteri';
                          final bakiye = (cariData['bakiye'] ?? 0.0) as double;
                          final ikon = tip == 'musteri' ? Icons.person : Icons.business;
                          final renk = bakiye > 0 ? Colors.green : (bakiye < 0 ? Colors.red : Colors.grey);

                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: InkWell(
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (c) => CariDetayScreen(
                                    cariId: cariDoc.id,
                                    cariAd: ad,
                                  ),
                                ),
                              ),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: renk.withValues(
                                    alpha: (renk.a * 255.0 * 0.1).clamp(0, 255),
                                  ),
                                  child: Icon(ikon, color: renk),
                                ),
                                title: Text(ad, style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Text(
                                  bakiye == 0 ? 'Dengede' : (bakiye > 0 ? 'Alacak' : 'Borç'),
                                  style: TextStyle(color: renk, fontSize: 12),
                                ),
                                trailing: Text(
                                  formatTL(bakiye.abs()),
                                  style: TextStyle(
                                    color: renk,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
              ],
            ),
          );
        },
      );
  }

  Widget _buildRuhsatTab() {
    final ruhsatMaddeleri = [
      'Aplikasyon Krokisi',
      'Kentsel dönüşüm ise metrekare ve daire sayısı kontrolü',
      'İmar durumu',
      'İstikamet',
      'Kot Kesit',
      'Rbt ve Muafiyet Onayı',
      'Bina Boş Yazısı',
      'Yıkım Ruhsatı',
      'Yanan Yıkılan',
      'Zemine Etütü',
      'Yola Terk, Hibe, Satın Alma, İfraz, Tevhit varsa Harita Folyosu',
      'Hibe, Satın alma, İfraz, Tevhit işlemi varsa 3. maddeye geri dön',
      'Harita folyosu encümen onayı',
      'Harita folyosu kadastro onayı',
      'İski müracatı',
      'İski harcı yatır',
      'Ruhsat Dilekçesi',
      'Mimari Proje Ozalit',
      'Fen işleri harç hesabı ve yatırma',
      'Yapı Denetim Ataması',
      'Mimari Proje Belediye Onayı',
      'Statik Proje Belediye Onayı',
      'Elektrik Proje Belediye Onayı',
      'Makine Proje Belediye Onayı',
      'Akustilk Belediye Onayı',
      'Zemin Etütü Belediye Onayı',
      'Harçları Hesaplat Yatır (Otopark Harcı, Proje Kontrol Harcı, Ruhsat Harcı, Tesisat Harcı)',
      'Asansör Proje',
      'Teminat Mektubu',
      'Şantiye Şefi Sözleşmesi, İnşaat Yapım Sözleşmesi',
      'Müteahhit Taahhütü',
      'Ruhsat Yazdır',
    ];

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          // Ruhsat ve Belgeler Tab'ları
          TabBar(
            tabs: const [
              Tab(text: 'İşlem Sırası'),
              Tab(text: 'Belgeler'),
            ],
            indicatorColor: Colors.blueGrey.shade700,
            labelColor: Colors.blueGrey.shade700,
          ),
          // Tab Content
          Expanded(
            child: TabBarView(
              children: [
                // Tab 1: İşlem Sırası (Kanban)
                _buildRuhsatIslemSirasi(ruhsatMaddeleri),
                // Tab 2: Belgeler
                _buildBelgeYuklemeTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRuhsatIslemSirasi(List<String> ruhsatMaddeleri) {
    return Column(
      children: [
        // Başlık ve Legendler
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _buildLegendItem(Colors.grey.shade300, 'Başlamadı'),
                  const SizedBox(width: 24),
                  _buildLegendItem(Colors.amber.shade100, 'Devam Ediyor'),
                  const SizedBox(width: 24),
                  _buildLegendItem(Colors.green.shade100, 'Tamamlandı'),
                ],
              ),
            ],
          ),
        ),
        // Kanban Kartları
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: ruhsatMaddeleri.length,
            itemBuilder: (context, index) {
              final madde = ruhsatMaddeleri[index];
              return _buildKanbanCard(madde, index + 1);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildKanbanCard(String madde, int sira) {
    // Status: 0 = Başlamadı, 1 = Devam Ediyor, 2 = Tamamlandı
    final statusValue = _ruhsatDurumlari[sira] ?? 0;

    final colors = [Colors.grey.shade300, Colors.amber.shade100, Colors.green.shade100];
    final statusLabels = ['Başlamadı', 'Devam Ediyor', 'Tamamlandı'];

    return GestureDetector(
      onTap: () {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Madde $sira - Durum Seç'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) => _buildStatusOption(i, statusLabels[i], colors[i], sira, madde)),
            ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Kapat'),
                  ),
                ],
              ),
            );
          },
          child: Card(
            margin: const EdgeInsets.only(bottom: 12),
            color: colors[statusValue],
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: Colors.blueGrey.shade700,
                        foregroundColor: Colors.white,
                        radius: 18,
                        child: Text(
                          '$sira',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          madde,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          statusLabels[statusValue],
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Colors.blueGrey.shade900),
                        ),
                      ),
                      const Icon(Icons.touch_app, size: 16, color: Colors.grey),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
  }

  Widget _buildStatusOption(int index, String label, Color color, int sira, String madde) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: ElevatedButton.icon(
        onPressed: () {
          // Local state güncelle
          setState(() {
            _ruhsatDurumlari[sira] = index;
          });
          
          // Firestore'a kaydet
          FirebaseFirestore.instance
              .collection('ruhsat')
              .doc(widget.projectId)
              .collection('islemler')
              .doc('madde_$sira')
              .set({
                'sira': sira,
                'madde': madde,
                'durum': index,
                'label': label,
                'guncellendiTarihi': DateTime.now(),
              }, SetOptions(merge: true));
          
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Durum: $label olarak işaretlendi')),
          );
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.black87,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        ),
        icon: const Icon(Icons.check),
        label: Text(label, style: const TextStyle(fontSize: 12)),
      ),
    );
  }

  Widget _buildBelgeYuklemeTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton.icon(
            onPressed: () {
              _tumBelgeleriYukle();
            },
            icon: const Icon(Icons.upload_file),
            label: const Text('Belge Yükle'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueGrey.shade700,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
            ),
          ),
        ),
        if (_yuklenenBelgeler.isEmpty)
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.file_upload_outlined, size: 64, color: Colors.grey.shade300),
                  const SizedBox(height: 16),
                  Text(
                    'Henüz belge yüklenmedi',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Belgeler bölümünde görüntülenmek için\nyukarıdaki butona tıklayarak belge yükleyin',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _yuklenenBelgeler.length,
              itemBuilder: (context, index) {
                final belge = _yuklenenBelgeler[index];
                return _buildBelgeKarti(belge, index);
              },
            ),
          ),
      ],
    );
  }

  Widget _buildBelgeKarti(Map<String, String> belge, int index) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.file_present,
                  size: 32,
                  color: Colors.blueGrey.shade700,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        belge['başlık'] ?? 'Belge',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        belge['tarih'] ?? '',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildBelgeIslemButonu(Icons.preview, 'Önizle', Colors.blueGrey.shade700, () {
                  _belgeOnizle(belge);
                }),
                _buildBelgeIslemButonu(Icons.download, 'İndir', Colors.green.shade700, () {
                  _belgeIndir(belge);
                }),
                _buildBelgeIslemButonu(Icons.delete, 'Sil', Colors.red.shade700, () {
                  _belgeySil(index);
                }),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBelgeIslemButonu(IconData icon, String label, Color color, VoidCallback onPressed) {
    return InkWell(
      onTap: onPressed,
      child: Column(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  void _tumBelgeleriYukle() async {
    try {
      // Dosya seç
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );

      if (result == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Dosya seçimi iptal edildi')),
        );
        return;
      }

      final file = result.files.single;
      
      // Yükleniyor göstergesi
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Belge yükleniyor...'),
          duration: const Duration(seconds: 30),
        ),
      );

      // Firebase Storage'a yükle
      final fileName = file.name;
      final fileExtension = fileName.split('.').last;
      final uniqueFileName = '${DateTime.now().millisecondsSinceEpoch}_$fileName';
      
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('ruhsat_belgeler')
          .child(widget.projectId)
          .child(uniqueFileName);

      // Dosyayı yükle
      await storageRef.putData(file.bytes!);

      // Firestore'a kaydet
      final yeniBelge = {
        'başlık': fileName,
        'tarih': DateTime.now().toString().split(' ')[0],
        'type': fileExtension,
        'firbaseUrl': await storageRef.getDownloadURL(),
        'boyut': file.size,
        'yuklenmeTarihi': DateTime.now(),
      };

      // Local state'e ekle
      setState(() {
        _yuklenenBelgeler.add({
          'başlık': yeniBelge['başlık'] as String,
          'tarih': yeniBelge['tarih'] as String,
          'firebaseUrl': yeniBelge['firbaseUrl'] as String,
        });
      });

      // Firestore'a kaydet
      await FirebaseFirestore.instance
          .collection('ruhsat')
          .doc(widget.projectId)
          .collection('belgeler')
          .add(yeniBelge);

      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Belge "$fileName" başarıyla yüklenmiştir'),
          backgroundColor: Colors.green.shade700,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Hata: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  void _belgeySil(int index) async {
    try {
      final belge = _yuklenenBelgeler[index];
      
      // Local state'ten sil
      setState(() {
        _yuklenenBelgeler.removeAt(index);
      });

      // Firestore'dan sil (başlık eşleşen ilk belgeyi sil)
      final ruhsatDoc = await FirebaseFirestore.instance
          .collection('ruhsat')
          .doc(widget.projectId)
          .collection('belgeler')
          .where('başlık', isEqualTo: belge['başlık'])
          .limit(1)
          .get();

      if (ruhsatDoc.docs.isNotEmpty) {
        await ruhsatDoc.docs.first.reference.delete();
      }
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Belge başarıyla silindi'),
          backgroundColor: Colors.green.shade700,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Hata: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  void _belgeOnizle(Map<String, String> belge) async {
    try {
      final url = belge['firebaseUrl'];
      final dosyaAdi = belge['başlık'] ?? '';
      
      if (url == null || url.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Belge URL bulunamadı'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // Dosya türünü belirle
      final dosyaTipi = dosyaAdi.toLowerCase();
      final isPdf = dosyaTipi.endsWith('.pdf');
      final isImage = dosyaTipi.endsWith('.jpg') || 
                      dosyaTipi.endsWith('.jpeg') || 
                      dosyaTipi.endsWith('.png') || 
                      dosyaTipi.endsWith('.gif');

      // Benzersiz view type oluştur
      final viewType = 'preview-${DateTime.now().millisecondsSinceEpoch}';
      
      // IFrame oluştur - dosya türüne göre
      ui.platformViewRegistry.registerViewFactory(
        viewType,
        (int viewId) {
          final iframe = html.IFrameElement();
          
          if (isPdf) {
            // PDF için PDF viewer embed
            final pdfViewerHtml = '''
            <html>
              <head>
                <style>
                  body { margin: 0; padding: 0; }
                  iframe { width: 100%; height: 100%; border: none; }
                </style>
              </head>
              <body>
                <iframe src="${Uri.encodeComponent(url)}" type="application/pdf"></iframe>
              </body>
            </html>
            ''';
            iframe.srcdoc = pdfViewerHtml;
          } else if (isImage) {
            // Resim için basit HTML
            final imageHtml = '''
            <html>
              <head>
                <style>
                  body { margin: 0; padding: 10px; background: #f5f5f5; display: flex; align-items: center; justify-content: center; height: 100vh; }
                  img { max-width: 100%; max-height: 100%; object-fit: contain; }
                </style>
              </head>
              <body>
                <img src="$url" />
              </body>
            </html>
            ''';
            iframe.srcdoc = imageHtml;
          } else {
            // Diğer dosyalar için indirme linki göster
            final downloadHtml = '''
            <html>
              <head>
                <style>
                  body { margin: 0; padding: 20px; background: #f5f5f5; font-family: Arial; display: flex; align-items: center; justify-content: center; height: 100vh; }
                  .container { text-align: center; background: white; padding: 40px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
                  .icon { font-size: 64px; margin-bottom: 20px; }
                  h2 { color: #333; margin: 0 0 10px 0; }
                  p { color: #666; margin: 0 0 20px 0; }
                  a { display: inline-block; background: #2196F3; color: white; padding: 10px 20px; text-decoration: none; border-radius: 4px; cursor: pointer; }
                  a:hover { background: #1976D2; }
                </style>
              </head>
              <body>
                <div class="container">
                  <div class="icon">📄</div>
                  <h2>Belge Önizlemesi Desteklenmiyor</h2>
                  <p>Bu dosya türü için önizleme mevcut değildir.</p>
                  <a href="$url" download="${dosyaAdi}">Dosyayı İndir</a>
                </div>
              </body>
            </html>
            ''';
            iframe.srcdoc = downloadHtml;
          }
          
          iframe.style.border = 'none';
          iframe.style.height = '100%';
          iframe.style.width = '100%';
          return iframe;
        },
      );

      // Dialog ile önizleme göster
      showDialog(
        context: context,
        builder: (context) => Dialog(
          child: Container(
            width: MediaQuery.of(context).size.width * 0.85,
            height: MediaQuery.of(context).size.height * 0.85,
            child: Column(
              children: [
                // Başlık ve Kapat butonu
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blueGrey.shade700,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(4),
                      topRight: Radius.circular(4),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          dosyaAdi,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            overflow: TextOverflow.ellipsis,
                          ),
                          maxLines: 1,
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: () {
                          _belgeIndir(belge);
                        },
                        icon: const Icon(Icons.download, size: 18),
                        label: const Text('İndir'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                // Önizleme alanı - HtmlElementView ile iframe göster
                Expanded(
                  child: Container(
                    color: Colors.grey.shade100,
                    child: HtmlElementView(viewType: viewType),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Hata: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  void _belgeIndir(Map<String, String> belge) async {
    try {
      final url = belge['firebaseUrl'];
      if (url == null || url.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Belge URL bulunamadı'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // Web için: İndirme bağlantısı oluştur ve tetikle
      final fileName = belge['başlık'] ?? 'belge';
      final anchor = html.AnchorElement(href: url)
        ..setAttribute('download', fileName)
        ..style.display = 'none';
      
      html.document.body?.children.add(anchor);
      anchor.click();
      
      // Kısa süre sonra kaldır
      await Future.delayed(const Duration(milliseconds: 100));
      html.document.body?.children.remove(anchor);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$fileName indiriliyor...'),
          backgroundColor: Colors.green.shade700,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Hata: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  Widget _buildSantiyeTab() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.construction_outlined, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            'Şantiye Dosyası',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 8),
          Text(
            'Yakında burada şantiye fotoğraflarınızı ve belgelerinizi görebileceksiniz',
            style: TextStyle(color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Future<void> _yeniCariDialog(BuildContext context) async {
    final adCtrl = TextEditingController();
    final telefonCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final adresCtrl = TextEditingController();
    String tip = 'musteri';

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Yeni Cari Hesap'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: RadioListTile<String>(
                        title: const Text('Müşteri', style: TextStyle(fontSize: 13)),
                        value: 'musteri',
                        groupValue: tip,
                        onChanged: (v) => setState(() => tip = v!),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    Expanded(
                      child: RadioListTile<String>(
                        title: const Text('Tedarikçi', style: TextStyle(fontSize: 13)),
                        value: 'tedarikci',
                        groupValue: tip,
                        onChanged: (v) => setState(() => tip = v!),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: adCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Ad / Firma Adı *',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: telefonCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Telefon',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: emailCtrl,
                  decoration: const InputDecoration(
                    labelText: 'E-posta',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: adresCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Adres',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('İptal'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (adCtrl.text.trim().isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Ad/Firma adı gerekli')),
                  );
                  return;
                }

                await FirebaseFirestore.instance.collection('cari_hesaplar').add({
                  'ad': adCtrl.text.trim(),
                  'tip': tip,
                  'telefon': telefonCtrl.text.trim(),
                  'email': emailCtrl.text.trim(),
                  'adres': adresCtrl.text.trim(),
                  'bakiye': 0.0,
                  'projectId': widget.projectId,
                  'olusturmaTarihi': FieldValue.serverTimestamp(),
                });

                if (context.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Cari hesap oluşturuldu')),
                  );
                }
              },
              child: const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(ProjectStatus status) {
    switch (status) {
      case ProjectStatus.planning:
        return Colors.blue;
      case ProjectStatus.ongoing:
        return Colors.orange;
      case ProjectStatus.completed:
        return Colors.green;
      case ProjectStatus.cancelled:
        return Colors.red;
    }
  }
}

class _FinanceCard extends StatelessWidget {
  final String title;
  final double amount;
  final Color color;

  const _FinanceCard({
    required this.title,
    required this.amount,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(title, style: TextStyle(fontSize: 12, color: color)),
          const SizedBox(height: 4),
          Text(
            '${formatNumber(amount)} ₺',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
