import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart'; 
import '../project_core.dart';
import '../theme/app_theme.dart';
import '../utils/responsive_utils.dart' as resp;
import 'login_screen.dart';

class AyarlarSayfasi extends StatefulWidget {
  const AyarlarSayfasi({super.key});

  @override
  State<AyarlarSayfasi> createState() => _AyarlarSayfasiState();
}

class _AyarlarSayfasiState extends State<AyarlarSayfasi> {
  
  Future<void> _davetMailiGonder(String email, String sirketAdi) async {
    final String subject = Uri.encodeComponent("Davet: $sirketAdi İnşaat Yönetim Sistemine Katılın");
    final String body = Uri.encodeComponent(
      "Merhaba,\n\n"
      "$sirketAdi şirketi sizi İnşaat Yönetim sistemine personel olarak ekledi.\n"
      "Lütfen uygulamayı indirin ve bu mail adresiyle kayıt olun.\n\n"
      "Saygılarımızla."
    );
    
    final Uri mailLaunchUri = Uri.parse("mailto:$email?subject=$subject&body=$body");

    if (!await launchUrl(mailLaunchUri)) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Mail uygulaması açılamadı.")));
    }
  }

  void _personelEkleDialog() {
    final emailCtrl = TextEditingController();
    bool ruhsat = true;
    bool santiye = true;
    bool muhasebe = false;

    showDialog(
      context: context, 
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text("Personel Ekle"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: emailCtrl, 
                  decoration: const InputDecoration(labelText: "Personel E-Mail", border: OutlineInputBorder())
                ),
                const SizedBox(height: 10),
                const Text("Erişim Yetkileri:", style: TextStyle(fontWeight: FontWeight.bold)),
                const Divider(),
                CheckboxListTile(title: const Text("Ruhsat İşlemleri"), value: ruhsat, onChanged: (v)=> setDialogState(()=>ruhsat=v!)),
                CheckboxListTile(title: const Text("Şantiye Takibi"), value: santiye, onChanged: (v)=> setDialogState(()=>santiye=v!)),
                CheckboxListTile(title: const Text("Muhasebe"), value: muhasebe, onChanged: (v)=> setDialogState(()=>muhasebe=v!)),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: ()=>Navigator.pop(ctx), child: const Text("İPTAL")),
            ElevatedButton(
              onPressed: () async {
                if(emailCtrl.text.isEmpty) return;
                
                String email = emailCtrl.text.trim();
                PersonelYetki yeniPersonel = PersonelYetki(
                  email: email,
                  goruntulemeRuhsat: ruhsat,
                  goruntulemeSantiye: santiye,
                  goruntulemeMuhasebe: muhasebe,
                  adminMi: false
                );

                Sirket sirket = SistemYoneticisi().aktifSirket!;
                sirket.personelListesi.add(yeniPersonel);

                List<Map<String, dynamic>> kayitListesi = sirket.personelListesi.map((e) => e.toMap()).toList();
                
                await FirebaseFirestore.instance.collection('sirketler').doc(sirket.id).update({
                  'personelListesi': kayitListesi
                });

                if(!mounted || !ctx.mounted) return;
                Navigator.pop(ctx);
                setState(() {}); 
                _davetMailiGonder(email, sirket.ad);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Personel eklendi ve mail uygulaması açılıyor.")));
              }, 
              child: const Text("EKLE & DAVET ET")
            )
          ],
        ),
      )
    );
  }

  void _yetkiDuzenle(PersonelYetki p) {
    bool ruhsat = p.goruntulemeRuhsat;
    bool santiye = p.goruntulemeSantiye;
    bool muhasebe = p.goruntulemeMuhasebe;

    showDialog(
      context: context, 
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text("${p.email} Yetkileri"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CheckboxListTile(title: const Text("Ruhsat"), value: ruhsat, onChanged: (v)=> setDialogState(()=>ruhsat=v!)),
                CheckboxListTile(title: const Text("Şantiye"), value: santiye, onChanged: (v)=> setDialogState(()=>santiye=v!)),
                CheckboxListTile(title: const Text("Muhasebe"), value: muhasebe, onChanged: (v)=> setDialogState(()=>muhasebe=v!)),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                Sirket sirket = SistemYoneticisi().aktifSirket!;
                sirket.personelListesi.removeWhere((element) => element.email == p.email);
                List<Map<String, dynamic>> kayitListesi = sirket.personelListesi.map((e) => e.toMap()).toList();
                await FirebaseFirestore.instance.collection('sirketler').doc(sirket.id).update({'personelListesi': kayitListesi});
                if(!mounted || !ctx.mounted) return;
                Navigator.pop(ctx); setState(() {});
              }, 
              child: const Text("SİL", style: TextStyle(color: Colors.red))
            ),
            ElevatedButton(
              onPressed: () async {
                Sirket sirket = SistemYoneticisi().aktifSirket!;
                var hedef = sirket.personelListesi.firstWhere((e) => e.email == p.email);
                hedef.goruntulemeRuhsat = ruhsat;
                hedef.goruntulemeSantiye = santiye;
                hedef.goruntulemeMuhasebe = muhasebe;
                List<Map<String, dynamic>> kayitListesi = sirket.personelListesi.map((e) => e.toMap()).toList();
                await FirebaseFirestore.instance.collection('sirketler').doc(sirket.id).update({'personelListesi': kayitListesi});
                if(!mounted || !ctx.mounted) return;
                Navigator.pop(ctx); setState(() {});
              }, 
              child: const Text("KAYDET")
            )
          ],
        ),
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    var sirket = SistemYoneticisi().aktifSirket;
    var aktifKullanici = SistemYoneticisi().aktifKullaniciYetkileri;

    if (sirket == null) return const Scaffold(body: Center(child: Text("Şirket verisi yüklenemedi.")));
    
    bool yoneticiMi = aktifKullanici?.adminMi == true;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Ayarlar"), 
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: EdgeInsets.all(resp.responsivePadding(context)),
        children: [
          const Text("Şirket Bilgileri", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.business, size: 40),
            title: Text(sirket.ad, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text("Yönetici: ${sirket.yoneticiEposta}"),
          ),
          
          const SizedBox(height: 30),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Personel Listesi", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              if(yoneticiMi)
                ElevatedButton.icon(
                  onPressed: _personelEkleDialog, 
                  icon: const Icon(Icons.add, size: 18), 
                  label: const Text("EKLE"),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                )
            ],
          ),
          const Divider(),
          
          if(sirket.personelListesi.isEmpty)
            const Padding(padding: EdgeInsets.all(20), child: Text("Henüz personel eklenmemiş.", style: TextStyle(color: Colors.grey))),

          ...sirket.personelListesi.map((p) => Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              leading: Icon(Icons.person, color: p.adminMi ? Colors.red : Colors.blue),
              title: Text(p.email, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                "Yetkiler: ${p.goruntulemeMuhasebe ? 'Muhasebe ✅ ' : ''}${p.goruntulemeSantiye ? 'Şantiye ✅ ' : ''}${p.goruntulemeRuhsat ? 'Ruhsat ✅' : ''}",
                style: const TextStyle(fontSize: 12),
              ),
              trailing: yoneticiMi 
                ? IconButton(icon: const Icon(Icons.settings), onPressed: () => _yetkiDuzenle(p))
                : null, 
            ),
          )),

          const SizedBox(height: 40),
          ElevatedButton.icon(
            onPressed: () {
              SistemYoneticisi().aktifSirket = null;
              SistemYoneticisi().aktifKullaniciYetkileri = null;
              Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (c)=> const LoginSayfasi()), (r)=>false);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white, padding: const EdgeInsets.all(15)),
            icon: const Icon(Icons.logout),
            label: const Text("ÇIKIŞ YAP"),
          )
        ],
      ),
    );
  }
}