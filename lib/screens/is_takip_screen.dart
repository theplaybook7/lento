import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/services.dart';

import '../project_core.dart'; 
import '../notification_service.dart'; 
import '../theme/app_theme.dart';

// --------------------------------------------------------------------------
// 1. ANA LİSTE EKRANI (FİLTRELEMELİ)
// --------------------------------------------------------------------------
class IsTakipSayfasi extends StatelessWidget {
  final int acilisIndex; // 0: Ruhsat, 1: Şantiye

  const IsTakipSayfasi({super.key, this.acilisIndex = 1});

  @override
  Widget build(BuildContext context) {
    String baslik = "Proje ve İş Takip";
    // FİLTRELEME SORGUSU
    Query sorgu = FirebaseFirestore.instance.collection('teklifler');

    if (acilisIndex == 0) {
      baslik = "Ruhsat Aşamasındaki İşler";
      // Sadece ruhsat aşamasındakiler
      sorgu = sorgu.where('mevcutAsama', isEqualTo: 'ruhsat');
    } 
    else if (acilisIndex == 1) {
      baslik = "Şantiye Aşamasındaki İşler";
      // Şantiye aşamasındakiler (Tamamlananlar Arşive gittiği için burada görünmez)
      sorgu = sorgu.where('mevcutAsama', isEqualTo: 'santiye');
    } 
    else {
      baslik = "Tüm Projeler (Muhasebe)";
      // Muhasebede anlaşılmış tüm aktif işler görünür
      sorgu = sorgu.where('durum', whereIn: ['anlasildi', 'tamamlandi']);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(baslik), 
        backgroundColor: AppTheme.primaryColor, 
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      backgroundColor: Colors.grey.shade100,
      
      // Sadece Ruhsat sayfasında "Yeni Dosya" butonu olur
      floatingActionButton: acilisIndex == 0 
        ? FloatingActionButton.extended(
            onPressed: () => _yeniDosyaOlusturDialog(context),
            backgroundColor: Colors.indigo,
            icon: const Icon(Icons.add_business, color: Colors.white),
            label: const Text("YENİ RUHSAT DOSYASI", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          )
        : null,
      
      body: StreamBuilder<QuerySnapshot>(
        stream: sorgu.snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          
          if (snapshot.data!.docs.isEmpty) {
            String mesaj = "Bu aşamada proje yok.";
            if (acilisIndex == 1) mesaj = "Henüz şantiye aşamasında aktif proje yok.\n(Ruhsatı bitenler buraya düşer)";
            
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.folder_off, size: 80, color: Colors.grey.shade400),
                  const SizedBox(height: 10),
                  Text(mesaj, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey, fontSize: 16)),
                ],
              ),
            );
          }

          var docs = snapshot.data!.docs;

          // Responsive Grid/List Yapısı
          return LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth > 800) {
                return GridView.builder(
                  padding: const EdgeInsets.all(20),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3, 
                    childAspectRatio: 2.0, 
                    crossAxisSpacing: 20,
                    mainAxisSpacing: 20,
                  ),
                  itemCount: docs.length,
                  itemBuilder: (c, i) => _buildProjeKarti(context, docs[i]),
                );
              } 
              else {
                return ListView.builder(
                  padding: const EdgeInsets.all(10),
                  itemCount: docs.length,
                  itemBuilder: (c, i) => _buildProjeKarti(context, docs[i]),
                );
              }
            },
          );
        },
      ),
    );
  }

  Widget _buildProjeKarti(BuildContext context, DocumentSnapshot doc) {
    var data = doc.data() as Map<String, dynamic>;
    bool bittiMi = data['durum'] == 'tamamlandi' || data['durum'] == 'arsiv';
    String asama = data['mevcutAsama'] ?? 'ruhsat';

    double yuzde = (data['yuzde'] ?? 0.0).toDouble();
    String sonIslem = data['sonIslem'] ?? "Dosya Oluşturuldu";

    IconData anaIkon = Icons.assignment; // Varsayılan Ruhsat
    Color ikonRenk = Colors.indigo;

    if (asama == 'santiye') {
      anaIkon = Icons.construction;
      ikonRenk = Colors.orange;
    } else if (asama == 'tamamlandi' || bittiMi) {
      anaIkon = Icons.check_circle;
      ikonRenk = Colors.green;
    }

    return Card(
      elevation: 4,
      margin: const EdgeInsets.only(bottom: 12),
      color: bittiMi ? Colors.green.shade50 : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15), 
        side: BorderSide(color: bittiMi ? Colors.green : Colors.grey.shade300)
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: () {
          // Detay sayfasına git
          Navigator.push(context, MaterialPageRoute(builder: (c) => ProjeDetayYonetimSayfasi(
            docId: doc.id, 
            projeData: data,
            acilisIndex: acilisIndex, 
          )));
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: ikonRenk, 
                child: Icon(anaIkon, color: Colors.white, size: 28)
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // TAM ADRES GÖSTERİMİ
                    Text(
                      "${data['ilce']} / ${data['mahalle']} / ${data['ada']} / ${data['parsel']}", 
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "Son: $sonIslem", 
                      style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                      maxLines: 1, 
                      overflow: TextOverflow.ellipsis
                    ),
                    const SizedBox(height: 4),
                    // Aşama Etiketi
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: ikonRenk.withAlpha(30),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: ikonRenk.withAlpha(100))
                      ),
                      child: Text(asama.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: ikonRenk)),
                    )
                  ],
                ),
              ),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 40, width: 4,
                    child: RotatedBox(
                      quarterTurns: -1,
                      child: LinearProgressIndicator(
                        value: yuzde, 
                        backgroundColor: Colors.grey.shade200, 
                        color: ikonRenk
                      ),
                    ),
                  )
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _yeniDosyaOlusturDialog(BuildContext context) {
    final ilceCtrl = TextEditingController();
    final mahalleCtrl = TextEditingController();
    final adaCtrl = TextEditingController();
    final parselCtrl = TextEditingController();

    showDialog(
      context: context, 
      builder: (ctx) {
        return AlertDialog(
          title: const Text("Yeni Ruhsat Dosyası"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: ilceCtrl, decoration: const InputDecoration(labelText: "İlçe", border: OutlineInputBorder())),
                const SizedBox(height: 10),
                TextField(controller: mahalleCtrl, decoration: const InputDecoration(labelText: "Mahalle", border: OutlineInputBorder())),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: TextField(controller: adaCtrl, decoration: const InputDecoration(labelText: "Ada", border: OutlineInputBorder()))),
                    const SizedBox(width: 10),
                    Expanded(child: TextField(controller: parselCtrl, decoration: const InputDecoration(labelText: "Parsel", border: OutlineInputBorder()))),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: ()=>Navigator.pop(ctx), child: const Text("İPTAL")),
            ElevatedButton(
              onPressed: () async {
                if(ilceCtrl.text.isEmpty || adaCtrl.text.isEmpty) return;

                await FirebaseFirestore.instance.collection('teklifler').add({
                  'ilce': ilceCtrl.text,
                  'mahalle': mahalleCtrl.text,
                  'ada': adaCtrl.text,
                  'parsel': parselCtrl.text,
                  'durum': 'anlasildi', 
                  'mevcutAsama': 'ruhsat', 
                  'tarih': FieldValue.serverTimestamp(),
                  'katListesi': [], 
                  'moduller': ['ruhsat', 'santiye', 'muhasebe'], 
                  'yuzde': 0.0, 
                  'sonIslem': 'Dosya Oluşturuldu'
                });
                
                if(context.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Ruhsat dosyası oluşturuldu!"), backgroundColor: Colors.green));
                }
              }, 
              child: const Text("OLUŞTUR")
            )
          ],
        );
      }
    );
  }
}

