import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../project_core.dart';
import '../theme/app_theme.dart';
import '../utils/error_handler.dart';
import '../payment_service.dart';
import '../main.dart' show AuthGate;
import 'paywall_screen.dart';

class SettingsSayfasi extends StatefulWidget {
  const SettingsSayfasi({super.key});

  @override
  State<SettingsSayfasi> createState() => _SettingsSayfasiState();
}

class _SettingsSayfasiState extends State<SettingsSayfasi> {
  late Sirket _sirket;
  bool _loading = true;
  bool _saving = false;

  bool get _isCompanyOwner {
    final sirketEmail = SistemYoneticisi().aktifSirket?.yoneticiEposta.trim().toLowerCase();
    final kullaniciEmail = (SistemYoneticisi().girisYapanEmail ?? '').trim().toLowerCase();
    return sirketEmail == kullaniciEmail;
  }

  bool get _isAdmin => _isCompanyOwner || (SistemYoneticisi().aktifKullaniciYetkileri?.adminMi == true);

  late TextEditingController _adCtrl;
  late TextEditingController _telefonCtrl;
  late TextEditingController _adresCtrl;

  @override
  void initState() {
    super.initState();
    _sirket = SistemYoneticisi().aktifSirket!;
    _adCtrl = TextEditingController(text: _sirket.ad);
    _telefonCtrl = TextEditingController(text: _sirket.telefon ?? '');
    _adresCtrl = TextEditingController(text: _sirket.adres ?? '');
    _loading = false;
  }

  @override
  void dispose() {
    _adCtrl.dispose();
    _telefonCtrl.dispose();
    _adresCtrl.dispose();
    super.dispose();
  }

  Future<void> _guncelleSirketBilgileri() async {
    if (!_isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Şirket bilgilerini sadece yetkililer düzenleyebilir")),
      );
      return;
    }
    if (_adCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Şirket adı boş olamaz")),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      await FirebaseFirestore.instance
          .collection('sirketler')
          .doc(_sirket.id)
          .update({
        'ad': _adCtrl.text,
        'telefon': _telefonCtrl.text,
        'adres': _adresCtrl.text,
      });

      // Yerel sistem yöneticisini güncelle
      _sirket.ad = _adCtrl.text;
      _sirket.telefon = _telefonCtrl.text;
      _sirket.adres = _adresCtrl.text;
      SistemYoneticisi().aktifSirket = _sirket;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Şirket bilgileri güncellendi"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(hataCevir(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _logoGuncelle() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );

      if (image == null) return;

      setState(() => _saving = true);

      try {
        // Eski logoyu sil
        if (_sirket.logoUrl != null) {
          try {
            final oldRef = FirebaseStorage.instance.refFromURL(_sirket.logoUrl!);
            await oldRef.delete();
          } catch (e) {
            // Eski logo silme başarısız olsa devam et
          }
        }

        // Yeni logoyu yükle
        final ref = FirebaseStorage.instance.ref(
          'sirket_logolari/${_sirket.id}_logo_${DateTime.now().millisecondsSinceEpoch}.png',
        );

        final bytes = await image.readAsBytes();
        await ref.putData(bytes);

        final logoUrl = await ref.getDownloadURL();

        // Firestore'da güncelle
        await FirebaseFirestore.instance
            .collection('sirketler')
            .doc(_sirket.id)
            .update({'logoUrl': logoUrl});

        // Yerel veriyi güncelle
        _sirket.logoUrl = logoUrl;
        SistemYoneticisi().aktifSirket = _sirket;

        if (mounted) {
          setState(() {});
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Logo güncellendi"),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(hataCevir(e))),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _sifreDegistir() async {
    final yeniSifre1Ctrl = TextEditingController();
    final yeniSifre2Ctrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          "Şifre Değiştir",
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: AppTheme.primaryColor,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: yeniSifre1Ctrl,
              obscureText: true,
              decoration: InputDecoration(
                labelText: "Yeni Şifre",
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
            const SizedBox(height: 12),
            TextField(
              controller: yeniSifre2Ctrl,
              obscureText: true,
              decoration: InputDecoration(
                labelText: "Şifreyi Onayla",
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
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("İPTAL"),
          ),
          ElevatedButton(
            onPressed: () async {
              if (yeniSifre1Ctrl.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Şifre boş olamaz")),
                );
                return;
              }

              if (yeniSifre1Ctrl.text != yeniSifre2Ctrl.text) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Şifreler eşleşmiyor")),
                );
                return;
              }

              try {
                await FirebaseAuth.instance.currentUser?.updatePassword(yeniSifre1Ctrl.text);
                if (mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Şifre değiştirildi"),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(hataCevir(e))),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
            ),
            child: const Text("KAYDET"),
          ),
        ],
      ),
    );
  }

