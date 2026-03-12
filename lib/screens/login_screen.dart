import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data';
import '../project_core.dart';
import '../theme/app_theme.dart';
import 'dashboard.dart';
import '../payment_service.dart';
import '../web_payment_service.dart';
import '../main.dart' show companyCreationInProgress;
import 'paywall_screen.dart';

class LoginSayfasi extends StatefulWidget {
  const LoginSayfasi({super.key});

  @override
  State<LoginSayfasi> createState() => _LoginSayfasiState();
}

enum _NoCompanyAction { createCompany, signOut }

class _LoginSayfasiState extends State<LoginSayfasi> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;

  String _normalizeEmail(String value) => value.trim().toLowerCase();

  @override
  void initState() {
    super.initState();
    PaymentService().initialize();
    if (kIsWeb) {
      _checkPaymentReturn();
    }
  }

  /// Web: Stripe ödeme sonrası URL parametrelerini kontrol et
  void _checkPaymentReturn() {
    final uri = Uri.base;
    final payment = uri.queryParameters['payment'];
    final email = uri.queryParameters['email'];

    if (payment == 'success' && email != null && email.isNotEmpty) {
      // URL'den parametreleri temizle (tarayıcı geçmişinde kalmasın)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showKayitVeSirketKurForm(email.toLowerCase().trim());
        }
      });
    }
  }

  Future<void> _girisYap() async {
    if(_emailCtrl.text.isEmpty || _passCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Lütfen alanları doldurun.")));
      return;
    }

    setState(() => _loading = true);
    
    try {
      final normalizedEmail = _normalizeEmail(_emailCtrl.text);

      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: normalizedEmail,
        password: _passCtrl.text.trim(),
      );
      
      String email = _normalizeEmail(cred.user!.email ?? normalizedEmail);
      final userUid = cred.user!.uid;
      SistemYoneticisi().girisYapanEmail = email;

      final Map<String, Map<String, dynamic>> eslesmeler = {};

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userUid)
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
            eslesmeler[s.id] = {
              'sirket': s,
              'yetki': PersonelYetki(email: email, adminMi: true),
              'rol': 'Yönetici',
            };
          } else {
            try {
              final p = s.personelListesi.firstWhere(
                (element) => _normalizeEmail(element.email) == email,
              );
              eslesmeler.putIfAbsent(s.id, () => {
                'sirket': s,
                'yetki': p,
                'rol': 'Personel',
              });
            } catch (e) {
              // Bu şirkette yok
            }
          }
        }
      }

      if (eslesmeler.isEmpty) {
        var sirketSnap = await FirebaseFirestore.instance.collection('sirketler').get();

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
              // Bu şirkette yok
            }
          }
        }
      }

      if (eslesmeler.isEmpty) {
        if (mounted) {
          final action = await showDialog<_NoCompanyAction>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              title: const Text("Şirket Bulunamadı"),
              content: const Text(
                "Bu hesapla ilişkili bir şirket bulunamadı. Hesabınızla şirket kurulumuna devam edebilir veya çıkış yapabilirsiniz.",
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, _NoCompanyAction.signOut),
                  child: const Text("ÇIKIŞ YAP"),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, _NoCompanyAction.createCompany),
                  child: const Text("ŞİRKET KUR"),
                ),
              ],
            ),
          );

          if (action == _NoCompanyAction.createCompany) {
            await _sirketKurDialog();
            return;
          }
        }

        await FirebaseAuth.instance.signOut();
        return;
      }

      Map<String, dynamic> secim;

      if (eslesmeler.length == 1) {
        secim = eslesmeler.values.first;
      } else {
        final result = await showDialog<Map<String, dynamic>>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(
              "Şirket Seçin",
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: AppTheme.primaryColor,
              ),
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: eslesmeler.values.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = eslesmeler.values.elementAt(index);
                  final Sirket s = item['sirket'] as Sirket;
                  final String rol = item['rol'] as String;
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.1),
                      child: Icon(Icons.business, color: AppTheme.primaryColor),
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
                child: const Text("İPTAL"),
              ),
            ],
          ),
        );

        if (!mounted) return;

        if (result == null) {
          await FirebaseAuth.instance.signOut();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Şirket seçimi iptal edildi.")),
          );
          return;
        }

        secim = result;
      }

      SistemYoneticisi().aktifSirket = secim['sirket'] as Sirket;
      SistemYoneticisi().aktifKullaniciYetkileri = secim['yetki'] as PersonelYetki;

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (c) => const DashboardSayfasi()),
        );
      }

    } catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Giriş Hatası: $e")));
    } finally {
      if(mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sirketKurDialog() async {
    if (kIsWeb) {
      // Web: Önce email al, sonra ödeme, sonra kayıt+şirket kurma
      await _webSirketKurAkisi();
      return;
    }

    // iOS/macOS: Önce hesap oluştur, sonra ödeme, sonra şirket kur
    if (!PaymentService().isApplePaymentSupported) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Platform Desteklenmiyor'),
            content: const Text('Şirket oluşturma aboneliği bu platformda desteklenmiyor.'),
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

    // iOS: Kullanıcı giriş yapmış mı kontrol et
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      // Giriş yapmamış - önce hesap oluşturmalı
      await _iosHesapOlusturVeOde();
      return;
    }

    // Giriş yapmış kullanıcı - direkt ödeme akışına git
    final paymentService = PaymentService();
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

    // Aktif subscription varsa, şirket kurma dialogunu göster
    await _showSirketKurForm();
  }

  /// iOS: Hesap oluştur → Ödeme → Şirket kur
  Future<void> _iosHesapOlusturVeOde() async {
    // Auth state değişikliğini bypass et - şirket kurma tamamlanana kadar
    companyCreationInProgress.value = true;

    try {
      await _iosHesapOlusturVeOdeInternal();
    } finally {
      companyCreationInProgress.value = false;
    }
  }

  Future<void> _iosHesapOlusturVeOdeInternal() async {
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    bool loading = false;
    String? hata;

    final hesapOlusturuldu = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(
            'Hesap Oluştur',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: AppTheme.primaryColor,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Şirket kurmak için önce bir hesap oluşturun. '
                  'Ardından abonelik satın alabilirsiniz.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: emailCtrl,
                  enabled: !loading,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: 'E-Posta *',
                    hintText: 'ornek@email.com',
                    prefixIcon: Icon(Icons.email_outlined, color: AppTheme.primaryColor),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    filled: true, fillColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passCtrl,
                  enabled: !loading,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'Şifre *',
                    hintText: 'En az 6 karakter',
                    prefixIcon: Icon(Icons.lock_outline, color: AppTheme.primaryColor),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    filled: true, fillColor: Colors.white,
                  ),
                ),
                if (hata != null) ...[
                  const SizedBox(height: 12),
                  Text(hata!, style: const TextStyle(color: Colors.red, fontSize: 13)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: loading ? null : () => Navigator.pop(ctx, false),
              child: const Text('İPTAL'),
            ),
            ElevatedButton(
              onPressed: loading
                  ? null
                  : () async {
                      final email = emailCtrl.text.trim();
                      final pass = passCtrl.text.trim();
                      if (email.isEmpty || !email.contains('@') || pass.isEmpty) {
                        setState(() => hata = 'Lütfen geçerli bir e-posta ve şifre girin.');
                        return;
                      }
                      if (pass.length < 6) {
                        setState(() => hata = 'Şifre en az 6 karakter olmalı.');
                        return;
                      }
                      setState(() { loading = true; hata = null; });
                      try {
                        await FirebaseAuth.instance.createUserWithEmailAndPassword(
                          email: email,
                          password: pass,
                        );
                        if (ctx.mounted) Navigator.pop(ctx, true);
                      } on FirebaseAuthException catch (e) {
                        String msg;
                        switch (e.code) {
                          case 'email-already-in-use':
                            // Email zaten kayıtlıysa giriş yapmayı dene
                            try {
                              await FirebaseAuth.instance.signInWithEmailAndPassword(
                                email: email, password: pass,
                              );
                              if (ctx.mounted) Navigator.pop(ctx, true);
                              return;
                            } catch (_) {
                              msg = 'Bu e-posta zaten kayıtlı. Farklı bir şifre deneyin veya giriş yapın.';
                            }
                            break;
                          case 'weak-password':
                            msg = 'Şifre çok zayıf. En az 6 karakter kullanın.';
                            break;
                          case 'invalid-email':
                            msg = 'Geçersiz e-posta adresi.';
                            break;
                          default:
                            msg = 'Hesap oluşturma hatası: ${e.message}';
                        }
                        setState(() { loading = false; hata = msg; });
                      } catch (e) {
                        setState(() { loading = false; hata = 'Hata: $e'; });
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: loading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Colors.white), strokeWidth: 2))
                  : const Text('HESAP OLUŞTUR'),
            ),
          ],
        ),
      ),
    );

    if (hesapOlusturuldu != true) return;

    // Hesap oluşturuldu, şimdi ödeme akışına yönlendir
    final paymentService = PaymentService();
    await paymentService.initialize();
    final subStatus = await paymentService.getSubscriptionStatus();

    if (!(subStatus['active'] as bool)) {
      if (mounted) {
        final purchased = await Navigator.push<bool>(
          context,
          MaterialPageRoute(builder: (ctx) => const PaywallScreen()),
        );
        if (purchased != true) {
          // Ödeme yapılmadıysa çıkış yap
          await FirebaseAuth.instance.signOut();
          return;
        }
      }
    }

    // Ödeme başarılı, şirket kurma formu
    if (mounted) {
      await _showSirketKurForm();
    }
  }

  /// Web akışı: Email → Ödeme → Kayıt + Şirket Kurma
  Future<void> _webSirketKurAkisi() async {
    // Adım 1: Email adresi al
    final emailResult = await _emailAlDialog();
    if (emailResult == null || emailResult.isEmpty) return;

    // Adım 2: Bu email ile daha önce ödeme yapılmış mı kontrol et
    final webPayment = WebPaymentService();
    final paymentStatus = await webPayment.checkPaymentByEmail(emailResult);

    if (paymentStatus['active'] == true) {
      // Ödeme zaten yapılmış, direkt kayıt + şirket kurma formuna git
      if (mounted) {
        await _showKayitVeSirketKurForm(emailResult);
      }
      return;
    }

    // Adım 3: Ödeme yapılmamış, PaywallScreen'e yönlendir
    if (mounted) {
      final purchased = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (ctx) => PaywallScreen(email: emailResult)),
      );

      if (purchased == true) {
        // Ödeme tamamlandı, kayıt + şirket kurma formunu göster
        if (mounted) {
          await _showKayitVeSirketKurForm(emailResult);
        }
      }
      // Not: Stripe'da ödeme yapıldıysa kullanıcı sayfaya
      // ?payment=success ile döner, orada da kontrol var
    }
  }

  /// Email adresi soran dialog
  Future<String?> _emailAlDialog() async {
    final emailCtrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Yeni Şirket Kur',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: AppTheme.primaryColor,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Şirket kurmak için önce e-posta adresinizi girin. '
              'Bu adres yönetici hesabınız olacaktır.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: 'E-Posta Adresi',
                hintText: 'ornek@email.com',
                prefixIcon: Icon(Icons.email_outlined, color: AppTheme.primaryColor),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: AppTheme.primaryColor, width: 2),
                ),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            style: TextButton.styleFrom(foregroundColor: Colors.grey.shade600),
            child: const Text('İPTAL'),
          ),
          ElevatedButton(
            onPressed: () {
              final email = emailCtrl.text.trim().toLowerCase();
              if (email.isNotEmpty && email.contains('@')) {
                Navigator.pop(ctx, email);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('DEVAM'),
          ),
        ],
      ),
    );
  }

  /// Ödeme sonrası: Kayıt + Şirket Kurma formu
  Future<void> _showKayitVeSirketKurForm(String email) async {
    final sifreCtrl = TextEditingController();
    final sirketAdCtrl = TextEditingController();
    final telefonCtrl = TextEditingController();
    final adresCtrl = TextEditingController();
    bool kurLoading = false;
    String? hataMetni;
    Uint8List? logoBytes;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(
            "Hesap Oluştur & Şirket Kur",
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: AppTheme.primaryColor,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle, color: Colors.green, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Ödeme onaylandı! Şimdi hesabınızı ve şirketinizi oluşturun.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.green.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // Email (readonly)
                TextField(
                  controller: TextEditingController(text: email),
                  enabled: false,
                  decoration: InputDecoration(
                    labelText: 'E-Posta',
                    prefixIcon: Icon(Icons.email_outlined, color: AppTheme.primaryColor),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    filled: true,
                    fillColor: Colors.grey.shade100,
                  ),
                ),
                const SizedBox(height: 12),
                // Şifre
                TextField(
                  controller: sifreCtrl,
                  enabled: !kurLoading,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'Şifre *',
                    hintText: 'En az 6 karakter',
                    prefixIcon: Icon(Icons.lock_outline, color: AppTheme.primaryColor),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: AppTheme.primaryColor, width: 2),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 16),
                // Logo Yükleme
                GestureDetector(
                  onTap: kurLoading ? null : () async {
                    try {
                      final ImagePicker picker = ImagePicker();
                      final XFile? image = await picker.pickImage(
                        source: ImageSource.gallery,
                        maxWidth: 512,
                        maxHeight: 512,
                        imageQuality: 85,
                      );
                      if (image != null) {
                        final bytes = await image.readAsBytes();
                        setState(() => logoBytes = bytes);
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text("Görsel seçme hatası: $e")),
                        );
                      }
                    }
                  },
                  child: Container(
                    width: double.infinity,
                    height: 100,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: AppTheme.primaryColor.withValues(alpha: 0.3),
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      color: AppTheme.primaryColor.withValues(alpha: 0.05),
                    ),
                    child: logoBytes != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.memory(logoBytes!, fit: BoxFit.cover),
                          )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.image_outlined, size: 32, color: AppTheme.primaryColor.withValues(alpha: 0.6)),
                              const SizedBox(height: 4),
                              Text('Logo Yükle (İsteğe bağlı)', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.primaryColor.withValues(alpha: 0.7))),
                            ],
                          ),
                  ),
                ),
                if (logoBytes != null)
                  TextButton.icon(
                    onPressed: () => setState(() => logoBytes = null),
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text("Kaldır"),
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                  ),
                const SizedBox(height: 12),
                // Şirket Adı
                TextField(
                  controller: sirketAdCtrl,
                  enabled: !kurLoading,
                  decoration: InputDecoration(
                    labelText: 'Şirket Adı *',
                    hintText: 'Şirketinizin adını yazın',
                    prefixIcon: Icon(Icons.business, color: AppTheme.primaryColor),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: AppTheme.primaryColor, width: 2),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: telefonCtrl,
                  enabled: !kurLoading,
                  decoration: InputDecoration(
                    labelText: 'Telefon',
                    hintText: '+90 555 123 4567',
                    prefixIcon: Icon(Icons.phone_outlined, color: AppTheme.primaryColor),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: AppTheme.primaryColor, width: 2),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: adresCtrl,
                  enabled: !kurLoading,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: 'Adres',
                    hintText: 'Şirket adresini yazın',
                    prefixIcon: Icon(Icons.location_on_outlined, color: AppTheme.primaryColor),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: AppTheme.primaryColor, width: 2),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    alignLabelWithHint: true,
                  ),
                ),
                if (hataMetni != null) ...[
                  const SizedBox(height: 12),
                  Text(hataMetni!, style: const TextStyle(color: Colors.red, fontSize: 13)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: kurLoading ? null : () => Navigator.pop(ctx),
              style: TextButton.styleFrom(foregroundColor: Colors.grey.shade600),
              child: const Text('İPTAL'),
            ),
            ElevatedButton(
              onPressed: kurLoading
                  ? null
                  : () async {
                      if (sirketAdCtrl.text.isEmpty || sifreCtrl.text.isEmpty) {
                        setState(() => hataMetni = 'Lütfen şifre ve şirket adını doldurun.');
                        return;
                      }
                      if (sifreCtrl.text.length < 6) {
                        setState(() => hataMetni = 'Şifre en az 6 karakter olmalı.');
                        return;
                      }

                      setState(() {
                        kurLoading = true;
                        hataMetni = null;
                      });

                      try {
                        // 1. Firebase Auth hesabı oluştur
                        final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
                          email: email,
                          password: sifreCtrl.text.trim(),
                        );

                        final uid = cred.user!.uid;

                        // 2. Logo yükle
                        String? logoUrl;
                        if (logoBytes != null) {
                          try {
                            final ref = FirebaseStorage.instance.ref(
                              'sirket_logolari/${email}_logo_${DateTime.now().millisecondsSinceEpoch}.png',
                            );
                            await ref.putData(logoBytes!);
                            logoUrl = await ref.getDownloadURL();
                          } catch (e) {
                            logoUrl = null;
                          }
                        }

                        // 3. Şirket kaydı
                        final sirketRef = await FirebaseFirestore.instance
                            .collection('sirketler')
                            .add({
                          'ad': sirketAdCtrl.text,
                          'yoneticiEposta': email,
                          'yoneticiIletisimEposta': email,
                          'telefon': telefonCtrl.text,
                          'adres': adresCtrl.text,
                          'logoUrl': logoUrl,
                          'personelListesi': [],
                          'olusturmaTarihi': FieldValue.serverTimestamp(),
                          'aktif': true,
                        });

                        // 4. Users doc güncelle (sirketId + ödeme bilgisi)
                        // pending_payments'tan ödeme bilgisini al
                        final pendingDoc = await FirebaseFirestore.instance
                            .collection('pending_payments')
                            .doc(email)
                            .get();

                        final paymentData = pendingDoc.data() ?? {};

                        await FirebaseFirestore.instance
                            .collection('users')
                            .doc(uid)
                            .set({
                          'email': email,
                          'sirketId': sirketRef.id,
                          'companyCreationPaid': true,
                          'paidAt': paymentData['paidAt'] ?? FieldValue.serverTimestamp(),
                          'subscriptionType': paymentData['planType'],
                          'subscriptionEndDate': paymentData['subscriptionEndDate'],
                          'stripeSubscriptionId': paymentData['stripeSubscriptionId'],
                          'autoRenew': true,
                          'lastPurchaseStatus': 'completed',
                          'createdAt': FieldValue.serverTimestamp(),
                        }, SetOptions(merge: true));

                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);

                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('✅ Hesap oluşturuldu ve şirket kuruldu! Giriş yapabilirsiniz.'),
                              backgroundColor: Colors.green,
                              duration: Duration(seconds: 3),
                            ),
                          );
                        }

                        // Çıkış yap (kullanıcı giriş ekranından giriş yapsın)
                        await FirebaseAuth.instance.signOut();
                      } on FirebaseAuthException catch (e) {
                        String msg;
                        switch (e.code) {
                          case 'email-already-in-use':
                            msg = 'Bu e-posta adresi zaten kayıtlı. Lütfen giriş yapın.';
                            break;
                          case 'weak-password':
                            msg = 'Şifre çok zayıf. En az 6 karakter kullanın.';
                            break;
                          case 'invalid-email':
                            msg = 'Geçersiz e-posta adresi.';
                            break;
                          default:
                            msg = 'Hesap oluşturma hatası: ${e.message}';
                        }
                        setState(() {
                          kurLoading = false;
                          hataMetni = msg;
                        });
                      } catch (e) {
                        setState(() {
                          kurLoading = false;
                          hataMetni = 'Hata: $e';
                        });
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: kurLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        strokeWidth: 2,
                      ),
                    )
                  : const Text('HESAP OLUŞTUR & ŞİRKET KUR'),
            ),
          ],
        ),
      ),
    );
  }

  /// iOS: Auth'lu kullanıcı için şirket kurma formu (Apple IAP sonrası)
  Future<void> _showSirketKurForm() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;
    final currentEmail = _normalizeEmail(currentUser.email ?? '');

    final sirketAdCtrl = TextEditingController();
    final telefonCtrl = TextEditingController();
    final adresCtrl = TextEditingController();
    bool kurLoading = false;
    Uint8List? logoBytes;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(
            "Yeni Şirket Kur",
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: AppTheme.primaryColor,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: kurLoading ? null : () async {
                    try {
                      final ImagePicker picker = ImagePicker();
                      final XFile? image = await picker.pickImage(
                        source: ImageSource.gallery, maxWidth: 512, maxHeight: 512, imageQuality: 85,
                      );
                      if (image != null) {
                        final bytes = await image.readAsBytes();
                        setState(() => logoBytes = bytes);
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Görsel seçme hatası: $e")));
                      }
                    }
                  },
                  child: Container(
                    width: double.infinity, height: 100,
                    decoration: BoxDecoration(
                      border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.3), width: 2),
                      borderRadius: BorderRadius.circular(12),
                      color: AppTheme.primaryColor.withValues(alpha: 0.05),
                    ),
                    child: logoBytes != null
                        ? ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.memory(logoBytes!, fit: BoxFit.cover))
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.image_outlined, size: 32, color: AppTheme.primaryColor.withValues(alpha: 0.6)),
                              const SizedBox(height: 4),
                              Text('Logo Yükle', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.primaryColor.withValues(alpha: 0.7))),
                            ],
                          ),
                  ),
                ),
                if (logoBytes != null)
                  TextButton.icon(
                    onPressed: () => setState(() => logoBytes = null),
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text("Kaldır"),
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: sirketAdCtrl, enabled: !kurLoading,
                  decoration: InputDecoration(
                    labelText: 'Şirket Adı *', hintText: 'Şirketinizin adını yazın',
                    prefixIcon: Icon(Icons.business, color: AppTheme.primaryColor),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    filled: true, fillColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: telefonCtrl, enabled: !kurLoading,
                  decoration: InputDecoration(
                    labelText: 'Telefon', hintText: '+90 555 123 4567',
                    prefixIcon: Icon(Icons.phone_outlined, color: AppTheme.primaryColor),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    filled: true, fillColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: adresCtrl, enabled: !kurLoading, maxLines: 2,
                  decoration: InputDecoration(
                    labelText: 'Adres', hintText: 'Şirket adresini yazın',
                    prefixIcon: Icon(Icons.location_on_outlined, color: AppTheme.primaryColor),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    filled: true, fillColor: Colors.white, alignLabelWithHint: true,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: kurLoading ? null : () => Navigator.pop(ctx),
              child: const Text('İPTAL'),
            ),
            ElevatedButton(
              onPressed: kurLoading
                  ? null
                  : () async {
                      if (sirketAdCtrl.text.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Lütfen şirket adını girin.')),
                        );
                        return;
                      }
                      setState(() => kurLoading = true);
                      try {
                        String? logoUrl;
                        if (logoBytes != null) {
                          try {
                            final ref = FirebaseStorage.instance.ref(
                              'sirket_logolari/${currentEmail}_logo_${DateTime.now().millisecondsSinceEpoch}.png',
                            );
                            await ref.putData(logoBytes!);
                            logoUrl = await ref.getDownloadURL();
                          } catch (e) {
                            logoUrl = null;
                          }
                        }
                        await FirebaseFirestore.instance.collection('sirketler').add({
                          'ad': sirketAdCtrl.text,
                          'yoneticiEposta': currentEmail,
                          'yoneticiIletisimEposta': currentEmail,
                          'telefon': telefonCtrl.text,
                          'adres': adresCtrl.text,
                          'logoUrl': logoUrl,
                          'personelListesi': [],
                          'olusturmaTarihi': FieldValue.serverTimestamp(),
                          'aktif': true,
                        });
                        if (!ctx.mounted || !mounted) return;
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Şirket başarıyla kuruldu!'), backgroundColor: Colors.green),
                        );
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red));
                      } finally {
                        if (mounted) setState(() => kurLoading = false);
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: kurLoading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Colors.white), strokeWidth: 2))
                  : const Text('ŞİRKET KUR'),
            ),
          ],
        ),
      ),
    );
  }

  void _personelKayitDialog() {
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    bool kayitLoading = false;
    String? hataMetni;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            "Personel Kaydı",
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: AppTheme.primaryColor,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hataMetni != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, color: Colors.red.shade700),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            hataMetni!,
                            style: TextStyle(
                              color: Colors.red.shade900,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: AppTheme.primaryColor),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          "Yöneticinizin size verdiği email adresiyle kayıt olun.",
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: emailCtrl,
                  enabled: !kayitLoading,
                  decoration: InputDecoration(
                    labelText: "Email",
                    hintText: "yonetici@sirket.com tarafından eklenen email",
                    prefixIcon: Icon(Icons.email_outlined, color: AppTheme.primaryColor),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: AppTheme.primaryColor, width: 2),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passCtrl,
                  enabled: !kayitLoading,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: "Şifre",
                    hintText: "Güçlü bir şifre girin",
                    prefixIcon: Icon(Icons.lock_outline, color: AppTheme.primaryColor),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: AppTheme.primaryColor, width: 2),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: kayitLoading ? null : () => Navigator.pop(ctx),
              style: TextButton.styleFrom(
                foregroundColor: Colors.grey.shade600,
              ),
              child: const Text("İPTAL"),
            ),
            ElevatedButton(
              onPressed: kayitLoading
                  ? null
                  : () async {
                      if (emailCtrl.text.isEmpty || passCtrl.text.isEmpty) {
                        setDialogState(() {
                          hataMetni = "Lütfen tüm alanları doldurun";
                        });
                        return;
                      }

                      setDialogState(() {
                        kayitLoading = true;
                        hataMetni = null;
                      });

                      try {
                        // ÖNCELİKLE: Şirkette bu email'e sahip personel var mı kontrol et
                        var sirketSnap = await FirebaseFirestore.instance.collection('sirketler').get();
                        bool bulundu = false;

                        for (var doc in sirketSnap.docs) {
                          Sirket s = Sirket.fromFirestore(doc);
                          try {
                            s.personelListesi.firstWhere(
                              (p) => _normalizeEmail(p.email) == _normalizeEmail(emailCtrl.text),
                            );
                            bulundu = true;
                            break;
                          } catch (e) {
                            // Bu şirkette yok
                          }
                        }

                        // Email personel listesinde yoksa kayıt yapma
                        if (!bulundu) {
                          setDialogState(() {
                            kayitLoading = false;
                            hataMetni = "Bu email adresi henüz hiçbir şirkete personel olarak eklenmemiş. "
                                "Lütfen yöneticinizin sizi önce personel olarak eklemesini sağlayın.";
                          });
                          return;
                        }

                        // Email personel listesinde varsa Firebase Auth'ta kullanıcı oluştur
                        await FirebaseAuth.instance.createUserWithEmailAndPassword(
                          email: emailCtrl.text.trim(),
                          password: passCtrl.text.trim(),
                        );

                        if (!ctx.mounted || !mounted) return;
                        Navigator.pop(ctx);

                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text("Kayıt başarılı! Şimdi giriş yapabilirsiniz."),
                              backgroundColor: Colors.green,
                              duration: Duration(seconds: 2),
                            ),
                          );
                        }

                        // Kullanıcıyı çıkış yaptır (giriş ekranından girmesi için)
                        await FirebaseAuth.instance.signOut();
                      } catch (e) {
                        setDialogState(() {
                          kayitLoading = false;
                          hataMetni = "Hata: $e";
                        });
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.secondaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: kayitLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        strokeWidth: 2,
                      ),
                    )
                  : const Text("KAYIT OL"),
            )
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppTheme.primaryColor.withValues(alpha: 0.1),
              AppTheme.secondaryColor.withValues(alpha: 0.1),
            ],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(isMobile ? 20.0 : 40.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo ve başlık
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppTheme.primaryColor, AppTheme.secondaryColor],
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.apartment, size: 45, color: Colors.white),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    "İNŞAAT YÖNETİM",
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryColor,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Proje ve işinizi kolaylıkla yönetin",
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey.shade600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 48),
                  
                  // Email TextField
                  TextField(
                    controller: _emailCtrl,
                    enabled: !_loading,
                    decoration: InputDecoration(
                      labelText: "E-Posta",
                      prefixIcon: Icon(Icons.email_outlined, color: AppTheme.primaryColor),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.transparent),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AppTheme.primaryColor, width: 2),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Password TextField
                  TextField(
                    controller: _passCtrl,
                    enabled: !_loading,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: "Şifre",
                      prefixIcon: Icon(Icons.lock_outline, color: AppTheme.primaryColor),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.transparent),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AppTheme.primaryColor, width: 2),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 28),
                  
                  // Giriş Yap Butonu
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _girisYap,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.grey.shade300,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                      child: _loading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                strokeWidth: 2,
                              ),
                            )
                          : Text(
                              "GİRİŞ YAP",
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Yeni Şirket Kur Butonu
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton(
                      onPressed: _loading ? null : _sirketKurDialog,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primaryColor,
                        side: BorderSide(color: AppTheme.primaryColor, width: 1.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        "YENİ ŞİRKET KUR",
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: AppTheme.primaryColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  // Personel Kaydı Butonu
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton(
                      onPressed: _loading ? null : _personelKayitDialog,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.secondaryColor,
                        side: BorderSide(color: AppTheme.secondaryColor, width: 1.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        "PERSONEL OLARAK KAYIT OL",
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: AppTheme.secondaryColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}