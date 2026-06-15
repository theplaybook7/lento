import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart'; 
import 'services/payment_notification_service.dart';
import 'services/fcm_service.dart';
import 'theme/app_theme.dart';
import 'utils/error_handler.dart';
import 'payment_service.dart';
import 'screens/paywall_screen.dart';

import 'project_core.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard.dart';

/// Şirket kurma akışı sırasında auth state değişikliğini bypass etmek için global flag.
/// iOS'ta hesap oluşturulduktan sonra ödeme ve şirket kurma tamamlanana kadar
/// StreamBuilder'ın VeriYuklemeEkrani'na geçmesini engeller.
final ValueNotifier<bool> companyCreationInProgress = ValueNotifier(false);

Future<void> _initializeIosServices() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
    return;
  }

  try {
    final notificationService = PaymentNotificationService();
    await notificationService.initialize().timeout(const Duration(seconds: 10));
  } catch (_) {
    // iOS arka plan/bildirim servisleri uygulama acilisini bloklamamali.
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  String? startupError;

  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  } on FirebaseException catch (e) {
    if (e.code != 'duplicate-app') {
      startupError = e.toString();
    }
  } catch (e) {
    startupError = e.toString();
  }
  
  runApp(InsaatYonetimApp(startupError: startupError));

  // Bildirim ve arka plan görevleri UI acildiktan sonra baslatilsin.
  if (startupError == null) {
    unawaited(_initializeIosServices());
  }
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
        // userChanges: sign-in/out + reload sonrası emailVerified güncellemelerini de yakalar
        stream: FirebaseAuth.instance.userChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          if (creatingCompany) {
            return const LoginSayfasi();
          }
          final user = snapshot.data;
          if (user != null) {
            if (!user.emailVerified) {
              return const EmailDogrulamaEkrani();
            }
            return const VeriYuklemeEkrani();
          }
          return const LoginSayfasi();
        },
      ),
    );
  }
}

/// E-posta doğrulanmamış kullanıcılar için ekran. Her 4 sn'de currentUser.reload() yapar;
/// userChanges stream'i bunu yakalar ve doğrulama tamamlandığında AuthGate ana akışa geçer.
class EmailDogrulamaEkrani extends StatefulWidget {
  const EmailDogrulamaEkrani({super.key});

  @override
  State<EmailDogrulamaEkrani> createState() => _EmailDogrulamaEkraniState();
}

class _EmailDogrulamaEkraniState extends State<EmailDogrulamaEkrani> {
  Timer? _timer;
  bool _yenidenGonderiyor = false;
  DateTime? _sonGonderim;