// --------------------------------------------------------------------------
// 2. DETAY SAYFASI (TAB YÖNETİMİ)
// --------------------------------------------------------------------------
class ProjeDetayYonetimSayfasi extends StatefulWidget {
  final String docId;
  final Map<String, dynamic> projeData;
  final int acilisIndex; 
  
  const ProjeDetayYonetimSayfasi({super.key, required this.docId, required this.projeData, this.acilisIndex = 1});

  @override
  State<ProjeDetayYonetimSayfasi> createState() => _ProjeDetayYonetimSayfasiState();
}

class _ProjeDetayYonetimSayfasiState extends State<ProjeDetayYonetimSayfasi> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Widget> _activeTabs = [];
  List<Widget> _activeViews = [];

  @override
  void initState() {
    super.initState();
    _sekmeleriOlustur();
  }

  void _sekmeleriOlustur() {
    String asama = widget.projeData['mevcutAsama'] ?? 'ruhsat';
    
    _activeTabs = [];
    _activeViews = [];

    // 1. Ruhsat Her Zaman Var
    _activeTabs.add(const Tab(icon: Icon(Icons.assignment_outlined), text: "Ruhsat"));
    _activeViews.add(_RuhsatTab(docId: widget.docId));

    // 2. Şantiye Sadece 'santiye' veya 'tamamlandi' veya 'arsiv' aşamasındaysa var
    if (asama == 'santiye' || asama == 'tamamlandi' || asama == 'arsiv') {
      _activeTabs.add(const Tab(icon: Icon(Icons.construction), text: "Şantiye"));
      _activeViews.add(_SantiyeTab(docId: widget.docId, projeData: widget.projeData));
    }

    // Açılış sekmesini ayarla
    int targetIndex = 0;
    if (widget.acilisIndex == 1 && (asama == 'santiye' || asama == 'tamamlandi')) {
      targetIndex = 1; 
    }

    _tabController = TabController(length: _activeTabs.length, vsync: this, initialIndex: targetIndex);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("${widget.projeData['ilce']} / ${widget.projeData['ada']} / ${widget.projeData['parsel']}"),
        backgroundColor: AppTheme.primaryColor, 
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white, 
          unselectedLabelColor: Colors.white60,
          indicatorColor: Colors.amber, 
          indicatorWeight: 4,
          tabs: _activeTabs,
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: _activeViews,
      ),
    );
  }
}

