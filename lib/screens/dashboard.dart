import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../project_core.dart';
import '../notification_service.dart';
import '../models/project_model.dart';
import '../theme/app_theme.dart';
import 'teklif_screen.dart';
import 'arsiv_screen.dart';
import 'new_project_screen.dart';
import 'project_details_screen.dart';
import 'project_archive_screen.dart';
import 'company_finance_dashboard.dart';
import 'cari_hesap_screen.dart';
import 'settings_screen.dart';
import '../services/firebase_service.dart';
import '../utils/responsive_utils.dart' as resp;
import '../main.dart' show AuthGate;
import '../utils/format_utils.dart' as format_utils;
import '../utils/error_handler.dart';

class DashboardSayfasi extends StatefulWidget {
  const DashboardSayfasi({super.key});

  @override
  State<DashboardSayfasi> createState() => _DashboardSayfasiState();
}

class _DashboardSayfasiState extends State<DashboardSayfasi> {
  int _navIndex = 0;
  final GlobalKey _notificationKey = GlobalKey();

  late String _companyId;
  StreamSubscription<User?>? _authSub;

  @override
  void initState() {
    super.initState();
    _companyId = SistemYoneticisi().aktifSirket?.id ?? '';
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user == null && mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AuthGate()),
          (route) => false,
        );
      }
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  Future<void> _sirketDegistir() async {
    final email = SistemYoneticisi().girisYapanEmail ?? '';
    if (email.isEmpty) return;

    try {
      final query = await FirebaseFirestore.instance
          .collection('sirketler')
          .where('emailler', arrayContains: email)
          .get();

      if (query.docs.length <= 1) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Yalnızca bir şirkete kayıtlısınız.')),
          );
        }
        return;
      }

      final sirketler = query.docs.map((d) => Sirket.fromFirestore(d)).toList();
      final mevcutId = SistemYoneticisi().aktifSirket?.id;

      if (!mounted) return;
      final secilen = await showDialog<Sirket>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Şirket Değiştir'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: sirketler.length,
              itemBuilder: (context, i) {
                final s = sirketler[i];
                final aktifMi = s.id == mevcutId;
                return ListTile(
                  leading: Icon(
                    aktifMi ? Icons.business : Icons.business_outlined,
                    color: aktifMi ? AppTheme.primaryColor : null,
                  ),
                  title: Text(
                    s.ad,
                    style: TextStyle(
                      fontWeight: aktifMi ? FontWeight.bold : FontWeight.normal,
                      color: aktifMi ? AppTheme.primaryColor : null,
                    ),
                  ),
                  subtitle: Text(aktifMi ? 'Aktif' : s.yoneticiEposta),
                  trailing: aktifMi ? const Icon(Icons.check, color: Colors.green) : null,
                  onTap: aktifMi ? null : () => Navigator.pop(ctx, s),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('İPTAL'),
            ),
          ],
        ),
      );

      if (secilen != null && mounted) {
        final user = FirebaseAuth.instance.currentUser;
        if (user == null) return;

        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'sirketId': secilen.id,
        }, SetOptions(merge: true));

        // Yetkiyi belirle
        final normalEmail = email.trim().toLowerCase();
        PersonelYetki? yetki;
        if (normalEmail == secilen.yoneticiEposta.trim().toLowerCase()) {
          yetki = PersonelYetki(email: normalEmail, adminMi: true);
        } else {
          final match = secilen.personelListesi.where(
            (p) => p.email.trim().toLowerCase() == normalEmail,
          );
          yetki = match.isNotEmpty ? match.first : null;
        }

        SistemYoneticisi().aktifSirket = secilen;
        SistemYoneticisi().aktifKullaniciYetkileri = yetki;

        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const DashboardSayfasi()),
            (route) => false,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(hataCevir(e))),
        );
      }
    }
  }

  Widget _buildNavIcon({
    required String tooltip,
    required IconData icon,
    required IconData selectedIcon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        icon: Icon(
          isSelected ? selectedIcon : icon,
          color: isSelected ? AppTheme.primaryColor : Colors.grey.shade600,
        ),
        onPressed: onTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (SistemYoneticisi().cikisYapiliyor) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final sistem = SistemYoneticisi();
    final canTeklif = sistem.yetkiVarMi('teklif');
    final canMuhasebe = sistem.yetkiVarMi('muhasebe');
    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = screenWidth < 900;
    final maxIndex = canMuhasebe ? 3 : 2;
    final navIndex = _navIndex > maxIndex ? 0 : _navIndex;

    if (!canTeklif) {
      return Scaffold(
        backgroundColor: Colors.grey.shade100,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.lock_outline, size: 48, color: Colors.grey),
                SizedBox(height: 12),
                Text(
                  "Bu sayfayı görüntülemek için yetkiniz yok.",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: GestureDetector(
          onTap: _sirketDegistir,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  SistemYoneticisi().aktifSirket?.ad ?? 'Lento',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.swap_horiz, size: 18),
            ],
          ),
        ),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        elevation: 1,
        actions: [
          StreamBuilder<QuerySnapshot>(
            stream: BildirimServisi.bildirimleriDinle(),
            builder: (context, snapshot) {
              int okunmayanSayisi = 0;
              if (snapshot.hasData && !snapshot.hasError) {
                okunmayanSayisi = BildirimServisi.okunmamisBildirimler(snapshot.data!).length;
              }
              return Stack(
                children: [
                  IconButton(
                    key: _notificationKey,
                    icon: const Icon(Icons.notifications_outlined),
                    tooltip: 'Bildirimler',
                    onPressed: () => _showNotificationsDropdown(context),
                  ),
                  if (okunmayanSayisi > 0)
                    Positioned(
                      right: 6,
                      top: 6,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                        child: Text(
                          okunmayanSayisi > 99 ? '99+' : okunmayanSayisi.toString(),
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          if (!isCompact) ...[
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: 'Ayarlar',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (c) => const SettingsSayfasi()),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Çıkış',
              onPressed: () async {
                SistemYoneticisi().temizle();
                await FirebaseAuth.instance.signOut();
              },
            ),
          ] else
            PopupMenuButton<String>(
              tooltip: 'Menü',
              onSelected: (value) async {
                if (value == 'settings') {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (c) => const SettingsSayfasi()),
                  );
                } else if (value == 'switch_company') {
                  _sirketDegistir();
                } else if (value == 'logout') {
                  SistemYoneticisi().temizle();
                  await FirebaseAuth.instance.signOut();
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'switch_company', child: Text('Şirket Değiştir')),
                PopupMenuItem(value: 'settings', child: Text('Ayarlar')),
                PopupMenuItem(value: 'logout', child: Text('Çıkış')),
              ],
            ),
        ],
      ),
      drawer: isCompact
          ? Drawer(
              child: SafeArea(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                      child: Row(
                        children: const [
                          Text('Lento', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.home_outlined),
                      title: const Text('Projeler'),
                      selected: navIndex == 0,
                      onTap: () {
                        Navigator.pop(context);
                        setState(() => _navIndex = 0);
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.description_outlined),
                      title: const Text('Teklifler'),
                      selected: navIndex == 1,
                      onTap: () {
                        Navigator.pop(context);
                        setState(() => _navIndex = 1);
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.account_balance_wallet_outlined),
                      title: const Text('Cariler'),
                      selected: navIndex == 2,
                      onTap: () {
                        Navigator.pop(context);
                        setState(() => _navIndex = 2);
                      },
                    ),
                    if (canMuhasebe)
                      ListTile(
                        leading: const Icon(Icons.assessment_outlined),
                        title: const Text('Muhasebe'),
                        selected: navIndex == 3,
                        onTap: () {
                          Navigator.pop(context);
                          setState(() => _navIndex = 3);
                        },
                      ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.folder_outlined),
                      title: const Text('Proje Arşivi'),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (c) => ProjectArchiveScreen(companyId: _companyId),
                          ),
                        );
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.archive_outlined),
                      title: const Text('Teklif Arşivi'),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (c) => const ArsivSayfasi()),
                        );
                      },
                    ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.settings_outlined),
                      title: const Text('Ayarlar'),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (c) => const SettingsSayfasi()),
                        );
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.logout),
                      title: const Text('Çıkış'),
                      onTap: () async {
                        Navigator.pop(context);
                        SistemYoneticisi().temizle();
                        await FirebaseAuth.instance.signOut();
                      },
                    ),
                  ],
                ),
              ),
            )
          : null,
      body: isCompact
          ? navIndex == 0
              ? _ProjectsTab(
                  companyId: _companyId,
                  onProjectTap: (projectId) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (c) => ProjectDetailsScreen(projectId: projectId),
                      ),
                    );
                  },
                )
                : navIndex == 1
                  ? const _TekliflerListesi()
                  : navIndex == 2
                    ? const _CarilerTab()
                    : canMuhasebe
                        ? CompanyFinanceDashboard(companyId: _companyId)
                        : const Center(child: Text('Yetkiniz yok'))
          : Row(
              children: [
                Container(
                  width: 56,
                  color: Colors.white,
                  child: Column(
                    children: [
                      const SizedBox(height: 8),
                      _buildNavIcon(
                        tooltip: 'Projeler',
                        icon: Icons.home_outlined,
                        selectedIcon: Icons.home,
                        isSelected: navIndex == 0,
                        onTap: () => setState(() => _navIndex = 0),
                      ),
                      _buildNavIcon(
                        tooltip: 'Teklifler',
                        icon: Icons.description_outlined,
                        selectedIcon: Icons.description,
                        isSelected: navIndex == 1,
                        onTap: () => setState(() => _navIndex = 1),
                      ),
                      _buildNavIcon(
                        tooltip: 'Cariler',
                        icon: Icons.account_balance_wallet_outlined,
                        selectedIcon: Icons.account_balance_wallet,
                        isSelected: navIndex == 2,
                        onTap: () => setState(() => _navIndex = 2),
                      ),
                      if (canMuhasebe)
                        _buildNavIcon(
                          tooltip: 'Muhasebe',
                          icon: Icons.assessment_outlined,
                          selectedIcon: Icons.assessment,
                          isSelected: navIndex == (canMuhasebe ? 3 : -1),
                          onTap: () => setState(() => _navIndex = 3),
                        ),
                      const Spacer(),
                      Tooltip(
                        message: 'Proje Arşivi',
                        child: IconButton(
                          icon: const Icon(Icons.folder_outlined),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (c) => ProjectArchiveScreen(companyId: _companyId),
                              ),
                            );
                          },
                        ),
                      ),
                      Tooltip(
                        message: 'Teklif Arşivi',
                        child: IconButton(
                          icon: const Icon(Icons.archive_outlined),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (c) => const ArsivSayfasi()),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
                Expanded(
                  child: navIndex == 0
                      ? _ProjectsTab(
                          companyId: _companyId,
                          onProjectTap: (projectId) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (c) => ProjectDetailsScreen(projectId: projectId),
                              ),
                            );
                          },
                        )
                        : navIndex == 1
                          ? const _TekliflerListesi()
                          : navIndex == 2
                            ? const _CarilerTab()
                            : canMuhasebe
                                ? CompanyFinanceDashboard(companyId: _companyId)
                                : const Center(child: Text('Yetkiniz yok')),
                ),
              ],
            ),
      bottomNavigationBar: isCompact
          ? BottomNavigationBar(
            currentIndex: navIndex,
              onTap: (i) => setState(() => _navIndex = i),
              items: [
                const BottomNavigationBarItem(
                  icon: Icon(Icons.home_outlined),
                  activeIcon: Icon(Icons.home),
                  label: 'Projeler',
                ),
                const BottomNavigationBarItem(
                  icon: Icon(Icons.description_outlined),
                  activeIcon: Icon(Icons.description),
                  label: 'Teklifler',
                ),
                const BottomNavigationBarItem(
                  icon: Icon(Icons.account_balance_wallet_outlined),
                  activeIcon: Icon(Icons.account_balance_wallet),
                  label: 'Cariler',
                ),
                if (canMuhasebe)
                  const BottomNavigationBarItem(
                    icon: Icon(Icons.assessment_outlined),
                    activeIcon: Icon(Icons.assessment),
                    label: 'Muhasebe',
                  ),
              ],
              type: BottomNavigationBarType.fixed,
            )
          : null,
      floatingActionButton: navIndex == 0
          ? (resp.isMobile(context)
              ? FloatingActionButton(
                  onPressed: () async {
                    if (!mounted) return;
                    final projectId = await Navigator.push<String?>(
                      context,
                      MaterialPageRoute(
                        builder: (c) => NewProjectScreen(companyId: _companyId),
                      ),
                    );
                    if (!mounted || projectId == null) return;
                    await Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (c) => ProjectDetailsScreen(projectId: projectId),
                      ),
                    );
                  },
                  backgroundColor: AppTheme.primaryColor,
                  tooltip: 'Yeni Proje',
                  child: const Icon(Icons.add),
                )
              : FloatingActionButton.extended(
                  onPressed: () async {
                    if (!mounted) return;
                    // ignore: use_build_context_synchronously
                    final projectId = await Navigator.push<String?>(
                      context,
                      MaterialPageRoute(
                        builder: (c) => NewProjectScreen(companyId: _companyId),
                      ),
                    );
                    if (!mounted || projectId == null) return;
                    // ignore: use_build_context_synchronously
                    await Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (c) => ProjectDetailsScreen(projectId: projectId),
                      ),
                    );
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Yeni Proje'),
                  backgroundColor: AppTheme.primaryColor,
                ))
            : navIndex == 1
              ? (resp.isMobile(context)
                  ? FloatingActionButton(
                      heroTag: 'yeniTeklif',
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (c) => const TeklifSayfasi(),
                          ),
                        );
                      },
                      backgroundColor: AppTheme.primaryColor,
                      tooltip: 'Yeni Teklif',
                      child: const Icon(Icons.add),
                    )
                  : FloatingActionButton.extended(
                      heroTag: 'yeniTeklif',
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (c) => const TeklifSayfasi(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Yeni Teklif'),
                      backgroundColor: AppTheme.primaryColor,
                    ))
              : navIndex == 2
                ? (resp.isMobile(context)
                    ? FloatingActionButton(
                        onPressed: () => _yeniCariDialogGlobal(context),
                        backgroundColor: AppTheme.primaryColor,
                        tooltip: 'Cari Ekle',
                        child: const Icon(Icons.add),
                      )
                    : FloatingActionButton.extended(
                        onPressed: () => _yeniCariDialogGlobal(context),
                        icon: const Icon(Icons.add),
                        label: const Text('Cari Ekle'),
                        backgroundColor: AppTheme.primaryColor,
                      ))
                : null,
    );
  }

  Future<void> _yeniCariDialogGlobal(BuildContext context) async {
    final adCtrl = TextEditingController();
    final telefonCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final adresCtrl = TextEditingController();
    String tip = 'musteri';

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Yeni Cari Hesap'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: RadioListTile<String>(
                        title: const Text('Müşteri', style: TextStyle(fontSize: 13)),
                        value: 'musteri',
                        groupValue: tip,
                        onChanged: (v) => setState(() => tip = v!),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    Expanded(
                      child: RadioListTile<String>(
                        title: const Text('Tedarikçi', style: TextStyle(fontSize: 13)),
                        value: 'tedarikci',
                        groupValue: tip,
                        onChanged: (v) => setState(() => tip = v!),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: adCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Ad / Firma Adı *',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: telefonCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Telefon',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: emailCtrl,
                  decoration: const InputDecoration(
                    labelText: 'E-posta',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: adresCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Adres',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('İptal'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (adCtrl.text.trim().isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Ad/Firma adı gerekli')),
                  );
                  return;
                }

                await FirebaseFirestore.instance.collection('cari_hesaplar').add({
                  'ad': adCtrl.text.trim(),
                  'tip': tip,
                  'telefon': telefonCtrl.text.trim(),
                  'email': emailCtrl.text.trim(),
                  'adres': adresCtrl.text.trim(),
                  'bakiye': 0.0,
                  'projectId': '',
                  'projectIds': <String>[],
                  'olusturmaTarihi': FieldValue.serverTimestamp(),
                  'sirketId': SistemYoneticisi().aktifSirket?.id ?? '',
                });

                if (context.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Cari hesap oluşturuldu')),
                  );
                }
              },
              child: const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );
  }

  void _showNotificationsDropdown(BuildContext context) {
    final keyContext = _notificationKey.currentContext;
    if (keyContext == null) return;

    final RenderBox button = keyContext.findRenderObject() as RenderBox;
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final Offset offset = button.localToGlobal(Offset.zero, ancestor: overlay);
    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromLTWH(offset.dx, offset.dy + button.size.height, button.size.width, 0),
      Offset.zero & overlay.size,
    );

    showMenu<int>(
      context: context,
      position: position,
      items: [
        PopupMenuItem(
          enabled: false,
          child: SizedBox(
            width: (MediaQuery.of(context).size.width - 24).clamp(260, 360).toDouble(),
            child: StreamBuilder<QuerySnapshot>(
              stream: BildirimServisi.bildirimleriDinle(),
              builder: (ctx, snap) {
                if (snap.hasError || !snap.hasData || snap.data!.docs.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.notifications_off_outlined, size: 40, color: Colors.grey.shade300),
                        const SizedBox(height: 8),
                        Text('Bildirim yok', style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
                      ],
                    ),
                  );
                }

                final okunmamis = BildirimServisi.okunmamisBildirimler(snap.data!);

                if (okunmamis.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_outline, size: 40, color: Colors.green.shade300),
                        const SizedBox(height: 8),
                        Text('Tüm bildirimler okundu', style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
                      ],
                    ),
                  );
                }

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
                      child: Row(
                        children: [
                          const Icon(Icons.notifications_active, size: 18, color: Colors.deepOrange),
                          const SizedBox(width: 6),
                          Text('Bildirimler', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.deepOrange,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text('${okunmamis.length}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 1, color: Colors.grey.shade200),
                    const SizedBox(height: 4),
                    ListView.builder(
                  shrinkWrap: true,
                  itemCount: okunmamis.length,
                  itemBuilder: (ctx, i) {
                    final doc = okunmamis[i];
                    final b = doc.data() as Map<String, dynamic>;
                    final baslik = b['baslik'] ?? '';
                    final mesaj = b['mesaj'] ?? '';
                    final gonderen = b['gonderen'] ?? '';
                    final projeId = b['projeId'] ?? '';
                    final modul = b['modul'] ?? '';
                    final tarih = b['tarih'] as Timestamp?;

                    // Modüle göre renk ve ikon
                    Color modulRenk;
                    IconData modulIkon;
                    switch (modul) {
                      case 'ruhsat':
                        modulRenk = Colors.red;
                        modulIkon = Icons.description_outlined;
                        break;
                      case 'santiye':
                        modulRenk = Colors.orange;
                        modulIkon = Icons.construction;
                        break;
                      case 'muhasebe':
                        modulRenk = Colors.blue;
                        modulIkon = Icons.account_balance_wallet;
                        break;
                      default:
                        modulRenk = Colors.teal;
                        modulIkon = Icons.notifications_active;
                    }

                    // Zaman farkı
                    String zamanStr = '';
                    if (tarih != null) {
                      final fark = DateTime.now().difference(tarih.toDate());
                      if (fark.inMinutes < 1) {
                        zamanStr = 'Az önce';
                      } else if (fark.inMinutes < 60) {
                        zamanStr = '${fark.inMinutes} dk önce';
                      } else if (fark.inHours < 24) {
                        zamanStr = '${fark.inHours} saat önce';
                      } else {
                        zamanStr = '${fark.inDays} gün önce';
                      }
                    }

                    return InkWell(
                      onTap: () async {
                        Navigator.pop(context);
                        await FirebaseFirestore.instance
                            .collection('sirketler')
                            .doc(SistemYoneticisi().aktifSirket?.id)
                            .collection('bildirimler')
                            .doc(doc.id)
                            .update({
                          'okuyanlar': FieldValue.arrayUnion([SistemYoneticisi().girisYapanEmail])
                        });
                        if (!mounted) return;
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (c) => ProjectDetailsScreen(projectId: projeId),
                          ),
                        );
                      },
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 3),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: modulRenk.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(8),
                          border: Border(left: BorderSide(color: modulRenk, width: 3)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: modulRenk.withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(modulIkon, size: 16, color: modulRenk),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(baslik, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: modulRenk)),
                                      ),
                                      if (zamanStr.isNotEmpty)
                                        Text(zamanStr, style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(mesaj, style: const TextStyle(fontSize: 11, color: Colors.black87)),
                                  if (gonderen.toString().isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Row(
                                        children: [
                                          Icon(Icons.person_outline, size: 12, color: Colors.grey.shade500),
                                          const SizedBox(width: 3),
                                          Text(gonderen.toString(), style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------
// CARİLER TAB (Dashboard embedded)
// -----------------------------------------------------------
class _CarilerTab extends StatefulWidget {
  const _CarilerTab();

  @override
  State<_CarilerTab> createState() => _CarilerTabState();
}

class _CarilerTabState extends State<_CarilerTab> {
  String _filtre = 'tum';
  String _arama = '';

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Filtre satırı
        Container(
          color: AppTheme.primaryColor,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          child: Row(
            children: [
              Expanded(child: _filtreButomu('tum', 'Tümü', Icons.list)),
              const SizedBox(width: 8),
              Expanded(child: _filtreButomu('musteri', 'Müşteriler', Icons.people)),
              const SizedBox(width: 8),
              Expanded(child: _filtreButomu('tedarikci', 'Tedarikçiler', Icons.business)),
            ],
          ),
        ),
        // Arama satırı
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Cari ara...',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _arama = v.trim()),
          ),
        ),
        // Cari listesi
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('cari_hesaplar').where('sirketId', isEqualTo: SistemYoneticisi().aktifSirket?.id ?? '').snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                if (SistemYoneticisi().cikisYapiliyor) return const SizedBox.shrink();
                return const Center(child: Text('Cari hesaplar yüklenemedi.'));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              var docs = snapshot.data!.docs.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final tip = data['tip'] ?? 'musteri';
                final ad = (data['ad'] ?? '').toString().toLowerCase();
                bool tipFiltre = _filtre == 'tum' || tip == _filtre;
                bool aramaFiltre = _arama.isEmpty || ad.contains(_arama.toLowerCase());
                return tipFiltre && aramaFiltre;
              }).toList();

              if (docs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.account_balance_wallet_outlined, size: 48, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      Text(
                        _arama.isNotEmpty ? 'Sonuç bulunamadı' : 'Henüz cari hesap kaydı yok',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final doc = docs[index];
                  final data = doc.data() as Map<String, dynamic>;
                  final ad = data['ad'] ?? 'İsimsiz';
                  final tip = data['tip'] ?? 'musteri';
                  final bakiye = (data['bakiye'] as num?)?.toDouble() ?? 0.0;
                  final telefon = data['telefon'] ?? '';
                  final email = data['email'] ?? '';
                  final alacak = bakiye > 0;
                  final renk = alacak ? AppTheme.successColor : Colors.red;
                  final ikon = tip == 'musteri' ? Icons.person_outline : Icons.business_outlined;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    elevation: 1,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Colors.grey.shade200),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (c) => CariDetayScreen(cariId: doc.id, cariAd: ad),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  colors: [renk.withValues(alpha: 0.2), renk.withValues(alpha: 0.1)],
                                ),
                              ),
                              child: Icon(ikon, color: renk, size: 24),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    ad,
                                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.primaryColor,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (telefon.toString().isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(telefon, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey.shade600)),
                                  ],
                                  if (email.toString().isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(email, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.grey.shade600)),
                                  ],
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  bakiye == 0 ? 'Dengede' : (alacak ? 'Alınan' : 'Ödenen'),
                                  style: TextStyle(
                                    color: bakiye == 0 ? Colors.grey : renk,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  format_utils.formatTL(bakiye.abs()),
                                  style: TextStyle(
                                    color: bakiye == 0 ? Colors.grey : renk,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
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

  Widget _filtreButomu(String deger, String etiket, IconData ikon) {
    final aktif = _filtre == deger;
    return InkWell(
      onTap: () => setState(() => _filtre = deger),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: aktif ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: aktif ? AppTheme.primaryColor : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(ikon, size: 18, color: aktif ? AppTheme.primaryColor : Colors.white.withValues(alpha: 0.7)),
            const SizedBox(width: 4),
            Text(
              etiket,
              style: TextStyle(
                color: aktif ? AppTheme.primaryColor : Colors.white.withValues(alpha: 0.7),
                fontWeight: aktif ? FontWeight.w600 : FontWeight.normal,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------
// TEKLİFLER LİSTESİ
// -----------------------------------------------------------
class _TekliflerListesi extends StatefulWidget {
  const _TekliflerListesi();

  @override
  State<_TekliflerListesi> createState() => _TekliflerListesiState();
}

class _TekliflerListesiState extends State<_TekliflerListesi> {
  late TextEditingController _searchCtrl;
  String _durumFiltre = 'teklif'; // Filtre: 'teklif', 'anlasildi', 'tamamlandi', 'all'

  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Arama ve Filtreleme Alanı
        Container(
          padding: const EdgeInsets.all(12),
          color: Colors.white,
          child: Column(
            children: [
              TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  prefixIcon: Icon(Icons.search, color: AppTheme.primaryColor),
                  hintText: "İlçe, mahalle, ada veya parsel ara...",
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Colors.transparent),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: AppTheme.primaryColor, width: 2),
                  ),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
                onChanged: (v) => setState(() {}),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: [
                  FilterChip(
                    label: const Text("Teklif"),
                    selected: _durumFiltre == 'teklif',
                    onSelected: (v) => setState(() => _durumFiltre = 'teklif'),
                    selectedColor: AppTheme.primaryColor.withValues(alpha: 0.2),
                    checkmarkColor: AppTheme.primaryColor,
                  ),
                  FilterChip(
                    label: const Text("Tamamlandı"),
                    selected: _durumFiltre == 'tamamlandi',
                    onSelected: (v) => setState(() => _durumFiltre = 'tamamlandi'),
                    selectedColor: AppTheme.primaryColor.withValues(alpha: 0.2),
                    checkmarkColor: AppTheme.primaryColor,
                  ),
                  FilterChip(
                    label: const Text("Tümü"),
                    selected: _durumFiltre == 'all',
                    onSelected: (v) => setState(() => _durumFiltre = 'all'),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Teklifler Listesi
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _durumFiltre == 'all'
                ? FirebaseFirestore.instance
                    .collection('teklifler')
                    .where('sirketId', isEqualTo: SistemYoneticisi().aktifSirket?.id ?? '')
                    .orderBy('tarih', descending: true)
                    .limit(50)
                    .snapshots()
                : FirebaseFirestore.instance
                    .collection('teklifler')
                    .where('sirketId', isEqualTo: SistemYoneticisi().aktifSirket?.id ?? '')
                    .where('durum', isEqualTo: _durumFiltre)
                    .orderBy('tarih', descending: true)
                    .limit(50)
                    .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                if (SistemYoneticisi().cikisYapiliyor) return const SizedBox.shrink();
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Text(
                      "Veriler yüklenemedi.\n${hataCevir(snapshot.error ?? 'Bilinmeyen hata')}",
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                );
              }

              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return const Center(child: Text("Teklif bulunamadı."));
              }
              final searchTerm = _searchCtrl.text.toLowerCase();
              final filtered = snapshot.data!.docs.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final ilce = (data['ilce'] ?? '').toString().toLowerCase();
                final mahalle = (data['mahalle'] ?? '').toString().toLowerCase();
                final ada = (data['ada'] ?? '').toString().toLowerCase();
                final parsel = (data['parsel'] ?? '').toString().toLowerCase();
                return ilce.contains(searchTerm) ||
                    mahalle.contains(searchTerm) ||
                    ada.contains(searchTerm) ||
                    parsel.contains(searchTerm);
              }).toList();

              if (filtered.isEmpty) {
                return Center(
                  child: Text("'$searchTerm' için teklif bulunamadı."),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(10),
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  var doc = filtered[index];
                  var data = doc.data() as Map<String, dynamic>;
                  DateTime tarih;
                  try {
                    tarih = (data['tarih'] as Timestamp).toDate();
                  } catch (e) {
                    tarih = DateTime.now();
                  }

                  return Card(
                    elevation: 1,
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Colors.grey.shade200),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      leading: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [AppTheme.primaryColor.withValues(alpha: 0.8), AppTheme.primaryColor],
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.description_outlined, color: Colors.white, size: 20),
                      ),
                      title: Text(
                        "${data['ilce']} / ${data['mahalle']}",
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primaryColor,
                        ),
                      ),
                      subtitle: Text(
                        "Ada: ${data['ada']} | Parsel: ${data['parsel']} | ${tarih.day}.${tarih.month}.${tarih.year}",
                        style: Theme.of(context).textTheme.bodySmall,
                      ),

                      trailing: IconButton(
                        icon: Icon(Icons.arrow_forward_ios, size: 14, color: AppTheme.primaryColor.withValues(alpha: 0.6)),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (c) => TeklifSayfasi(mevcutTeklifData: data, mevcutDocId: doc.id),
                            ),
                          );
                        },
                      ),

                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (c) => TeklifSayfasi(mevcutTeklifData: data, mevcutDocId: doc.id),
                          ),
                        );
                      },
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
}