  @override
  void initState() {
    super.initState();
    _ilkGonderim();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) async {
      try {
        await FirebaseAuth.instance.currentUser?.reload();
      } catch (_) {}
    });
  }

  Future<void> _ilkGonderim() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u != null && !u.emailVerified) {
      try {
        FirebaseAuth.instance.setLanguageCode('tr');
        await u.sendEmailVerification();
        _sonGonderim = DateTime.now();
      } catch (_) {}
    }
  }

  Future<void> _yenidenGonder() async {
    if (_yenidenGonderiyor) return;
    if (_sonGonderim != null &&
        DateTime.now().difference(_sonGonderim!).inSeconds < 30) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen 30 saniye bekleyip tekrar deneyin.')),
      );
      return;
    }
    setState(() => _yenidenGonderiyor = true);
    try {
      FirebaseAuth.instance.setLanguageCode('tr');
      await FirebaseAuth.instance.currentUser?.sendEmailVerification();
      _sonGonderim = DateTime.now();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Doğrulama bağlantısı tekrar gönderildi.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gönderilemedi: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _yenidenGonderiyor = false);
    }
  }

  Future<void> _kontrolEt() async {
    try {
      await FirebaseAuth.instance.currentUser?.reload();
      final u = FirebaseAuth.instance.currentUser;
      if (u != null && !u.emailVerified && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('E-posta henüz doğrulanmamış.')),
        );
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final email = FirebaseAuth.instance.currentUser?.email ?? '';
    return Scaffold(
      appBar: AppBar(
        title: const Text('E-posta Doğrulama'),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.mark_email_unread, size: 72, color: AppTheme.primaryColor),
              const SizedBox(height: 16),
              const Text(
                'Hesabınızı doğrulayın',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Dogrulama baglantisi gonderildi:\n$email\n\nMail bazen Spam/Junk klasorune dusebilir, lutfen orayi da kontrol edin.\n\nE-postadaki baglantiya tikladiktan sonra bu ekran otomatik kapanacaktir.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, height: 1.5),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _kontrolEt,
                icon: const Icon(Icons.refresh),
                label: const Text('Doğrulama durumunu kontrol et'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 48),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _yenidenGonderiyor ? null : _yenidenGonder,
                icon: _yenidenGonderiyor
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
                label: const Text('Bağlantıyı tekrar gönder'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                ),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () async {
                  await FirebaseAuth.instance.signOut();
                },
                icon: const Icon(Icons.logout),
                label: const Text('Çıkış yap'),
              ),
            ],
          ),
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
                'Uygulama başlatılırken bir hata oluştu. Lütfen internet bağlantınızı kontrol edip tekrar deneyin.',
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
  bool _sirketKurulumYonlendirmesiAcildi = false;

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

  /// Birden fazla şirkete kayıtlı kullanıcı için şirket seçim dialogu
  Future<Sirket?> _sirketSecDialog(List<Sirket> sirketler, {Sirket? varsayilan}) async {
    return showDialog<Sirket>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text("Şirket Seçin"),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: sirketler.length,
            itemBuilder: (context, index) {
              final s = sirketler[index];
              final isVarsayilan = varsayilan != null && s.id == varsayilan.id;
              return ListTile(
                leading: const Icon(Icons.business),
                title: Text(s.ad),
                subtitle: Text(s.yoneticiEposta),
                trailing: isVarsayilan
                    ? const Icon(Icons.check_circle, color: Colors.green)
                    : null,
                selected: isVarsayilan,
                onTap: () => Navigator.pop(ctx, s),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text("İPTAL"),
          ),
        ],
      ),
    );
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

        // Her zaman email ile tüm şirketleri ara (çoklu şirket desteği)
        try {
          final emailQuery = await FirebaseFirestore.instance
              .collection('sirketler')
              .where('emailler', arrayContains: email)
              .get();

          final bulunanSirketler = <Sirket>[];
          final bulunanYetkiler = <PersonelYetki>[];
          final bulunanDocIds = <String>{};

          for (final doc in emailQuery.docs) {
            final s = Sirket.fromFirestore(doc);
            PersonelYetki? yetki;
            if (_normalizeEmail(s.yoneticiEposta) == email) {
              yetki = PersonelYetki(email: email, adminMi: true);
              // Mevcut şirketlerde adminlar haritasını otomatik oluştur
              final data = doc.data();
              if (data['adminlar'] == null || !(data['adminlar'] as Map).containsKey(user.uid)) {
                try {
                  await FirebaseFirestore.instance
                      .collection('sirketler')
                      .doc(doc.id)
                      .update({'adminlar.${user.uid}': true});
                } catch (_) {}
              }
              // emailler field yoksa otomatik oluştur (migration)
              if (data['emailler'] == null) {
                try {
                  final emails = <String>[_normalizeEmail(s.yoneticiEposta)];
                  for (final p in s.personelListesi) {
                    final pe = _normalizeEmail(p.email);
                    if (pe.isNotEmpty && !emails.contains(pe)) emails.add(pe);
                  }
                  await FirebaseFirestore.instance
                      .collection('sirketler')
                      .doc(doc.id)
                      .update({'emailler': emails});
                } catch (_) {}
              }
            } else {
              try {
                yetki = s.personelListesi.firstWhere(
                  (element) => _normalizeEmail(element.email) == email,
                );
              } catch (_) {
                continue;
              }
            }
            bulunanSirketler.add(s);
            bulunanYetkiler.add(yetki);
            bulunanDocIds.add(doc.id);
          }

          // sirketId ile kayıtlı şirket email sorgusunda bulunamadıysa kontrol et
          if (sirketId != null && sirketId.isNotEmpty && !bulunanDocIds.contains(sirketId)) {
            try {
              final sirketDoc = await FirebaseFirestore.instance
                  .collection('sirketler')
                  .doc(sirketId)
                  .get();
              if (sirketDoc.exists) {
                final s = Sirket.fromFirestore(sirketDoc);
                PersonelYetki? yetki;
                if (_normalizeEmail(s.yoneticiEposta) == email) {
                  yetki = PersonelYetki(email: email, adminMi: true);
                } else {
                  try {
                    yetki = s.personelListesi.firstWhere(
                      (element) => _normalizeEmail(element.email) == email,
                    );
                  } catch (_) {}
                }
                if (yetki != null) {
                  bulunanSirketler.add(s);
                  bulunanYetkiler.add(yetki);
                  // emailler array'ini otomatik düzelt
                  try {
                    await FirebaseFirestore.instance
                        .collection('sirketler')
                        .doc(sirketId)
                        .update({'emailler': FieldValue.arrayUnion([email])});
                  } catch (_) {}
                }
              }
            } catch (_) {}
          }

          // Tüm şirketlerde personelListesi'nden emailler migration
          for (int i = 0; i < bulunanSirketler.length; i++) {
            final s = bulunanSirketler[i];
            final docId = i < emailQuery.docs.length ? emailQuery.docs[i].id : s.id;
            // emailler'de olmayan personel emaillerini ekle
            try {
              final allEmails = <String>[_normalizeEmail(s.yoneticiEposta)];
              for (final p in s.personelListesi) {
                final pe = _normalizeEmail(p.email);
                if (pe.isNotEmpty && !allEmails.contains(pe)) allEmails.add(pe);
              }
              await FirebaseFirestore.instance
                  .collection('sirketler')
                  .doc(docId)
                  .update({'emailler': allEmails});
            } catch (_) {}
          }

          if (bulunanSirketler.length == 1) {
            bulunanSirket = bulunanSirketler.first;
            kullaniciYetkisi = bulunanYetkiler.first;
            await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
              'sirketId': bulunanSirket.id,
            }, SetOptions(merge: true));
          } else if (bulunanSirketler.length > 1) {
            // Birden fazla şirket — kayıtlı sirketId varsa onu varsayılan yap, yoksa seçtir
            Sirket? varsayilan;
            if (sirketId != null && sirketId.isNotEmpty) {
              try {
                varsayilan = bulunanSirketler.firstWhere((s) => s.id == sirketId);
              } catch (_) {}
            }
            if (mounted) {
              final secim = await _sirketSecDialog(bulunanSirketler, varsayilan: varsayilan);
              if (secim != null) {
                final idx = bulunanSirketler.indexOf(secim);
                bulunanSirket = secim;
                kullaniciYetkisi = bulunanYetkiler[idx];
                await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
                  'sirketId': bulunanSirket.id,
                }, SetOptions(merge: true));
              }
            }
          }
        } catch (_) {
          // Email sorgusu başarısız — sirketId ile fallback dene
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
                } else {
                  try {
                    final p = s.personelListesi.firstWhere(
                      (element) => _normalizeEmail(element.email) == email,
                    );
                    bulunanSirket = s;
                    kullaniciYetkisi = p;
                  } catch (_) {}
                }
              }
            } catch (_) {}
          }
        }

        if (bulunanSirket != null) {
          SistemYoneticisi().aktifSirket = bulunanSirket;
          SistemYoneticisi().aktifKullaniciYetkileri = kullaniciYetkisi;

          // FCM push bildirim token kaydı
          unawaited(FcmService().initialize());

          final resolvedPlan = planTierFromRaw(
            bulunanSirket.planTier,
            subscriptionType: bulunanSirket.subscriptionType,
            subscriptionEndDate: bulunanSirket.subscriptionEndDate,
          );
          if (bulunanSirket.planTier != resolvedPlan.name) {
            bulunanSirket.planTier = resolvedPlan.name;
            unawaited(
              FirebaseFirestore.instance
                  .collection('sirketler')
                  .doc(bulunanSirket.id)
                  .set({'planTier': resolvedPlan.name}, SetOptions(merge: true)),
            );
          }

          if (mounted) {
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (c) => const DashboardSayfasi()));
          }
        } else {
          if (mounted) {
            setState(() {
              _sirketBulunamadi = true;
            });

            if (!_sirketKurulumYonlendirmesiAcildi) {
              _sirketKurulumYonlendirmesiAcildi = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && _sirketBulunamadi) {
                  _sirketKur();
                }
              });
            }
          }
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _hataMetni = hataCevir(e);
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
          title: const Text("Yeni Kullanıcı Kaydı"),
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
                          'emailler': [userEmail],
                          'adminlar': {user.uid: true},
                          'olusturmaTarihi': FieldValue.serverTimestamp(),
                          'aktif': true,
                          'planTier': PlanTier.free.name,
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
                            SnackBar(content: Text(hataCevir(e))),
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
                if (isSubscriptionError && PaymentService().isPaymentSupported && !_hataMetni!.contains('yöneticinize')) ...[
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
                if (!isSubscriptionError || !PaymentService().isPaymentSupported || _hataMetni!.contains('yöneticinize'))
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
                  "Bu hesapla ilişkili bir şirket bulunamadı. Şirket ayarları/kurulum adımına yönlendirilebilirsiniz.",
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _sirketKur,
                    icon: const Icon(Icons.add_business),
                    label: const Text("Şirket Ayarlarına Git"),
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