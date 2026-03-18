import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart'; 
import 'services/payment_notification_service.dart';
import 'theme/app_theme.dart';
import 'payment_service.dart';
import 'screens/paywall_screen.dart';

import 'project_core.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard.dart';

/// Şirket kurma akışı sırasında auth state değişikliğini bypass etmek için global flag.
/// iOS'ta hesap oluşturulduktan sonra ödeme ve şirket kurma tamamlanana kadar
/// StreamBuilder'ın VeriYuklemeEkrani'na geçmesini engeller.
final ValueNotifier<bool> companyCreationInProgress = ValueNotifier(false);

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
          : ValueListenableBuilder<bool>(
        valueListenable: companyCreationInProgress,
        builder: (context, creatingCompany, _) => StreamBuilder<User?>(
          stream: FirebaseAuth.instance.authStateChanges(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }
            // Şirket kurma süreci devam ediyorsa login ekranında kal
            if (creatingCompany) {
              return const LoginSayfasi();
            }
            if (snapshot.hasData) {
              return const VeriYuklemeEkrani(); 
            }
            return const LoginSayfasi();
          },
        ),
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
  bool _sirketBulunamadi = false;
  String? _hataMetni;

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
          final Map<String, Map<String, dynamic>> eslesmeler = {};

          for (var doc in sirketSnap.docs) {
            Sirket s = Sirket.fromFirestore(doc);
            if (_normalizeEmail(s.yoneticiEposta) == email) {
              eslesmeler[s.id] = {
                'sirket': s,
                'yetki': PersonelYetki(email: email, adminMi: true),
                'rol': 'Yönetici',
              };
            } else {
              try {
                var p = s.personelListesi.firstWhere(
                  (element) => _normalizeEmail(element.email) == email,
                );
                eslesmeler.putIfAbsent(s.id, () => {
                  'sirket': s,
                  'yetki': p,
                  'rol': 'Personel',
                });
              } catch (e) {
                continue;
              }
            }
          }

          if (eslesmeler.length == 1) {
            final secim = eslesmeler.values.first;
            bulunanSirket = secim['sirket'] as Sirket;
            kullaniciYetkisi = secim['yetki'] as PersonelYetki;
          } else if (eslesmeler.length > 1 && mounted) {
            final result = await showDialog<Map<String, dynamic>>(
              context: context,
              barrierDismissible: false,
              builder: (ctx) => AlertDialog(
                title: const Text('Şirket Seçin'),
                content: SizedBox(
                  width: double.maxFinite,
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: eslesmeler.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = eslesmeler.values.elementAt(index);
                      final Sirket s = item['sirket'] as Sirket;
                      final String rol = item['rol'] as String;
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.blue.withValues(alpha: 0.1),
                          child: const Icon(Icons.business, color: Colors.blue),
                        ),
                        title: Text(s.ad),
                        subtitle: Text(rol),
                        onTap: () => Navigator.pop(ctx, item),
                      );
                    },
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('ÇIKIŞ YAP'),
                  ),
                ],
              ),
            );
            if (result != null) {
              bulunanSirket = result['sirket'] as Sirket;
              kullaniciYetkisi = result['yetki'] as PersonelYetki;
            } else {
              await FirebaseAuth.instance.signOut();
              return;
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
          if (mounted) {
            setState(() {
              _sirketBulunamadi = true;
            });
          }
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _hataMetni = 'Veri yükleme hatası: $e';
          });
        }
      }
    }
  }

  Future<void> _cikisYap() async {
    await FirebaseAuth.instance.signOut();
  }

  Future<void> _sirketKur() async {
    final paymentService = PaymentService();
    await paymentService.initialize();

    if (!paymentService.isApplePaymentSupported) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Platform Desteklenmiyor'),
            content: const Text('Şirket oluşturma aboneliği bu platformda desteklenmiyor. Lütfen iOS uygulamasını kullanın.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('TAMAM'),
              ),
            ],
          ),
        );
      }
      return;
    }

    // Apple IAP ile ödeme
    final subStatus = await paymentService.getSubscriptionStatus();

    if (!(subStatus['active'] as bool)) {
      if (mounted) {
        final purchased = await Navigator.push<bool>(
          context,
          MaterialPageRoute(builder: (ctx) => const PaywallScreen()),
        );
        if (purchased != true) return;
      }
    }

    if (mounted) {
      _sirketKurDialog();
    }
  }

  void _sirketKurDialog() {
    final sirketAdCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    bool kurLoading = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text("Yeni Şirket Kur"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: sirketAdCtrl,
                  enabled: !kurLoading,
                  decoration: const InputDecoration(
                    labelText: "Şirket Adı *",
                    hintText: "Şirketinizin adını yazın",
                    prefixIcon: Icon(Icons.business),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: emailCtrl,
                  enabled: !kurLoading,
                  decoration: const InputDecoration(
                    labelText: "Yönetici Email *",
                    hintText: "admin@sirket.com",
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: kurLoading ? null : () => Navigator.pop(ctx),
              child: const Text("İPTAL"),
            ),
            ElevatedButton(
              onPressed: kurLoading
                  ? null
                  : () async {
                      if (sirketAdCtrl.text.isEmpty || emailCtrl.text.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Lütfen zorunlu alanları doldurun")),
                        );
                        return;
                      }
                      setDialogState(() => kurLoading = true);
                      try {
                        final user = FirebaseAuth.instance.currentUser;
                        final userEmail = _normalizeEmail(user?.email ?? '');
                        if (user == null || userEmail.isEmpty) {
                          throw Exception("Oturum bulunamadı.");
                        }
                        await FirebaseFirestore.instance.collection('sirketler').add({
                          'ad': sirketAdCtrl.text,
                          'yoneticiEposta': userEmail,
                          'yoneticiIletisimEposta': _normalizeEmail(emailCtrl.text),
                          'telefon': '',
                          'adres': '',
                          'personelListesi': [],
                          'olusturmaTarihi': FieldValue.serverTimestamp(),
                          'aktif': true,
                        });
                        if (ctx.mounted) Navigator.pop(ctx);
                        // Reload company data
                        setState(() {
                          _sirketBulunamadi = false;
                          _hataMetni = null;
                        });
                        _sirketVerisiniYukle();
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text("Hata: $e")),
                          );
                        }
                      } finally {
                        if (context.mounted) setDialogState(() => kurLoading = false);
                      }
                    },
              child: kurLoading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text("KUR"),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_hataMetni != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 64, color: Colors.red.shade400),
                const SizedBox(height: 16),
                Text(_hataMetni!, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _hataMetni = null;
                      _sirketBulunamadi = false;
                    });
                    _sirketVerisiniYukle();
                  },
                  child: const Text("Tekrar Dene"),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _cikisYap,
                  child: const Text("Çıkış Yap"),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_sirketBulunamadi) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.business_outlined, size: 64, color: Colors.orange.shade400),
                const SizedBox(height: 16),
                const Text(
                  "Şirket Bulunamadı",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  "Bu hesapla ilişkili bir şirket bulunamadı. Yeni bir şirket kurabilir veya çıkış yapabilirsiniz.",
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _sirketKur,
                    icon: const Icon(Icons.add_business),
                    label: const Text("Şirket Kur"),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _cikisYap,
                  child: const Text("Çıkış Yap"),
                ),
              ],
            ),
          ),
        ),
      );
    }

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