// -----------------------------------------------------------
// PROJELER TAB'I
// -----------------------------------------------------------
class _ProjectsTab extends StatefulWidget {
  final String companyId;
  final Function(String) onProjectTap;

  const _ProjectsTab({
    required this.companyId,
    required this.onProjectTap,
  });

  @override
  State<_ProjectsTab> createState() => _ProjectsTabState();
}

class _ProjectsTabState extends State<_ProjectsTab> {
  final _firebase = FirebaseService();
  final _searchController = TextEditingController();
  String _searchQuery = '';

  static const _ruhsatMaddeleri = [
    'LİHKAB BAŞVURU',
    'LİHKAB SONUÇ',
    'TECAVÜZ DURUMU-SATIN ALMA VB DİĞER HUSUSLAR',
    'İMAR DURUMU BAŞVURU',
    'İMAR DURUMU SONUÇ',
    'FERRUH BÖLGE',
    'İST- KOT ÇİZİMİ',
    'ETÜT',
    'KAROT DURUMU- BİNA BOŞALTMA DURUMU',
    'YOLA TERK DURUMU',
    'YIKIM',
    'FOLYO HAZIRLANMASI',
    'ENCÜMENE GİRİŞ',
    'ENCÜMENDEN ÇIKIŞ',
    'KADASTRO',
    'TAPU',
    '2. LİHKAB',
    '2. İMAR DURUMU',
    '2. KOT- İSTİKAMET',
    'ETÜT ONAYI',
    'MİMARİ',
    'STATİK TASLAK YAPILACAKLAR',
    'STATİK TASLAK YAPILAN-ZEMİNCİYE YÜK ATILANLAR',
    'GERÇEK ZEMİN DEĞERLERİ GELEN',
    'STATİK',
    'YİBF GİRİŞİ',
    'MİMARİ- STATİK UYUM KONTROLÜ',
    'ELK-MEKANİK PROJE',
    'AKUSTİK PROJE',
    'EKB ÖN ONAY HESAP SONUCU',
    'MÜELLİF EVRAKLARI',
    'İSKİ BAŞVURU',
    'İSKİ ONAY',
    'STATİK - MİMARİ RAPORTÖRE DWG AT',
    'YAPI DENETİM VE RAPORTÖR EKSİKLERİNİN GİDERİLMESİ',
    'RUHSAT DİLEKÇESİ',
    'FEN İŞLERİ',
    'YAPI DENETİM PROJE ONAYI',
    'PROJELERİN BELEDİYE ONAYI',
    'MÜTEAHHİT EKSİKLERİNİN İSTENDİĞİ DOSYALAR (NOTER TEMİNAT VS)',
    'HARÇLARIN YATIRILMASI',
    'OTOPARK TAAHHÜTNAMESİ YAPILACAK DOSYALAR',
    'TEMİNAT MEKTUBU TESLİMİ YAPILACAK DOSYALAR',
    'NUMARATAJ',
    'RUHSAT YAZIMI',
    'PROJE VE RUHSATLARIN TESLİMİ',
    'KAT İRTİFAKI DİLEKÇESİ VERİLENLER',
    'KAT İRTİFAKI ONAYLANAN',
  ];

