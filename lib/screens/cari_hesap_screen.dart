// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../services/firebase_service.dart';
import '../utils/format_utils.dart';
import '../utils/image_utils.dart';
import '../utils/upload_helper.dart';
import '../theme/app_theme.dart';
import '../utils/error_handler.dart';
import '../project_core.dart' show SistemYoneticisi;
import 'package:url_launcher/url_launcher.dart';
import '../web/web_utils.dart' as web_utils;
import '../utils/responsive_utils.dart' as resp;

class CariHesapScreen extends StatefulWidget {
  const CariHesapScreen({super.key});

  @override
  State<CariHesapScreen> createState() => _CariHesapScreenState();
}

class _CariHesapScreenState extends State<CariHesapScreen> {
  String _filtre = 'tum';
  String _arama = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Cari Hesaplar'),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        elevation: 1,
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: _aramaDialogAc,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Container(
            color: AppTheme.primaryColor,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            child: Row(
              children: [
                Expanded(child: _filtreButomu('tum', 'Tümü', Icons.list)),
                const SizedBox(width: 8),
                Expanded(child: _filtreButomu('musteri', 'Müşteriler', Icons.people)),
                const SizedBox(width: 8),
                Expanded(child: _filtreButomu('tedarikci', 'Tedarikçiler', Icons.business)),
              ],
            ),
          ),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('cari_hesaplar').where('sirketId', isEqualTo: SistemYoneticisi().aktifSirket?.id ?? '').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text(hataCevir(snapshot.error ?? '')));
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          var docs = snapshot.data!.docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final tip = data['tip'] ?? 'musteri';
            final ad = (data['ad'] ?? '').toString().toLowerCase();
            
            bool tipFiltre = _filtre == 'tum' || tip == _filtre;
            bool aramaFiltre = _arama.isEmpty || ad.contains(_arama.toLowerCase());
            
            return tipFiltre && aramaFiltre;
          }).toList();

          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.account_balance_wallet_outlined, size: 48, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  Text(
                    'Henüz cari hesap kaydı yok',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: EdgeInsets.all(resp.responsivePadding(context)),
            itemCount: docs.length,
            itemBuilder: (context, index) => _cariKart(context, docs[index]),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _yeniCariDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('Cari Ekle'),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
      ),
    );
  }

  Widget _filtreButomu(String deger, String etiket, IconData ikon) {
    final aktif = _filtre == deger;
    return InkWell(
      onTap: () => setState(() => _filtre = deger),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: aktif ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: aktif ? AppTheme.primaryColor : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(ikon, size: 16, color: aktif ? AppTheme.primaryColor : Colors.white.withValues(alpha: 0.7)),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                etiket,
                style: TextStyle(
                  color: aktif ? AppTheme.primaryColor : Colors.white.withValues(alpha: 0.7),
                  fontWeight: aktif ? FontWeight.w600 : FontWeight.normal,
                  fontSize: 12,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _aramaDialogAc() {
    final ctrl = TextEditingController(text: _arama);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cari Ara'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            hintText: 'İsim, firma adı...',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('İptal')),
          ElevatedButton(
            onPressed: () {
              setState(() => _arama = ctrl.text.trim());
              Navigator.pop(ctx);
            },
            child: const Text('Ara'),
          ),
        ],
      ),
    );
  }

  Widget _cariKart(BuildContext context, QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final ad = data['ad'] ?? 'İsimsiz';
    final tip = data['tip'] ?? 'musteri';
    final bakiye = ((data['bakiye'] ?? 0) as num).toDouble();
    final telefon = data['telefon'] ?? '';
    final email = data['email'] ?? '';

    final alacak = bakiye > 0;
    final renk = alacak ? AppTheme.successColor : Colors.red;
    final ikon = tip == 'musteri' ? Icons.person_outline : Icons.business_outlined;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (c) => CariDetayScreen(cariId: doc.id, cariAd: ad),
          ),
        ),
        child: Padding(
          padding: EdgeInsets.all(resp.isMobile(context) ? 12 : 16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [renk.withValues(alpha: 0.2), renk.withValues(alpha: 0.1)],
                  ),
                ),
                child: Icon(ikon, color: renk, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ad,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primaryColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (telefon.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(telefon, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey.shade600)),
                    ],
                    if (email.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(email, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.grey.shade600)),
                    ],
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    bakiye == 0 ? 'Dengede' : (alacak ? 'Alınan' : 'Ödenen'),
                    style: TextStyle(
                      color: bakiye == 0 ? Colors.grey : renk,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    formatTL(bakiye.abs()),
                    style: TextStyle(
                      color: bakiye == 0 ? Colors.grey : renk,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
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
                  'projectId': '',
                  'projectIds': <String>[],
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
}

class CariDetayScreen extends StatefulWidget {
  final String cariId;
  final String cariAd;
  final String? projectId;

  const CariDetayScreen({super.key, required this.cariId, required this.cariAd, this.projectId});

  @override
  State<CariDetayScreen> createState() => _CariDetayScreenState();
}

class _CariDetayScreenState extends State<CariDetayScreen> {
  final Map<String, String> _projeAdlariCache = {};

  Future<void> _projeAdlariniGetir(Set<String> projeIdler) async {
    bool updated = false;
    for (var id in projeIdler) {
      try {
        final doc = await FirebaseFirestore.instance.collection('projects').doc(id).get();
        if (doc.exists) {
          _projeAdlariCache[id] = (doc.data()?['name'] ?? 'Proje') as String;
          updated = true;
        }
      } catch (_) {}
    }
    if (updated && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.cariAd),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'duzenle') {
                _cariDuzenle();
              } else if (value == 'proje_sec') {
                _projeSec();
              } else if (value == 'sil') {
                _cariSil();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'duzenle', child: Text('Düzenle')),
              const PopupMenuItem(value: 'proje_sec', child: Text('Proje Seç')),
              const PopupMenuItem(value: 'sil', child: Text('Sil')),
            ],
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('cari_hesaplar').doc(widget.cariId).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snapshot.data!.data() as Map<String, dynamic>? ?? {};
          final globalBakiye = ((data['bakiye'] ?? 0) as num).toDouble();
          final telefon = data['telefon'] ?? '';
          final email = data['email'] ?? '';
          final adres = data['adres'] ?? '';

          return Column(
            children: [
              // Bakiye kartı: projectId yoksa global bakiye göster, varsa hareketlerden hesaplanacak
              if (widget.projectId == null)
                _bakiyeKart(globalBakiye),
              if (telefon.isNotEmpty || email.isNotEmpty || adres.isNotEmpty)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.shade200,
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('İletişim Bilgileri', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const Divider(height: 20),
                      if (telefon.isNotEmpty) ...[
                        Row(
                          children: [
                            Icon(Icons.phone, size: 18, color: Colors.grey.shade600),
                            const SizedBox(width: 8),
                            Expanded(child: Text(telefon, maxLines: 1, overflow: TextOverflow.ellipsis)),
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],
                      if (email.isNotEmpty) ...[
                        Row(
                          children: [
                            Icon(Icons.email, size: 18, color: Colors.grey.shade600),
                            const SizedBox(width: 8),
                            Expanded(child: Text(email, maxLines: 1, overflow: TextOverflow.ellipsis)),
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],
                      if (adres.isNotEmpty)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.location_on, size: 18, color: Colors.grey.shade600),
                            const SizedBox(width: 8),
                            Expanded(child: Text(adres)),
                          ],
                        ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Hesap Hareketleri', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton.icon(
                          onPressed: () => _taksitliPlanOlusturDialog(),
                          icon: const Icon(Icons.calendar_month, size: 16),
                          label: const Text('Taksitli Plan', style: TextStyle(fontSize: 12)),
                          style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                        ),
                        TextButton.icon(
                          onPressed: () => _yeniHareketDialog(),
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Yeni Hareket', style: TextStyle(fontSize: 12)),
                          style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Taksit Planları bölümü
              _taksitPlanlariWidget(),
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('cari_hesaplar')
                      .doc(widget.cariId)
                      .collection('hareketler')
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    var docsWithTarih = snapshot.data!.docs
                        .where((doc) => doc.data() is Map<String, dynamic> && 
                               (doc.data() as Map<String, dynamic>).containsKey('tarih') && 
                               (doc.data() as Map<String, dynamic>)['tarih'] != null)
                        .toList();
                    
                    // Proje içinden açıldıysa sadece o projenin hareketlerini göster
                    if (widget.projectId != null) {
                      docsWithTarih = docsWithTarih.where((doc) {
                        final d = doc.data() as Map<String, dynamic>;
                        return d['projeId'] == widget.projectId;
                      }).toList();
                    }
                    
                    docsWithTarih.sort((a, b) {
                      final ta = (a.data() as Map<String, dynamic>)['tarih'] as Timestamp;
                      final tb = (b.data() as Map<String, dynamic>)['tarih'] as Timestamp;
                      return tb.compareTo(ta);
                    });

                    if (docsWithTarih.isEmpty) {
                      return const Center(
                        child: Text('Henüz hareket kaydı yok', style: TextStyle(color: Colors.grey)),
                      );
                    }

                    // Fetch missing project names for old hareketler
                    final yeniProjeIdler = <String>{};
                    for (var doc in docsWithTarih) {
                      final d = doc.data() as Map<String, dynamic>;
                      final pid = d['projeId'] as String? ?? 'manuel';
                      final pad = d['projeAd'] as String?;
                      if (pid != 'manuel' && pid.isNotEmpty &&
                          (pad == null || pad.isEmpty || pad == 'Proje') &&
                          !_projeAdlariCache.containsKey(pid)) {
                        yeniProjeIdler.add(pid);
                      }
                    }
                    if (yeniProjeIdler.isNotEmpty) {
                      _projeAdlariniGetir(yeniProjeIdler);
                    }

                    Map<String, List<Map<String, dynamic>>> projeGruplari = {};
                    for (var doc in docsWithTarih) {
                      final data = doc.data() as Map<String, dynamic>;
                      final projeId = data['projeId'] as String? ?? 'manuel';
                      data['_docId'] = doc.id;
                      String projeAd;
                      
                      if (projeId == 'manuel') {
                        final tarih = data['tarih'] as Timestamp?;
                        final tip = data['tip'] ?? 'borc';
                        if (tarih != null) {
                          final dt = tarih.toDate();
                          projeAd = '${dt.day}.${dt.month}.${dt.year} tarihli ${tip == "alacak" ? "Tahsilat" : "Ödeme"}';
                        } else {
                          projeAd = tip == "alacak" ? "Tahsilat" : "Ödeme";
                        }
                      } else {
                        projeAd = data['projeAd'] as String? ?? _projeAdlariCache[projeId] ?? 'Proje';
                      }
                      
                      final key = projeId == 'manuel' ? 'manuel_${doc.id}' : projeId;
                      if (!projeGruplari.containsKey(key)) {
                        projeGruplari[key] = [];
                      }
                      
                      final hareketData = Map<String, dynamic>.from(data);
                      hareketData['_projeAd'] = projeAd;
                      hareketData['_projeId'] = projeId;
                      projeGruplari[key]!.add(hareketData);
                    }

                    // Tüm projelerden toplam borç ve alacak hesapla
                    double genelToplamBorc = 0;
                    double genelToplamAlacak = 0;
                    for (var doc in docsWithTarih) {
                      final d = doc.data() as Map<String, dynamic>;
                      final tutarTL = ((d['tutarTL'] ?? d['tutar'] ?? 0.0) as num).toDouble();
                      final t = d['tip'] ?? 'borc';
                      if (t == 'borc') {
                        genelToplamBorc += tutarTL;
                      } else {
                        genelToplamAlacak += tutarTL;
                      }
                    }
                    final genelNet = genelToplamAlacak - genelToplamBorc;

                    // Proje içinden açıldıysa bakiye kartını burada göster
                    final projeBakiyeKart = widget.projectId != null
                        ? _bakiyeKart(genelNet)
                        : const SizedBox.shrink();

                    return Column(
                      children: [
                        if (widget.projectId != null) projeBakiyeKart,
                        Expanded(
                          child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: projeGruplari.length + 1, // +1 for summary card
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          // Genel özet kartı
                          return Card(
                            margin: const EdgeInsets.only(bottom: 16),
                            color: Colors.blue.shade50,
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                children: [
                                  const Text('Genel Özet', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                  const SizedBox(height: 12),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                    children: [
                                      Column(
                                        children: [
                                          const Text('Toplam Ödenen', style: TextStyle(color: Colors.red, fontSize: 12)),
                                          const SizedBox(height: 4),
                                          Text(formatTL(genelToplamBorc), style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 15)),
                                        ],
                                      ),
                                      Column(
                                        children: [
                                          const Text('Toplam Alınan', style: TextStyle(color: Colors.green, fontSize: 12)),
                                          const SizedBox(height: 4),
                                          Text(formatTL(genelToplamAlacak), style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 15)),
                                        ],
                                      ),
                                      Column(
                                        children: [
                                          const Text('Net', style: TextStyle(fontSize: 12)),
                                          const SizedBox(height: 4),
                                          Text(
                                            formatTL(genelNet.abs()),
                                            style: TextStyle(
                                              color: genelNet >= 0 ? Colors.green : Colors.red,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 15,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        }
                        final projeKey = projeGruplari.keys.elementAt(index - 1);
                        final hareketler = projeGruplari[projeKey]!;
                        final projeAd = hareketler.first['_projeAd'] as String;
                        
                        double toplamBorc = 0;
                        double toplamAlacak = 0;
                        for (var h in hareketler) {
                          final tutarTL = ((h['tutarTL'] ?? h['tutar'] ?? 0.0) as num).toDouble();
                          final tip = h['tip'] ?? 'borc';
                          if (tip == 'borc') {
                            toplamBorc += tutarTL;
                          } else {
                            toplamAlacak += tutarTL;
                          }
                        }
                        
                        final netHareket = toplamAlacak - toplamBorc;
                        final netRenk = netHareket >= 0 ? Colors.green : Colors.red;
                        
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: ExpansionTile(
                            tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            childrenPadding: const EdgeInsets.only(bottom: 8),
                            leading: Icon(
                              projeKey.startsWith('manuel') ? Icons.edit : Icons.business,
                              color: Colors.blue,
                            ),
                            title: Text(
                              projeAd,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                            subtitle: Text(
                              '${hareketler.length} hareket',
                              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                            ),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (toplamBorc > 0)
                                  Text(
                                    'Ödenen: ${formatTL(toplamBorc)}',
                                    style: const TextStyle(color: Colors.red, fontSize: 11),
                                  ),
                                if (toplamAlacak > 0)
                                  Text(
                                    'Alınan: ${formatTL(toplamAlacak)}',
                                    style: const TextStyle(color: Colors.green, fontSize: 11),
                                  ),
                                const SizedBox(height: 2),
                                Text(
                                  'Net: ${formatTL(netHareket.abs())}',
                                  style: TextStyle(
                                    color: netRenk,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                            children: hareketler.map((data) => _hareketKart(data, docId: data['_docId'])).toList(),
                          ),
                        );
                      },
                    ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _bakiyeKart(double bakiye) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: bakiye >= 0
              ? [Colors.green.shade600, Colors.green.shade400]
              : [Colors.red.shade600, Colors.red.shade400],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        children: [
          Text(
            bakiye == 0 ? 'Dengede' : (bakiye > 0 ? 'Alınan' : 'Ödenen'),
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 8),
          Text(
            formatTL(bakiye.abs()),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _hareketKart(Map<String, dynamic> data, {String? docId}) {
    final tip = data['tip'] ?? 'borc';
    final tutarTL = ((data['tutarTL'] ?? data['tutar'] ?? 0.0) as num).toDouble();
    final orijinalTutar = ((data['tutar'] ?? 0.0) as num).toDouble();
    final paraBirimi = data['paraBirimi'] ?? 'TL';
    final orijinalBirimLabel = paraBirimi == 'ALTIN' ? 'gr ALTIN' : paraBirimi;
    final aciklama = data['aciklama'] ?? '';
    final fotoUrls = List<String>.from(data['fotoUrls'] ?? []);
    final giderId = data['giderId'];
    
    DateTime? tarih;
    if (data.containsKey('tarih') && data['tarih'] != null) {
      try {
        tarih = (data['tarih'] as Timestamp).toDate();
      } catch (_) {}
    }
    
    final renk = tip == 'alacak' ? Colors.green : Colors.red;
    final ikon = tip == 'alacak' ? Icons.arrow_downward : Icons.arrow_upward;

    return Card(
      margin: const EdgeInsets.only(bottom: 8, left: 8, right: 8),
      child: Column(
        children: [
          ListTile(
            leading: CircleAvatar(
              backgroundColor: renk.withValues(alpha: (renk.a * 255.0 * 0.1).clamp(0, 255)),
              child: Icon(ikon, color: renk, size: 20),
            ),
            title: Text(
              tip == 'alacak' ? 'Tahsilat' : 'Ödeme',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (data['_projeId'] != null && data['_projeId'] != 'manuel' && data['_projeAd'] != null) ...[
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(Icons.business, size: 14, color: Colors.blue.shade600),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          tarih != null
                              ? "${data['_projeAd']}'de gerçekleşen ${tarih.day.toString().padLeft(2, '0')}.${tarih.month.toString().padLeft(2, '0')}.${tarih.year} tarihli ${tip == 'alacak' ? 'tahsilat' : 'ödeme'}"
                              : "${data['_projeAd']}'de gerçekleşen ${tip == 'alacak' ? 'tahsilat' : 'ödeme'}",
                          style: TextStyle(
                            color: Colors.blue.shade700,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ] else if (tarih != null) ...[
                  Text(
                    '${tarih.day.toString().padLeft(2, '0')}.${tarih.month.toString().padLeft(2, '0')}.${tarih.year}',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                ],
                if (aciklama.isNotEmpty)
                  Text(aciklama, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      formatTL(tutarTL),
                      style: TextStyle(color: renk, fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    if (paraBirimi != 'TL') ...[
                      const SizedBox(height: 2),
                      Text(
                        '${formatDecimal(orijinalTutar)} $orijinalBirimLabel',
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                      ),
                    ],
                  ],
                ),
                if (docId != null) ...[
                  const SizedBox(width: 8),
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert, size: 20, color: Colors.grey.shade600),
                    onSelected: (value) {
                      if (value == 'duzenle') {
                        _hareketDuzenle(docId, data);
                      } else if (value == 'sil') {
                        _hareketSil(docId, tutarTL, tip, giderId);
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(value: 'duzenle', child: Text('Düzenle')),
                      const PopupMenuItem(value: 'sil', child: Text('Sil')),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (fotoUrls.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: fotoUrls.asMap().entries.map((entry) {
                      return Stack(
                        children: [
                          InkWell(
                            onTap: () => _showCariImagePreview(entry.value),
                            child: Container(
                              width: 70,
                              height: 70,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  entry.value,
                                  fit: BoxFit.cover,
                                  loadingBuilder: (context, child, progress) {
                                    if (progress == null) return child;
                                    return Center(
                                      child: CircularProgressIndicator(
                                        value: progress.expectedTotalBytes != null
                                            ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes!
                                            : null,
                                      ),
                                    );
                                  },
                                  errorBuilder: (context, error, stackTrace) => Container(
                                    color: Colors.grey.shade200,
                                    child: const Icon(Icons.broken_image, color: Colors.grey),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            right: 0,
                            top: 0,
                            child: GestureDetector(
                              onTap: () => _downloadCariImage(entry.value),
                              child: Container(
                                decoration: const BoxDecoration(color: Colors.blue, shape: BoxShape.circle),
                                padding: const EdgeInsets.all(4),
                                child: const Icon(Icons.download, size: 12, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _yeniHareketDialog() async {
    final tutarCtrl = TextEditingController();
    final aciklamaCtrl = TextEditingController();
    final tarihCtrl = TextEditingController(text: DateFormat('dd.MM.yyyy').format(DateTime.now()));
    DateTime selectedDate = DateTime.now();
    String tip = 'borc';
    String paraBirimi = 'TL';
    final kurUSDCtrl = TextEditingController();
    final kurEURCtrl = TextEditingController();
    final kurGBPCtrl = TextEditingController();
    final altinKurCtrl = TextEditingController();
    final List<XFile> selectedImages = [];

    if (!mounted || !context.mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Yeni Hareket'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: RadioListTile<String>(
                        title: const Text('Ödeme', style: TextStyle(fontSize: 13)),
                        value: 'borc',
                        groupValue: tip,
                        onChanged: (v) => setState(() => tip = v!),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    Expanded(
                      child: RadioListTile<String>(
                        title: const Text('Tahsilat', style: TextStyle(fontSize: 13)),
                        value: 'alacak',
                        groupValue: tip,
                        onChanged: (v) => setState(() => tip = v!),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
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
                  controller: tutarCtrl,
                  decoration: InputDecoration(
                    labelText: 'Tutar ($paraBirimi) *',
                    border: const OutlineInputBorder(),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                  onChanged: (value) {
                    if (paraBirimi != 'TL') {
                      setState(() {});
                    }
                  },
                ),
                if (paraBirimi == 'USD') ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: kurUSDCtrl,
                    decoration: const InputDecoration(
                      labelText: 'USD Kuru (TL) *',
                      border: OutlineInputBorder(),
                      hintText: 'Örn: 34,50',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                    onChanged: (val) => setState(() {}),
                  ),
                ],
                if (paraBirimi == 'EUR') ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: kurEURCtrl,
                    decoration: const InputDecoration(
                      labelText: 'EUR Kuru (TL) *',
                      border: OutlineInputBorder(),
                      hintText: 'Örn: 37,50',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                    onChanged: (val) => setState(() {}),
                  ),
                ],
                if (paraBirimi == 'GBP') ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: kurGBPCtrl,
                    decoration: const InputDecoration(
                      labelText: 'GBP Kuru (TL) *',
                      border: OutlineInputBorder(),
                      hintText: 'Örn: 43,50',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                    onChanged: (val) => setState(() {}),
                  ),
                ],
                if (paraBirimi == 'ALTIN') ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: altinKurCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Gram Fiyatı (TL) *',
                      border: OutlineInputBorder(),
                      hintText: 'Örn: 2.850,00',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                    onChanged: (val) => setState(() {}),
                  ),
                ],
                if (paraBirimi != 'TL') ...[
                  const SizedBox(height: 8),
                  Builder(
                    builder: (context) {
                      final tutar = parseFormatted(tutarCtrl.text);
                      double kur = 0;
                      if (paraBirimi == 'USD') {
                        kur = parseFormatted(kurUSDCtrl.text);
                      } else if (paraBirimi == 'EUR') {
                        kur = parseFormatted(kurEURCtrl.text);
                      } else if (paraBirimi == 'GBP') {
                        kur = parseFormatted(kurGBPCtrl.text);
                      } else if (paraBirimi == 'ALTIN') {
                        kur = parseFormatted(altinKurCtrl.text);
                      }
                      
                      if (tutar > 0 && kur > 0) {
                        final tlKarsilik = tutar * kur;
                        return Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.blue.shade200),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Kur: ${formatDecimal(kur, decimals: paraBirimi == 'ALTIN' ? 2 : 4)} TL',
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                              ),
                              Text(
                                '≈ ${formatTL(tlKarsilik)}',
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blue),
                              ),
                            ],
                          ),
                        );
                      }
                      return const SizedBox();
                    },
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: aciklamaCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Açıklama',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: tarihCtrl,
                  readOnly: true,
                  decoration: InputDecoration(
                    labelText: 'Tarih',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.calendar_today),
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: selectedDate,
                          firstDate: DateTime(2000),
                          lastDate: DateTime.now(),
                        );
                        if (picked != null) {
                          selectedDate = picked;
                          tarihCtrl.text = DateFormat('dd.MM.yyyy').format(picked);
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: () async {
                    final picker = ImagePicker();
                    final pickedFile = await picker.pickImage(source: ImageSource.camera);
                    if (pickedFile != null) {
                      setState(() => selectedImages.add(pickedFile));
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
                      setState(() => selectedImages.addAll(pickedFiles));
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
                    runSpacing: 8,
                    children: selectedImages.asMap().entries.map((entry) {
                      return Stack(
                        children: [
                          FutureBuilder<Widget>(
                            future: _buildCariImageWidget(entry.value),
                            builder: (context, snapshot) {
                              if (snapshot.hasData) return snapshot.data!;
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
                              onTap: () => setState(() => selectedImages.removeAt(entry.key)),
                              child: Container(
                                decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                                child: const Icon(Icons.close, size: 16, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ],
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
                final tutar = parseFormatted(tutarCtrl.text);
                if (tutar <= 0) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Geçerli bir tutar girin')),
                  );
                  return;
                }

                double tutarTL = tutar;
                double kur = 1.0;
                if (paraBirimi != 'TL') {
                  if (paraBirimi == 'USD') {
                    kur = parseFormatted(kurUSDCtrl.text);
                  } else if (paraBirimi == 'EUR') {
                    kur = parseFormatted(kurEURCtrl.text);
                  } else if (paraBirimi == 'GBP') {
                    kur = parseFormatted(kurGBPCtrl.text);
                  } else if (paraBirimi == 'ALTIN') {
                    kur = parseFormatted(altinKurCtrl.text);
                  }
                  
                  if (kur <= 0) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(
                        content: Text(
                          paraBirimi == 'ALTIN'
                              ? 'Gram fiyatını girin (TL)'
                              : '$paraBirimi kurunu girin (TL)',
                        ),
                      ),
                    );
                    return;
                  }
                  
                  tutarTL = tutar * kur;
                }

                try {
                  final List<String> photoUrls = [];
                  if (selectedImages.isNotEmpty) {
                    for (var i = 0; i < selectedImages.length; i++) {
                      final fileName = 'cari_${widget.cariId}_${DateTime.now().millisecondsSinceEpoch}_$i.jpg';
                      final storageRef = FirebaseService().getStorageRef('cari_hareketler/$fileName');
                      
                      final compressedList = await compressImage(selectedImages[i]);
                      final compressedBytes = Uint8List.fromList(compressedList);
                      
                      final url = await uploadToStorage(
                        storageRef,
                        compressedBytes,
                        SettableMetadata(contentType: 'image/jpeg'),
                      );
                      photoUrls.add(url);
                    }
                  }

                  String? giderId;
                  String? financeTransactionId;
                  String projeId = '';
                  String projeAd = '';
                  
                  // Eğer ödeme veya tahsilat ise giderlere kaydet
                  if (tip == 'borc' || tip == 'alacak') {
                    var projectId = '';
                    
                    // Proje içinden açıldıysa o projeyi kullan
                    if (widget.projectId != null && widget.projectId!.isNotEmpty) {
                      projectId = widget.projectId!;
                      projeId = projectId;
                      try {
                        final projeDoc = await FirebaseFirestore.instance.collection('projects').doc(projectId).get();
                        projeAd = projeDoc.data()?['name'] ?? 'Proje';
                      } catch (_) {
                        projeAd = 'Proje';
                      }
                    } else {
                      // Cariler sekmesinden açıldıysa proje seçtir
                      if (!mounted) return;
                      final projects = await FirebaseFirestore.instance
                          .collection('projects')
                          .where('companyId', isEqualTo: SistemYoneticisi().aktifSirket?.id ?? '')
                          .get();
                    
                      if (projects.docs.length == 1) {
                        projectId = projects.docs.first.id;
                        projeId = projectId;
                        projeAd = projects.docs.first.data()['name'] ?? 'Proje';
                      } else if (projects.docs.isNotEmpty && mounted) {
                        final selected = await showDialog<Map<String, String>>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Proje Seç'),
                            content: SingleChildScrollView(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: projects.docs.map((doc) {
                                  final pAd = doc.data()['name'] ?? 'İsimsiz';
                                  return ListTile(
                                    title: Text(pAd),
                                    onTap: () => Navigator.pop(ctx, {'id': doc.id, 'ad': pAd}),
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                        );
                        
                        if (selected != null) {
                          projectId = selected['id']!;
                          projeId = projectId;
                          projeAd = selected['ad']!;
                        }
                      }
                    } // else bloğunun sonu
                    
                    // Seçilen projeyi cari'nin projectIds listesine ekle
                    if (projectId.isNotEmpty) {
                      await FirebaseFirestore.instance
                          .collection('cari_hesaplar')
                          .doc(widget.cariId)
                          .update({
                            'projectIds': FieldValue.arrayUnion([projectId]),
                          });
                    }
                    
                    // ProjectId varsa gelir/gider kaydet
                    if (projectId.isNotEmpty) {
                      if (tip == 'borc') {
                        // ÖDEME (GİDER)
                        // Global giderler'e kaydet
                        final giderDoc = await FirebaseFirestore.instance.collection('giderler').add({
                          'aciklama': 'Cari Ödeme: ${widget.cariAd}${aciklamaCtrl.text.trim().isNotEmpty ? ' - ${aciklamaCtrl.text.trim()}' : ''}',
                          'tutar': tutarTL,
                          'kategori': 'Cari Ödeme',
                          'tarih': selectedDate,
                          'olusturmaTarihi': FieldValue.serverTimestamp(),
                          'projectId': projectId,
                          'cariId': widget.cariId,
                          'cariAd': widget.cariAd,
                          'paraBirimi': paraBirimi,
                          'orijinalTutar': tutar,
                          'kur': kur,
                          'sirketId': SistemYoneticisi().aktifSirket?.id ?? '',
                        });
                        giderId = giderDoc.id;
                        
                        // Proje giderlerine de kaydet
                        await FirebaseFirestore.instance
                            .collection('teklifler')
                            .doc(projectId)
                            .collection('giderler')
                            .add({
                              'kategori': 'Cari Ödeme',
                              'altKategori': widget.cariAd,
                              'tutar': tutarTL,
                              'aciklama': aciklamaCtrl.text.trim().isNotEmpty ? aciklamaCtrl.text.trim() : 'Cari ödeme',
                              'tarih': selectedDate,
                              'foto': null,
                            });
                      } else if (tip == 'alacak') {
                        // TAHSİLAT (GELİR)
                        // Global gelirler'e kaydet
                        final gelirDoc = await FirebaseFirestore.instance.collection('gelirler').add({
                          'aciklama': 'Cari Tahsilat: ${widget.cariAd}${aciklamaCtrl.text.trim().isNotEmpty ? ' - ${aciklamaCtrl.text.trim()}' : ''}',
                          'tutar': tutarTL,
                          'kategori': 'Cari Tahsilat',
                          'tarih': selectedDate,
                          'olusturmaTarihi': FieldValue.serverTimestamp(),
                          'projectId': projectId,
                          'cariId': widget.cariId,
                          'cariAd': widget.cariAd,
                          'paraBirimi': paraBirimi,
                          'orijinalTutar': tutar,
                          'kur': kur,
                          'sirketId': SistemYoneticisi().aktifSirket?.id ?? '',
                        });
                        giderId = gelirDoc.id;
                        
                        // Proje gelirlerine de kaydet
                        await FirebaseFirestore.instance
                            .collection('teklifler')
                            .doc(projectId)
                            .collection('gelirler')
                            .add({
                              'kategori': 'Cari Tahsilat',
                              'altKategori': widget.cariAd,
                              'tutar': tutarTL,
                              'aciklama': aciklamaCtrl.text.trim().isNotEmpty ? aciklamaCtrl.text.trim() : 'Cari tahsilat',
                              'tarih': selectedDate,
                              'foto': null,
                            });
                      }
                      
                      // Project Finance tablosuna kaydet
                      final transactionRef = FirebaseFirestore.instance
                          .collection('project_finance')
                          .doc(projectId)
                          .collection('transactions')
                          .doc();
                      financeTransactionId = transactionRef.id;
                      
                      await transactionRef.set({
                        'id': transactionRef.id,
                        'type': tip == 'borc' ? 'expense' : 'income',
                        'amount': tutarTL,
                        'category': tip == 'borc' ? 'other' : 'other',
                        'description': tip == 'borc' 
                            ? 'Cari Ödeme: ${widget.cariAd}${aciklamaCtrl.text.trim().isNotEmpty ? ' - ${aciklamaCtrl.text.trim()}' : ''}'
                            : 'Cari Tahsilat: ${widget.cariAd}${aciklamaCtrl.text.trim().isNotEmpty ? ' - ${aciklamaCtrl.text.trim()}' : ''}',
                        'date': Timestamp.fromDate(selectedDate),
                        'createdAt': FieldValue.serverTimestamp(),
                      });
                      
                      // Proje finansmanını güncelle
                      final financeDoc = await FirebaseFirestore.instance
                          .collection('project_finance')
                          .doc(projectId)
                          .get();
                      
                      final currentIncome = ((financeDoc.data()?['totalIncome'] ?? 0) as num).toDouble();
                      final currentExpenses = ((financeDoc.data()?['totalExpenses'] ?? 0) as num).toDouble();
                      
                      if (tip == 'borc') {
                        await FirebaseFirestore.instance
                            .collection('project_finance')
                            .doc(projectId)
                            .set({
                              'totalExpenses': currentExpenses + tutarTL,
                            }, SetOptions(merge: true));
                      } else if (tip == 'alacak') {
                        await FirebaseFirestore.instance
                            .collection('project_finance')
                            .doc(projectId)
                            .set({
                              'totalIncome': currentIncome + tutarTL,
                            }, SetOptions(merge: true));
                      }
                    }
                  }

                  // Bakiye güncelleme ve hareket eklemeyi paralel yap
                  final cariDoc = await FirebaseFirestore.instance
                      .collection('cari_hesaplar')
                      .doc(widget.cariId)
                      .get();
                  
                  final mevcutBakiye = ((cariDoc.data()?['bakiye'] ?? 0) as num).toDouble();
                  final yeniBakiye = tip == 'alacak' 
                      ? mevcutBakiye + tutarTL 
                      : mevcutBakiye - tutarTL;

                  // Hareket ekle ve bakiye güncelle paralel yap
                  final hareketAdd = FirebaseFirestore.instance
                      .collection('cari_hesaplar')
                      .doc(widget.cariId)
                      .collection('hareketler')
                      .add({
                    'tip': tip,
                    'tutar': tutar,
                    'tutarTL': tutarTL,
                    'paraBirimi': paraBirimi,
                    'kur': kur,
                    'aciklama': aciklamaCtrl.text.trim(),
                    'tarih': selectedDate,
                    'fotoUrls': photoUrls,
                    'giderId': giderId,
                    'financeTransactionId': financeTransactionId,
                    'projeId': projeId.isNotEmpty ? projeId : 'manuel',
                    'projeAd': projeAd,
                  });
                  
                  final bakiyeUpdate = FirebaseFirestore.instance
                      .collection('cari_hesaplar')
                      .doc(widget.cariId)
                      .update({'bakiye': yeniBakiye});
                  
                  await Future.wait([hareketAdd, bakiyeUpdate]);

                  if (!ctx.mounted || !mounted) return;
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Hareket kaydedildi')),
                  );
                } catch (e) {
                  if (!ctx.mounted) return;
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text(hataCevir(e))),
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

  Future<void> _hareketDuzenle(String hareketId, Map<String, dynamic> mevcutData) async {
    final tutarCtrl = TextEditingController(text: formatDecimal((mevcutData['tutar'] ?? 0.0) as num));
    final aciklamaCtrl = TextEditingController(text: mevcutData['aciklama'] ?? '');
    
    final mevcutTarih = mevcutData['tarih'] != null 
        ? (mevcutData['tarih'] as Timestamp).toDate() 
        : DateTime.now();
    final tarihCtrl = TextEditingController(text: DateFormat('dd.MM.yyyy').format(mevcutTarih));
    DateTime selectedDate = mevcutTarih;
    
    String tip = mevcutData['tip'] ?? 'borc';
    String paraBirimi = mevcutData['paraBirimi'] ?? 'TL';
    double mevcutKur = ((mevcutData['kur'] ?? 1.0) as num).toDouble();
    
    final kurUSDCtrl = TextEditingController(text: paraBirimi == 'USD' ? formatDecimal(mevcutKur, decimals: 4) : '');
    final kurEURCtrl = TextEditingController(text: paraBirimi == 'EUR' ? formatDecimal(mevcutKur, decimals: 4) : '');
    final kurGBPCtrl = TextEditingController(text: paraBirimi == 'GBP' ? formatDecimal(mevcutKur, decimals: 4) : '');
    final altinKurCtrl = TextEditingController(text: paraBirimi == 'ALTIN' ? formatDecimal(mevcutKur, decimals: 2) : '');
    
    final mevcutFotoUrls = List<String>.from(mevcutData['fotoUrls'] ?? []);
    // final List<XFile> selectedImages = [];

    if (!mounted || !context.mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Hareketi Düzenle'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: RadioListTile<String>(
                        title: const Text('Ödeme', style: TextStyle(fontSize: 13)),
                        value: 'borc',
                        groupValue: tip,
                        onChanged: (v) => setState(() => tip = v!),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    Expanded(
                      child: RadioListTile<String>(
                        title: const Text('Tahsilat', style: TextStyle(fontSize: 13)),
                        value: 'alacak',
                        groupValue: tip,
                        onChanged: (v) => setState(() => tip = v!),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: paraBirimi,
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
                  controller: tutarCtrl,
                  decoration: InputDecoration(
                    labelText: 'Tutar ($paraBirimi) *',
                    border: const OutlineInputBorder(),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                  onChanged: (value) {
                    if (paraBirimi != 'TL') {
                      setState(() {});
                    }
                  },
                ),
                if (paraBirimi == 'USD') ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: kurUSDCtrl,
                    decoration: const InputDecoration(
                      labelText: 'USD Kuru (TL) *',
                      border: OutlineInputBorder(),
                      hintText: 'Örn: 34,50',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                    onChanged: (val) => setState(() {}),
                  ),
                ],
                if (paraBirimi == 'EUR') ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: kurEURCtrl,
                    decoration: const InputDecoration(
                      labelText: 'EUR Kuru (TL) *',
                      border: OutlineInputBorder(),
                      hintText: 'Örn: 37,50',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                    onChanged: (val) => setState(() {}),
                  ),
                ],
                if (paraBirimi == 'GBP') ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: kurGBPCtrl,
                    decoration: const InputDecoration(
                      labelText: 'GBP Kuru (TL) *',
                      border: OutlineInputBorder(),
                      hintText: 'Örn: 43,50',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                    onChanged: (val) => setState(() {}),
                  ),
                ],
                if (paraBirimi == 'ALTIN') ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: altinKurCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Gram Fiyatı (TL) *',
                      border: OutlineInputBorder(),
                      hintText: 'Örn: 2.850,00',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                    onChanged: (val) => setState(() {}),
                  ),
                ],
                if (paraBirimi != 'TL') ...[
                  const SizedBox(height: 8),
                  Builder(
                    builder: (context) {
                      final tutar = parseFormatted(tutarCtrl.text);
                      double kur = 0;
                      if (paraBirimi == 'USD') {
                        kur = parseFormatted(kurUSDCtrl.text);
                      } else if (paraBirimi == 'EUR') {
                        kur = parseFormatted(kurEURCtrl.text);
                      } else if (paraBirimi == 'GBP') {
                        kur = parseFormatted(kurGBPCtrl.text);
                      } else if (paraBirimi == 'ALTIN') {
                        kur = parseFormatted(altinKurCtrl.text);
                      }
                      
                      if (tutar > 0 && kur > 0) {
                        final tlKarsilik = tutar * kur;
                        return Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.blue.shade200),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Kur: ${formatDecimal(kur, decimals: paraBirimi == 'ALTIN' ? 2 : 4)} TL',
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                              ),
                              Text(
                                '≈ ${formatTL(tlKarsilik)}',
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blue),
                              ),
                            ],
                          ),
                        );
                      }
                      return const SizedBox();
                    },
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: aciklamaCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Açıklama',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: tarihCtrl,
                  readOnly: true,
                  decoration: InputDecoration(
                    labelText: 'Tarih',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.calendar_today),
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: selectedDate,
                          firstDate: DateTime(2000),
                          lastDate: DateTime.now(),
                        );
                        if (picked != null) {
                          selectedDate = picked;
                          tarihCtrl.text = DateFormat('dd.MM.yyyy').format(picked);
                        }
                      },
                    ),
                  ),
                ),
                if (mevcutFotoUrls.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('Mevcut Fotoğraflar:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: mevcutFotoUrls.map((url) {
                      return Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(url, fit: BoxFit.cover),
                        ),
                      );
                    }).toList(),
                  ),
                ],
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
                final tutar = parseFormatted(tutarCtrl.text);
                if (tutar <= 0) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Geçerli bir tutar girin')),
                  );
                  return;
                }

                double tutarTL = tutar;
                double kur = 1.0;
                if (paraBirimi != 'TL') {
                  if (paraBirimi == 'USD') {
                    kur = parseFormatted(kurUSDCtrl.text);
                  } else if (paraBirimi == 'EUR') {
                    kur = parseFormatted(kurEURCtrl.text);
                  } else if (paraBirimi == 'GBP') {
                    kur = parseFormatted(kurGBPCtrl.text);
                  } else if (paraBirimi == 'ALTIN') {
                    kur = parseFormatted(altinKurCtrl.text);
                  }
                  
                  if (kur <= 0) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(
                        content: Text(
                          paraBirimi == 'ALTIN'
                              ? 'Gram fiyatını girin (TL)'
                              : '$paraBirimi kurunu girin (TL)',
                        ),
                      ),
                    );
                    return;
                  }
                  
                  tutarTL = tutar * kur;
                }

                try {
                  // Eski ve yeni tip karşılaştır
                  final eskiTip = mevcutData['tip'];
                  final eskiTutarTL = ((mevcutData['tutarTL'] ?? mevcutData['tutar'] ?? 0.0) as num).toDouble();
                  final eskiGiderId = mevcutData['giderId'];

                  // Gider kaydını güncelle veya oluştur/sil
                  String? yeniGiderId = eskiGiderId;
                  
                  if (tip == 'borc') {
                    // Ödeme - gider olmalı
                    if (eskiGiderId != null) {
                      // Mevcut gideri güncelle
                      await FirebaseFirestore.instance.collection('giderler').doc(eskiGiderId).update({
                        'aciklama': 'Cari Ödeme: ${widget.cariAd}${aciklamaCtrl.text.trim().isNotEmpty ? ' - ${aciklamaCtrl.text.trim()}' : ''}',
                        'tutar': tutarTL,
                        'tarih': selectedDate,
                        'paraBirimi': paraBirimi,
                        'orijinalTutar': tutar,
                        'kur': kur,
                      });
                    } else {
                      // Yeni gider oluştur
                      final giderDoc = await FirebaseFirestore.instance.collection('giderler').add({
                        'aciklama': 'Cari Ödeme: ${widget.cariAd}${aciklamaCtrl.text.trim().isNotEmpty ? ' - ${aciklamaCtrl.text.trim()}' : ''}',
                        'tutar': tutarTL,
                        'kategori': 'Cari Ödeme',
                        'tarih': selectedDate,
                        'olusturmaTarihi': FieldValue.serverTimestamp(),
                        'cariId': widget.cariId,
                        'cariAd': widget.cariAd,
                        'paraBirimi': paraBirimi,
                        'orijinalTutar': tutar,
                        'kur': kur,
                        'sirketId': SistemYoneticisi().aktifSirket?.id ?? '',
                      });
                      yeniGiderId = giderDoc.id;
                    }
                  } else if (eskiGiderId != null) {
                    // Tahsilat'a çevrildi - eski gideri sil
                    await FirebaseFirestore.instance.collection('giderler').doc(eskiGiderId).delete();
                    yeniGiderId = null;
                  }

                  // Cari ve Finance dokümantasyon paralel al
                  final cariDocFuture = FirebaseFirestore.instance
                      .collection('cari_hesaplar')
                      .doc(widget.cariId)
                      .get();
                  
                  final results = await Future.wait([cariDocFuture]);
                  final cariDoc = results[0] as DocumentSnapshot;
                  
                  final mevcutBakiye = ((cariDoc.data() is Map ? (cariDoc.data() as Map)['bakiye'] ?? 0 : 0) as num).toDouble();
                  
                  // Eski hareketi geri al
                  double yeniBakiye = mevcutBakiye;
                  if (eskiTip == 'alacak') {
                    yeniBakiye -= eskiTutarTL;
                  } else {
                    yeniBakiye += eskiTutarTL;
                  }
                  
                  // Yeni hareketi uygula
                  if (tip == 'alacak') {
                    yeniBakiye += tutarTL;
                  } else {
                    yeniBakiye -= tutarTL;
                  }

                  // Tüm updateler paralel yap
                  final hareketUpdate = FirebaseFirestore.instance
                      .collection('cari_hesaplar')
                      .doc(widget.cariId)
                      .collection('hareketler')
                      .doc(hareketId)
                      .update({
                    'tip': tip,
                    'tutar': tutar,
                    'tutarTL': tutarTL,
                    'paraBirimi': paraBirimi,
                    'kur': kur,
                    'aciklama': aciklamaCtrl.text.trim(),
                    'tarih': selectedDate,
                    'giderId': yeniGiderId,
                  });
                  
                  final bakiyeUpdate = FirebaseFirestore.instance
                      .collection('cari_hesaplar')
                      .doc(widget.cariId)
                      .update({'bakiye': yeniBakiye});
                  
                  final updateList = [hareketUpdate, bakiyeUpdate];
                  
                  // Gider silme işlemi varsa ekle
                  if (eskiGiderId != null) {
                    updateList.add(FirebaseFirestore.instance.collection('giderler').doc(eskiGiderId).delete());
                  }

                  // Project Finance'ı güncelle (eğer cariye proje atanmışsa)
                  final projectId = cariDoc.data() is Map ? (cariDoc.data() as Map)['projectId'] as String? : null;
                  
                  if (projectId != null && projectId.isNotEmpty) {
                    final financeDoc = await FirebaseFirestore.instance
                        .collection('project_finance')
                        .doc(projectId)
                        .get();
                    
                    var currentIncome = ((financeDoc.data()?['totalIncome'] ?? 0) as num).toDouble();
                    var currentExpenses = ((financeDoc.data()?['totalExpenses'] ?? 0) as num).toDouble();
                    
                    // Eski hareketi reverse et
                    if (eskiTip == 'alacak') {
                      currentIncome -= eskiTutarTL;
                    } else if (eskiTip == 'borc') {
                      currentExpenses -= eskiTutarTL;
                    }
                    
                    // Yeni hareketi uygula
                    if (tip == 'alacak') {
                      currentIncome += tutarTL;
                    } else if (tip == 'borc') {
                      currentExpenses += tutarTL;
                    }
                    
                    updateList.add(FirebaseFirestore.instance
                        .collection('project_finance')
                        .doc(projectId)
                        .set({
                          'totalIncome': currentIncome,
                          'totalExpenses': currentExpenses,
                        }, SetOptions(merge: true)));
                  }
                  
                  // Tüm update işlemlerini paralel yap
                  await Future.wait(updateList);

                  if (!ctx.mounted || !mounted) return;
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Hareket güncellendi')),
                  );
                } catch (e) {
                  if (!ctx.mounted) return;
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text(hataCevir(e))),
                  );
                }
              },
              child: const Text('Güncelle'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _hareketSil(String hareketId, double tutarTL, String tip, String? giderId) async {
    final onay = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hareket Sil'),
        content: const Text('Bu hareketi silmek istediğinize emin misiniz?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Sil'),
          ),
        ],
      ),
    );

    if (onay == true) {
      try {
        // Hareket dokümanını ve cari dokümanını paralel al
        final hareketDocFuture = FirebaseFirestore.instance
            .collection('cari_hesaplar')
            .doc(widget.cariId)
            .collection('hareketler')
            .doc(hareketId)
            .get();
        final cariDocFuture = FirebaseFirestore.instance
            .collection('cari_hesaplar')
            .doc(widget.cariId)
            .get();
        
        final results = await Future.wait([hareketDocFuture, cariDocFuture]);
        final hareketDoc = results[0] as DocumentSnapshot;
        final cariDoc = results[1] as DocumentSnapshot;
        final hareketData = hareketDoc.data() as Map<String, dynamic>?;
        
        final mevcutBakiye = (((cariDoc.data() as Map<String, dynamic>?)?['bakiye'] ?? 0) as num).toDouble();
        final yeniBakiye = tip == 'alacak' 
            ? mevcutBakiye - tutarTL 
            : mevcutBakiye + tutarTL;

        // Silme ve güncelleme işlemlerini hazırla
        final List<Future<void>> deleteList = [];
        
        // Gelir/Gider kaydını sil (tip'e göre doğru koleksiyon)
        if (giderId != null) {
          if (tip == 'alacak') {
            deleteList.add(FirebaseFirestore.instance.collection('gelirler').doc(giderId).delete());
          } else {
            deleteList.add(FirebaseFirestore.instance.collection('giderler').doc(giderId).delete());
          }
        }
        
        // Hareketi sil
        deleteList.add(FirebaseFirestore.instance
            .collection('cari_hesaplar')
            .doc(widget.cariId)
            .collection('hareketler')
            .doc(hareketId)
            .delete());
        
        // Bakiye güncelle
        deleteList.add(FirebaseFirestore.instance
            .collection('cari_hesaplar')
            .doc(widget.cariId)
            .update({'bakiye': yeniBakiye}));

        // Project Finance'ı güncelle (eğer cariye proje atanmışsa)
        final cariData = cariDoc.data() as Map<String, dynamic>?;
        final projectId = cariData?['projectId'] as String?;
        
        if (projectId != null && projectId.isNotEmpty) {
          // project_finance/transactions alt koleksiyonundan sil
          final financeTransactionId = hareketData?['financeTransactionId'] as String?;
          if (financeTransactionId != null) {
            // Yeni hareketler: doğrudan ID ile sil
            deleteList.add(FirebaseFirestore.instance
                .collection('project_finance')
                .doc(projectId)
                .collection('transactions')
                .doc(financeTransactionId)
                .delete());
          } else {
            // Eski hareketler: amount + type ile bul ve sil
            final queryType = tip == 'borc' ? 'expense' : 'income';
            final matchingTx = await FirebaseFirestore.instance
                .collection('project_finance')
                .doc(projectId)
                .collection('transactions')
                .where('amount', isEqualTo: tutarTL)
                .where('type', isEqualTo: queryType)
                .limit(1)
                .get();
            for (final doc in matchingTx.docs) {
              deleteList.add(doc.reference.delete());
            }
          }

          // Toplam gelir/gider güncelle
          final financeDoc = await FirebaseFirestore.instance
              .collection('project_finance')
              .doc(projectId)
              .get();
          
          var currentIncome = ((financeDoc.data()?['totalIncome'] ?? 0) as num).toDouble();
          var currentExpenses = ((financeDoc.data()?['totalExpenses'] ?? 0) as num).toDouble();
          
          if (tip == 'alacak') {
            currentIncome = (currentIncome - tutarTL).clamp(0, double.infinity);
          } else if (tip == 'borc') {
            currentExpenses = (currentExpenses - tutarTL).clamp(0, double.infinity);
          }
          
          deleteList.add(FirebaseFirestore.instance
              .collection('project_finance')
              .doc(projectId)
              .set({
                'totalIncome': currentIncome,
                'totalExpenses': currentExpenses,
              }, SetOptions(merge: true)));
        }

        // Tüm işlemleri paralel yap
        await Future.wait(deleteList);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Hareket silindi')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(hataCevir(e))),
          );
        }
      }
    }
  }

  // ── Taksit Planları Widget ──
  Widget _taksitPlanlariWidget() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('cari_hesaplar')
          .doc(widget.cariId)
          .collection('taksit_planlari')
          .orderBy('olusturmaTarihi', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }
        final planlar = snapshot.data!.docs;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Divider(height: 1),
              const SizedBox(height: 8),
              Text('Taksit Planları (${planlar.length})',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.blueGrey)),
              const SizedBox(height: 4),
              ...planlar.map((planDoc) {
                final plan = planDoc.data() as Map<String, dynamic>;
                final tip = plan['tip'] ?? 'tahsilat';
                final toplamTutar = ((plan['toplamTutar'] ?? 0) as num).toDouble();
                final taksitSayisi = plan['taksitSayisi'] ?? 0;
                final projeAd = plan['projeAd'] ?? '';
                final aciklama = plan['aciklama'] ?? '';
                final isTahsilat = tip == 'tahsilat';

                return StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('cari_hesaplar')
                      .doc(widget.cariId)
                      .collection('taksit_planlari')
                      .doc(planDoc.id)
                      .collection('taksitler')
                      .orderBy('sira')
                      .snapshots(),
                  builder: (context, taksitSnap) {
                    final taksitler = taksitSnap.data?.docs ?? [];
                    int odenen = taksitler.where((t) => (t.data() as Map)['odendi'] == true).length;
                    double odenenTutarToplam = 0;
                    for (var t in taksitler) {
                      final td = t.data() as Map<String, dynamic>;
                      odenenTutarToplam += ((td['odenenTutar'] ?? 0) as num).toDouble();
                    }
                    final kalanTutar = (toplamTutar - odenenTutarToplam).clamp(0.0, double.infinity);
                    final tamamlandi = odenen == taksitSayisi && taksitSayisi > 0;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(color: tamamlandi ? Colors.green.shade200 : Colors.grey.shade200),
                      ),
                      color: tamamlandi ? Colors.green.shade50 : null,
                      child: ExpansionTile(
                        leading: Icon(
                          isTahsilat ? Icons.arrow_downward : Icons.arrow_upward,
                          color: isTahsilat ? Colors.green : Colors.red,
                          size: 20,
                        ),
                        title: Text(
                          '${isTahsilat ? "Tahsilat" : "Ödeme"} Planı — ${formatTL(toplamTutar)}',
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                        subtitle: Text(
                          '${projeAd.isNotEmpty ? "$projeAd • " : ""}$odenen/$taksitSayisi taksit • Kalan: ${formatTL(kalanTutar)}${aciklama.isNotEmpty ? " • $aciklama" : ""}',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        children: [
                          if (taksitler.isNotEmpty)
                            ...taksitler.map((taksitDoc) {
                              final t = taksitDoc.data() as Map<String, dynamic>;
                              final sira = t['sira'] ?? 0;
                              final tutar = ((t['tutar'] ?? 0) as num).toDouble();
                              final odenenTutarT = ((t['odenenTutar'] ?? 0) as num).toDouble();
                              final odendi = t['odendi'] == true;
                              final kismi = !odendi && odenenTutarT > 0;
                              final vadeTarihi = t['vadeTarihi'] is Timestamp
                                  ? (t['vadeTarihi'] as Timestamp).toDate()
                                  : DateTime.now();
                              final gecikmi = !odendi && vadeTarihi.isBefore(DateTime.now());

                              Color bg;
                              Widget leading;
                              if (odendi) {
                                bg = Colors.green.shade100;
                                leading = Icon(Icons.check, size: 16, color: Colors.green.shade700);
                              } else if (kismi) {
                                bg = Colors.amber.shade100;
                                leading = Icon(Icons.adjust, size: 16, color: Colors.amber.shade800);
                              } else if (gecikmi) {
                                bg = Colors.red.shade100;
                                leading = Text('$sira', style: TextStyle(
                                    fontSize: 11, fontWeight: FontWeight.bold, color: Colors.red));
                              } else {
                                bg = Colors.grey.shade100;
                                leading = Text('$sira', style: TextStyle(
                                    fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey.shade700));
                              }

                              return ListTile(
                                dense: true,
                                leading: CircleAvatar(radius: 14, backgroundColor: bg, child: leading),
                                title: Text(
                                  '${formatTL(tutar)} — ${DateFormat('dd.MM.yyyy').format(vadeTarihi)}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    decoration: odendi ? TextDecoration.lineThrough : null,
                                    color: odendi ? Colors.grey : (gecikmi ? Colors.red : null),
                                  ),
                                ),
                                subtitle: kismi
                                    ? Text('Yatan: ${formatTL(odenenTutarT)} • Kalan: ${formatTL(tutar - odenenTutarT)}',
                                        style: TextStyle(fontSize: 10, color: Colors.amber.shade800, fontWeight: FontWeight.w600))
                                    : null,
                                trailing: odendi
                                    ? Text('Ödendi', style: TextStyle(fontSize: 10, color: Colors.green.shade700, fontWeight: FontWeight.bold))
                                    : (gecikmi
                                        ? Text('Gecikmiş', style: TextStyle(fontSize: 10, color: Colors.red.shade700, fontWeight: FontWeight.bold))
                                        : null),
                              );
                            }),
                          // Tek buton: Tahsilat / Ödeme Yap
                          if (!tamamlandi)
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              child: SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: () => _taksitliPlanaTopluTahsilat(
                                      planDoc.id, plan, taksitler, kalanTutar),
                                  icon: Icon(isTahsilat ? Icons.payments_outlined : Icons.upload_outlined, size: 18),
                                  label: Text(isTahsilat ? 'Tahsilat Yap' : 'Ödeme Yap'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: isTahsilat ? Colors.green : Colors.red,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                  ),
                                ),
                              ),
                            ),
                          // Plan sil butonu
                          if (!tamamlandi)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8, right: 16),
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: TextButton.icon(
                                  onPressed: () => _taksitPlanSil(planDoc.id),
                                  icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
                                  label: const Text('Planı Sil', style: TextStyle(fontSize: 11, color: Colors.red)),
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                );
              }),
              const SizedBox(height: 4),
            ],
          ),
        );
      },
    );
  }

  // ── Taksitli Plan Oluştur Dialog ──
  Future<void> _taksitliPlanOlusturDialog() async {
    final toplamCtrl = TextEditingController();
    final taksitSayisiCtrl = TextEditingController(text: '12');
    final aciklamaCtrl = TextEditingController();
    DateTime baslangicTarihi = DateTime.now().add(const Duration(days: 30));
    String tip = 'tahsilat';
    String projeId = widget.projectId ?? '';
    String projeAd = '';

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Taksitli Plan Oluştur'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: RadioListTile<String>(
                        title: const Text('Tahsilat', style: TextStyle(fontSize: 13)),
                        value: 'tahsilat',
                        groupValue: tip,
                        onChanged: (v) => setDialogState(() => tip = v!),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    Expanded(
                      child: RadioListTile<String>(
                        title: const Text('Ödeme', style: TextStyle(fontSize: 13)),
                        value: 'odeme',
                        groupValue: tip,
                        onChanged: (v) => setDialogState(() => tip = v!),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: toplamCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.,]'))],
                  decoration: const InputDecoration(
                    labelText: 'Toplam Tutar (₺)',
                    border: OutlineInputBorder(),
                    prefixText: '₺ ',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: taksitSayisiCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Taksit Sayısı',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: baslangicTarihi,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 3650)),
                    );
                    if (picked != null) {
                      setDialogState(() => baslangicTarihi = picked);
                    }
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'İlk Taksit Tarihi',
                      border: OutlineInputBorder(),
                      suffixIcon: Icon(Icons.calendar_today),
                    ),
                    child: Text(DateFormat('dd.MM.yyyy').format(baslangicTarihi)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: aciklamaCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Açıklama (opsiyonel)',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (projeId.isEmpty) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final projects = await FirebaseFirestore.instance
                          .collection('projects')
                          .where('companyId', isEqualTo: SistemYoneticisi().aktifSirket?.id ?? '')
                          .get();
                      if (!ctx.mounted) return;
                      final selected = await showDialog<Map<String, String>>(
                        context: ctx,
                        builder: (c) => AlertDialog(
                          title: const Text('Proje Seç'),
                          content: SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ListTile(
                                  title: const Text('Projesiz (Manuel)', style: TextStyle(fontStyle: FontStyle.italic)),
                                  onTap: () => Navigator.pop(c, {'id': '', 'ad': ''}),
                                ),
                                ...projects.docs.map((doc) {
                                  final pAd = doc.data()['name'] ?? 'İsimsiz';
                                  return ListTile(
                                    title: Text(pAd),
                                    onTap: () => Navigator.pop(c, {'id': doc.id, 'ad': pAd}),
                                  );
                                }),
                              ],
                            ),
                          ),
                        ),
                      );
                      if (selected != null) {
                        setDialogState(() {
                          projeId = selected['id']!;
                          projeAd = selected['ad']!;
                        });
                      }
                    },
                    icon: const Icon(Icons.folder_outlined, size: 18),
                    label: Text(projeAd.isNotEmpty ? projeAd : 'Proje Seç (opsiyonel)', style: const TextStyle(fontSize: 13)),
                  ),
                ],
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
                final toplamStr = toplamCtrl.text.replaceAll('.', '').replaceAll(',', '.');
                final toplam = double.tryParse(toplamStr) ?? 0;
                final taksitSayisi = int.tryParse(taksitSayisiCtrl.text) ?? 0;

                if (toplam <= 0) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Geçerli bir tutar girin')),
                  );
                  return;
                }
                if (taksitSayisi <= 0 || taksitSayisi > 120) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Taksit sayısı 1-120 arası olmalı')),
                  );
                  return;
                }

                try {
                  // Plan oluştur
                  final planRef = await FirebaseFirestore.instance
                      .collection('cari_hesaplar')
                      .doc(widget.cariId)
                      .collection('taksit_planlari')
                      .add({
                    'tip': tip,
                    'toplamTutar': toplam,
                    'taksitSayisi': taksitSayisi,
                    'projeId': projeId,
                    'projeAd': projeAd,
                    'aciklama': aciklamaCtrl.text.trim(),
                    'olusturmaTarihi': FieldValue.serverTimestamp(),
                    'cariAd': widget.cariAd,
                    'sirketId': SistemYoneticisi().aktifSirket?.id ?? '',
                  });

                  // Taksitleri oluştur
                  final taksitTutar = toplam / taksitSayisi;
                  final batch = FirebaseFirestore.instance.batch();
                  for (int i = 0; i < taksitSayisi; i++) {
                    final taksitRef = planRef.collection('taksitler').doc();
                    final vadeTarihi = DateTime(
                      baslangicTarihi.year,
                      baslangicTarihi.month + i,
                      baslangicTarihi.day,
                    );
                    batch.set(taksitRef, {
                      'sira': i + 1,
                      'tutar': double.parse(taksitTutar.toStringAsFixed(2)),
                      'odenenTutar': 0.0,
                      'vadeTarihi': Timestamp.fromDate(vadeTarihi),
                      'odendi': false,
                      'odemeTarihi': null,
                      'hareketId': null,
                    });
                  }
                  await batch.commit();

                  if (!ctx.mounted) return;
                  Navigator.pop(ctx);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('$taksitSayisi taksitli plan oluşturuldu')),
                    );
                  }
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(content: Text(hataCevir(e))),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
              ),
              child: const Text('Oluştur'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Taksitli Plana Toplu Tahsilat / Ödeme ──
  // Kullanıcı bir tutar girer, sıraya göre ödenmemiş/kısmi taksitlere dağıtılır.
  // Kalan veya fazla tutar bir sonraki taksitlere uygulanır. Tek bir cari hareket
  // ve tek bir gelir/gider kaydı oluşturur. Fotoğraf eklenebilir.
  Future<void> _taksitliPlanaTopluTahsilat(
    String planId,
    Map<String, dynamic> planData,
    List<QueryDocumentSnapshot> taksitDocs,
    double kalanToplam,
  ) async {
    final isTahsilat = (planData['tip'] ?? 'tahsilat') == 'tahsilat';
    final projeId = planData['projeId'] ?? '';
    final projeAd = planData['projeAd'] ?? '';

    final tutarCtrl = TextEditingController(text: formatNumber(kalanToplam));
    final aciklamaCtrl = TextEditingController();
    List<XFile> dekontImages = [];

    final result = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDialogState) => AlertDialog(
          title: Text(isTahsilat ? 'Tahsilat Yap' : 'Ödeme Yap'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Plan kalan tutarı: ${formatTL(kalanToplam)}\n'
                  'Girilen tutar sıraya göre taksitlere dağıtılır. '
                  'Eksik yatırılırsa kısmi olarak işlenir, fazla yatırılırsa sonraki taksitlere geçer.',
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 12),
                const Text('Tutar (TL)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 6),
                TextField(
                  controller: tutarCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    prefixText: '₺ ',
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('Açıklama (opsiyonel)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 6),
                TextField(
                  controller: aciklamaCtrl,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'Örn: 3 taksit birden',
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
                const SizedBox(height: 12),
                const Divider(),
                const Text('Dekont / Fotoğraf (opsiyonel)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final picker = ImagePicker();
                          final pickedFile = await picker.pickImage(source: ImageSource.camera);
                          if (pickedFile != null) {
                            setDialogState(() => dekontImages.add(pickedFile));
                          }
                        },
                        icon: const Icon(Icons.camera_alt, size: 16),
                        label: const Text('Çek', style: TextStyle(fontSize: 12)),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.grey.shade700, foregroundColor: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final picker = ImagePicker();
                          final pickedFiles = await picker.pickMultiImage();
                          if (pickedFiles.isNotEmpty) {
                            setDialogState(() => dekontImages.addAll(pickedFiles));
                          }
                        },
                        icon: const Icon(Icons.photo_library, size: 16),
                        label: const Text('Galeri', style: TextStyle(fontSize: 12)),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade600, foregroundColor: Colors.white),
                      ),
                    ),
                  ],
                ),
                if (dekontImages.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('✓ ${dekontImages.length} fotoğraf seçildi',
                      style: TextStyle(color: Colors.green.shade700, fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: dekontImages.asMap().entries.map((entry) {
                      return Stack(
                        children: [
                          FutureBuilder<Widget>(
                            future: _buildCariImageWidget(entry.value),
                            builder: (context, snapshot) {
                              if (snapshot.hasData) return snapshot.data!;
                              return const SizedBox(width: 50, height: 50, child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
                            },
                          ),
                          Positioned(
                            right: 0,
                            top: 0,
                            child: GestureDetector(
                              onTap: () => setDialogState(() => dekontImages.removeAt(entry.key)),
                              child: Container(
                                decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                                child: const Icon(Icons.close, size: 14, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('İptal')),
            ElevatedButton(
              onPressed: () => Navigator.pop(c, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: isTahsilat ? Colors.green : Colors.red,
                foregroundColor: Colors.white,
              ),
              child: Text(isTahsilat ? 'Tahsil Et' : 'Öde'),
            ),
          ],
        ),
      ),
    );

    if (result != true || !mounted) return;

    final girilenTutar = parseFormatted(tutarCtrl.text);
    if (girilenTutar <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Geçerli bir tutar girin')),
      );
      return;
    }

    final tip = isTahsilat ? 'alacak' : 'borc';

    try {
      // 1) Tutarı sıraya göre dağıt
      double kalan = girilenTutar;
      final List<Map<String, dynamic>> dagilim = []; // [{taksitDocRef, eklenenTutar, taksitTumOdendi, sira}]
      for (final taksitDoc in taksitDocs) {
        if (kalan <= 0.001) break;
        final t = taksitDoc.data() as Map<String, dynamic>;
        if (t['odendi'] == true) continue;
        final taksitTutar = ((t['tutar'] ?? 0) as num).toDouble();
        final mevcutOdenen = ((t['odenenTutar'] ?? 0) as num).toDouble();
        final taksitKalan = (taksitTutar - mevcutOdenen).clamp(0.0, double.infinity);
        if (taksitKalan <= 0.001) continue;
        final eklenecek = kalan >= taksitKalan ? taksitKalan : kalan;
        final yeniOdenen = mevcutOdenen + eklenecek;
        final tumOdendi = (yeniOdenen + 0.01) >= taksitTutar;
        dagilim.add({
          'docRef': taksitDoc.reference,
          'sira': t['sira'] ?? 0,
          'eklenen': eklenecek,
          'yeniOdenen': yeniOdenen,
          'tumOdendi': tumOdendi,
        });
        kalan -= eklenecek;
      }

      if (dagilim.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ödenecek taksit kalmadı veya tüm taksitler ödendi')),
        );
        return;
      }

      final dagitilanTutar = girilenTutar - kalan;
      final fazlaTutar = kalan; // dağıtılamayan kısım — uyarı gösteririz

      // 2) Fotoğraf yükle
      final List<String> photoUrls = [];
      if (dekontImages.isNotEmpty) {
        for (var i = 0; i < dekontImages.length; i++) {
          final fileName = 'taksit_${widget.cariId}_${planId}_${DateTime.now().millisecondsSinceEpoch}_$i.jpg';
          final storageRef = FirebaseService().getStorageRef('cari_hareketler/$fileName');
          final compressedList = await compressImage(dekontImages[i]);
          final compressedBytes = Uint8List.fromList(compressedList);
          final url = await uploadToStorage(storageRef, compressedBytes, SettableMetadata(contentType: 'image/jpeg'));
          photoUrls.add(url);
        }
      }

      // 3) Açıklama metnini oluştur
      final siralar = dagilim.map((d) => '#${d['sira']}').join(', ');
      final aciklamaTxt = aciklamaCtrl.text.trim().isNotEmpty
          ? aciklamaCtrl.text.trim()
          : 'Taksit $siralar${projeAd.isNotEmpty ? " ($projeAd)" : ""}';

      // 4) Proje seçiliyse gelir/gider + project_finance kaydet (tek seferde)
      String giderId = '';
      String financeTransactionId = '';
      final projectId = projeId;

      if (projectId.isNotEmpty) {
        if (tip == 'borc') {
          final giderDoc = await FirebaseFirestore.instance.collection('giderler').add({
            'aciklama': '$aciklamaTxt - ${widget.cariAd}',
            'tutar': dagitilanTutar,
            'kategori': 'Cari Ödeme',
            'tarih': DateTime.now(),
            'olusturmaTarihi': FieldValue.serverTimestamp(),
            'projectId': projectId,
            'cariId': widget.cariId,
            'cariAd': widget.cariAd,
            'paraBirimi': 'TL',
            'orijinalTutar': dagitilanTutar,
            'kur': 1.0,
            'sirketId': SistemYoneticisi().aktifSirket?.id ?? '',
          });
          giderId = giderDoc.id;
          await FirebaseFirestore.instance
              .collection('teklifler').doc(projectId).collection('giderler').add({
            'kategori': 'Cari Ödeme',
            'altKategori': widget.cariAd,
            'tutar': dagitilanTutar,
            'aciklama': aciklamaTxt,
            'tarih': DateTime.now(),
            'foto': null,
          });
        } else {
          final gelirDoc = await FirebaseFirestore.instance.collection('gelirler').add({
            'aciklama': '$aciklamaTxt - ${widget.cariAd}',
            'tutar': dagitilanTutar,
            'kategori': 'Cari Tahsilat',
            'tarih': DateTime.now(),
            'olusturmaTarihi': FieldValue.serverTimestamp(),
            'projectId': projectId,
            'cariId': widget.cariId,
            'cariAd': widget.cariAd,
            'paraBirimi': 'TL',
            'orijinalTutar': dagitilanTutar,
            'kur': 1.0,
            'sirketId': SistemYoneticisi().aktifSirket?.id ?? '',
          });
          giderId = gelirDoc.id;
          await FirebaseFirestore.instance
              .collection('teklifler').doc(projectId).collection('gelirler').add({
            'kategori': 'Cari Tahsilat',
            'altKategori': widget.cariAd,
            'tutar': dagitilanTutar,
            'aciklama': aciklamaTxt,
            'tarih': DateTime.now(),
            'foto': null,
          });
        }

        final transactionRef = FirebaseFirestore.instance
            .collection('project_finance').doc(projectId).collection('transactions').doc();
        financeTransactionId = transactionRef.id;
        await transactionRef.set({
          'id': transactionRef.id,
          'type': tip == 'borc' ? 'expense' : 'income',
          'amount': dagitilanTutar,
          'category': 'other',
          'description': '$aciklamaTxt: ${widget.cariAd}',
          'date': Timestamp.fromDate(DateTime.now()),
          'createdAt': FieldValue.serverTimestamp(),
        });

        final financeDoc = await FirebaseFirestore.instance
            .collection('project_finance').doc(projectId).get();
        final currentIncome = ((financeDoc.data()?['totalIncome'] ?? 0) as num).toDouble();
        final currentExpenses = ((financeDoc.data()?['totalExpenses'] ?? 0) as num).toDouble();
        if (tip == 'borc') {
          await FirebaseFirestore.instance.collection('project_finance').doc(projectId)
              .set({'totalExpenses': currentExpenses + dagitilanTutar}, SetOptions(merge: true));
        } else {
          await FirebaseFirestore.instance.collection('project_finance').doc(projectId)
              .set({'totalIncome': currentIncome + dagitilanTutar}, SetOptions(merge: true));
        }
      }

      // 5) Cari hareket + bakiye
      final cariDoc = await FirebaseFirestore.instance
          .collection('cari_hesaplar').doc(widget.cariId).get();
      final mevcutBakiye = ((cariDoc.data()?['bakiye'] ?? 0) as num).toDouble();
      final yeniBakiye = tip == 'alacak' ? mevcutBakiye + dagitilanTutar : mevcutBakiye - dagitilanTutar;

      await FirebaseFirestore.instance
          .collection('cari_hesaplar').doc(widget.cariId).collection('hareketler').add({
        'tip': tip,
        'tutar': dagitilanTutar,
        'tutarTL': dagitilanTutar,
        'paraBirimi': 'TL',
        'kur': 1.0,
        'aciklama': aciklamaTxt,
        'tarih': DateTime.now(),
        'fotoUrls': photoUrls,
        'giderId': giderId,
        'financeTransactionId': financeTransactionId,
        'projeId': projectId.isNotEmpty ? projectId : 'manuel',
        'projeAd': projeAd,
        'taksitPlanId': planId,
        'taksitDagilimi': dagilim.map((d) => {
          'sira': d['sira'],
          'eklenen': d['eklenen'],
        }).toList(),
      });

      await FirebaseFirestore.instance
          .collection('cari_hesaplar').doc(widget.cariId)
          .update({'bakiye': yeniBakiye});

      // 6) Taksit dokümanlarını güncelle (batch)
      final batch = FirebaseFirestore.instance.batch();
      for (final d in dagilim) {
        final ref = d['docRef'] as DocumentReference;
        batch.update(ref, {
          'odenenTutar': d['yeniOdenen'],
          if (d['tumOdendi'] == true) 'odendi': true,
          if (d['tumOdendi'] == true) 'odemeTarihi': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();

      if (mounted) {
        final mesajParts = <String>[
          '${formatTL(dagitilanTutar)} ${isTahsilat ? "tahsilat" : "ödeme"} kaydedildi',
          '${dagilim.length} taksite dağıtıldı',
        ];
        if (fazlaTutar > 0.01) {
          mesajParts.add('${formatTL(fazlaTutar)} dağıtılamadı (taksit kalmadı)');
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(mesajParts.join(' • ')),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(hataCevir(e)), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ── Taksit Planı Sil ──
  Future<void> _taksitPlanSil(String planId) async {
    final onay = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Plan Sil'),
        content: const Text('Bu taksit planı ve tüm taksitleri silinecek. Devam etmek istiyor musunuz?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('İptal')),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (onay != true || !mounted) return;

    try {
      // Önce taksitleri sil
      final taksitler = await FirebaseFirestore.instance
          .collection('cari_hesaplar').doc(widget.cariId)
          .collection('taksit_planlari').doc(planId)
          .collection('taksitler').get();
      final batch = FirebaseFirestore.instance.batch();
      for (var t in taksitler.docs) {
        batch.delete(t.reference);
      }
      // Planı sil
      batch.delete(FirebaseFirestore.instance
          .collection('cari_hesaplar').doc(widget.cariId)
          .collection('taksit_planlari').doc(planId));
      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Taksit planı silindi')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(hataCevir(e)), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _cariDuzenle() async {
    final doc = await FirebaseFirestore.instance.collection('cari_hesaplar').doc(widget.cariId).get();
    final data = doc.data() ?? {};

    final adCtrl = TextEditingController(text: data['ad']);
    final telefonCtrl = TextEditingController(text: data['telefon']);
    final emailCtrl = TextEditingController(text: data['email']);
    final adresCtrl = TextEditingController(text: data['adres']);

    if (!mounted || !context.mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cari Düzenle'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: adCtrl,
                decoration: const InputDecoration(labelText: 'Ad / Firma Adı', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: telefonCtrl,
                decoration: const InputDecoration(labelText: 'Telefon', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: emailCtrl,
                decoration: const InputDecoration(labelText: 'E-posta', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: adresCtrl,
                decoration: const InputDecoration(labelText: 'Adres', border: OutlineInputBorder()),
                maxLines: 2,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('İptal')),
          ElevatedButton(
            onPressed: () async {
              await FirebaseFirestore.instance.collection('cari_hesaplar').doc(widget.cariId).update({
                'ad': adCtrl.text.trim(),
                'telefon': telefonCtrl.text.trim(),
                'email': emailCtrl.text.trim(),
                'adres': adresCtrl.text.trim(),
              });
              
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Güncellendi')),
              );
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
  }

  Future<void> _cariSil() async {
    final onay = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cari Sil'),
        content: const Text('Bu cari hesabı silmek istediğinize emin misiniz? Tüm hareketler de silinecektir.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Sil'),
          ),
        ],
      ),
    );

    if (onay == true) {
      // Cari dokümanını al (proje bilgisi için)
      final cariDoc = await FirebaseFirestore.instance
          .collection('cari_hesaplar')
          .doc(widget.cariId)
          .get();
      final cariData = cariDoc.data();
      final projectId = cariData?['projectId'] as String?;

      final hareketler = await FirebaseFirestore.instance
          .collection('cari_hesaplar')
          .doc(widget.cariId)
          .collection('hareketler')
          .get();

      // Project finance'ı güncelle (toplam gelir/gider düş + transactions sil)
      if (projectId != null && projectId.isNotEmpty) {
        double gelirDusulecek = 0;
        double giderDusulecek = 0;

        for (var doc in hareketler.docs) {
          final data = doc.data();
          final tip = data['tip'] as String?;
          final tutarTL = ((data['tutarTL'] ?? 0) as num).toDouble();

          if (tip == 'alacak') {
            gelirDusulecek += tutarTL;
          } else if (tip == 'borc') {
            giderDusulecek += tutarTL;
          }

          // Finance transaction sil
          final ftId = data['financeTransactionId'] as String?;
          if (ftId != null) {
            await FirebaseFirestore.instance
                .collection('project_finance')
                .doc(projectId)
                .collection('transactions')
                .doc(ftId)
                .delete();
          } else {
            final queryType = tip == 'borc' ? 'expense' : 'income';
            final matchingTx = await FirebaseFirestore.instance
                .collection('project_finance')
                .doc(projectId)
                .collection('transactions')
                .where('amount', isEqualTo: tutarTL)
                .where('type', isEqualTo: queryType)
                .limit(1)
                .get();
            for (final txDoc in matchingTx.docs) {
              await txDoc.reference.delete();
            }
          }
        }

        // Toplam gelir/gider güncelle
        if (gelirDusulecek > 0 || giderDusulecek > 0) {
          final financeDoc = await FirebaseFirestore.instance
              .collection('project_finance')
              .doc(projectId)
              .get();
          if (financeDoc.exists) {
            final curIncome = ((financeDoc.data()?['totalIncome'] ?? 0) as num).toDouble();
            final curExpenses = ((financeDoc.data()?['totalExpenses'] ?? 0) as num).toDouble();
            await FirebaseFirestore.instance
                .collection('project_finance')
                .doc(projectId)
                .set({
                  'totalIncome': (curIncome - gelirDusulecek).clamp(0, double.infinity),
                  'totalExpenses': (curExpenses - giderDusulecek).clamp(0, double.infinity),
                }, SetOptions(merge: true));
          }
        }
      }

      // Hareketleri sil
      for (var doc in hareketler.docs) {
        await doc.reference.delete();
      }

      await FirebaseFirestore.instance.collection('cari_hesaplar').doc(widget.cariId).delete();

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cari hesap silindi')),
        );
      }
    }
  }

  Future<Widget> _buildCariImageWidget(XFile imageFile) async {
    final bytes = await imageFile.readAsBytes();
    return Image.memory(bytes, width: 60, height: 60, fit: BoxFit.cover);
  }

  void _showCariImagePreview(String imageUrl) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBar(
              title: const Text('Fotoğraf Önizleme'),
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(ctx),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.download),
                  tooltip: 'İndir',
                  onPressed: () => _downloadCariImage(imageUrl),
                ),
              ],
            ),
            Expanded(
              child: InteractiveViewer(
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return Center(
                      child: CircularProgressIndicator(
                        value: progress.expectedTotalBytes != null
                            ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes!
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

  void _downloadCariImage(String imageUrl) async {
    try {
      if (kIsWeb) {
        web_utils.downloadImage(
          imageUrl,
          fileName: 'cari_${DateTime.now().millisecondsSinceEpoch}.jpg',
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('İndirme başlatıldı')),
          );
        }
      } else {
        await launchUrl(Uri.parse(imageUrl), mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(hataCevir(e))),
        );
      }
    }
  }  Future<void> _projeSec() async {
    final projects = await FirebaseFirestore.instance.collection('projects').where('companyId', isEqualTo: SistemYoneticisi().aktifSirket?.id ?? '').get();
    
    if (!mounted) return;
    
    if (projects.docs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Proje bulunamadı')),
      );
      return;
    }

    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Proje Seç'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: projects.docs.map((doc) {
              final projeAd = doc.data()['name'] ?? 'İsimsiz Proje';
              return ListTile(
                title: Text(projeAd),
                onTap: () => Navigator.pop(ctx, doc.id),
              );
            }).toList(),
          ),
        ),
      ),
    );

    if (selected != null && mounted) {
      await FirebaseFirestore.instance
          .collection('cari_hesaplar')
          .doc(widget.cariId)
          .update({
            'projectId': selected,
            'projectIds': FieldValue.arrayUnion([selected]),
          });
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Proje atandı')),
      );
    }
  }
}
