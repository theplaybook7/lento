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
          : const AuthGate(),
    );
  }
}

/// Auth state'e göre LoginSayfasi veya VeriYuklemeEkrani gösteren wrapper.
/// Hem MaterialApp home'da hem logout sonrası navigasyonda kullanılır.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: companyCreationInProgress,
      builder: (context, creatingCompany, _) => StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          if (creatingCompany) {
            return const LoginSayfasi();
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
  bool _sirketBulunamadi = false;
  String? _hataMetni;
  bool _yuklemeUzunSuruyor = false;

  @override
  void initState() {
    super.initState();
    _sirketVerisiniYukle();
    // 12 saniye sonra hâlâ yükleniyorsa kullanıcıya çıkış seçeneği sun
    Future.delayed(const Duration(seconds: 12), () {
      if (mounted && !_sirketBulunamadi && _hataMetni == null) {
        setState(() => _yuklemeUzunSuruyor = true);
      }
    });
  }

  Future<void> _sirketVerisiniYukle() async {
    // Yeni giriş yapıldı, flag'i sıfırla
    SistemYoneticisi().cikisYapiliyor = false;
    
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final email = _normalizeEmail(user.email ?? '');
      if (email.isEmpty) {
        SistemYoneticisi().temizle();
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
          try {
            final sirketDoc = await FirebaseFirestore.instance
                .collection('sirketler')
                .doc(sirketId)
                .get();

            if (sirketDoc.exists) {
              final s = Sirket.fromFirestore(sirketDoc);
              if (_normalizeEmail(s.yoneticiEposta) == email) {
                bulunanSirket = s;
                kullaniciYetkisi = PersonelYetki(email: email, adminMi: true);
                // Mevcut şirketlerde adminlar haritasını otomatik oluştur
                final data = sirketDoc.data() as Map<String, dynamic>?;
                if (data != null && (data['adminlar'] == null || !(data['adminlar'] as Map).containsKey(user.uid))) {
                  try {
                    await FirebaseFirestore.instance
                        .collection('sirketler')
                        .doc(sirketId)
                        .update({'adminlar.${user.uid}': true});
                  } catch (_) {}
                }
              } else {
                try {
                  final p = s.personelListesi.firstWhere(
                    (element) => _normalizeEmail(element.email) == email,
                  );
                  bulunanSirket = s;
                  kullaniciYetkisi = p;
                } catch (_) {
                  // Bu şirkette yok
                }
              }
            }
          } catch (_) {
            // Bozuk şirket verisi, fallback taramaya devam et
          }
        }

        if (bulunanSirket == null) {
          // users dokümanında sirketId yoksa veya şirket bulunamadıysa
          // Şirket bulunamadı durumuna düş
        }

        if (bulunanSirket != null) {
          SistemYoneticisi().aktifSirket = bulunanSirket;
          SistemYoneticisi().aktifKullaniciYetkileri = kullaniciYetkisi;

          // Abonelik kontrolü - tüm platformlar (Apple Guideline 3.1.1)
          bool subscriptionActive = false;

          // 1. Şirket aboneliğini kontrol et
          if (bulunanSirket.subscriptionEndDate != null) {
            subscriptionActive = bulunanSirket.subscriptionEndDate!.isAfter(DateTime.now());
          }

          // 2. Kullanıcının kendi aboneliğini kontrol et (fallback)
          if (!subscriptionActive) {
            final subStatus = await PaymentService().getSubscriptionStatus();
            subscriptionActive = subStatus['active'] as bool;
            // Kullanıcıda aktif ama şirkette yoksa, şirkete kopyala
            if (subscriptionActive && bulunanSirket.id.isNotEmpty) {
              final type = subStatus['type'] as String?;
              final endDate = subStatus['endDate'] as DateTime?;
              if (type != null && endDate != null) {
                await PaymentService().updateCompanySubscription(
                  sirketId: bulunanSirket.id,
                  subscriptionType: type,
                  subscriptionEndDate: endDate,
                );
              }
            }
          }

          if (!subscriptionActive) {
            final isAdmin = kullaniciYetkisi?.adminMi == true ||
                _normalizeEmail(bulunanSirket.yoneticiEposta) == email;

            if (isAdmin && PaymentService().isApplePaymentSupported) {
              // iOS/macOS: Abonelik satın alma ekranı göster
              if (mounted) {
                final purchased = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (ctx) => const PaywallScreen(mode: PaywallMode.subscription),
                  ),
                );
                if (purchased != true) {
                  setState(() {
                    _hataMetni = 'Devam etmek için aktif bir abonelik gerekli.';
                  });
                  return;
                }
                // Satın alma sonrası şirkete kaydet
                final newSub = await PaymentService().getSubscriptionStatus();
                if (newSub['active'] == true) {
                  final t = newSub['type'] as String?;
                  final d = newSub['endDate'] as DateTime?;
                  if (t != null && d != null) {
                    await PaymentService().updateCompanySubscription(
                      sirketId: bulunanSirket.id,
                      subscriptionType: t,
                      subscriptionEndDate: d,
                    );
                  }
                }
              }
            } else if (isAdmin) {
              // Web/diğer platformlar: Abonelik gerekli ama satın alma yapılamıyor
              if (mounted) {
                setState(() {
                  _hataMetni = 'Devam etmek için aktif bir abonelik gerekli.';
                });
              }
              return;
            } else {
              // Personel: Yöneticiye başvur
              if (mounted) {
                setState(() {
                  _hataMetni = 'Şirketinizin aboneliği sona ermiştir. Lütfen şirket yöneticinize başvurun.';
                });
              }
              return;
            }
          }

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
    SistemYoneticisi().temizle();
    await FirebaseAuth.instance.signOut();
  }

  Future<void> _sirketKur() async {
    final paymentService = PaymentService();
    await paymentService.initialize();

    // Abonelik kontrolü
    final subStatus = await paymentService.getSubscriptionStatus();

    if (!(subStatus['active'] as bool)) {
      if (paymentService.isApplePaymentSupported) {
        // iOS/macOS: IAP ile satın alma
        if (mounted) {
          final purchased = await Navigator.push<bool>(
            context,
            MaterialPageRoute(builder: (ctx) => const PaywallScreen()),
          );
          if (purchased != true) return;
        }
      } else {
        // Diğer platformlar: Abonelik gerekli
        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Abonelik Gerekli'),
              content: const Text('Devam etmek için aktif bir abonelik gereklidir.'),
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
                        final companyRef = await FirebaseFirestore.instance.collection('sirketler').add({
                          'ad': sirketAdCtrl.text,
                          'yoneticiEposta': userEmail,
                          'yoneticiIletisimEposta': _normalizeEmail(emailCtrl.text),
                          'telefon': '',
                          'adres': '',
                          'personelListesi': [],
                          'adminlar': {user.uid: true},
                          'olusturmaTarihi': FieldValue.serverTimestamp(),
                          'aktif': true,
                        });
                        // sirketId'yi kullanıcıya kaydet
                        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
                          'sirketId': companyRef.id,
                        }, SetOptions(merge: true));
                        // Abonelik bilgisini şirkete kopyala
                        final subStatus = await PaymentService().getSubscriptionStatus();
                        if (subStatus['active'] == true) {
                          final t = subStatus['type'] as String?;
                          final d = subStatus['endDate'] as DateTime?;
                          if (t != null && d != null) {
                            await PaymentService().updateCompanySubscription(
                              sirketId: companyRef.id,
                              subscriptionType: t,
                              subscriptionEndDate: d,
                            );
                          }
                        }
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
      final isSubscriptionError = _hataMetni!.contains('abonelik') || _hataMetni!.contains('Abonelik');
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isSubscriptionError ? Icons.lock_outline : Icons.error_outline,
                  size: 64,
                  color: isSubscriptionError ? Colors.orange.shade400 : Colors.red.shade400,
                ),
                const SizedBox(height: 16),
                Text(_hataMetni!, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                if (isSubscriptionError && PaymentService().isApplePaymentSupported) ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        final purchased = await Navigator.push<bool>(
                          context,
                          MaterialPageRoute(
                            builder: (ctx) => const PaywallScreen(mode: PaywallMode.subscription),
                          ),
                        );
                        if (purchased == true && mounted) {
                          setState(() {
                            _hataMetni = null;
                            _sirketBulunamadi = false;
                          });
                          _sirketVerisiniYukle();
                        }
                      },
                      icon: const Icon(Icons.payment),
                      label: const Text("Abonelik Satın Al"),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () async {
                      final paymentService = PaymentService();
                      await paymentService.initialize();
                      final restored = await paymentService.restorePurchases();
                      if (restored && mounted) {
                        setState(() {
                          _hataMetni = null;
                          _sirketBulunamadi = false;
                        });
                        _sirketVerisiniYukle();
                      } else if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(paymentService.lastError.isNotEmpty
                              ? paymentService.lastError
                              : 'Geri yüklenecek satın alım bulunamadı.')),
                        );
                      }
                    },
                    child: const Text("Satın Alımları Geri Yükle"),
                  ),
                  const SizedBox(height: 8),
                ],
                if (!isSubscriptionError || !PaymentService().isApplePaymentSupported)
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

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 20),
              const Text("Veriler yükleniyor...", style: TextStyle(color: Colors.grey)),
              if (_yuklemeUzunSuruyor) ...[
                const SizedBox(height: 24),
                const Text(
                  "Bağlantı yavaş olabilir.",
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _yuklemeUzunSuruyor = false;
                      _sirketBulunamadi = false;
                      _hataMetni = null;
                    });
                    _sirketVerisiniYukle();
                    Future.delayed(const Duration(seconds: 12), () {
                      if (mounted && !_sirketBulunamadi && _hataMetni == null) {
                        setState(() => _yuklemeUzunSuruyor = true);
                      }
                    });
                  },
                  child: const Text("Tekrar Dene"),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _cikisYap,
                  child: const Text("Çıkış Yap"),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}