  Future<void> _cikisYap() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Çıkış Yap"),
        content: const Text("Emin misiniz?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("İPTAL"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text("EVET"),
          ),
        ],
      ),
    );

    if (confirm == true) {
      SistemYoneticisi().temizle();
      await FirebaseAuth.instance.signOut();
    }
  }

  Future<void> _hesabiSil() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Hesabı Sil", style: TextStyle(color: Colors.red.shade700)),
        content: const Text(
          "Hesabınız ve tüm ilişkili verileriniz kalıcı olarak silinecektir. "
          "Bu işlem geri alınamaz.\n\n"
          "Aktif bir aboneliğiniz varsa, lütfen önce Ayarlar > Apple Kimliği > Abonelikler bölümünden iptal edin.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("İPTAL"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("HESABIMI SİL", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // Ek onay — email yazarak doğrulama
    final emailCtrl = TextEditingController();
    final user = FirebaseAuth.instance.currentUser;
    final userEmail = (user?.email ?? '').trim().toLowerCase();

    final emailConfirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Onay"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Silme işlemini onaylamak için email adresinizi yazın:"),
            const SizedBox(height: 12),
            TextField(
              controller: emailCtrl,
              decoration: InputDecoration(
                hintText: userEmail,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("İPTAL"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("ONAYLA", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (emailConfirm != true || emailCtrl.text.trim().toLowerCase() != userEmail) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Email adresi eşleşmedi. İşlem iptal edildi.")),
        );
      }
      return;
    }

    setState(() => _saving = true);
    try {
      // 1. Kullanıcı Firestore verilerini sil
      if (user != null) {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).delete();
      }

      // 2. Firebase Auth hesabını sil
      await user?.delete();

      // 3. Temizle ve çıkış yap
      SistemYoneticisi().temizle();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Hesabınız silindi."), backgroundColor: Colors.green),
        );
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AuthGate()),
          (_) => false,
        );
      }
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Güvenlik nedeniyle önce çıkış yapıp tekrar giriş yapın, ardından hesabı silin."),
              duration: Duration(seconds: 5),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(hataCevir(e))),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(hataCevir(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _yetkiMetniOlustur(PersonelYetki personel) {
    if (personel.adminMi) return "Admin (Tüm yetkiler)";
    List<String> yetkiler = [];
    if (personel.goruntulemeRuhsat) yetkiler.add("Ruhsat");
    if (personel.goruntulemeSantiye) yetkiler.add("Şantiye");
    if (personel.goruntulemeMuhasebe) yetkiler.add("Muhasebe");
    return yetkiler.isEmpty ? "Yetki yok" : yetkiler.join(", ");
  }

  Future<void> _personelEkle() async {
    if (!_isCompanyOwner) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Sadece şirket yetkilisi personel yetkilerini değiştirebilir")),
        );
      }
      return;
    }
    final emailCtrl = TextEditingController();
    bool ruhsat = true;
    bool santiye = true;
    bool muhasebe = true;
    bool admin = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            "Yeni Personel Ekle",
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: AppTheme.primaryColor,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: emailCtrl,
                  decoration: InputDecoration(
                    labelText: "Email",
                    hintText: "personel@sirket.com",
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
                const SizedBox(height: 16),
                Text(
                  "Yetkiler",
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  value: admin,
                  onChanged: (val) {
                    setDialogState(() {
                      admin = val ?? false;
                      if (admin) {
                        ruhsat = true;
                        santiye = true;
                        muhasebe = true;
                      }
                    });
                  },
                  title: const Text("Admin (Tüm yetkiler)"),
                  activeColor: AppTheme.primaryColor,
                  dense: true,
                ),
                const Divider(),
                CheckboxListTile(
                  value: ruhsat,
                  onChanged: admin ? null : (val) => setDialogState(() => ruhsat = val ?? false),
                  title: const Text("Ruhsat"),
                  activeColor: AppTheme.primaryColor,
                  dense: true,
                ),
                CheckboxListTile(
                  value: santiye,
                  onChanged: admin ? null : (val) => setDialogState(() => santiye = val ?? false),
                  title: const Text("Şantiye"),
                  activeColor: AppTheme.primaryColor,
                  dense: true,
                ),
                CheckboxListTile(
                  value: muhasebe,
                  onChanged: admin ? null : (val) => setDialogState(() => muhasebe = val ?? false),
                  title: const Text("Muhasebe"),
                  activeColor: AppTheme.primaryColor,
                  dense: true,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("İPTAL"),
            ),
            ElevatedButton(
              onPressed: () async {
                if (emailCtrl.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Email boş olamaz")),
                  );
                  return;
                }

                final yeniPersonel = PersonelYetki(
                  email: emailCtrl.text.trim(),
                  adminMi: admin,
                  goruntulemeRuhsat: ruhsat,
                  goruntulemeSantiye: santiye,
                  goruntulemeMuhasebe: muhasebe,
                );

                try {
                  final updatedList = [..._sirket.personelListesi, yeniPersonel];
                  final normalizedEmail = emailCtrl.text.trim().toLowerCase();
                  await FirebaseFirestore.instance
                      .collection('sirketler')
                      .doc(_sirket.id)
                      .update({
                    'personelListesi': updatedList.map((p) => p.toMap()).toList(),
                    'emailler': FieldValue.arrayUnion([normalizedEmail]),
                  });

                  _sirket.personelListesi = updatedList;
                  SistemYoneticisi().aktifSirket = _sirket;

                  if (mounted) {
                    setState(() {});
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Personel eklendi"),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(hataCevir(e))),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
              ),
              child: const Text("EKLE"),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _personelDuzenle(PersonelYetki personel) async {
    if (!_isCompanyOwner) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Sadece şirket yetkilisi personel yetkilerini değiştirebilir")),
        );
      }
      return;
    }
    bool ruhsat = personel.goruntulemeRuhsat;
    bool santiye = personel.goruntulemeSantiye;
    bool muhasebe = personel.goruntulemeMuhasebe;
    bool admin = personel.adminMi;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            "Personel Yetkileri Düzenle",
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: AppTheme.primaryColor,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.email, color: AppTheme.primaryColor),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          personel.email,
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  "Yetkiler",
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  value: admin,
                  onChanged: (val) {
                    setDialogState(() {
                      admin = val ?? false;
                      if (admin) {
                        ruhsat = true;
                        santiye = true;
                        muhasebe = true;
                      }
                    });
                  },
                  title: const Text("Admin (Tüm yetkiler)"),
                  activeColor: AppTheme.primaryColor,
                  dense: true,
                ),
                const Divider(),
                CheckboxListTile(
                  value: ruhsat,
                  onChanged: admin ? null : (val) => setDialogState(() => ruhsat = val ?? false),
                  title: const Text("Ruhsat"),
                  activeColor: AppTheme.primaryColor,
                  dense: true,
                ),
                CheckboxListTile(
                  value: santiye,
                  onChanged: admin ? null : (val) => setDialogState(() => santiye = val ?? false),
                  title: const Text("Şantiye"),
                  activeColor: AppTheme.primaryColor,
                  dense: true,
                ),
                CheckboxListTile(
                  value: muhasebe,
                  onChanged: admin ? null : (val) => setDialogState(() => muhasebe = val ?? false),
                  title: const Text("Muhasebe"),
                  activeColor: AppTheme.primaryColor,
                  dense: true,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("İPTAL"),
            ),
            ElevatedButton(
              onPressed: () async {
                personel.adminMi = admin;
                personel.goruntulemeRuhsat = ruhsat;
                personel.goruntulemeSantiye = santiye;
                personel.goruntulemeMuhasebe = muhasebe;

                try {
                  await FirebaseFirestore.instance
                      .collection('sirketler')
                      .doc(_sirket.id)
                      .update({
                    'personelListesi': _sirket.personelListesi.map((p) => p.toMap()).toList(),
                  });

                  SistemYoneticisi().aktifSirket = _sirket;

                  if (mounted) {
                    setState(() {});
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Personel yetkileri güncellendi"),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(hataCevir(e))),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
              ),
              child: const Text("KAYDET"),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _personelSil(PersonelYetki personel) async {
    if (!_isCompanyOwner) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Sadece şirket yetkilisi personel yetkilerini değiştirebilir")),
        );
      }
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Personel Sil"),
        content: Text("${personel.email} adresli personeli silmek istediğinize emin misiniz?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("İPTAL"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text("SİL"),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final silinecekEmail = personel.email.trim().toLowerCase();
        _sirket.personelListesi.removeWhere((p) => p.email == personel.email);
        await FirebaseFirestore.instance
            .collection('sirketler')
            .doc(_sirket.id)
            .update({
          'personelListesi': _sirket.personelListesi.map((p) => p.toMap()).toList(),
          'emailler': FieldValue.arrayRemove([silinecekEmail]),
        });

        SistemYoneticisi().aktifSirket = _sirket;

        if (mounted) {
          setState(() {});
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Personel silindi"),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(hataCevir(e))),
          );
        }
      }
    }
  }

  List<Widget> _buildSubscriptionSection() {
    final sirket = SistemYoneticisi().aktifSirket;
    final subEnd = sirket?.subscriptionEndDate;
    final subType = sirket?.subscriptionType;
    final isActive = subEnd != null && subEnd.isAfter(DateTime.now());
    final isAdmin = SistemYoneticisi().aktifKullaniciYetkileri?.adminMi == true;

    return [
      Text(
        'Abonelik Durumu',
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.bold,
          color: AppTheme.primaryColor,
        ),
      ),
      const SizedBox(height: 12),
      Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    isActive ? Icons.check_circle : Icons.warning_amber_rounded,
                    color: isActive ? Colors.green : Colors.orange,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isActive ? 'Aktif' : 'Pasif',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: isActive ? Colors.green.shade700 : Colors.orange.shade700,
                    ),
                  ),
                ],
              ),
              if (subType != null) ...[
                const SizedBox(height: 8),
                Text('Plan: ${subType == 'yearly' ? 'Yıllık' : subType == 'monthly' ? 'Aylık' : subType}'),
              ],
              if (subEnd != null) ...[
                const SizedBox(height: 4),
                Text('Bitiş: ${DateFormat('dd.MM.yyyy').format(subEnd)}'),
              ],
              if (isAdmin && !isActive && PaymentService().isApplePaymentSupported) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final purchased = await Navigator.push<bool>(
                        context,
                        MaterialPageRoute(builder: (_) => const PaywallScreen(mode: PaywallMode.subscription)),
                      );
                      if (purchased == true && mounted) {
                        final sub = await PaymentService().getSubscriptionStatus();
                        if (sub['active'] == true && sirket != null) {
                          await PaymentService().updateCompanySubscription(
                            sirketId: sirket.id,
                            subscriptionType: sub['type'] as String,
                            subscriptionEndDate: sub['endDate'] as DateTime,
                          );
                        }
                        setState(() {});
                      }
                    },
                    icon: const Icon(Icons.payment),
                    label: const Text('Aboneliği Yenile'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
              if (isAdmin && PaymentService().isApplePaymentSupported) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => launchUrl(
                      Uri.parse('https://apps.apple.com/account/subscriptions'),
                      mode: LaunchMode.externalApplication,
                    ),
                    icon: const Icon(Icons.settings, size: 18),
                    label: const Text('Aboneliği Yönet'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.primaryColor,
                      side: BorderSide(color: AppTheme.primaryColor),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    onPressed: () async {
                      final paymentService = PaymentService();
                      await paymentService.initialize();
                      final restored = await paymentService.restorePurchases();
                      if (mounted) {
                        if (restored) {
                          final sub = await paymentService.getSubscriptionStatus();
                          if (sub['active'] == true && sirket != null) {
                            await paymentService.updateCompanySubscription(
                              sirketId: sirket.id,
                              subscriptionType: sub['type'] as String,
                              subscriptionEndDate: sub['endDate'] as DateTime,
                            );
                          }
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Satın alımlar geri yüklendi.'), backgroundColor: Colors.green),
                          );
                          setState(() {});
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(paymentService.lastError.isNotEmpty
                                ? paymentService.lastError
                                : 'Geri yüklenecek satın alım bulunamadı.')),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.restore, size: 18),
                    label: const Text('Satın Alımları Geri Yükle'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.grey.shade700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      const SizedBox(height: 24),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Ayarlar"),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        centerTitle: true,
        elevation: 2,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Logo Bölümü
                  Center(
                    child: Column(
                      children: [
                        Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: AppTheme.primaryColor.withValues(alpha: 0.3),
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            color: AppTheme.primaryColor.withValues(alpha: 0.05),
                          ),
                          child: _sirket.logoUrl != null
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Image.network(
                                    _sirket.logoUrl!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Icon(
                                        Icons.image_not_supported,
                                        size: 50,
                                        color: AppTheme.primaryColor.withValues(alpha: 0.3),
                                      );
                                    },
                                  ),
                                )
                              : Icon(
                                  Icons.image_outlined,
                                  size: 50,
                                  color: AppTheme.primaryColor.withValues(alpha: 0.3),
                                ),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _saving || !_isAdmin ? null : _logoGuncelle,
                          icon: const Icon(Icons.upload_outlined),
                          label: const Text("Logo Değiştir"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryColor,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Abonelik Durumu
                  ..._buildSubscriptionSection(),

                  // Şirket Bilgileri
                  Text(
                    "Şirket Bilgileri",
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _adCtrl,
                    enabled: !_saving && _isAdmin,
                    decoration: InputDecoration(
                      labelText: "Şirket Adı",
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
                    controller: _telefonCtrl,
                    enabled: !_saving && _isAdmin,
                    decoration: InputDecoration(
                      labelText: "Telefon",
                      prefixIcon: Icon(Icons.phone, color: AppTheme.primaryColor),
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
                    controller: _adresCtrl,
                    enabled: !_saving && _isAdmin,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: "Adres",
                      prefixIcon: Icon(Icons.location_on, color: AppTheme.primaryColor),
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
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _saving || !_isAdmin ? null : _guncelleSirketBilgileri,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                strokeWidth: 2,
                              ),
                            )
                          : const Text("DEĞİŞİKLİKLERİ KAYDET"),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Personel Yönetimi
                  Text(
                    "Personel Yönetimi",
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                      color: Colors.white,
                    ),
                    child: Column(
                      children: [
                        if (!_isCompanyOwner)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                            child: Text(
                              "Sadece şirket yetkilisi personel yetkilerini düzenleyebilir.",
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ),
                        if (_sirket.personelListesi.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              "Henüz personel eklenmemiş",
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Colors.grey.shade600,
                              ),
                            ),
                          )
                        else
                          ..._sirket.personelListesi.map((personel) {
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.1),
                                child: Icon(Icons.person, color: AppTheme.primaryColor),
                              ),
                              title: Text(personel.email),
                              subtitle: Text(
                                _yetkiMetniOlustur(personel),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit_outlined),
                                    onPressed: _isCompanyOwner ? () => _personelDuzenle(personel) : null,
                                    tooltip: "Düzenle",
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                                    onPressed: _isCompanyOwner ? () => _personelSil(personel) : null,
                                    tooltip: "Sil",
                                  ),
                                ],
                              ),
                            );
                          }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: _saving || !_isCompanyOwner ? null : _personelEkle,
                      icon: const Icon(Icons.person_add_outlined),
                      label: const Text("Yeni Personel Ekle"),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primaryColor,
                        side: BorderSide(color: AppTheme.primaryColor, width: 1.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Email Bilgisi
                  Text(
                    "Hesap",
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                      color: Colors.grey.shade50,
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.email, color: AppTheme.primaryColor),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Email",
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _sirket.yoneticiEposta,
                                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: _saving ? null : _sifreDegistir,
                      icon: const Icon(Icons.lock_outlined),
                      label: const Text("Şifre Değiştir"),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primaryColor,
                        side: BorderSide(color: AppTheme.primaryColor, width: 1.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _saving ? null : _cikisYap,
                      icon: const Icon(Icons.logout),
                      label: const Text("Çıkış Yap"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: _saving ? null : _hesabiSil,
                      icon: const Icon(Icons.delete_forever_outlined),
                      label: const Text("Hesabımı Sil"),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red.shade700,
                        side: BorderSide(color: Colors.red.shade300, width: 1.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }
}