// --------------------------------------------------------------------------
// 3. RUHSAT TAB
// --------------------------------------------------------------------------
class _RuhsatTab extends StatefulWidget {
  final String docId;
  const _RuhsatTab({required this.docId});
  @override
  State<_RuhsatTab> createState() => _RuhsatTabState();
}

class _RuhsatTabState extends State<_RuhsatTab> {
  final List<String> _ruhsatAsamalari = [
    "1. Karot Alımı ve Riskli Yapı Başvurusu", "2. Aplikasyon Krokisi", "3. İmar Durumu", 
    "4. Avan Proje", "5. Sözleşmeler", "6. Yapı Denetim Atama", 
    "7. Mimari Proje", "8. Statik Proje", "9. Tesisat Projeleri", 
    "10. RUHSAT ALINDI (Şantiyeyi Başlat)" 
  ];

  void _toggleAsamaDurumu(String asama, List<dynamic> mevcutListe) async {
    bool isAdding = !mevcutListe.contains(asama);
    if (mevcutListe.contains(asama)) { mevcutListe.remove(asama); } else { mevcutListe.add(asama); }
    
    double yuzde = mevcutListe.length / _ruhsatAsamalari.length;
    String sonIslem = "Ruhsat: $asama";
    
    Map<String, dynamic> updateData = {
      'tamamlanmisRuhsatAsamalari': mevcutListe,
      'yuzde': yuzde,
      'sonIslem': sonIslem
    };

    if (asama.contains("RUHSAT ALINDI") && isAdding) {
      updateData['mevcutAsama'] = 'santiye'; 
      
      if(mounted) {
        showDialog(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text("Tebrikler! 🎉"),
            content: const Text("Ruhsat alındı olarak işaretlendi.\n\nArtık 'Şantiyeler' menüsünde bu projeyi görebilir ve inşaat aşamalarını takip edebilirsiniz."),
            actions: [TextButton(onPressed: (){ Navigator.pop(c); Navigator.pop(context); }, child: const Text("TAMAM"))],
          )
        );
      }
      
      await BildirimServisi.bildirimGonder(
        baslik: "Şantiye Başladı!", 
        mesaj: "Ruhsat alındı, şantiye aşamasına geçildi.", 
        projeId: widget.docId
      );
    } else {
      if (isAdding) {
         await BildirimServisi.bildirimGonder(baslik: "Ruhsat İlerlemesi", mesaj: "$asama tamamlandı.", projeId: widget.docId);
      }
    }

    await FirebaseFirestore.instance.collection('teklifler').doc(widget.docId).update(updateData);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('teklifler').doc(widget.docId).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || !snapshot.data!.exists) return const Center(child: CircularProgressIndicator());
        var data = snapshot.data!.data() as Map<String, dynamic>;
        List<dynamic> tamamlanmis = data['tamamlanmisRuhsatAsamalari'] ?? [];
        return ListView.separated(
          padding: const EdgeInsets.all(15), itemCount: _ruhsatAsamalari.length, separatorBuilder: (c,i)=>const SizedBox(height: 10),
          itemBuilder: (context, index) {
            String asama = _ruhsatAsamalari[index];
            bool isDone = tamamlanmis.contains(asama);
            bool isFinal = index == _ruhsatAsamalari.length - 1;
            return Card(
              color: isDone ? Colors.green.shade50 : (isFinal ? Colors.orange.shade50 : Colors.white),
              shape: isFinal ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: Colors.orange, width: 2)) : null,
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: isDone ? Colors.green : (isFinal ? Colors.orange : Colors.indigo.shade100), 
                  child: isDone ? const Icon(Icons.check, color: Colors.white) : Text("${index+1}")
                ),
                title: Text(asama, style: TextStyle(fontWeight: isFinal ? FontWeight.bold : FontWeight.normal)),
                trailing: Checkbox(activeColor: Colors.green, value: isDone, onChanged: (v)=>_toggleAsamaDurumu(asama, List.from(tamamlanmis))),
                onTap: () => _detayDialogAc(asama),
              ),
            );
          },
        );
      }
    );
  }
  void _detayDialogAc(String asama) {
    showModalBottomSheet(context: context, isScrollControlled: true, builder: (context) => _GenelAsamaDetaySayfasi(docId: widget.docId, asamaBasligi: asama, koleksiyonAdi: 'ruhsat_gecmis'));
  }
}

