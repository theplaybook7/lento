import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart'; 
import 'services/payment_notification_service.dart';
import 'theme/app_theme.dart';

import 'project_core.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  String? startupError;

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    startupError = e.toString();
  }
  
  // Bildirim ve arka plan görevleri sadece iOS'ta aktiftir.
  if (startupError == null && !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
    final notificationService = PaymentNotificationService();
    await notificationService.initialize();
    await notificationService.initializeBackgroundTasks();
  }
  
  runApp(InsaatYonetimApp(startupError: startupError));
}

class InsaatYonetimApp extends StatelessWidget {
  const InsaatYonetimApp({super.key, this.startupError});

  final String? startupError;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Lento',
      theme: AppTheme.lightTheme(),
      home: startupError != null
          ? StartupErrorScreen(error: startupError!)
          : StreamBuilder<User?>(
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

class StartupErrorScreen extends StatelessWidget {
  const StartupErrorScreen({super.key, required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),
              Text(
                'Baslangic hatasi',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.red.shade700,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Uygulama Firebase baslatilirken hata aldi. Xcode Scheme > Run > Arguments altinda gerekli --dart-define degerlerinin verildigini kontrol edin.',
              ),
              const SizedBox(height: 16),
              Expanded(
                child: SingleChildScrollView(
                  child: Text(
                    error,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
        ),
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
  String _normalizeEmail(String value) => value.trim().toLowerCase();

  @override
  void initState() {
    super.initState();
    _sirketVerisiniYukle();
  }

  Future<void> _sirketVerisiniYukle() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final email = _normalizeEmail(user.email ?? '');
      if (email.isEmpty) {
        await FirebaseAuth.instance.signOut();
        return;
      }

      SistemYoneticisi().girisYapanEmail = email;

      try {
        Sirket? bulunanSirket;
        PersonelYetki? kullaniciYetkisi;

        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        final sirketId = userDoc.data()?['sirketId'] as String?;
        if (sirketId != null && sirketId.isNotEmpty) {
          final sirketDoc = await FirebaseFirestore.instance
              .collection('sirketler')
              .doc(sirketId)
              .get();

          if (sirketDoc.exists) {
            final s = Sirket.fromFirestore(sirketDoc);
            if (_normalizeEmail(s.yoneticiEposta) == email) {
              bulunanSirket = s;
              kullaniciYetkisi = PersonelYetki(email: email, adminMi: true);
            } else {
              try {
                final p = s.personelListesi.firstWhere(
                  (element) => _normalizeEmail(element.email) == email,
                );
                bulunanSirket = s;
                kullaniciYetkisi = p;
              } catch (e) {
                // Bu şirkette yok
              }
            }
          }
        }

        if (bulunanSirket == null) {
          var sirketSnap = await FirebaseFirestore.instance.collection('sirketler').get();

          for (var doc in sirketSnap.docs) {
            Sirket s = Sirket.fromFirestore(doc);
            if (_normalizeEmail(s.yoneticiEposta) == email) {
              bulunanSirket = s;
              kullaniciYetkisi = PersonelYetki(email: email, adminMi: true);
              break;
            }
            try {
              var p = s.personelListesi.firstWhere(
                (element) => _normalizeEmail(element.email) == email,
              );
              bulunanSirket = s;
              kullaniciYetkisi = p;
              break;
            } catch (e) {
              continue;
            }
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