  Future<Map<String, dynamic>> _getRuhsatOzet(String projectId) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('ruhsat')
        .doc(projectId)
        .collection('islemler')
        .get();

    int tamamlanan = 0;
    int devamEden = 0;
    int sonTamamlananSira = 0;
    DateTime? sonIslemTarihi;

    for (var doc in snapshot.docs) {
      final data = doc.data();
      final durum = data['durum'] as int? ?? 0;
      final sira = data['sira'] as int? ?? 0;
      if (durum == 2) {
        tamamlanan++;
        if (sira > sonTamamlananSira) sonTamamlananSira = sira;
      }
      if (durum == 1) devamEden++;

      // En son işlem tarihini bul
      final gt = data['guncellendiTarihi'];
      if (gt != null) {
        DateTime? t;
        if (gt is Timestamp) {
          t = gt.toDate();
        } else if (gt is DateTime) {
          t = gt;
        }
        if (t != null && (sonIslemTarihi == null || t.isAfter(sonIslemTarihi))) {
          sonIslemTarihi = t;
        }
      }
    }

    // Şu anki aşama: devam eden varsa onu göster, yoksa son tamamlananın sonraki adımı
    int aktifSira = 0;
    for (var doc in snapshot.docs) {
      final data = doc.data();
      if ((data['durum'] as int? ?? 0) == 1) {
        final s = data['sira'] as int? ?? 0;
        if (aktifSira == 0 || s < aktifSira) aktifSira = s;
      }
    }
    if (aktifSira == 0 && sonTamamlananSira < _ruhsatMaddeleri.length) {
      aktifSira = sonTamamlananSira + 1;
    }