// --------------------------------------------------------------------------
// 4. ŞANTİYE TAB
// --------------------------------------------------------------------------
class _SantiyeTab extends StatefulWidget {
  final String docId;
  final Map<String, dynamic> projeData;
  const _SantiyeTab({required this.docId, required this.projeData});
  @override
  State<_SantiyeTab> createState() => _SantiyeTabState();
}

class _SantiyeTabState extends State<_SantiyeTab> {
  List<String> _asamalar = [];
  @override
  void initState() { super.initState(); _asamaListesiniOlustur(); }
  
  void _asamaListesiniOlustur() {
    List<String> liste = ["1. Hafriyat", "2. Grobeton", "3. Temel Tesisat"];
    List<dynamic> katlar = widget.projeData['katListesi'] ?? [];
    for (var kat in katlar) { liste.add("👉 ${kat['ad']}: Demir"); liste.add("👉 ${kat['ad']}: Kalıp"); liste.add("👉 ${kat['ad']}: Beton"); }
    liste.addAll(["Duvar", "Çatı", "Tesisat", "Sıva", "Şap", "Pencere", "Boya", "Parke", "Kapı", "İSKAN"]);
    setState(() => _asamalar = liste);
  }

  void _toggle(String asama, List<dynamic> liste) async {
    bool isAdding = !liste.contains(asama);
    if(liste.contains(asama)) {
      liste.remove(asama);
    } else {
      liste.add(asama);
    }
    double yuzde = liste.length / _asamalar.length;
    
    if (isAdding) {
       await BildirimServisi.bildirimGonder(baslik: "Şantiye İlerlemesi", mesaj: "$asama tamamlandı.", projeId: widget.docId);
    }

    await FirebaseFirestore.instance.collection('teklifler').doc(widget.docId).update({'tamamlanmisAsamalar': liste, 'yuzde': yuzde, 'sonIslem': asama});
  }

  // YENİ: ARŞİVLEME FONKSİYONU
  void _projeBitirVeArsivle() async {
    bool? emin = await showDialog(
      context: context, 
      builder: (c) => AlertDialog(
        title: const Text("Projeyi Arşivle?"),
        content: const Text("Bu işlem projeyi 'Tamamlandı' olarak işaretleyip arşiv bölümüne taşıyacaktır.\nAktif işler listesinden kaldırılacaktır."),
        actions: [
          TextButton(onPressed: ()=>Navigator.pop(c,false), child: const Text("İPTAL")),
          TextButton(onPressed: ()=>Navigator.pop(c,true), child: const Text("ARŞİVLE", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold))),
        ],
      )
    );

    if (emin == true) {
      await FirebaseFirestore.instance.collection('teklifler').doc(widget.docId).update({
        'mevcutAsama': 'tamamlandi',
        'durum': 'arsiv', // Arşivlendi olarak işaretle
        'sonIslem': 'PROJE TAMAMLANDI'
      });
      if(mounted) {
        Navigator.pop(context); // Detay sayfasını kapat
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Tebrikler! Proje başarıyla tamamlandı ve arşivlendi."), backgroundColor: Colors.green));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance.collection('teklifler').doc(widget.docId).snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              var data = snapshot.data!.data() as Map<String, dynamic>;
              List<dynamic> tamamlanmis = data['tamamlanmisAsamalar'] ?? [];
              return ListView.separated(padding: const EdgeInsets.all(15), itemCount: _asamalar.length, separatorBuilder: (c,i)=>const SizedBox(height: 10), itemBuilder: (context, index) {
                  String asama = _asamalar[index]; bool isDone = tamamlanmis.contains(asama);
                  return Card(
                    color: isDone ? Colors.green.shade50 : Colors.white,
                    child: ListTile(
                      leading: CircleAvatar(backgroundColor: isDone ? Colors.green : Colors.orange.shade100, child: isDone ? const Icon(Icons.check, color: Colors.white) : Text("${index+1}")),
                      title: Text(asama),
                      trailing: Checkbox(activeColor: Colors.green, value: isDone, onChanged: (v)=>_toggle(asama, List.from(tamamlanmis))),
                      onTap: () => showModalBottomSheet(context: context, builder: (c) => _GenelAsamaDetaySayfasi(docId: widget.docId, asamaBasligi: asama, koleksiyonAdi: 'santiye_gecmis')),
                    ),
                  );
                },
              );
            }
          ),
        ),
        // ALTTA ARŞİVLE BUTONU
        Container(
          padding: const EdgeInsets.all(16),
          width: double.infinity,
          decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.grey.withAlpha(50), blurRadius: 10, offset: const Offset(0,-3))]),
          child: ElevatedButton.icon(
            onPressed: _projeBitirVeArsivle,
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, padding: const EdgeInsets.symmetric(vertical: 15)),
            icon: const Icon(Icons.archive, color: Colors.white),
            label: const Text("PROJEYİ BİTİR VE ARŞİVLE", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
          ),
        )
      ],
    );
  }
}

