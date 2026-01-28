import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../project_core.dart';
import 'dashboard.dart';

class LoginSayfasi extends StatefulWidget {
  const LoginSayfasi({super.key});

  @override
  State<LoginSayfasi> createState() => _LoginSayfasiState();
}

class _LoginSayfasiState extends State<LoginSayfasi> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;

  Future<void> _girisYap() async {
    if(_emailCtrl.text.isEmpty || _passCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Lütfen alanları doldurun.")));
      return;
    }

    setState(() => _loading = true);
    
    try {
      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text.trim(),
      );
      
      String email = cred.user!.email!;
      SistemYoneticisi().girisYapanEmail = email;

      var sirketSnap = await FirebaseFirestore.instance.collection('sirketler').get();
      
      Sirket? bulunanSirket;
      PersonelYetki? kullaniciYetkisi;

      for (var doc in sirketSnap.docs) {
        Sirket s = Sirket.fromFirestore(doc);
        if (s.yoneticiEposta == email) {
          bulunanSirket = s;
          kullaniciYetkisi = PersonelYetki(email: email, adminMi: true);
          break;
        }
        try {
          var p = s.personelListesi.firstWhere((element) => element.email == email);
          bulunanSirket = s;
          kullaniciYetkisi = p;
          break;
        } catch (e) {
          // Bu şirkette yok
        }
      }

      if (bulunanSirket != null) {
        SistemYoneticisi().aktifSirket = bulunanSirket;
        SistemYoneticisi().aktifKullaniciYetkileri = kullaniciYetkisi;

        if (mounted) {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (c) => const DashboardSayfasi()));
        }
      } else {
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Bu mail adresine bağlı bir şirket bulunamadı.")));
        await FirebaseAuth.instance.signOut();
      }

    } catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Giriş Hatası: $e")));
    } finally {
      if(mounted) setState(() => _loading = false);
    }
  }

  void _sirketKurDialog() {
    final sirketAdCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();

    showDialog(
      context: context, 
      builder: (ctx) => AlertDialog(
        title: const Text("Yeni Şirket Kur"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: sirketAdCtrl, decoration: const InputDecoration(labelText: "Şirket Adı")),
              const SizedBox(height: 10),
              TextField(controller: emailCtrl, decoration: const InputDecoration(labelText: "Yönetici Email")),
              const SizedBox(height: 10),
              TextField(controller: passCtrl, obscureText: true, decoration: const InputDecoration(labelText: "Şifre")),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () async {
              try {
                await FirebaseAuth.instance.createUserWithEmailAndPassword(email: emailCtrl.text.trim(), password: passCtrl.text.trim());
                await FirebaseFirestore.instance.collection('sirketler').add({
                  'ad': sirketAdCtrl.text,
                  'yoneticiEposta': emailCtrl.text.trim(),
                  'personelListesi': [],
                  'olusturmaTarihi': FieldValue.serverTimestamp()
                });

                if(!ctx.mounted || !mounted) return;
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Şirket kuruldu! Şimdi giriş yapabilirsiniz."), backgroundColor: Colors.green));
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Hata: $e")));
              }
            },
            child: const Text("KUR VE KAYDOL")
          )
        ],
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.blueGrey.shade50,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(30.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.apartment, size: 80, color: Colors.blueGrey),
              const SizedBox(height: 10),
              const Text("İNŞAAT YÖNETİM", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
              const SizedBox(height: 40),
              TextField(controller: _emailCtrl, decoration: const InputDecoration(labelText: "E-Posta", prefixIcon: Icon(Icons.email), border: OutlineInputBorder())),
              const SizedBox(height: 15),
              TextField(controller: _passCtrl, obscureText: true, decoration: const InputDecoration(labelText: "Şifre", prefixIcon: Icon(Icons.lock), border: OutlineInputBorder())),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _loading ? null : _girisYap,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey.shade800, foregroundColor: Colors.white),
                  child: _loading ? const CircularProgressIndicator(color: Colors.white) : const Text("GİRİŞ YAP", style: TextStyle(fontSize: 16)),
                ),
              ),
              const SizedBox(height: 20),
              TextButton(onPressed: _sirketKurDialog, child: const Text("Yeni Şirket Oluştur"))
            ],
          ),
        ),
      ),
    );
  }
}