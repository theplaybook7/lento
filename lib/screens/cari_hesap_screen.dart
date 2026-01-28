// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'dart:io';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import '../services/firebase_service.dart';
import '../utils/format_utils.dart';
import '../utils/image_utils.dart';

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
      appBar: AppBar(
        title: const Text('Cari Hesaplar'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: _aramaDialogAc,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
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
        stream: FirebaseFirestore.instance.collection('cari_hesaplar').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Hata: ${snapshot.error}'));
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
                  Icon(Icons.account_balance_wallet, size: 80, color: Colors.grey.shade300),
                  const SizedBox(height: 16),
                  const Text('Henüz cari hesap kaydı yok', style: TextStyle(color: Colors.grey, fontSize: 16)),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, index) => _cariKart(context, docs[index]),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _yeniCariDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('Cari Ekle'),
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
          color: aktif ? Colors.blue : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(ikon, size: 18, color: aktif ? Colors.white : Colors.grey.shade700),
            const SizedBox(width: 4),
            Text(
              etiket,
              style: TextStyle(
                color: aktif ? Colors.white : Colors.grey.shade700,
                fontWeight: aktif ? FontWeight.bold : FontWeight.normal,
                fontSize: 12,
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
    final bakiye = (data['bakiye'] ?? 0.0) as double;
    final telefon = data['telefon'] ?? '';
    final email = data['email'] ?? '';

    final alacak = bakiye > 0;
    final renk = alacak ? Colors.green : Colors.red;
    final ikon = tip == 'musteri' ? Icons.person : Icons.business;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (c) => CariDetayScreen(cariId: doc.id, cariAd: ad),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: renk.withValues(alpha: (renk.a * 255.0 * 0.1).clamp(0, 255)),
                child: Icon(ikon, color: renk),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(ad, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    if (telefon.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(telefon, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                    ],
                    if (email.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(email, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                    ],
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    bakiye == 0 ? 'Dengede' : (alacak ? 'Alacak' : 'Borç'),
                    style: TextStyle(
                      color: bakiye == 0 ? Colors.grey : renk,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
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
}

class CariDetayScreen extends StatefulWidget {
  final String cariId;
  final String cariAd;

  const CariDetayScreen({super.key, required this.cariId, required this.cariAd});

  @override
  State<CariDetayScreen> createState() => _CariDetayScreenState();
}

class _CariDetayScreenState extends State<CariDetayScreen> {
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
          final bakiye = (data['bakiye'] ?? 0.0) as double;
          final telefon = data['telefon'] ?? '';
          final email = data['email'] ?? '';
          final adres = data['adres'] ?? '';

          return Column(
            children: [
              Container(
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
                      bakiye == 0 ? 'Dengede' : (bakiye > 0 ? 'Alacak' : 'Borç'),
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
              ),
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
                            Text(telefon),
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],
                      if (email.isNotEmpty) ...[
                        Row(
                          children: [
                            Icon(Icons.email, size: 18, color: Colors.grey.shade600),
                            const SizedBox(width: 8),
                            Text(email),
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
                    TextButton.icon(
                      onPressed: () => _yeniHareketDialog(),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Yeni Hareket'),
                    ),
                  ],
                ),
              ),
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

                    final docsWithTarih = snapshot.data!.docs
                        .where((doc) => doc.data() is Map<String, dynamic> && 
                               (doc.data() as Map<String, dynamic>).containsKey('tarih') && 
                               (doc.data() as Map<String, dynamic>)['tarih'] != null)
                        .toList();
                    
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
                        projeAd = data['projeAd'] as String? ?? 'Proje';
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

                    return ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: projeGruplari.length,
                      itemBuilder: (context, index) {
                        final projeKey = projeGruplari.keys.elementAt(index);
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
                                    'Borç: ${formatTL(toplamBorc)}',
                                    style: const TextStyle(color: Colors.red, fontSize: 11),
                                  ),
                                if (toplamAlacak > 0)
                                  Text(
                                    'Alacak: ${formatTL(toplamAlacak)}',
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
                if (aciklama.isNotEmpty) Text(aciklama),
                if (tarih != null)
                  Text(
                    '${tarih.day}/${tarih.month}/${tarih.year}',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
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
                      
                      // Resmi sıkıştır
                      final compressedList = await compressImage(selectedImages[i]);
                      final compressedBytes = Uint8List.fromList(compressedList);
                      
                      await storageRef.putData(compressedBytes);
                      final url = await storageRef.getDownloadURL();
                      photoUrls.add(url);
                    }
                  }

                  String? giderId;
                  
                  // Eğer ödeme veya tahsilat ise giderlere kaydetto
                  if (tip == 'borc' || tip == 'alacak') {
                    // Cari kaydından projectId'yi al
                    final cariDoc = await FirebaseFirestore.instance.collection('cari_hesaplar').doc(widget.cariId).get();
                    var projectId = cariDoc.data()?['projectId'] ?? '';
                    
                    // ProjectId boş ise proje seç
                    if (projectId.isEmpty) {
                      if (!mounted) return;
                      final projects = await FirebaseFirestore.instance.collection('projects').get();
                      if (projects.docs.isNotEmpty && mounted) {
                        final selected = await showDialog<String>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Proje Seç'),
                            content: SingleChildScrollView(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: projects.docs.map((doc) {
                                  return ListTile(
                                    title: Text(doc.data()['name'] ?? 'İsimsiz'),
                                    onTap: () => Navigator.pop(ctx, doc.id),
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                        );
                        
                        if (selected != null) {
                          projectId = selected;
                          // Cari'ye proje atama yap
                          await FirebaseFirestore.instance
                              .collection('cari_hesaplar')
                              .doc(widget.cariId)
                              .update({'projectId': projectId});
                        }
                      }
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
                      
                      final currentIncome = (financeDoc.data()?['totalIncome'] ?? 0.0) as double;
                      final currentExpenses = (financeDoc.data()?['totalExpenses'] ?? 0.0) as double;
                      
                      if (tip == 'borc') {
                        await FirebaseFirestore.instance
                            .collection('project_finance')
                            .doc(projectId)
                            .update({
                              'totalExpenses': currentExpenses + tutarTL,
                            });
                      } else if (tip == 'alacak') {
                        await FirebaseFirestore.instance
                            .collection('project_finance')
                            .doc(projectId)
                            .update({
                              'totalIncome': currentIncome + tutarTL,
                            });
                      }
                    }
                  }

                  // Bakiye güncelleme ve hareket eklemeyi paralel yap
                  final cariDoc = await FirebaseFirestore.instance
                      .collection('cari_hesaplar')
                      .doc(widget.cariId)
                      .get();
                  
                  final mevcutBakiye = (cariDoc.data()?['bakiye'] ?? 0.0) as double;
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
                    SnackBar(content: Text('Hata: $e')),
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
                  
                  final mevcutBakiye = (cariDoc.data() is Map ? (cariDoc.data() as Map)['bakiye'] : 0.0) as double;
                  
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
                    
                    var currentIncome = (financeDoc.data()?['totalIncome'] ?? 0.0) as double;
                    var currentExpenses = (financeDoc.data()?['totalExpenses'] ?? 0.0) as double;
                    
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
                        .update({
                          'totalIncome': currentIncome,
                          'totalExpenses': currentExpenses,
                        }));
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
                    SnackBar(content: Text('Hata: $e')),
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
        // Cari dokümantasyonunu paralel al
        final cariDocFuture = FirebaseFirestore.instance
            .collection('cari_hesaplar')
            .doc(widget.cariId)
            .get();
        
        final cariDoc = await cariDocFuture;
        
        final mevcutBakiye = (cariDoc.data()?['bakiye'] ?? 0.0) as double;
        final yeniBakiye = tip == 'alacak' 
            ? mevcutBakiye - tutarTL 
            : mevcutBakiye + tutarTL;

        // Silme ve güncelleme işlemlerini hazırla
        final List<Future<void>> deleteList = [];
        
        // Gider kaydını silinecek listesine ekle
        if (giderId != null) {
          deleteList.add(FirebaseFirestore.instance.collection('giderler').doc(giderId).delete());
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
        final projectId = cariDoc.data()?['projectId'] as String?;
        
        if (projectId != null && projectId.isNotEmpty) {
          final financeDoc = await FirebaseFirestore.instance
              .collection('project_finance')
              .doc(projectId)
              .get();
          
          var currentIncome = (financeDoc.data()?['totalIncome'] ?? 0.0) as double;
          var currentExpenses = (financeDoc.data()?['totalExpenses'] ?? 0.0) as double;
          
          // Hareketi reverse et
          if (tip == 'alacak') {
            currentIncome -= tutarTL;
          } else if (tip == 'borc') {
            currentExpenses -= tutarTL;
          }
          
          deleteList.add(FirebaseFirestore.instance
              .collection('project_finance')
              .doc(projectId)
              .update({
                'totalIncome': currentIncome,
                'totalExpenses': currentExpenses,
              }));
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
            SnackBar(content: Text('Hata: $e')),
          );
        }
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
      final hareketler = await FirebaseFirestore.instance
          .collection('cari_hesaplar')
          .doc(widget.cariId)
          .collection('hareketler')
          .get();

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
    if (kIsWeb) {
      return Image.memory(bytes, width: 60, height: 60, fit: BoxFit.cover);
    } else {
      final file = File(imageFile.path);
      return Image.file(file, width: 60, height: 60, fit: BoxFit.cover);
    }
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

  void _downloadCariImage(String imageUrl) {
    try {
      if (kIsWeb) {
        (html.document.createElement('a') as html.AnchorElement)
          ..href = imageUrl
          ..download = 'cari_${DateTime.now().millisecondsSinceEpoch}.jpg'
          ..click();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('İndirme başlatıldı')),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mobilde indirme: fotoğrafa uzun basarak kaydedin')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('İndirme hatası: $e')),
      );
    }
  }  Future<void> _projeSec() async {
    final projects = await FirebaseFirestore.instance.collection('projects').get();
    
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
          .update({'projectId': selected});
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Proje atandı')),
      );
    }
  }
}
