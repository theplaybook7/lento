import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart'; 
import 'services/payment_notification_service.dart';

import 'project_core.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  // Bildirim servisi başlat
  final notificationService = PaymentNotificationService();
  await notificationService.initialize();
  await notificationService.initializeBackgroundTasks();
  
  runApp(const InsaatYonetimApp());
}

class InsaatYonetimApp extends StatelessWidget {
  const InsaatYonetimApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'İnşaat Yönetim',
      theme: ThemeData(
        primarySwatch: Colors.blueGrey,
        scaffoldBackgroundColor: Colors.grey.shade100,
        useMaterial3: false,
      ),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          if (snapshot.hasData) {
            return const VeriYuklemeEkrani(); 
          }
          return const LoginSayfasi();
        },
      ),
    );
  }
}

class VeriYuklemeEkrani extends StatefulWidget {
  const VeriYuklemeEkrani({super.key});

  @override
  State<VeriYuklemeEkrani> createState() => _VeriYuklemeEkraniState();
}

class _VeriYuklemeEkraniState extends State<VeriYuklemeEkrani> {
  @override
  void initState() {
    super.initState();
    _sirketVerisiniYukle();
  }

  Future<void> _sirketVerisiniYukle() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      String email = user.email!;
      SistemYoneticisi().girisYapanEmail = email;

      try {
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
            continue;
          }
        }

        if (bulunanSirket != null) {
          SistemYoneticisi().aktifSirket = bulunanSirket;
          SistemYoneticisi().aktifKullaniciYetkileri = kullaniciYetkisi;
          if (mounted) {
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (c) => const DashboardSayfasi()));
          }
        } else {
          await FirebaseAuth.instance.signOut();
        }
      } catch (e) {
        await FirebaseAuth.instance.signOut();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 20),
            Text("Veriler yükleniyor...", style: TextStyle(color: Colors.grey))
          ],
        ),
      ),
    );
  }
}