// --------------------------------------------------------------------------
// 5. MUHASEBE TAB
// --------------------------------------------------------------------------
class _MuhasebeTab extends StatefulWidget {
  final String docId;
  final Map<String, dynamic> projeData;
  const _MuhasebeTab({required this.docId, required this.projeData});
  @override
  State<_MuhasebeTab> createState() => _MuhasebeTabState();
}

class _MuhasebeTabState extends State<_MuhasebeTab> {
  String _aktifMod = 'GELIR';
  
  final List<String> giderKategorileri = ["1. Projelendirme", "2. Kamu Ödemeleri", "3. Hafriyat", "4. Kalfa", "5. Beton", "6. Demir", "7. Yalıtım", "8. Duvar", "9. Çatı", "10. Asansör", "11. Dış Cephe", "12. Doğalgaz", "13. Şap", "14. Seramik", "15. Elektrik", "16. Sıva", "17. Boya", "18. Alçıpan", "19. Pencere", "20. Parke", "21. Kapı", "22. Mutfak ve Banyo", "23. Korkuluk", "24. Küpeşte", "25. Mermer"];
  final List<String> _standartAltKategoriler = ["İşçilik", "Malzeme", "Nakliyat", "İş Makinesi", "Diğer"];

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Container(padding: const EdgeInsets.all(10), child: Row(children: [
        Expanded(child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: _aktifMod=='GELIR'?Colors.green:Colors.white, foregroundColor: _aktifMod=='GELIR'?Colors.white:Colors.black), onPressed: ()=>setState(()=>_aktifMod='GELIR'), child: const Text("GELİRLER"))),
        const SizedBox(width: 10),
        Expanded(child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: _aktifMod=='GIDER'?Colors.red:Colors.white, foregroundColor: _aktifMod=='GIDER'?Colors.white:Colors.black), onPressed: ()=>setState(()=>_aktifMod='GIDER'), child: const Text("GİDERLER")))
      ])),
      Expanded(child: _aktifMod=='GELIR' ? _buildGelirListesi() : _buildGiderListesi())
    ]);
  }

  Future<void> _pdfRaporuOlusturVeGoster() async {
    try {
      // var gelirSnap = await FirebaseFirestore.instance.collection('teklifler').doc(widget.docId).collection('gelirler').get();
      // List<Map<String, dynamic>> gelirListesi = gelirSnap.docs.map((d) => d.data()).toList();
      // var giderSnap = await FirebaseFirestore.instance.collection('teklifler').doc(widget.docId).collection('giderler').get();
      // List<Map<String, dynamic>> giderListesi = giderSnap.docs.map((d) => d.data()).toList();

      // final pdf = await generateMuhasebePdf(
      //   sirket: SistemYoneticisi().aktifSirket?.ad ?? "İnşaat Yönetim",
      //   projeAdi: "${widget.projeData['ada']}/${widget.projeData['parsel']}",
      //   gelirler: gelirListesi,
      //   giderler: giderListesi
      // );

      // if (mounted) Navigator.push(context, MaterialPageRoute(builder: (c) => Scaffold(appBar: AppBar(title: const Text("PDF Önizleme")), body: PdfPreview(build: (f) => Future.value(pdf)))));
    } catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("PDF Hatası: $e")));
    }
  }

  Widget _buildGelirListesi() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(10.0),
          child: SizedBox(width: double.infinity, child: ElevatedButton.icon(style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 15)), onPressed: _yeniGelirKalemiEkleDialog, icon: const Icon(Icons.add_card), label: const Text("GELİR EKLE"))),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10.0),
          child: SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: _pdfRaporuOlusturVeGoster, icon: const Icon(Icons.picture_as_pdf), label: const Text("RAPOR AL"))),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('teklifler').doc(widget.docId).collection('gelirler').snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              var docs = snapshot.data!.docs;
              if(docs.isEmpty) return const Center(child: Text("Kayıtlı gelir yok."));
              return ListView.builder(
                padding: const EdgeInsets.all(10),
                itemCount: docs.length,
                itemBuilder: (c, i) {
                  var data = docs[i].data() as Map<String, dynamic>;
                  double tutar = (data['tutar'] as num).toDouble();
                  double odenen = (data['odenen'] ?? 0 as num).toDouble();
                  double kalan = tutar - odenen;
                  bool isDevlet = data['tur'] == 'Devlet';
                  return Card(
                    color: isDevlet ? Colors.indigo.shade50 : Colors.white,
                    child: ExpansionTile(
                      leading: CircleAvatar(backgroundColor: isDevlet ? Colors.indigo : Colors.green, child: const Icon(Icons.attach_money, color: Colors.white)),
                      title: Row(
                        children: [
                          Expanded(child: Text(data['aciklama'])),
                          // SİLME BUTONU
                          IconButton(icon: const Icon(Icons.delete, color: Colors.red, size: 20), onPressed: () => _kayitSil(docs[i].reference))
                        ],
                      ),
                      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text("Toplam: ${formatNumber(tutar)} TL"),
                        LinearProgressIndicator(value: tutar>0?odenen/tutar:0, color: Colors.green, backgroundColor: Colors.grey.shade300),
                        Text("Kalan: ${formatNumber(kalan)} TL", style: const TextStyle(fontWeight: FontWeight.bold))
                      ]),
                      children: [
                         Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                          TextButton.icon(icon: const Icon(Icons.history), label: const Text("Geçmiş"), onPressed: () => _gecmisOdemeleriGoster(context, docs[i].reference)),
                          TextButton.icon(icon: const Icon(Icons.add_card), label: const Text("Tahsilat Ekle"), onPressed: () => _tahsilatEkleDialog(context, docs[i].reference, odenen, tutar, isDevlet)),
                        ])
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildGiderListesi() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(10.0),
          child: SizedBox(width: double.infinity, child: ElevatedButton.icon(style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 15)), onPressed: _giderEkleDialogAc, icon: const Icon(Icons.remove_circle), label: const Text("GİDER EKLE"))),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10.0),
          child: SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: _pdfRaporuOlusturVeGoster, icon: const Icon(Icons.picture_as_pdf), label: const Text("RAPOR AL"))),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('teklifler').doc(widget.docId).collection('giderler').orderBy('tarih', descending: true).snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              var docs = snapshot.data!.docs;
              if (docs.isEmpty) return const Center(child: Text("Henüz kayıtlı gider yok."));
              return ListView.builder(
                padding: const EdgeInsets.all(10),
                itemCount: docs.length,
                itemBuilder: (c, i) {
                  var data = docs[i].data() as Map<String, dynamic>;
                  DateTime tarih; 
                  try { tarih = (data['tarih'] as Timestamp).toDate(); } catch(e) { tarih = DateTime.now(); }
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(backgroundColor: Colors.red.shade100, child: const Icon(Icons.money_off, color: Colors.red)),
                      title: Text("${data['kategori'] ?? 'Genel'} / ${data['altKategori'] ?? 'Diğer'}"),
                      subtitle: Text("${tarih.day}.${tarih.month}.${tarih.year} - ${data['aciklama']}"),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text("-${formatNumber(data['tutar'])} TL", style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                          // SİLME BUTONU
                          IconButton(icon: const Icon(Icons.delete, color: Colors.grey, size: 20), onPressed: () => _kayitSil(docs[i].reference))
                        ],
                      ),
                      onTap: () => _giderDetayGoster(data, docs[i].reference),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  void _kayitSil(DocumentReference ref) async {
    bool? onayla = await showDialog(context: context, builder: (c) => AlertDialog(title: const Text("Silinsin mi?"), actions: [TextButton(onPressed: ()=>Navigator.pop(c, true), child: const Text("EVET"))]));
    if(onayla == true) await ref.delete();
  }

  void _yeniGelirKalemiEkleDialog() {
    final t1 = TextEditingController(); final t2 = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text("Gelir Kalemi"),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: t1, decoration: const InputDecoration(labelText: "Açıklama")),
        TextField(controller: t2, keyboardType: TextInputType.number, inputFormatters: [BinlikInputFormatter()], decoration: const InputDecoration(labelText: "Tutar")),
      ]),
      actions: [
        ElevatedButton(onPressed: () async {
          await FirebaseFirestore.instance.collection('teklifler').doc(widget.docId).collection('gelirler').add({
            'aciklama': t1.text, 'tutar': parseFormatted(t2.text), 'odenen': 0, 'tur': 'Manuel', 'tarih': FieldValue.serverTimestamp()
          });
          if(ctx.mounted) Navigator.pop(ctx);
        }, child: const Text("KAYDET"))
      ],
    ));
  }

  // --- TAHSİLAT EKLE (FOTOĞRAF ÖZELLİĞİ İLE) ---
  void _tahsilatEkleDialog(BuildContext context, DocumentReference ref, double mevcut, double toplam, bool isDevlet) {
    final t1 = TextEditingController(); 
    final aciklamaCtrl = TextEditingController();
    final picker = ImagePicker();
    XFile? secilenFoto;

    showDialog(context: context, builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(isDevlet ? "Hakediş Ekle" : "Tahsilat Ekle"),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(controller: t1, keyboardType: TextInputType.number, inputFormatters: [BinlikInputFormatter()], decoration: const InputDecoration(labelText: "Yatan Tutar")),
                    const SizedBox(height: 10),
                    TextField(controller: aciklamaCtrl, decoration: const InputDecoration(labelText: "Açıklama (Dekont No vb.)")),
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: () async {
                        try {
                          final XFile? image = await picker.pickImage(
                            source: ImageSource.gallery,
                            imageQuality: 30, // Hata önlemek için kalite düşürüldü
                            maxWidth: 800,
                            maxHeight: 800,
                          );
                          if (image != null) setDialogState(() => secilenFoto = image);
                        } catch(e, st) {
                          // İzin hatası vb. yakala
                          developer.log('Resim seçme hatası', error: e, stackTrace: st);
                        }
                      },
                      child: Container(
                        height: 100, width: double.infinity, decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey)),
                        child: secilenFoto == null ? const Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.camera_alt, color: Colors.grey), Text("Dekont Ekle (Galeri)")]) : Image.network(secilenFoto!.path, fit: BoxFit.cover) 
                      ),
                    )
                  ],
                ),
              ),
              actions: [
                ElevatedButton(onPressed: () async {
                  if (t1.text.isEmpty) return;
                  double val = parseFormatted(t1.text);
                  String? base64Foto;
                  if (secilenFoto != null) { 
                    List<int> bytes = await secilenFoto!.readAsBytes(); 
                    base64Foto = base64Encode(bytes); 
                  }
                  await ref.collection('odemeler').add({ 'tutar': val, 'tarih': FieldValue.serverTimestamp(), 'aciklama': aciklamaCtrl.text, 'foto': base64Foto });
                  await ref.update({'odenen': mevcut + val});
                  if(ctx.mounted) Navigator.pop(ctx);
                }, child: const Text("KAYDET"))
              ],
            );
          }
        );
      }
    );
  }

  // --- GİDER EKLE (FOTOĞRAF ÖZELLİĞİ İLE) ---
  void _giderEkleDialogAc() {
    String? kat; String? altKat; final t1 = TextEditingController(); final t2 = TextEditingController(); 
    final picker = ImagePicker(); XFile? secilenFoto;

    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (c, setState) => AlertDialog(
      title: const Text("Gider Ekle"),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField(initialValue: kat, items: giderKategorileri.map((e)=>DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 12)))).toList(), onChanged: (v)=>setState((){kat=v as String; altKat=null;}), hint: const Text("Kategori")),
          DropdownButtonFormField(initialValue: altKat, items: _standartAltKategoriler.map((e)=>DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: (v)=>setState(()=>altKat=v as String), hint: const Text("Alt Kategori")),
          TextField(controller: t1, keyboardType: TextInputType.number, inputFormatters: [BinlikInputFormatter()], decoration: const InputDecoration(labelText: "Tutar")),
          TextField(controller: t2, decoration: const InputDecoration(labelText: "Açıklama")),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () async {
              try {
                final XFile? image = await picker.pickImage(
                  source: ImageSource.gallery, 
                  imageQuality: 30,
                  maxWidth: 800,
                  maxHeight: 800
                );
                if (image != null) setState(() => secilenFoto = image);
              } catch (e, st) {
                developer.log('Fiş fotoğrafı seçme hatası', error: e, stackTrace: st);
              }
            },
            child: Container(
              height: 100, width: double.infinity, decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey)),
              child: secilenFoto == null ? const Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.camera_alt, color: Colors.grey), Text("Fiş Fotoğrafı Ekle")]) : Image.network(secilenFoto!.path, fit: BoxFit.cover) 
            ),
          )
        ]),
      ),
      actions: [
        ElevatedButton(onPressed: () async {
          String? base64Foto;
          if (secilenFoto != null) { List<int> bytes = await secilenFoto!.readAsBytes(); base64Foto = base64Encode(bytes); }
          await FirebaseFirestore.instance.collection('teklifler').doc(widget.docId).collection('giderler').add({
            'kategori': kat, 'altKategori': altKat, 'tutar': parseFormatted(t1.text), 'aciklama': t2.text, 'tarih': FieldValue.serverTimestamp(), 'foto': base64Foto
          });
          if(ctx.mounted) Navigator.pop(ctx);
        }, child: const Text("KAYDET"))
      ],
    )));
  }

  void _giderDetayGoster(Map<String, dynamic> data, DocumentReference ref) {
    showDialog(context: context, builder: (c) => AlertDialog(
      title: Text(data['kategori'] ?? "Genel"),
      content: Column(mainAxisSize: MainAxisSize.min, children: [Text("Tutar: ${formatNumber(data['tutar'])} TL"), Text(data['aciklama'] ?? ""), if(data['foto']!=null) Image.memory(base64Decode(data['foto']), height: 200)]),
      actions: [TextButton(onPressed: () async { await ref.delete(); if(c.mounted) Navigator.pop(c); }, child: const Text("SİL", style: TextStyle(color: Colors.red)))],
    ));
  }

  void _gecmisOdemeleriGoster(BuildContext context, DocumentReference ref) {
    showModalBottomSheet(context: context, builder: (c) => StreamBuilder<QuerySnapshot>(
      stream: ref.collection('odemeler').orderBy('tarih', descending: true).snapshots(),
      builder: (context, snapshot) {
        if(!snapshot.hasData) return const SizedBox();
        return ListView(children: snapshot.data!.docs.map((d) {
          var data = d.data() as Map<String, dynamic>;
          return ListTile(title: Text("${data['tutar']} TL"), subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(data['aciklama']??""), if(data['foto']!=null) Image.memory(base64Decode(data['foto']), height: 100)]), trailing: IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () async {
            await ref.update({'odenen': FieldValue.increment(-(data['tutar'] as num))});
            await d.reference.delete();
          }));
        }).toList());
      },
    ));
  }
}

