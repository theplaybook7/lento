import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:developer' as developer;
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import '../models/project_model.dart';
import '../services/firebase_service.dart';
import '../utils/format_utils.dart' as format_utils;
import '../theme/app_theme.dart';
import '../utils/error_handler.dart';
import '../project_core.dart';
import '../notification_service.dart';
import '../utils/responsive_utils.dart' as resp;
import '../web/web_utils.dart' as web_utils;
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
  final Map<int, String> _ruhsatNotlari = {}; // sıra -> not metni
  
  // Belgeler
  final List<Map<String, String>> _yuklenenBelgeler = []; // {başlık, tarih, type}
  
  // Ruhsat arama
  String _ruhsatArama = '';
  String _belgeArama = '';

  // Akış Diyagramı durum yönetimi
  final Map<int, int> _akisDurumlari = {};
  final Map<int, String> _akisNotlari = {};
  String _akisArama = '';
  int? _expandedAkisNodeId;
  final TextEditingController _akisNotEditController = TextEditingController();
  bool _tapuSureciGerekli = false; // Karar Kontrolü Evet/Hayır
  bool _yolaTerkMi = false; // Yola Terk Kontrolü
  bool _yolaTerkKararVerildi = false; // Karar verildi mi?

  // Proje adı
  String _projeAdi = '';

  // Şantiye durum yönetimi
  int _santiyeKatSayisi = 0; // Kullanıcının girdiği kat sayısı
  final Map<int, int> _santiyeDurumlari = {}; // sıra -> durum (0: başlamadı, 1: devam ediyor, 2: tamamlandı)
  final Map<int, List<Map<String, String>>> _santiyeFotograflar = {}; // sıra -> [{url, tarih}]

  @override
  void initState() {
    super.initState();
    _firebase = FirebaseService();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() { if (mounted) setState(() {}); });
    _projeAdiniYukle();
    _ruhsatVerileriniYukle();
    _belgeleriYukle();
    _akisDiyagramiYukle();
    _santiyeVerileriniYukle();
  }
  
  void _projeAdiniYukle() async {
    try {
      final project = await _firebase.getProject(widget.projectId);
      if (project != null && mounted) {
        setState(() => _projeAdi = project.name);
      }
    } catch (_) {}
  }

  void _akisDiyagramiYukle() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('ruhsat')
          .doc(widget.projectId)
          .collection('akis_diyagrami')
          .get();
      for (var doc in snapshot.docs) {
        final data = doc.data();
        if (doc.id == 'karar_kontrol') {
          if (mounted) setState(() { _tapuSureciGerekli = data['tapuGerekli'] == true; });
          continue;
        }
        if (doc.id == 'yola_terk_kontrol') {
          if (mounted) setState(() {
            _yolaTerkMi = data['yolaTerk'] == true;
            _yolaTerkKararVerildi = data['kararVerildi'] == true;
          });
          continue;
        }
        final sira = data['sira'] as int?;
        final durum = data['durum'] as int?;
        final not = data['not'] as String?;
        if (sira != null && mounted) {
          setState(() {
            if (durum != null) _akisDurumlari[sira] = durum;
            if (not != null && not.isNotEmpty) _akisNotlari[sira] = not;
          });
        }
      }
    } catch (e) {
      developer.log('Akış diyagramı yükleme hatası: $e');
    }
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
        final not = data['not'] as String?;
        
        if (sira != null && mounted) {
          setState(() {
            if (durum != null) _ruhsatDurumlari[sira] = durum;
            if (not != null && not.isNotEmpty) _ruhsatNotlari[sira] = not;
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
  
  void _santiyeVerileriniYukle() async {
    try {
      // Kat sayısını yükle
      final santiyeDoc = await FirebaseFirestore.instance
          .collection('santiye')
          .doc(widget.projectId)
          .get();
      
      if (santiyeDoc.exists) {
        final data = santiyeDoc.data();
        if (mounted && data != null) {
          setState(() {
            _santiyeKatSayisi = data['katSayisi'] ?? 0;
          });
        }
      }
      
      // İşlem durumlarını yükle
      final snapshot = await FirebaseFirestore.instance
          .collection('santiye')
          .doc(widget.projectId)
          .collection('islemler')
          .get();
      
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final sira = data['sira'] as int?;
        final durum = data['durum'] as int?;
        
        if (sira != null && durum != null && mounted) {
          setState(() {
            _santiyeDurumlari[sira] = durum;
          });
        }
      }
      
      // Fotoğrafları yükle
      final fotografSnapshot = await FirebaseFirestore.instance
          .collection('santiye')
          .doc(widget.projectId)
          .collection('fotograflar')
          .get();
      
      for (var doc in fotografSnapshot.docs) {
        final data = doc.data();
        final sira = data['sira'] as int?;
        final url = data['url'] as String?;
        final tarih = data['tarih'] as String?;
        final aciklama = data['aciklama'] as String?;
        
        if (sira != null && url != null && mounted) {
          if (!_santiyeFotograflar.containsKey(sira)) {
            _santiyeFotograflar[sira] = [];
          }
          setState(() {
            _santiyeFotograflar[sira]!.add({
              'url': url,
              'tarih': tarih ?? '',
              'id': doc.id,
              'aciklama': aciklama ?? '',
            });
          });
        }
      }
    } catch (e) {
      developer.log('Şantiye verileri yükleme hatası: $e');
    }
  }

  Future<void> _projeIsimDuzenle() async {
    final project = await _firebase.getProject(widget.projectId);
    if (project == null || !mounted) return;
    final controller = TextEditingController(text: project.name);
    final yeniIsim = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Proje İsmini Düzenle',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: AppTheme.primaryColor,
          ),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Proje Adı',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty) Navigator.pop(context, text);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
            ),
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (yeniIsim != null && yeniIsim != project.name && mounted) {
      try {
        await _firebase.updateProject(widget.projectId, {'name': yeniIsim});
        if (!mounted) return;
        setState(() => _projeAdi = yeniIsim);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Proje ismi güncellendi')),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(hataCevir(e)), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _akisNotEditController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text(_projeAdi.isNotEmpty ? _projeAdi : 'Proje Detayları'),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        elevation: 1,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Row(
            children: List.generate(3, (i) {
              final isSelected = _tabController.index == i;
              final labels = ['Muhasebe', 'Ruhsat', 'Şantiye'];
              final icons = [Icons.info_outline, Icons.description_outlined, Icons.construction_outlined];
              final activeColors = [Colors.blue.shade700, Colors.red.shade700, Colors.orange.shade800];
              return Expanded(
                child: GestureDetector(
                  onTap: () => _tabController.animateTo(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.white : Colors.transparent,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(10),
                        topRight: Radius.circular(10),
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icons[i], size: resp.isMobile(context) ? 18 : 20, color: isSelected ? activeColors[i] : Colors.white70),
                        const SizedBox(height: 2),
                        Text(labels[i], style: TextStyle(
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? activeColors[i] : Colors.white70,
                        )),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
        actions: [
          if (SistemYoneticisi().isAdminKullanici)
            PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'rename') {
                await _projeIsimDuzenle();
              } else if (value == 'archive') {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text(
                      'Projeyi Arşivle',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                    content: const Text('Bu projeyi arşivlemek istediğinizden emin misiniz?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('İptal'),
                      ),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          foregroundColor: Colors.white,
                        ),
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
                      SnackBar(content: Text(hataCevir(e)), backgroundColor: Colors.red),
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
                      SnackBar(content: Text(hataCevir(e)), backgroundColor: Colors.red),
                    );
                  }
                }
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'rename',
                child: Row(
                  children: [
                    Icon(Icons.edit_outlined, color: Colors.blue),
                    SizedBox(width: 8),
                    Text('İsim Düzenle'),
                  ],
                ),
              ),
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
          _buildYetkiKontrolluTab('muhasebe', _buildMuhasebeTab()),
          // Ruhsat Tab
          _buildYetkiKontrolluTab('ruhsat', _buildRuhsatTab()),
          // Şantiye Tab
          _buildYetkiKontrolluTab('santiye', _buildSantiyeTab()),
        ],
      ),
    );
  }

  Widget _buildYetkiKontrolluTab(String modul, Widget content) {
    final sistem = SistemYoneticisi();
    final yetkiVar = sistem.yetkiVarMi(modul);

    if (!yetkiVar) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline, size: 64, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              Text(
                "Bu sekmeyi görüntülemek için yetkiniz yok.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      );
    }

    return content;
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
                  color: AppTheme.primaryColor.withValues(alpha: 0.05),
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
                
                // Ön Muhasebe Özeti
                FutureBuilder<ProjectFinance>(
                  future: _firebase.getProjectFinanceSummary(widget.projectId),
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
                          padding: EdgeInsets.all(resp.responsivePadding(context)),
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
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _FinanceCard(
                                      title: 'Gider',
                                      amount: finance.totalExpenses,
                                      color: Colors.red,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              _FinanceCard(
                                title: 'Kâr',
                                amount: finance.profit,
                                color: finance.profit >= 0 ? Colors.blue : Colors.orange,
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
                          backgroundColor: AppTheme.primaryColor,
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
                      .where('sirketId', isEqualTo: SistemYoneticisi().aktifSirket?.id ?? '')
                      .snapshots(),
                  builder: (context, cariSnap) {
                    if (!cariSnap.hasData) {
                      return const SizedBox();
                    }

                    // Hem eski projectId hem yeni projectIds formatını destekle
                    final cariler = cariSnap.data!.docs.where((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      final pids = List<String>.from(data['projectIds'] ?? []);
                      final pid = data['projectId'] ?? '';
                      return pids.contains(widget.projectId) || pid == widget.projectId;
                    }).toList();

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
                          final ikon = tip == 'musteri' ? Icons.person : Icons.business;

                          return FutureBuilder<QuerySnapshot>(
                            future: FirebaseFirestore.instance
                                .collection('cari_hesaplar')
                                .doc(cariDoc.id)
                                .collection('hareketler')
                                .where('projeId', isEqualTo: widget.projectId)
                                .get(),
                            builder: (context, hareketSnap) {
                              double bakiye = 0;
                              if (hareketSnap.hasData) {
                                for (var h in hareketSnap.data!.docs) {
                                  final hData = h.data() as Map<String, dynamic>;
                                  final tutarTL = ((hData['tutarTL'] ?? hData['tutar'] ?? 0.0) as num).toDouble();
                                  final hTip = hData['tip'] ?? 'borc';
                                  bakiye += hTip == 'alacak' ? tutarTL : -tutarTL;
                                }
                              }
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
                                    projectId: widget.projectId,
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
                                  bakiye == 0 ? 'Dengede' : (bakiye > 0 ? 'Alınan' : 'Ödenen'),
                                  style: TextStyle(color: renk, fontSize: 12),
                                ),
                                trailing: Text(
                                  format_utils.formatTL(bakiye.abs()),
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
      'LİHKAB BAŞVURU',
      'LİHKAB SONUÇ',
      'TECAVÜZ DURUMU-SATIN ALMA VB DİĞER HUSUSLAR',
      'İMAR DURUMU BAŞVURU',
      'İMAR DURUMU SONUÇ',
      'FERRUH BÖLGE',
      'İST- KOT ÇİZİMİ',
      'ETÜT',
      'KAROT DURUMU- BİNA BOŞALTMA DURUMU',
      'YOLA TERK DURUMU',
      'YIKIM',
      'FOLYO HAZIRLANMASI',
      'ENCÜMENE GİRİŞ',
      'ENCÜMENDEN ÇIKIŞ',
      'KADASTRO',
      'TAPU',
      '2. LİHKAB',
      '2. İMAR DURUMU',
      '2. KOT- İSTİKAMET',
      'ETÜT ONAYI',
      'MİMARİ',
      'STATİK TASLAK YAPILACAKLAR',
      'STATİK TASLAK YAPILAN-ZEMİNCİYE YÜK ATILANLAR',
      'GERÇEK ZEMİN DEĞERLERİ GELEN',
      'STATİK',
      'YİBF GİRİŞİ',
      'MİMARİ- STATİK UYUM KONTROLÜ',
      'ELK-MEKANİK PROJE',
      'AKUSTİK PROJE',
      'EKB ÖN ONAY HESAP SONUCU',
      'MÜELLİF EVRAKLARI',
      'İSKİ BAŞVURU',
      'İSKİ ONAY',
      'STATİK - MİMARİ RAPORTÖRE DWG AT',
      'YAPI DENETİM VE RAPORTÖR EKSİKLERİNİN GİDERİLMESİ',
      'RUHSAT DİLEKÇESİ',
      'FEN İŞLERİ',
      'YAPI DENETİM PROJE ONAYI',
      'PROJELERİN BELEDİYE ONAYI',
      'MÜTEAHHİT EKSİKLERİNİN İSTENDİĞİ DOSYALAR (NOTER TEMİNAT VS)',
      'HARÇLARIN YATIRILMASI',
      'OTOPARK TAAHHÜTNAMESİ YAPILACAK DOSYALAR',
      'TEMİNAT MEKTUBU TESLİMİ YAPILACAK DOSYALAR',
      'NUMARATAJ',
      'RUHSAT YAZIMI',
      'PROJE VE RUHSATLARIN TESLİMİ',
      'KAT İRTİFAKI DİLEKÇESİ VERİLENLER',
      'KAT İRTİFAKI ONAYLANAN',
    ];

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          TabBar(
            tabs: const [
              Tab(text: 'Akış Diyagramı'),
              Tab(text: 'Belgeler'),
            ],
            indicatorColor: AppTheme.primaryColor,
            labelColor: AppTheme.primaryColor,
            labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            unselectedLabelStyle: const TextStyle(fontSize: 12),
          ),
          // Tab Content
          Expanded(
            child: TabBarView(
              children: [
                _buildAkisDiyagramiTab(),
                _buildBelgeYuklemeTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRuhsatIslemSirasi(List<String> ruhsatMaddeleri) {
    // İlerleme hesapla
    final tamamlanan = _ruhsatDurumlari.values.where((d) => d == 2).length;
    final devamEden = _ruhsatDurumlari.values.where((d) => d == 1).length;
    final toplam = ruhsatMaddeleri.length;

    return Column(
      children: [
        // İlerleme barı ve legend
        Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2)),
            ],
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Flexible(child: Text('$tamamlanan/$toplam tamamlandı', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey.shade700))),
                  if (devamEden > 0) ...[
                    const SizedBox(width: 8),
                    Text('• $devamEden devam ediyor', style: TextStyle(fontSize: 12, color: Colors.orange.shade600)),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: toplam > 0 ? tamamlanan / toplam : 0,
                  backgroundColor: const Color(0xFFE8EAF0),
                  valueColor: AlwaysStoppedAnimation(Colors.green.shade500),
                  minHeight: 7,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  _buildLegendDot(Colors.blueGrey.shade400, 'Başlamadı'),
                  _buildLegendDot(Colors.orange.shade600, 'Devam Ediyor'),
                  _buildLegendDot(Colors.green.shade600, 'Tamamlandı'),
                ],
              ),
            ],
          ),
        ),
        // Kanban Kartları
        Expanded(
          child: Builder(
            builder: (context) {
              final filtrelenmis = <MapEntry<int, String>>[];
              for (int i = 0; i < ruhsatMaddeleri.length; i++) {
                final madde = ruhsatMaddeleri[i];
                final sira = i + 1;
                if (_ruhsatArama.isEmpty ||
                    madde.toLowerCase().contains(_ruhsatArama) ||
                    (_ruhsatNotlari[sira]?.toLowerCase().contains(_ruhsatArama) ?? false) ||
                    sira.toString() == _ruhsatArama) {
                  filtrelenmis.add(MapEntry(sira, madde));
                }
              }
              if (filtrelenmis.isEmpty && _ruhsatArama.isNotEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.search_off, size: 48, color: Colors.grey.shade300),
                      const SizedBox(height: 12),
                      Text('"$_ruhsatArama" için sonuç bulunamadı', style: TextStyle(color: Colors.grey.shade500)),
                    ],
                  ),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                itemCount: filtrelenmis.length,
                itemBuilder: (context, index) {
                  final entry = filtrelenmis[index];
                  return _buildKanbanCard(entry.value, entry.key);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  // ==================== AKIŞ DİYAGRAMI (AĞAÇ GÖRÜNÜMÜ) ====================

  static const _akisStatusColors = [Color(0xFFFFFFFF), Color(0xFFFFF8E1), Color(0xFFE8F5E9)];
  static const _akisStatusBorders = [Color(0xFF90A4AE), Color(0xFFFFA726), Color(0xFF66BB6A)];
  static const _akisStatusIcons = [Icons.radio_button_unchecked, Icons.timelapse_rounded, Icons.check_circle_rounded];
  static const _akisStatusLabels = ['Başlamadı', 'Devam Ediyor', 'Tamamlandı'];

  // Bağımlılık haritası: düğüm_id → bağımlı olduğu düğüm id'leri
  static const Map<int, List<int>> _akisBagimliliklari = {
    2: [1], 3: [2], 4: [3], 5: [4], 6: [5, 4], 7: [5],
    38: [6], 39: [38], 40: [39], 41: [40],
    45: [41], 42: [45], 43: [42], 44: [43],
    9: [8], 10: [8], 11: [8], 12: [8], 13: [8], 14: [13],
    15: [7], 16: [7], 17: [16, 14],
    18: [17, 15],
    19: [18], 20: [18], 21: [18], 22: [18], 23: [18], 24: [18], 46: [18], 47: [18],
    25: [19, 20, 21, 22, 23, 24, 46, 47],
    26: [25],
    27: [26], 28: [26], 29: [26], 30: [26], 31: [26], 32: [26], 33: [26], 34: [26],
    35: [27, 28, 29, 30, 31, 32, 33, 34],
    36: [35], 37: [36],
  };

  static const Map<int, String> _akisNodeNames = {
    1: 'LİHKAP', 2: 'İmar Durumu', 3: 'İstikamet Memuru',
    4: 'İstikamet Çizimi', 5: 'Karar Kontrolü', 6: 'Folyo Hazırlanması', 7: 'Etüt Çalışması',
    8: 'Karot Alımı', 9: 'RBT', 10: 'Kesim Yazıları', 11: 'Muafiyet',
    12: 'Boş Yazısı', 13: 'Yıkım', 14: 'Zemin Etütü',
    15: 'Mimari Proje', 16: 'Statik Taslak', 17: 'Statik Proje',
    18: 'YİBF Girişi', 19: 'Elektrik Proje', 20: 'Mekanik Proje',
    21: 'Akustik Proje', 22: 'EKB', 23: 'Müellif Evrakları', 24: 'İSKİ',
    25: 'Eksiklerin Giderilmesi', 26: 'Ruhsat Dilekçesi',
    27: 'YD Proje Onayı', 28: 'Belediye Proje Onayı', 29: 'Fen İşleri',
    30: 'Müteahhit Belgeleri', 31: 'Harçlar', 32: 'Otopark',
    33: 'Teminat Mektubu', 34: 'Numarataj', 35: 'Ruhsat Yazımı',
    36: 'Ruhsat Teslimi', 37: 'Kat İrtifakı',
    38: 'Encümen Girişi', 39: 'Encümen Çıkışı', 40: 'Kadastro', 41: 'Tapu İşlemi',
    45: 'Yola Terk Kontrolü', 42: '2. LİHKAP', 43: '2. İmar Durumu', 44: '2. İstikamet Çizimi',
    46: 'Zemin Etütü Onayı', 47: 'Noter Evrakları',
  };

  bool _akisDepsComplete(int id) {
    final deps = _akisBagimliliklari[id];
    if (deps == null || deps.isEmpty) return true;
    return deps.every((d) => (_akisDurumlari[d] ?? 0) == 2);
  }

  List<String> _akisUnmetDeps(int id) {
    final deps = _akisBagimliliklari[id] ?? [];
    return deps
        .where((d) => (_akisDurumlari[d] ?? 0) != 2)
        .map((d) => _akisNodeNames[d] ?? '#$d')
        .toList();
  }

  Widget _buildAkisDiyagramiTab() {
    final toplam = _tapuSureciGerekli ? (_yolaTerkMi ? 44 : 47) : 39;
    final tamamlanan = _akisDurumlari.values.where((d) => d == 2).length;
    final devamEden = _akisDurumlari.values.where((d) => d == 1).length;
    final yuzde = toplam > 0 ? tamamlanan / toplam : 0.0;

    return Column(
      children: [
        // ── İlerleme Barı ──
        Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.white, Colors.blue.shade50.withValues(alpha: 0.3)],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 3))],
          ),
          child: Column(
            children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('$tamamlanan/$toplam', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.primaryColor)),
                ),
                const SizedBox(width: 8),
                Text('tamamlandı', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                const Spacer(),
                if (devamEden > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(12)),
                    child: Text('$devamEden devam ediyor', style: TextStyle(fontSize: 11, color: Colors.orange.shade700, fontWeight: FontWeight.w500)),
                  ),
              ]),
              const SizedBox(height: 12),
              Stack(
                children: [
                  Container(height: 8, decoration: BoxDecoration(color: const Color(0xFFE8EAF0), borderRadius: BorderRadius.circular(4))),
                  FractionallySizedBox(
                    widthFactor: yuzde,
                    child: Container(
                      height: 8,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [Colors.green.shade400, Colors.green.shade600]),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                _buildLegendDot(Colors.blueGrey.shade300, 'Başlamadı'),
                const SizedBox(width: 16),
                _buildLegendDot(Colors.orange.shade500, 'Devam Ediyor'),
                const SizedBox(width: 16),
                _buildLegendDot(Colors.green.shade500, 'Tamamlandı'),
              ]),
            ],
          ),
        ),
        // ── Ağaç Görünümü ──
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
            child: Column(
              children: [
                _akisNodeStart('BAŞLA', Icons.play_arrow_rounded),
                _connDownStyled(),

                // ══════ PARALEL DALLAR ══════
                LayoutBuilder(builder: (ctx, boxConstraints) {
                  final isMobileLayout = boxConstraints.maxWidth < 500;
                  Widget lihkapKolu = Container(
                          margin: isMobileLayout ? const EdgeInsets.only(bottom: 8) : const EdgeInsets.only(right: 3),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.blue.shade100),
                          ),
                          child: Column(children: [
                            _branchLabel('LİHKAP Kolu', Colors.blue, Icons.description),
                            _akisNode(1, 'LİHKAP'),
                            _connDownStyled(),
                            _akisNode(2, 'İmar Durumu'),
                            _connDownStyled(),
                            _akisNode(3, 'İstikamet Memuru'),
                            _connDownStyled(),
                            _akisNode(4, 'İstikamet Çizimi'),
                            _connDownStyled(),

                            // ── KARAR KONTROLÜ (Evet / Hayır) ──
                            _buildKararKontrolNode(),

                            _connDownStyled(),
                            _akisNode(7, 'Etüt Çalışması'),
                          ]),
                        );

                  Widget? tapuKolu = _tapuSureciGerekli ? Container(
                            margin: isMobileLayout ? const EdgeInsets.only(bottom: 8) : const EdgeInsets.symmetric(horizontal: 3),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade50.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.orange.shade200),
                            ),
                            child: Column(children: [
                              _branchLabel('Tapu Kolu', Colors.orange, Icons.account_balance),
                              _akisNode(6, 'Folyo Hazırlanması'),
                              _connDownStyled(),
                              _akisNodeCompact(38, 'Encümen Girişi'),
                              _connDownStyled(height: 14),
                              _akisNodeCompact(39, 'Encümen Çıkışı'),
                              _connDownStyled(height: 14),
                              _akisNodeCompact(40, 'Kadastro'),
                              _connDownStyled(height: 14),
                              _akisNodeCompact(41, 'Tapu İşlemi'),
                              _buildCompactExpandedPanel([38, 39, 40, 41]),
                              _connDownStyled(height: 14),
                              _buildYolaTerkKontrolNode(),
                              if (!_yolaTerkMi && _yolaTerkKararVerildi) ...[
                                _connDownStyled(height: 14),
                                _sectionLabel('2. Süreç', Icons.refresh),
                                _akisNodeCompact(42, '2. LİHKAP'),
                                _connDownStyled(height: 14),
                                _akisNodeCompact(43, '2. İmar Durumu'),
                                _connDownStyled(height: 14),
                                _akisNodeCompact(44, '2. İstikamet Çizimi'),
                                _buildCompactExpandedPanel([42, 43, 44]),
                              ],
                            ]),
                          ) : null;

                  Widget karotKolu = Container(
                          margin: isMobileLayout ? EdgeInsets.zero : const EdgeInsets.only(left: 3),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.purple.shade50.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.purple.shade100),
                          ),
                          child: Column(children: [
                            _branchLabel('Karot Kolu', Colors.purple, Icons.build_circle),
                            _akisNode(8, 'Karot Alımı'),
                            _splitConnStyled(),
                            Wrap(
                              alignment: WrapAlignment.center,
                              spacing: 5, runSpacing: 5,
                              children: [
                                _akisNodeCompact(9, 'RBT'),
                                _akisNodeCompact(10, 'Kesim Yazıları'),
                                _akisNodeCompact(11, 'Muafiyet'),
                                _akisNodeCompact(12, 'Boş Yazısı'),
                                _akisNodeCompact(13, 'Yıkım'),
                              ],
                            ),
                            _buildCompactExpandedPanel([9, 10, 11, 12, 13]),
                            _mergeConnStyled(),
                            _akisNode(14, 'Zemin Etütü'),
                          ]),
                        );

                  if (isMobileLayout) {
                    return Column(children: [
                      lihkapKolu,
                      if (tapuKolu != null) tapuKolu,
                      karotKolu,
                    ]);
                  }
                  return IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: lihkapKolu),
                        if (tapuKolu != null) Expanded(child: tapuKolu),
                        Expanded(child: karotKolu),
                      ],
                    ),
                  );
                }),

                // ══════ BİRLEŞME ══════
                _mergeConnStyled(),

                // ── PROJE AŞAMASI ──
                _sectionLabel('Proje Aşaması', Icons.architecture),
                Row(children: [
                  Expanded(child: _akisNode(15, 'Mimari Proje')),
                  const SizedBox(width: 6),
                  Expanded(child: _akisNode(16, 'Statik Taslak')),
                ]),
                _connDownStyled(),
                _akisNode(17, 'Statik Proje'),

                _mergeConnStyled(),

                // ── YAPI DENETİM ──
                _sectionLabel('Yapı Denetim', Icons.verified_user),
                _akisNode(18, 'YİBF Girişi'),
                _splitConnStyled(),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 5, runSpacing: 5,
                  children: [
                    _akisNodeCompact(19, 'Elektrik Proje'),
                    _akisNodeCompact(20, 'Mekanik Proje'),
                    _akisNodeCompact(21, 'Akustik Proje'),
                    _akisNodeCompact(22, 'EKB'),
                    _akisNodeCompact(23, 'Müellif Evrakları'),
                    _akisNodeCompact(24, 'İSKİ'),
                    _akisNodeCompact(46, 'Zemin Etütü Onayı'),
                    _akisNodeCompact(47, 'Noter Evrakları'),
                  ],
                ),
                _buildCompactExpandedPanel([19, 20, 21, 22, 23, 24, 46, 47]),
                _mergeConnStyled(),
                _akisNode(25, 'Eksiklerin Giderilmesi'),

                _connDownStyled(),

                // ── RUHSAT ──
                _sectionLabel('Ruhsat', Icons.gavel),
                _akisNode(26, 'Ruhsat Dilekçesi'),
                _splitConnStyled(),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 5, runSpacing: 5,
                  children: [
                    _akisNodeCompact(27, 'YD Proje Onayı'),
                    _akisNodeCompact(28, 'Belediye Proje Onayı'),
                    _akisNodeCompact(29, 'Fen İşleri'),
                    _akisNodeCompact(30, 'Müteahhit Belgeleri'),
                    _akisNodeCompact(31, 'Harçların Yatırılması'),
                    _akisNodeCompact(32, 'Otopark'),
                    _akisNodeCompact(33, 'Teminat Mektubu'),
                    _akisNodeCompact(34, 'Numarataj'),
                  ],
                ),
                _buildCompactExpandedPanel([27, 28, 29, 30, 31, 32, 33, 34]),
                _mergeConnStyled(),
                _akisNode(35, 'Ruhsat Yazımı'),
                _connDownStyled(),

                // ── KAPANIŞ ──
                _sectionLabel('Kapanış', Icons.flag),
                _akisNode(36, 'Ruhsat ve Projelerin Teslimi'),
                _connDownStyled(),
                _akisNode(37, 'Kat İrtifakı'),
                _connDownStyled(),
                _akisNodeStart('BİTİŞ', Icons.check_rounded),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Karar Kontrolü Düğümü (Evet/Hayır) ──
  Widget _buildKararKontrolNode() {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.amber.shade600, width: 2),
          boxShadow: [BoxShadow(color: Colors.amber.withValues(alpha: 0.15), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.diamond_outlined, size: 16, color: Colors.amber.shade700),
              const SizedBox(width: 6),
              Flexible(child: Text('Karar Kontrolü', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey.shade800))),
            ]),
            const SizedBox(height: 4),
            Text('Satın Alma / Tecavüz / Tevhid / İfraz', style: TextStyle(fontSize: 9, color: Colors.grey.shade500), textAlign: TextAlign.center),
            const SizedBox(height: 10),
            Text('Tapu süreçleri gerekli mi?', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildKararButton('Evet', Colors.green, true),
                const SizedBox(width: 8),
                _buildKararButton('Hayır', Colors.red, false),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKararButton(String label, Color color, bool value) {
    final isSelected = _tapuSureciGerekli == value;
    return GestureDetector(
      onTap: () async {
        setState(() {
          _tapuSureciGerekli = value;
          _akisDurumlari[5] = 2;
        });
        try {
          await FirebaseFirestore.instance
              .collection('ruhsat').doc(widget.projectId)
              .collection('akis_diyagrami').doc('karar_kontrol')
              .set({'tapuGerekli': value}, SetOptions(merge: true));
          await FirebaseFirestore.instance
              .collection('ruhsat').doc(widget.projectId)
              .collection('akis_diyagrami').doc('madde_5')
              .set({'sira': 5, 'madde': 'Karar Kontrolü', 'durum': 2, 'not': '', 'guncellendiTarihi': DateTime.now()}, SetOptions(merge: true));
          final projeDoc = await FirebaseFirestore.instance.collection('projects').doc(widget.projectId).get();
          final projeAdi = projeDoc.data()?['name'] ?? 'Proje';
          await BildirimServisi.bildirimGonder(
            baslik: 'Akış Diyagramı Güncellendi',
            mesaj: '$projeAdi - Karar Kontrolü: ${value ? "Evet" : "Hayır"}',
            projeId: widget.projectId,
            modul: 'ruhsat',
          );
        } catch (e) {
          developer.log('Karar kontrolü bildirim hatası: $e', name: 'akis');
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.15) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? color : Colors.grey.shade300, width: isSelected ? 2 : 1),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(isSelected ? Icons.check_circle : Icons.circle_outlined, size: 14, color: isSelected ? color : Colors.grey.shade400),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500, color: isSelected ? color : Colors.grey.shade500)),
        ]),
      ),
    );
  }

  // ── Yola Terk Kontrolü Düğümü ──
  Widget _buildYolaTerkKontrolNode() {
    final depsOk = _akisDepsComplete(45);
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.deepPurple.shade400, width: 2),
          boxShadow: [BoxShadow(color: Colors.deepPurple.withValues(alpha: 0.12), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.diamond_outlined, size: 14, color: Colors.deepPurple.shade600),
              const SizedBox(width: 4),
              Flexible(child: Text('Yola Terk Kontrolü', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey.shade800))),
            ]),
            const SizedBox(height: 6),
            Text('Yola terk var mı?', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
            const SizedBox(height: 6),
            if (!depsOk)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.lock_outline, size: 12, color: Colors.grey.shade400),
                  const SizedBox(width: 4),
                  Text('Önce Tapu İşlemi tamamlanmalı', style: TextStyle(fontSize: 9, color: Colors.grey.shade400)),
                ]),
              )
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildYolaTerkButton('Yola Terk', Colors.blue, true, depsOk),
                  const SizedBox(width: 6),
                  _buildYolaTerkButton('Diğer', Colors.orange, false, depsOk),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildYolaTerkButton(String label, Color color, bool value, bool depsOk) {
    final isSelected = _yolaTerkKararVerildi && _yolaTerkMi == value;
    return GestureDetector(
      onTap: !depsOk ? null : () async {
        setState(() {
          _yolaTerkMi = value;
          _yolaTerkKararVerildi = true;
          _akisDurumlari[45] = 2;
        });
        try {
          await FirebaseFirestore.instance
              .collection('ruhsat').doc(widget.projectId)
              .collection('akis_diyagrami').doc('yola_terk_kontrol')
              .set({'yolaTerk': value, 'kararVerildi': true}, SetOptions(merge: true));
          await FirebaseFirestore.instance
              .collection('ruhsat').doc(widget.projectId)
              .collection('akis_diyagrami').doc('madde_45')
              .set({'sira': 45, 'madde': 'Yola Terk Kontrolü', 'durum': 2, 'not': '', 'guncellendiTarihi': DateTime.now()}, SetOptions(merge: true));
          final projeDoc = await FirebaseFirestore.instance.collection('projects').doc(widget.projectId).get();
          final projeAdi = projeDoc.data()?['name'] ?? 'Proje';
          await BildirimServisi.bildirimGonder(
            baslik: 'Akış Diyagramı Güncellendi',
            mesaj: '$projeAdi - Yola Terk Kontrolü: $label',
            projeId: widget.projectId,
            modul: 'ruhsat',
          );
        } catch (e) {
          developer.log('Yola terk kontrolü hatası: $e', name: 'akis');
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.15) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isSelected ? color : Colors.grey.shade300, width: isSelected ? 2 : 1),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(isSelected ? Icons.check_circle : Icons.circle_outlined, size: 12, color: isSelected ? color : Colors.grey.shade400),
          const SizedBox(width: 3),
          Text(label, style: TextStyle(fontSize: 10, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500, color: isSelected ? color : Colors.grey.shade500)),
        ]),
      ),
    );
  }

  // ── Ağaç Düğümü (Normal — genişleyebilir) ──
  Widget _akisNode(int id, String title, {bool isDecision = false}) {
    final s = _akisDurumlari[id] ?? 0;
    final hasNote = (_akisNotlari[id] ?? '').isNotEmpty;
    final noteText = _akisNotlari[id] ?? '';
    final isExpanded = _expandedAkisNodeId == id;
    final depsOk = _akisDepsComplete(id);
    return Center(
      child: GestureDetector(
        onTap: () => setState(() {
          if (isExpanded) { _expandedAkisNodeId = null; }
          else { _expandedAkisNodeId = id; _akisNotEditController.text = _akisNotlari[id] ?? ''; }
        }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: isExpanded ? 14 : 10),
          decoration: BoxDecoration(
            color: isExpanded ? Colors.white : _akisStatusColors[s],
            border: Border.all(
              color: isExpanded ? AppTheme.primaryColor : _akisStatusBorders[s],
              width: isExpanded ? 2 : 1.5,
            ),
            borderRadius: BorderRadius.circular(isExpanded ? 16 : 12),
            boxShadow: [BoxShadow(
              color: (isExpanded ? AppTheme.primaryColor : _akisStatusBorders[s]).withValues(alpha: isExpanded ? 0.2 : 0.1),
              blurRadius: isExpanded ? 16 : 6,
              offset: Offset(0, isExpanded ? 4 : 2),
            )],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                if (!depsOk && !isExpanded)
                  Padding(padding: const EdgeInsets.only(right: 5),
                    child: Icon(Icons.lock_outline, size: 13, color: Colors.red.shade300)),
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: _akisStatusBorders[s].withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(_akisStatusIcons[s], size: 14, color: _akisStatusBorders[s]),
                ),
                const SizedBox(width: 8),
                Flexible(child: Text(title, textAlign: TextAlign.center,
                  style: TextStyle(fontSize: isExpanded ? 12 : 11, fontWeight: FontWeight.w600, color: Colors.grey.shade800))),
                const SizedBox(width: 3),
                Icon(isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, size: 18, color: Colors.grey.shade400),
              ]),
              // Sticky note görünümü
              if (hasNote && !isExpanded)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(top: 6),
                  padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [const Color(0xFFFFF9C4), const Color(0xFFFFF176).withValues(alpha: 0.6)],
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: [BoxShadow(color: Colors.amber.withValues(alpha: 0.18), blurRadius: 4, offset: const Offset(1, 2))],
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.push_pin, size: 10, color: Colors.orange.shade400),
                      const SizedBox(width: 4),
                      Expanded(child: Text(
                        noteText,
                        style: TextStyle(fontSize: 9, fontStyle: FontStyle.italic, color: Colors.brown.shade700, height: 1.3),
                        maxLines: 2, overflow: TextOverflow.ellipsis,
                      )),
                    ],
                  ),
                ),
              if (isExpanded) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Container(height: 1, color: Colors.grey.shade200),
                ),
                _buildInlineStatusSelector(id, title),
                if (!depsOk) _buildDependencyWarning(id),
                _buildInlineNoteField(id, title),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── Ağaç Düğümü (Kompakt — Wrap içinde, seçimle genişler) ──
  Widget _akisNodeCompact(int id, String title) {
    final s = _akisDurumlari[id] ?? 0;
    final hasNote = (_akisNotlari[id] ?? '').isNotEmpty;
    final noteText = _akisNotlari[id] ?? '';
    final isSelected = _expandedAkisNodeId == id;
    final depsOk = _akisDepsComplete(id);
    return GestureDetector(
      onTap: () => setState(() {
        if (_expandedAkisNodeId == id) { _expandedAkisNodeId = null; }
        else { _expandedAkisNodeId = id; _akisNotEditController.text = _akisNotlari[id] ?? ''; }
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: _akisStatusColors[s],
          border: Border.all(
            color: isSelected ? AppTheme.primaryColor : _akisStatusBorders[s],
            width: isSelected ? 2 : 1.2,
          ),
          borderRadius: BorderRadius.circular(10),
          boxShadow: [BoxShadow(
            color: (isSelected ? AppTheme.primaryColor : _akisStatusBorders[s]).withValues(alpha: isSelected ? 0.2 : 0.08),
            blurRadius: isSelected ? 8 : 3,
            offset: const Offset(0, 1),
          )],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              if (!depsOk)
                Padding(padding: const EdgeInsets.only(right: 3),
                  child: Icon(Icons.lock_outline, size: 10, color: Colors.red.shade300)),
              Icon(_akisStatusIcons[s], size: 11, color: _akisStatusBorders[s]),
              const SizedBox(width: 5),
              Flexible(child: Text(title, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey.shade700))),
            ]),
            if (hasNote)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.fromLTRB(5, 3, 5, 3),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [const Color(0xFFFFF9C4), const Color(0xFFFFF176).withValues(alpha: 0.5)],
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(3),
                  boxShadow: [BoxShadow(color: Colors.amber.withValues(alpha: 0.15), blurRadius: 2, offset: const Offset(0.5, 1))],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.push_pin, size: 8, color: Colors.orange.shade400),
                    const SizedBox(width: 3),
                    Expanded(child: Text(
                      noteText,
                      style: TextStyle(fontSize: 8, fontStyle: FontStyle.italic, color: Colors.brown.shade700, height: 1.2),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                    )),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Başla/Bitiş Düğümü ──
  Widget _akisNodeStart(String title, IconData icon) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [AppTheme.primaryColor, AppTheme.primaryColor.withValues(alpha: 0.75)]),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [BoxShadow(color: AppTheme.primaryColor.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 3))],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 6),
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 1)),
        ]),
      ),
    );
  }

  // ── Dikey Bağlantı (Stilize) ──
  Widget _connDownStyled({double height = 20}) {
    return Center(
      child: Column(
        children: [
          Container(width: 2, height: height * 0.4, decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [Colors.grey.shade300, Colors.grey.shade400]),
          )),
          Icon(Icons.arrow_drop_down, size: 16, color: Colors.grey.shade400),
        ],
      ),
    );
  }

  // ── Dallanma (Stilize) ──
  Widget _splitConnStyled() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        Expanded(child: Container(height: 1.5, decoration: BoxDecoration(
          gradient: LinearGradient(colors: [Colors.transparent, Colors.blue.shade300]),
        ))),
        Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(colors: [Colors.blue.shade50, Colors.blue.shade100]),
            border: Border.all(color: Colors.blue.shade300),
          ),
          child: Icon(Icons.call_split, size: 12, color: Colors.blue.shade600),
        ),
        Expanded(child: Container(height: 1.5, decoration: BoxDecoration(
          gradient: LinearGradient(colors: [Colors.blue.shade300, Colors.transparent]),
        ))),
      ]),
    );
  }

  // ── Birleşme (Stilize) ──
  Widget _mergeConnStyled() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        Expanded(child: Container(height: 1.5, decoration: BoxDecoration(
          gradient: LinearGradient(colors: [Colors.transparent, Colors.green.shade300]),
        ))),
        Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(colors: [Colors.green.shade50, Colors.green.shade100]),
            border: Border.all(color: Colors.green.shade300),
          ),
          child: Icon(Icons.call_merge, size: 12, color: Colors.green.shade600),
        ),
        Expanded(child: Container(height: 1.5, decoration: BoxDecoration(
          gradient: LinearGradient(colors: [Colors.green.shade300, Colors.transparent]),
        ))),
      ]),
    );
  }

  // ── Dal Etiketi ──
  Widget _branchLabel(String text, Color color, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 2),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [color.withValues(alpha: 0.12), color.withValues(alpha: 0.05)]),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 5),
            Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
          ]),
        ),
      ),
    );
  }

  // ── Bölüm Etiketi ──
  Widget _sectionLabel(String text, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 6),
      child: Row(children: [
        Expanded(child: Container(height: 1, decoration: BoxDecoration(
          gradient: LinearGradient(colors: [Colors.transparent, Colors.grey.shade300]),
        ))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 14, color: AppTheme.primaryColor.withValues(alpha: 0.6)),
            const SizedBox(width: 5),
            Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey.shade600, letterSpacing: 0.5)),
          ]),
        ),
        Expanded(child: Container(height: 1, decoration: BoxDecoration(
          gradient: LinearGradient(colors: [Colors.grey.shade300, Colors.transparent]),
        ))),
      ]),
    );
  }

  // ── Lejant Noktası ──
  Widget _buildLegendDot(Color color, String label) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
      const SizedBox(width: 5),
      Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
    ]);
  }

  // ── Satır İçi Durum Seçici ──
  Widget _buildInlineStatusSelector(int id, String madde) {
    final currentStatus = _akisDurumlari[id] ?? 0;
    final depsOk = _akisDepsComplete(id);
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 3,
      runSpacing: 4,
      children: List.generate(3, (i) {
        final isSelected = currentStatus == i;
        final isLocked = i == 2 && !depsOk;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: GestureDetector(
            onTap: isLocked ? () {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('Önce bağımlı adımları tamamlayın: ${_akisUnmetDeps(id).join(", ")}'),
                backgroundColor: Colors.red.shade400,
                duration: const Duration(seconds: 2),
              ));
            } : () async {
              setState(() { _akisDurumlari[id] = i; });
              final yeniNot = _akisNotEditController.text.trim();
              if (yeniNot.isNotEmpty) _akisNotlari[id] = yeniNot;
              try {
                await FirebaseFirestore.instance
                    .collection('ruhsat').doc(widget.projectId)
                    .collection('akis_diyagrami').doc('madde_$id')
                    .set({'sira': id, 'madde': madde, 'durum': i, 'not': yeniNot, 'guncellendiTarihi': DateTime.now()}, SetOptions(merge: true));
                // Bildirim gönder
                final projeDoc = await FirebaseFirestore.instance.collection('projects').doc(widget.projectId).get();
                final projeAdi = projeDoc.data()?['name'] ?? 'Proje';
                await BildirimServisi.bildirimGonder(
                  baslik: 'Akış Diyagramı Güncellendi',
                  mesaj: '$projeAdi - $madde: ${_akisStatusLabels[i]}',
                  projeId: widget.projectId,
                  modul: 'ruhsat',
                );
              } catch (e) {
                developer.log('Akış durum güncelleme hatası: $e', name: 'akis');
              }
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected ? _akisStatusBorders[i].withValues(alpha: 0.15) : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isLocked ? Colors.grey.shade300 : (isSelected ? _akisStatusBorders[i] : Colors.grey.shade300),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isSelected ? Icons.check_circle : (isLocked ? Icons.lock_outline : Icons.circle_outlined),
                    size: 14,
                    color: isLocked ? Colors.grey.shade400 : _akisStatusBorders[i],
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _akisStatusLabels[i],
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      color: isLocked ? Colors.grey.shade400 : _akisStatusBorders[i],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }

  // ── Bağımlılık Uyarısı ──
  Widget _buildDependencyWarning(int id) {
    final unmet = _akisUnmetDeps(id);
    if (unmet.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.red.shade200),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.warning_amber_rounded, size: 14, color: Colors.red.shade400),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'Önce tamamlanmalı: ${unmet.join(", ")}',
                style: TextStyle(fontSize: 10, color: Colors.red.shade600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Satır İçi Not Alanı ──
  Widget _buildInlineNoteField(int id, String madde) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _akisNotEditController,
            maxLines: 2,
            style: const TextStyle(fontSize: 12),
            decoration: InputDecoration(
              hintText: 'Not ekle...',
              hintStyle: TextStyle(fontSize: 11, color: Colors.grey.shade400),
              filled: true,
              fillColor: Colors.grey.shade50,
              isDense: true,
              contentPadding: const EdgeInsets.all(10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppTheme.primaryColor)),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () async {
                final yeniNot = _akisNotEditController.text.trim();
                setState(() {
                  if (yeniNot.isEmpty) _akisNotlari.remove(id);
                  else _akisNotlari[id] = yeniNot;
                  _expandedAkisNodeId = null;
                });
                try {
                  await FirebaseFirestore.instance
                      .collection('ruhsat').doc(widget.projectId)
                      .collection('akis_diyagrami').doc('madde_$id')
                      .set({'sira': id, 'madde': madde, 'durum': _akisDurumlari[id] ?? 0, 'not': yeniNot, 'guncellendiTarihi': DateTime.now()}, SetOptions(merge: true));
                  if (yeniNot.isNotEmpty) {
                    final projeDoc = await FirebaseFirestore.instance.collection('projects').doc(widget.projectId).get();
                    final projeAdi = projeDoc.data()?['name'] ?? 'Proje';
                    await BildirimServisi.bildirimGonder(
                      baslik: 'Akış Diyagramı Notu Eklendi',
                      mesaj: '$projeAdi - $madde: $yeniNot',
                      projeId: widget.projectId,
                      modul: 'ruhsat',
                    );
                  }
                } catch (e) {
                  developer.log('Akış not kaydetme hatası: $e', name: 'akis');
                }
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kaydedildi'), duration: Duration(seconds: 1)));
              },
              icon: const Icon(Icons.save, size: 14),
              label: const Text('Kaydet', style: TextStyle(fontSize: 11)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Kompakt Düğüm Genişletilmiş Panel ──
  Widget _buildCompactExpandedPanel(List<int> groupIds) {
    if (_expandedAkisNodeId == null || !groupIds.contains(_expandedAkisNodeId)) return const SizedBox.shrink();
    final id = _expandedAkisNodeId!;
    final title = _akisNodeNames[id] ?? '';
    final s = _akisDurumlari[id] ?? 0;
    final depsOk = _akisDepsComplete(id);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.3)),
        boxShadow: [BoxShadow(color: AppTheme.primaryColor.withValues(alpha: 0.1), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            Icon(_akisStatusIcons[s], size: 16, color: _akisStatusBorders[s]),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.grey.shade800))),
            GestureDetector(
              onTap: () => setState(() { _expandedAkisNodeId = null; }),
              child: Icon(Icons.close, size: 18, color: Colors.grey.shade500),
            ),
          ]),
          const Divider(height: 16),
          _buildInlineStatusSelector(id, title),
          if (!depsOk) _buildDependencyWarning(id),
          _buildInlineNoteField(id, title),
        ],
      ),
    );
  }

  Widget _buildKanbanCard(String madde, int sira) {
    final statusValue = _ruhsatDurumlari[sira] ?? 0;
    final not = _ruhsatNotlari[sira];

    final statusColors = [
      const Color(0xFFE8EAF0), // Başlamadı - soft grey-blue
      const Color(0xFFFFF3E0), // Devam Ediyor - warm amber
      const Color(0xFFE8F5E9), // Tamamlandı - soft green
    ];
    final statusAccents = [
      Colors.blueGrey.shade400,
      Colors.orange.shade600,
      Colors.green.shade600,
    ];
    final statusIcons = [
      Icons.radio_button_unchecked,
      Icons.timelapse_rounded,
      Icons.check_circle_rounded,
    ];
    final statusLabels = ['Başlamadı', 'Devam Ediyor', 'Tamamlandı'];

    return GestureDetector(
      onTap: () => _showMaddeDialog(sira, madde, statusLabels, statusColors, statusAccents),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: statusColors[statusValue], width: 1.5),
          boxShadow: [
            BoxShadow(
              color: statusAccents[statusValue].withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            // Üst renkli şerit
            Container(
              height: 4,
              decoration: BoxDecoration(
                color: statusAccents[statusValue],
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(14),
                  topRight: Radius.circular(14),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Sıra numarası
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: statusAccents[statusValue].withValues(alpha: 0.12),
                        ),
                        child: Center(
                          child: Text(
                            '$sira',
                            style: TextStyle(
                              color: statusAccents[statusValue],
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Madde adı
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              madde,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                height: 1.35,
                                color: Colors.grey.shade800,
                              ),
                            ),
                            if (not != null && not.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.sticky_note_2_outlined, size: 14, color: Colors.grey.shade500),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      not,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600,
                                        fontStyle: FontStyle.italic,
                                        height: 1.3,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Alt durum satırı
                  Row(
                    children: [
                      Icon(statusIcons[statusValue], size: 16, color: statusAccents[statusValue]),
                      const SizedBox(width: 6),
                      Text(
                        statusLabels[statusValue],
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: statusAccents[statusValue],
                        ),
                      ),
                      const Spacer(),
                      Icon(Icons.edit_note_rounded, size: 18, color: Colors.grey.shade400),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showMaddeDialog(int sira, String madde, List<String> statusLabels, List<Color> statusColors, List<Color> statusAccents) {
    final notController = TextEditingController(text: _ruhsatNotlari[sira] ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
        actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
        title: Text('Madde $sira', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
            Text(madde, style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
            const SizedBox(height: 16),
            const Text('Durum', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            ...List.generate(3, (i) => _buildStatusOption(i, statusLabels[i], statusColors[i], statusAccents[i], sira, madde, notController)),
            const SizedBox(height: 16),
            const Text('Not', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: notController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Bu madde hakkında not ekleyin...',
                hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                filled: true,
                fillColor: Colors.grey.shade50,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AppTheme.primaryColor),
                ),
                contentPadding: const EdgeInsets.all(12),
              ),
              style: const TextStyle(fontSize: 13),
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
              final yeniNot = notController.text.trim();
              setState(() {
                if (yeniNot.isEmpty) {
                  _ruhsatNotlari.remove(sira);
                } else {
                  _ruhsatNotlari[sira] = yeniNot;
                }
              });
              await FirebaseFirestore.instance
                  .collection('ruhsat')
                  .doc(widget.projectId)
                  .collection('islemler')
                  .doc('madde_$sira')
                  .set({
                    'sira': sira,
                    'madde': madde,
                    'not': yeniNot,
                  }, SetOptions(merge: true));
              // Not değiştiyse bildirim gönder
              if (yeniNot.isNotEmpty) {
                final projeDoc = await FirebaseFirestore.instance
                    .collection('projects')
                    .doc(widget.projectId)
                    .get();
                final projeAdi = projeDoc.data()?['name'] ?? 'Proje';
                await BildirimServisi.bildirimGonder(
                  baslik: 'Ruhsat Notu Eklendi',
                  mesaj: '$projeAdi - Madde $sira: $yeniNot',
                  projeId: widget.projectId,
                  modul: 'ruhsat',
                );
              }
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Not kaydedildi')),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Notu Kaydet'),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusOption(int index, String label, Color bgColor, Color accentColor, int sira, String madde, TextEditingController notController) {
    final isSelected = (_ruhsatDurumlari[sira] ?? 0) == index;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: isSelected ? accentColor.withValues(alpha: 0.15) : bgColor.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () async {
            setState(() {
              _ruhsatDurumlari[sira] = index;
            });
            
            final yeniNot = notController.text.trim();
            if (yeniNot.isNotEmpty) {
              _ruhsatNotlari[sira] = yeniNot;
            }
            
            await FirebaseFirestore.instance
                .collection('ruhsat')
                .doc(widget.projectId)
                .collection('islemler')
                .doc('madde_$sira')
                .set({
                  'sira': sira,
                  'madde': madde,
                  'durum': index,
                  'label': label,
                  'not': yeniNot,
                  'guncellendiTarihi': DateTime.now(),
                }, SetOptions(merge: true));
            
            final projeDoc = await FirebaseFirestore.instance
                .collection('projects')
                .doc(widget.projectId)
                .get();
            final projeAdi = projeDoc.data()?['name'] ?? 'Proje';
            
            await BildirimServisi.bildirimGonder(
              baslik: 'Ruhsat Durumu Güncellendi',
              mesaj: '$projeAdi - $madde: $label',
              projeId: widget.projectId,
              modul: 'ruhsat',
            );
            
            developer.log('✅ Bildirim gönderildi: $projeAdi - $madde: $label');
            
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('$madde → $label')),
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            child: Row(
              children: [
                Icon(
                  isSelected ? Icons.check_circle : Icons.circle_outlined,
                  size: 20,
                  color: isSelected ? accentColor : Colors.grey.shade400,
                ),
                const SizedBox(width: 10),
                Text(label, style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: isSelected ? accentColor : Colors.grey.shade700,
                )),
              ],
            ),
          ),
        ),
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
              backgroundColor: AppTheme.primaryColor,
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
            child: Builder(
              builder: (context) {
                final filtrelenmis = <MapEntry<int, Map<String, String>>>[];
                for (int i = 0; i < _yuklenenBelgeler.length; i++) {
                  final belge = _yuklenenBelgeler[i];
                  if (_belgeArama.isEmpty ||
                      (belge['başlık']?.toLowerCase().contains(_belgeArama) ?? false) ||
                      (belge['tarih']?.toLowerCase().contains(_belgeArama) ?? false)) {
                    filtrelenmis.add(MapEntry(i, belge));
                  }
                }
                if (filtrelenmis.isEmpty && _belgeArama.isNotEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.search_off, size: 48, color: Colors.grey.shade300),
                        const SizedBox(height: 12),
                        Text('"$_belgeArama" için belge bulunamadı', style: TextStyle(color: Colors.grey.shade500)),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: filtrelenmis.length,
                  itemBuilder: (context, index) {
                    final entry = filtrelenmis[index];
                    return _buildBelgeKarti(entry.value, entry.key);
                  },
                );
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
                  color: AppTheme.primaryColor,
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
                _buildBelgeIslemButonu(Icons.preview, 'Önizle', AppTheme.primaryColor, () {
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
        withData: true,
      );

      if (result == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Dosya seçimi iptal edildi')),
        );
        return;
      }

      final file = result.files.single;

      if (file.bytes == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Dosya okunamadı. Lütfen tekrar deneyin.')),
        );
        return;
      }

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
          content: Text(hataCevir(e)),
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
          content: Text(hataCevir(e)),
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

      // Dialog ile önizleme göster
      showDialog(
        context: context,
        builder: (context) => Dialog(
          child: SizedBox(
            width: resp.dialogWidth(context),
            height: resp.dialogHeight(context),
            child: Column(
              children: [
                // Başlık ve Kapat butonu
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor,
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
                // Önizleme alanı
                Expanded(
                  child: Container(
                    color: Colors.grey.shade100,
                    child: (isPdf || isImage)
                        ? FutureBuilder<Uint8List>(
                            future: _fetchFileBytes(url),
                            builder: (context, snapshot) {
                              if (snapshot.connectionState == ConnectionState.waiting) {
                                return const Center(child: CircularProgressIndicator());
                              }
                              if (snapshot.hasError || !snapshot.hasData) {
                                return _buildPreviewError(message: snapshot.error?.toString());
                              }
                              
                              final bytes = snapshot.data!;
                              
                              if (bytes.isEmpty) {
                                return _buildPreviewError(message: 'Dosya boş (0 bytes)');
                              }
                              
                              return _buildWebPreview(bytes, isPdf, dosyaAdi);
                            },
                          )
                        : _buildPreviewUnsupported(),
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
          content: Text(hataCevir(e)),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  Future<Uint8List> _fetchFileBytes(String url) async {
    try {
      final ref = FirebaseStorage.instance.refFromURL(url);
      final metadata = await ref.getMetadata();
      final maxSize = metadata.size ?? (50 * 1024 * 1024);
      final bytes = await ref.getData(maxSize);
      
      if (bytes == null) {
        throw Exception('Dosya indirilemedi');
      }
      
      return bytes;
    } catch (e) {
      rethrow;
    }
  }

  Widget _buildPreviewError({String? message}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 56, color: Colors.red.shade400),
            const SizedBox(height: 12),
            Text(
              'Önizleme yüklenemedi',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.red.shade400),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            if (message != null && message.isNotEmpty)
              Text(
                message,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                textAlign: TextAlign.center,
              ),
            const SizedBox(height: 6),
            Text(
              'Lütfen indirme butonunu kullanın.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewUnsupported() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.file_present, size: 64, color: AppTheme.primaryColor),
            const SizedBox(height: 16),
            Text(
              'Bu dosya türü için önizleme yok',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.primaryColor),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'İndirme butonu ile dosyayı açabilirsiniz.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWebPreview(Uint8List bytes, bool isPdf, String fileName) {
    try {
      if (kIsWeb) {
        // Mobil tarayıcılarda iframe PDF/görsel gösteremiyor,
        // SfPdfViewer ve Image.memory kullan
        final isMobile = resp.isMobile(context);
        if (isMobile) {
          if (isPdf) {
            return SfPdfViewer.memory(bytes);
          }
          return InteractiveViewer(
            child: Image.memory(bytes, fit: BoxFit.contain),
          );
        }
        // Masaüstü tarayıcılarda iframe ile önizleme
        return web_utils.buildWebPreview(
          bytes: bytes,
          isPdf: isPdf,
          fileName: fileName,
        );
      }

      if (isPdf) {
        return SfPdfViewer.memory(bytes);
      }

      return InteractiveViewer(
        child: Image.memory(
          bytes,
          fit: BoxFit.contain,
        ),
      );
    } catch (e) {
      developer.log('_buildWebPreview hatasi: $e');
      return _buildPreviewError(message: e.toString());
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

      final fileName = belge['başlık'] ?? 'belge';
      if (kIsWeb) {
        await web_utils.downloadFile(url, fileName);
      } else {
        // iOS/Android: Tarayıcıda aç
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$fileName indiriliyor...'),
          backgroundColor: Colors.green.shade700,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(hataCevir(e)),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  Widget _buildSantiyeTab() {
    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.all(resp.responsivePadding(context)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Kat sayısı seçimi
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Zemin Üstü Kat Sayısı',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _santiyeKatSayisi > 0
                                ? '$_santiyeKatSayisi kat'
                                : 'Henüz belirlenmedi',
                            style: TextStyle(
                              fontSize: 14,
                              color: _santiyeKatSayisi > 0
                                  ? Colors.green.shade700
                                  : Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: _katSayisiDialog,
                      icon: Icon(_santiyeKatSayisi > 0 ? Icons.edit : Icons.add),
                      label: Text(_santiyeKatSayisi > 0 ? 'Değiştir' : 'Belirle'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade700,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            // İşlemler listesi
            if (_santiyeKatSayisi > 0) ...[
              const Text(
                'Yapım Aşamaları',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              ..._getSantiyeIslemleri().asMap().entries.map((entry) {
                final sira = entry.key + 1;
                final islem = entry.value;
                return _buildSantiyeKanbanCard(sira, islem);
              }),
            ] else
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    children: [
                      Icon(Icons.construction, size: 64, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      Text(
                        'Başlamak için kat sayısını belirleyin',
                        style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
  
  List<String> _getSantiyeIslemleri() {
    final islemler = <String>[
      'Hafriyat yapılacak alanın işaretlenmesi',
      'Hafriyat',
      'Hafriyat zeminine düşük dansiteli beton',
      'Temel atılması için kalıp, demir bağlantıları',
      'Hazır beton ile temel atılması',
      'Perde duvarlı bodrum kat (varsa) kalıp, demir ve su basmanı katı döşeme kalıp ve demir işlemleri',
      'Su basmanı betonu',
      'Zemin kat kalıp, demir işlemleri',
      'Hazır betonla Zemin kat betonu',
    ];
    
    // Kat sayısına göre dinamik maddeler ekle
    for (int i = 1; i <= _santiyeKatSayisi; i++) {
      islemler.add('$i. kat kalıp ve demir işleri');
      islemler.add('$i. kat beton dökülmesi');
    }
    
    // Kalan maddeler
    islemler.addAll([
      'Bodrum katın toprakla örtülecek kısmının su izolasyonunun yapılması',
      'Çatı katı ve çatının beton yada taşıyıcı tuğla ile taşıyıcı sisteminin yapılması',
      'Çatının kiremit altı ahşap kurulumundan önce oturacağı yüzeye demir ve betonla hatıl yapılması',
      'Kaliteli kereste ile 10×10 ve 5×10 kereste ile çatı kurulumu üzerine kiremit altı döşeme tahtalarının çakılması',
      'Çatıda Su izolasyonu',
      'Çatıda Isı izolasyonu',
      'Kiremit çıtalarının ısı izolasyonu levhaları üzerine çakılması',
      'Kiremit döşenmesi',
      'Çinko olukların ve yağmur inişlerinin hazırlanması',
      'Binada dış ve iç duvarların tuğla ile örülmesi',
      'İskele kurulması',
      'Dış sıvaya başlanması',
      'İç sıvaya başlanması',
      'İçeride su, elektrik, kalorifer, telefon, televizyon, sıhhi tesisata başlanması',
      'İç duvarlarda ve tavanlarda İnce sıva ve kaba alçıya başlanması',
      'Dışarıda duvarlara dıştan izolasyona başlanması',
      'Pencerelere antipas sürülmüş profil demirden kör kasaların takılması',
      'Dış Kapının ve Pencerelerin takılması',
      'Dış cephe boyası, yağmur boruları inişleri yapılması ve iskelenin sökülmesi',
      'İçeride tüm tesisatın kontrolunü takiben şap yapılmaya başlanması',
      'Seramik kaplanacak banyo, tuvalet ve diğer yerlerin yapılması',
      'İçeride ince alçı ve boyaya başlanması',
      'Korkulukların montajı',
      'Elektrik priz ve anahtarlarının montajı',
      'Kombi ve radyatörlerin montajı, testi',
      'Banyo ve tuvaletler vitrifiye ve bataryalar montajı',
      'Yer döşemesi, merdiven basamakları döşemesi',
      'İç kapıların montajı',
      'Balkon yer döşemeleri',
      'Mutfak kurulumu',
      'Dolapların montajı',
      'Çevre düzenlemesi',
      'İnşaat temizliği',
    ]);
    
    return islemler;
  }
  
  Widget _buildSantiyeKanbanCard(int sira, String islem) {
    final durum = _santiyeDurumlari[sira] ?? 0;
    final fotograflar = _santiyeFotograflar[sira] ?? [];
    
    Color bgColor;
    String durumText;
    IconData icon;
    
    switch (durum) {
      case 0:
        bgColor = Colors.grey.shade300;
        durumText = 'Başlamadı';
        icon = Icons.radio_button_unchecked;
        break;
      case 1:
        bgColor = Colors.yellow.shade300;
        durumText = 'Devam Ediyor';
        icon = Icons.access_time;
        break;
      case 2:
        bgColor = Colors.green.shade300;
        durumText = 'Tamamlandı';
        icon = Icons.check_circle;
        break;
      default:
        bgColor = Colors.grey.shade300;
        durumText = 'Başlamadı';
        icon = Icons.radio_button_unchecked;
    }
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(12),
              topRight: Radius.circular(12),
            ),
            onTap: () => _santiyeDurumSecDialog(sira, islem),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 4,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        '$sira',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                          color: AppTheme.primaryColor,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          islem,
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(icon, size: 16, color: Colors.white),
                            const SizedBox(width: 6),
                            Text(
                              durumText,
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: Colors.white.withValues(alpha: 0.8)),
                ],
              ),
            ),
          ),
          // Fotoğraf bölümü
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(12),
                bottomRight: Radius.circular(12),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.photo_library, size: 18, color: Colors.grey),
                    const SizedBox(width: 8),
                    Text(
                      'Fotoğraflar (${fotograflar.length})',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey,
                      ),
                    ),
                    const Spacer(),
                    ElevatedButton.icon(
                      onPressed: () => _santiyeFotografYukle(sira),
                      icon: const Icon(Icons.add_a_photo, size: 16),
                      label: const Text('Ekle'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade600,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ),
                if (fotograflar.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 120,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: fotograflar.length,
                      itemBuilder: (context, index) {
                        final foto = fotograflar[index];
                        final aciklama = foto['aciklama'] ?? '';
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: GestureDetector(
                            onTap: () => _santiyeFotografOnizle(fotograflar, index),
                            child: Stack(
                              children: [
                                Column(
                                  children: [
                                    Container(
                                      width: 80,
                                      height: 80,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(8),
                                        image: DecorationImage(
                                          image: NetworkImage(foto['url']!),
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                    ),
                                    if (aciklama.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      SizedBox(
                                        width: 80,
                                        child: Text(
                                          aciklama,
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.grey.shade700,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                Positioned(
                                  top: 2,
                                  right: 2,
                                  child: GestureDetector(
                                    onTap: () => _santiyeFotografSil(sira, foto['id']!, foto['url']!),
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: Colors.red.shade700,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.close,
                                        size: 14,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Future<void> _katSayisiDialog() async {
    final ctrl = TextEditingController(text: _santiyeKatSayisi > 0 ? '$_santiyeKatSayisi' : '');
    
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Zemin Üstü Kat Sayısı'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Kat Sayısı',
            hintText: 'Örn: 2',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () async {
              final katSayisi = int.tryParse(ctrl.text) ?? 0;
              if (katSayisi <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Lütfen geçerli bir sayı girin')),
                );
                return;
              }
              
              // Firestore'a kaydet
              await FirebaseFirestore.instance
                  .collection('santiye')
                  .doc(widget.projectId)
                  .set({'katSayisi': katSayisi}, SetOptions(merge: true));
              
              setState(() {
                _santiyeKatSayisi = katSayisi;
              });
              
              Navigator.pop(ctx);
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
  }
  
  Future<void> _santiyeDurumSecDialog(int sira, String islem) async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$sira. $islem'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildSantiyeStatusOption(ctx, sira, 0, 'Başlamadı', Colors.grey.shade300, Icons.radio_button_unchecked),
            const SizedBox(height: 8),
            _buildSantiyeStatusOption(ctx, sira, 1, 'Devam Ediyor', Colors.yellow.shade300, Icons.access_time),
            const SizedBox(height: 8),
            _buildSantiyeStatusOption(ctx, sira, 2, 'Tamamlandı', Colors.green.shade300, Icons.check_circle),
          ],
        ),
      ),
    );
  }
  
  Widget _buildSantiyeStatusOption(BuildContext ctx, int sira, int durum, String label, Color color, IconData icon) {
    final isSelected = (_santiyeDurumlari[sira] ?? 0) == durum;
    
    return InkWell(
      onTap: () async {
        // Firestore'a kaydet
        await FirebaseFirestore.instance
            .collection('santiye')
            .doc(widget.projectId)
            .collection('islemler')
            .doc('madde_$sira')
            .set({
          'sira': sira,
          'durum': durum,
        }, SetOptions(merge: true));
        
        setState(() {
          _santiyeDurumlari[sira] = durum;
        });
        
        // Proje adını al ve bildirim gönder
        final projeDoc = await FirebaseFirestore.instance
            .collection('projects')
            .doc(widget.projectId)
            .get();
        final projeAdi = projeDoc.data()?['name'] ?? 'Proje';
        
        // İşlem adını al
        final islemler = _getSantiyeIslemleri();
        final islemAdi = sira <= islemler.length ? islemler[sira - 1] : 'İşlem $sira';
        
        await BildirimServisi.bildirimGonder(
          baslik: 'Şantiye Durumu Güncellendi',
          mesaj: '$projeAdi - $islemAdi: $label',
          projeId: widget.projectId,
          modul: 'santiye',
        );
        
        developer.log('✅ Bildirim gönderildi: $projeAdi - $islemAdi: $label');
        
        Navigator.pop(ctx);
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
          border: isSelected ? Border.all(color: Colors.blue, width: 3) : null,
        ),
        child: Row(
          children: [
            Icon(icon, size: 24),
            const SizedBox(width: 12),
            Text(
              label,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
  
  Future<void> _santiyeFotografYukle(int sira) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: true,
        withData: true,
      );
      
      if (result == null || result.files.isEmpty) return;
      
      // Her fotoğraf için açıklama girme dialogu
      final fotografBilgileri = <Map<String, dynamic>>[];
      
      for (final file in result.files) {
        if (file.bytes == null) {
          developer.log('Fotograf okunamadi: ${file.name}');
          continue;
        }
        
        final aciklamaCtrl = TextEditingController();
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('Fotoğraf Açıklaması'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: 150,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(
                      file.bytes!,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: aciklamaCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Açıklama (isteğe bağlı)',
                    hintText: 'Örn: Zemin kat kalıp işlemi başlandı',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Atla'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Devam'),
              ),
            ],
          ),
        );
        
        if (confirmed == false) continue;
        
        fotografBilgileri.add({
          'file': file,
          'aciklama': aciklamaCtrl.text,
        });
      }
      
      if (fotografBilgileri.isEmpty) return;
      
      // Yükleniyor göstergesi
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Text('${fotografBilgileri.length} fotoğraf yükleniyor...'),
              ],
            ),
            duration: const Duration(seconds: 60),
            backgroundColor: Colors.blue.shade700,
          ),
        );
      }
      
      // Fotoğrafları yükle
      for (final fotoBilgi in fotografBilgileri) {
        final file = fotoBilgi['file'] as PlatformFile;
        final aciklama = fotoBilgi['aciklama'] as String;
        
        // Firebase Storage'a yükle
        final fileName = '${DateTime.now().millisecondsSinceEpoch}_${file.name}';
        final storageRef = FirebaseStorage.instance
            .ref()
            .child('santiye_fotograflar/${widget.projectId}/$fileName');
        
        await storageRef.putData(file.bytes!);
        final downloadUrl = await storageRef.getDownloadURL();
        
        // Firestore'a kaydet
        final docRef = await FirebaseFirestore.instance
            .collection('santiye')
            .doc(widget.projectId)
            .collection('fotograflar')
            .add({
          'sira': sira,
          'url': downloadUrl,
          'tarih': DateTime.now().toIso8601String(),
          'aciklama': aciklama,
        });
        
        // State'e ekle
        if (!_santiyeFotograflar.containsKey(sira)) {
          _santiyeFotograflar[sira] = [];
        }
        
        setState(() {
          _santiyeFotograflar[sira]!.add({
            'url': downloadUrl,
            'tarih': DateTime.now().toIso8601String(),
            'id': docRef.id,
            'aciklama': aciklama,
          });
        });
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${fotografBilgileri.length} fotoğraf yüklendi'),
            backgroundColor: Colors.green.shade700,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(hataCevir(e)),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }
  
  Future<void> _santiyeFotografSil(int sira, String docId, String url) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Fotoğraf Sil'),
        content: const Text('Bu fotoğrafı silmek istediğinize emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    
    if (confirm != true) return;
    
    try {
      // Firestore'dan sil
      await FirebaseFirestore.instance
          .collection('santiye')
          .doc(widget.projectId)
          .collection('fotograflar')
          .doc(docId)
          .delete();
      
      // Firebase Storage'dan sil
      try {
        final ref = FirebaseStorage.instance.refFromURL(url);
        await ref.delete();
      } catch (e) {
        developer.log('Storage silme hatası: $e');
      }
      
      // State'den sil
      setState(() {
        _santiyeFotograflar[sira]?.removeWhere((f) => f['id'] == docId);
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Fotoğraf silindi'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(hataCevir(e)),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  Future<void> _santiyeFotografOnizle(List<Map<String, String>> fotograflar, int baslangicIndex) async {
    await showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            PageView.builder(
              controller: PageController(initialPage: baslangicIndex),
              itemCount: fotograflar.length,
              itemBuilder: (context, index) {
                final foto = fotograflar[index];
                final aciklama = foto['aciklama'] ?? '';
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(
                      child: InteractiveViewer(
                        child: Image.network(
                          foto['url']!,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) {
                            return const Center(
                              child: Icon(Icons.error, color: Colors.white, size: 64),
                            );
                          },
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          if (aciklama.isNotEmpty) ...[
                            Text(
                              aciklama,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                          ],
                          if (foto['tarih']!.isNotEmpty)
                            Text(
                              DateTime.parse(foto['tarih']!).toString().substring(0, 16),
                              style: const TextStyle(color: Colors.white70, fontSize: 14),
                            ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
            Positioned(
              top: 16,
              right: 16,
              child: IconButton(
                onPressed: () => Navigator.pop(ctx),
                icon: const Icon(Icons.close, color: Colors.white, size: 32),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black54,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _yeniCariDialog(BuildContext context) async {
    if (!mounted) return;

    // İlk dialog: Var olan cari seç veya yeni oluştur
    final secim = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cari Hesap Ekle'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('İptal'),
          ),
        ],
        actionsAlignment: MainAxisAlignment.start,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Var olan bir cari hesabı bu projeye atayabilir veya yeni bir cari hesap oluşturabilirsiniz.'),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(ctx, 'mevcut'),
              icon: const Icon(Icons.search),
              label: const Text('Var Olandan Seç'),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(ctx, 'yeni'),
              icon: const Icon(Icons.add),
              label: const Text('Yeni Oluştur'),
            ),
          ],
        ),
      ),
    );

    if (secim == null || !mounted) return;

    if (secim == 'mevcut') {
      await _mevcutCariSec(context);
    } else {
      await _yeniCariOlustur(context);
    }
  }

  Future<void> _mevcutCariSec(BuildContext context) async {
    String arama = '';

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Cari Seç'),
          content: SizedBox(
            width: double.maxFinite,
            height: (MediaQuery.of(context).size.height * 0.5).clamp(200, 400),
            child: Column(
              children: [
                TextField(
                  decoration: InputDecoration(
                    hintText: 'Cari ara...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => arama = v.trim().toLowerCase()),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance.collection('cari_hesaplar').where('sirketId', isEqualTo: SistemYoneticisi().aktifSirket?.id ?? '').snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      // Projede zaten olan carileri filtrele
                      var docs = snapshot.data!.docs.where((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        final pids = List<String>.from(data['projectIds'] ?? []);
                        // Eski format desteği
                        final pid = data['projectId'] ?? '';
                        // Bu projede zaten olan carileri gösterme
                        if (pids.contains(widget.projectId) || pid == widget.projectId) return false;
                        final ad = (data['ad'] ?? '').toString().toLowerCase();
                        return arama.isEmpty || ad.contains(arama);
                      }).toList();

                      if (docs.isEmpty) {
                        return Center(
                          child: Text(
                            arama.isNotEmpty ? 'Sonuç bulunamadı' : 'Mevcut cari hesap yok',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        );
                      }

                      return ListView.builder(
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          final doc = docs[index];
                          final data = doc.data() as Map<String, dynamic>;
                          final ad = data['ad'] ?? 'İsimsiz';
                          final tip = data['tip'] ?? 'musteri';
                          final telefon = data['telefon'] ?? '';
                          final ikon = tip == 'musteri' ? Icons.person_outline : Icons.business_outlined;

                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.1),
                              child: Icon(ikon, color: AppTheme.primaryColor, size: 20),
                            ),
                            title: Text(ad, style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: telefon.toString().isNotEmpty ? Text(telefon) : null,
                            trailing: Text(
                              tip == 'musteri' ? 'Müşteri' : 'Tedarikçi',
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                            ),
                            onTap: () async {
                              // Cari'nin projectIds listesine bu projeyi ekle
                              await FirebaseFirestore.instance
                                  .collection('cari_hesaplar')
                                  .doc(doc.id)
                                  .update({
                                    'projectIds': FieldValue.arrayUnion([widget.projectId]),
                                  });

                              if (ctx.mounted) {
                                Navigator.pop(ctx);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('$ad bu projeye eklendi')),
                                );
                              }
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('İptal'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _yeniCariOlustur(BuildContext context) async {
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
                  'projectIds': [widget.projectId],
                  'olusturmaTarihi': FieldValue.serverTimestamp(),
                  'sirketId': SistemYoneticisi().aktifSirket?.id ?? '',
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withValues(alpha: 0.08),
            color.withValues(alpha: 0.03),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.08),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '${format_utils.formatNumber(amount)} ₺',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