    return {
      'tamamlanan': tamamlanan,
      'devamEden': devamEden,
      'toplam': _ruhsatMaddeleri.length,
      'aktifSira': aktifSira,
      'sonIslemTarihi': sonIslemTarihi,
    };
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Proje ara...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
            onChanged: (v) => setState(() => _searchQuery = v),
          ),
        ),
        Expanded(
          child: StreamBuilder<List<Project>>(
            stream: _firebase.getProjectsStream(widget.companyId),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                if (SistemYoneticisi().cikisYapiliyor) return const SizedBox.shrink();
                return const Center(
                  child: Text('Projeler yüklenemedi.'),
                );
              }

              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.folder_open_outlined, size: 48, color: Colors.grey),
                      const SizedBox(height: 12),
                      const Text('Henüz proje yok'),
                    ],
                  ),
                );
              }

              final allProjects = snapshot.data!;
              final projects = _searchQuery.isEmpty
                  ? allProjects
                  : allProjects.where((p) => p.name.toLowerCase().contains(_searchQuery.toLowerCase())).toList();

              if (projects.isEmpty) {
                return Center(
                  child: Text(
                    'Aramayla eşleşen proje bulunamadı',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: projects.length,
          itemBuilder: (context, index) {
            final project = projects[index];

            return FutureBuilder<ProjectFinance>(
              future: _firebase.getProjectFinanceSummary(project.id),
              builder: (context, financeSnap) {
                final finance = financeSnap.data;

                return Card(
                  elevation: 1,
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.grey.shade200),
                  ),
                  child: InkWell(
                    onTap: () => widget.onProjectTap(project.id),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      project.name,
                                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.primaryColor,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      '${project.startDate.day}.${project.startDate.month}.${project.startDate.year}',
                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (project.status != ProjectStatus.planning)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _getStatusColor(project.status).withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: _getStatusColor(project.status).withValues(alpha: 0.5),
                                    ),
                                  ),
                                  child: Text(
                                    project.status.name.toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: _getStatusColor(project.status),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (finance != null && SistemYoneticisi().yetkiVarMi('muhasebe'))
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                Chip(
                                  label: Text(
                                    'Gelir: ${formatNumber(finance.totalIncome)} ₺',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green,
                                    ),
                                  ),
                                  backgroundColor: Colors.green.withValues(alpha: 0.1),
                                ),
                                Chip(
                                  label: Text(
                                    'Gider: ${formatNumber(finance.totalExpenses)} ₺',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.red,
                                    ),
                                  ),
                                  backgroundColor: Colors.red.withValues(alpha: 0.1),
                                ),
                                Chip(
                                  label: Text(
                                    'Kâr: ${formatNumber(finance.profit)} ₺',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue,
                                    ),
                                  ),
                                  backgroundColor: Colors.blue.withValues(alpha: 0.1),
                                ),
                              ],
                            ),
                          // Ruhsat ilerleme durumu
                          if (SistemYoneticisi().yetkiVarMi('ruhsat'))
                            FutureBuilder<Map<String, dynamic>>(
                              future: _getRuhsatOzet(project.id),
                              builder: (context, ruhsatSnap) {
                                if (!ruhsatSnap.hasData) return const SizedBox.shrink();
                                final r = ruhsatSnap.data!;
                                final tamamlanan = r['tamamlanan'] as int;
                                final devamEden = r['devamEden'] as int;
                                final toplam = r['toplam'] as int;
                                final aktifSira = r['aktifSira'] as int;

                                if (tamamlanan == 0 && devamEden == 0) return const SizedBox.shrink();

                                final sonIslemTarihi = r['sonIslemTarihi'] as DateTime?;
                                int pasifGunSayisi = 0;
                                if (sonIslemTarihi != null) {
                                  pasifGunSayisi = DateTime.now().difference(sonIslemTarihi).inDays;
                                }

                                final aktifMadde = aktifSira > 0 && aktifSira <= _ruhsatMaddeleri.length
                                    ? _ruhsatMaddeleri[aktifSira - 1]
                                    : null;
                                final tamamlandi = tamamlanan == toplam;

                                return Padding(
                                  padding: const EdgeInsets.only(top: 10),
                                  child: Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: tamamlandi
                                          ? Colors.green.withValues(alpha: 0.06)
                                          : Colors.orange.withValues(alpha: 0.06),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: tamamlandi
                                            ? Colors.green.withValues(alpha: 0.2)
                                            : Colors.orange.withValues(alpha: 0.2),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(
                                              tamamlandi ? Icons.verified : Icons.description_outlined,
                                              size: 15,
                                              color: tamamlandi ? Colors.green.shade700 : Colors.orange.shade700,
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              'Ruhsat: $tamamlanan/$toplam',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                                color: tamamlandi ? Colors.green.shade700 : Colors.orange.shade700,
                                              ),
                                            ),
                                            if (devamEden > 0) ...[
                                              const SizedBox(width: 6),
                                              Text(
                                                '($devamEden devam ediyor)',
                                                style: TextStyle(fontSize: 10, color: Colors.orange.shade600),
                                              ),
                                            ],
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(4),
                                          child: LinearProgressIndicator(
                                            value: toplam > 0 ? tamamlanan / toplam : 0,
                                            backgroundColor: Colors.grey.shade200,
                                            valueColor: AlwaysStoppedAnimation(
                                              tamamlandi ? Colors.green.shade500 : Colors.orange.shade500,
                                            ),
                                            minHeight: 5,
                                          ),
                                        ),
                                        if (pasifGunSayisi >= 10) ...[
                                          const SizedBox(height: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: Colors.red.withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                                            ),
                                            child: Row(
                                              children: [
                                                const Icon(Icons.warning_amber_rounded, size: 14, color: Colors.red),
                                                const SizedBox(width: 4),
                                                Text(
                                                  '$pasifGunSayisi gündür işlem yapılmadı!',
                                                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.red),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                        if (aktifMadde != null && !tamamlandi) ...[
                                          const SizedBox(height: 6),
                                          Text(
                                            '▸ $aktifMadde',
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: Colors.grey.shade600,
                                              fontStyle: FontStyle.italic,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
              },
            );
          },
        ),
        ),
      ],
    );
  }

  Color _getStatusColor(ProjectStatus status) {
    switch (status) {
      case ProjectStatus.planning:
        return Colors.blue;
      case ProjectStatus.ongoing:
        return Colors.orange;
      case ProjectStatus.completed:
        return Colors.green;
      case ProjectStatus.cancelled:
        return Colors.red;
    }
  }
}