// --------------------------------------------------------------------------
// 6. GENEL FOTOĞRAF/NOT EKLEME DİYALOGU
// --------------------------------------------------------------------------
class _GenelAsamaDetaySayfasi extends StatefulWidget {
  final String docId, asamaBasligi, koleksiyonAdi;
  const _GenelAsamaDetaySayfasi({required this.docId, required this.asamaBasligi, required this.koleksiyonAdi});
  @override
  State<_GenelAsamaDetaySayfasi> createState() => _GenelAsamaDetaySayfasiState();
}

class _GenelAsamaDetaySayfasiState extends State<_GenelAsamaDetaySayfasi> {
  final t1 = TextEditingController();
  final _picker = ImagePicker();
  Uint8List? _imgBytes; 
  bool _loading = false;

  Future<void> _fotoSec(ImageSource src) async {
    try {
      final xfile = await _picker.pickImage(source: src, imageQuality: 30, maxWidth: 800, maxHeight: 800);
      if(xfile != null) {
        final bytes = await xfile.readAsBytes();
        setState(() => _imgBytes = bytes);
      }
    } catch(e, st) {
      developer.log('Genel aşama fotoğraf hatası', error: e, stackTrace: st);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(widget.asamaBasligi, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        const SizedBox(height: 10),
        TextField(controller: t1, decoration: const InputDecoration(labelText: "Not", border: OutlineInputBorder())),
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton(icon: const Icon(Icons.camera_alt), onPressed: ()=>_fotoSec(ImageSource.camera)),
          IconButton(icon: const Icon(Icons.photo), onPressed: ()=>_fotoSec(ImageSource.gallery)),
        ]),
        if(_imgBytes != null) SizedBox(height: 100, child: Image.memory(_imgBytes!)),
        ElevatedButton(onPressed: _loading ? null : () async {
          setState(()=>_loading=true);
          String? b64;
          if(_imgBytes!=null) b64 = base64Encode(_imgBytes!);
          
          await FirebaseFirestore.instance.collection('teklifler').doc(widget.docId).collection(widget.koleksiyonAdi).add({
            'asama': widget.asamaBasligi, 'aciklama': t1.text, 'foto': b64, 'tarih': FieldValue.serverTimestamp()
          });
          
          if(!context.mounted) return;
          await BildirimServisi.bildirimGonder(baslik: "Yeni Detay Eklendi", mesaj: "${widget.asamaBasligi} için yeni fotoğraf/not.", projeId: widget.docId);
          if(!context.mounted) return;
          Navigator.pop(context);
        }, child: _loading ? const CircularProgressIndicator() : const Text("KAYDET"))
      ]),
    );
  }
}