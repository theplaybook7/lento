import 'dart:async';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
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
import 'bildirimler_screen.dart';
import 'cari_hesap_screen.dart';
import 'settings_screen.dart';
import 'gorev_ata_dialog.dart';
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
  final GlobalKey _guideButtonKey = GlobalKey();
  final GlobalKey _taskButtonKey = GlobalKey();
  final GlobalKey _settingsButtonKey = GlobalKey();
  final GlobalKey _logoutButtonKey = GlobalKey();
  final GlobalKey _guideRaporButtonKey = GlobalKey();
  final GlobalKey _guideYeniProjeButtonKey = GlobalKey();
  final GlobalKey _guideYeniTeklifButtonKey = GlobalKey();
  final GlobalKey _guideYeniCariButtonKey = GlobalKey();
  bool _kilavuzKontrolEdildi = false;

  void _goToTab(int index) {
    setState(() => _navIndex = index);
  }

  Future<bool> _showCoachBubble(
    GlobalKey targetKey, {
    required String title,
    required String body,
    required String stepLabel,
    required bool isLast,
  }) async {
    if (!mounted) return false;

    final targetContext = targetKey.currentContext;
    if (targetContext == null) return true;

    final box = targetContext.findRenderObject() as RenderBox?;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null || !box.hasSize) return true;

    final offset = box.localToGlobal(Offset.zero, ancestor: overlay);
    final rect = Rect.fromLTWH(
      offset.dx,
      offset.dy,
      box.size.width,
      box.size.height,
    );

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (ctx) {
        final screenWidth = MediaQuery.of(ctx).size.width;
        final bubbleWidth = screenWidth.clamp(280.0, 390.0).toDouble();

        final isBelow = rect.top < MediaQuery.of(ctx).size.height * 0.5;
        final bubbleTop = isBelow ? rect.bottom + 14 : rect.top - 14;
        final bubbleLeft = (rect.center.dx - bubbleWidth / 2)
            .clamp(12.0, screenWidth - bubbleWidth - 12.0);

        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: () {},
                child: const SizedBox.expand(),
              ),
            ),
            Positioned(
              left: (rect.left - 8).clamp(4.0, screenWidth - rect.width - 4.0),
              top: (rect.top - 8).clamp(4.0, MediaQuery.of(ctx).size.height - rect.height - 4.0),
              child: IgnorePointer(
                child: Container(
                  width: rect.width + 16,
                  height: rect.height + 16,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.blueAccent.withValues(alpha: 0.7),
                        blurRadius: 18,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: bubbleLeft,
              top: isBelow ? bubbleTop : null,
              bottom: isBelow ? null : MediaQuery.of(ctx).size.height - bubbleTop,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: bubbleWidth,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 22,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        stepLabel,
                        style: TextStyle(
                          color: AppTheme.primaryColor,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        body,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.45,
                          color: Colors.grey.shade800,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          const Spacer(),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Atla'),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: Text(isLast ? 'Bitir' : 'İleri'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    return result == true;
  }

  late String _companyId;
  StreamSubscription<User?>? _authSub;
  // Bildirim stream'ini cache'le — AppBar ve dropdown aynı stream'i kullanır
  late final Stream<QuerySnapshot> _bildirimStream =
      BildirimServisi.bildirimleriDinle();

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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ilkAcilisKilavuzunuGoster();
    });
  }

  Future<void> _ilkAcilisKilavuzunuGoster() async {
    if (_kilavuzKontrolEdildi) return;
    _kilavuzKontrolEdildi = true;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final goruldu = userDoc.data()?['uygulamaKilavuzuGoruldu'] == true;
      if (goruldu || !mounted) return;

      await _kullanimKilavuzuDialoguAc();
      if (!mounted) return;

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'uygulamaKilavuzuGoruldu': true,
      }, SetOptions(merge: true));
    } catch (_) {
      // Kılavuz kontrolü başarısız olsa da uygulama akışı devam etsin.
    }
  }

  Future<void> _kullanimKilavuzuDialoguAc() async {
    if (!mounted) return;

    final isDesktopLike = MediaQuery.of(context).size.width >= 900;
    final steps = <Map<String, dynamic>>[
      {
        'key': _guideButtonKey,
        'title': 'Yardım Kılavuzu',
        'body': 'Bu butondan kılavuzu istediğiniz an tekrar açabilirsiniz.',
        'prepare': null,
      },
      {
        'key': _taskButtonKey,
        'title': 'Görev Ata',
        'body': 'Ekip için görev oluşturma ve atama işlemlerini buradan yaparsınız.',
        'prepare': null,
      },
      {
        'key': _notificationKey,
        'title': 'Bildirimler',
        'body': 'Ruhsat, şantiye, muhasebe ve görev bildirimlerini buradan takip edersiniz.',
        'prepare': null,
      },
      {
        'key': _guideRaporButtonKey,
        'title': 'Rapor Al',
        'body': 'Filtreli veya filtresiz şekilde proje listesinin PDF raporunu buradan üretirsiniz.',
        'prepare': () => _goToTab(0),
      },
      {
        'key': _guideYeniProjeButtonKey,
        'title': 'Yeni Proje Oluşturma',
        'body': 'Yeni proje kaydı açmak için bu butonu kullanırsınız. Proje oluşturduktan sonra ruhsat, şantiye ve muhasebe süreçleri detay ekranından yönetilir.',
        'prepare': () => _goToTab(0),
      },
      {
        'key': _guideYeniTeklifButtonKey,
        'title': 'Yeni Teklif Oluşturma',
        'body': 'Teklif hesapları, kat planı ve maliyet senaryosu için bu butondan yeni teklif oluşturursunuz.',
        'prepare': () => _goToTab(1),
      },
      {
        'key': _guideYeniCariButtonKey,
        'title': 'Yeni Cari Oluşturma',
        'body': 'Müşteri veya tedarikçi cari hesabını bu butondan ekleyip proje bazlı borç/alacak takibi yaparsınız.',
        'prepare': () => _goToTab(2),
      },
      if (isDesktopLike)
        {
          'key': _settingsButtonKey,
          'title': 'Ayarlar',
          'body': 'Şirket bilgileri, personel yetkileri ve abonelik ayarlarını bu butondan yönetirsiniz.',
          'prepare': null,
        },
      if (isDesktopLike)
        {
          'key': _logoutButtonKey,
          'title': 'Çıkış',
          'body': 'Güvenli çıkış için bu butonu kullanırsınız.',
          'prepare': null,
        },
    ];

    int shownCount = 0;
    int totalVisible = 0;
    for (final step in steps) {
      final prep = step['prepare'] as VoidCallback?;
      prep?.call();
      await Future.delayed(const Duration(milliseconds: 80));
      final key = step['key'] as GlobalKey;
      if (key.currentContext != null) {
        totalVisible++;
      }
    }
    if (totalVisible == 0) return;

    for (var i = 0; i < steps.length; i++) {
      final step = steps[i];
      final prep = step['prepare'] as VoidCallback?;
      prep?.call();
      await Future.delayed(const Duration(milliseconds: 220));
      if (!mounted) return;

      final key = step['key'] as GlobalKey;
      if (key.currentContext == null) {
        continue;
      }

      shownCount++;
      final shouldContinue = await _showCoachBubble(
        key,
        stepLabel: '$shownCount / $totalVisible',
        title: step['title'] as String,
        body: step['body'] as String,
        isLast: shownCount == totalVisible,
      );
      if (!shouldContinue) break;
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
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
        title: Text(
          SistemYoneticisi().aktifSirket?.ad ?? 'Lento',
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        elevation: 1,
        actions: [
          IconButton(
            key: _guideButtonKey,
            icon: const Icon(Icons.help_outline),
            tooltip: 'Nasıl Kullanılır?',
            onPressed: _kullanimKilavuzuDialoguAc,
          ),
          IconButton(
            key: _taskButtonKey,
            icon: const Icon(Icons.assignment_turned_in_outlined),
            tooltip: 'Görev Ata',
            onPressed: () {
              showDialog(
                context: context,
                builder: (_) => const GorevAtaDialog(),
              );
            },
          ),
          StreamBuilder<QuerySnapshot>(
            stream: _bildirimStream,
            builder: (context, snapshot) {
              int okunmayanSayisi = 0;
              if (snapshot.hasData && !snapshot.hasError) {
                okunmayanSayisi = BildirimServisi.okunmamisBildirimler(
                  snapshot.data!,
                ).length;
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
                        constraints: const BoxConstraints(
                          minWidth: 18,
                          minHeight: 18,
                        ),
                        child: Text(
                          okunmayanSayisi > 99
                              ? '99+'
                              : okunmayanSayisi.toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
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
              key: _settingsButtonKey,
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
              key: _logoutButtonKey,
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
                if (value == 'guide') {
                  _kullanimKilavuzuDialoguAc();
                } else if (value == 'settings') {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (c) => const SettingsSayfasi()),
                  );
                } else if (value == 'logout') {
                  SistemYoneticisi().temizle();
                  await FirebaseAuth.instance.signOut();
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'guide', child: Text('Nasıl Kullanılır?')),
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
                          Text(
                            'Lento',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
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
                      leading: const Icon(
                        Icons.account_balance_wallet_outlined,
                      ),
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
                            builder: (c) =>
                                ProjectArchiveScreen(companyId: _companyId),
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
                          MaterialPageRoute(
                            builder: (c) => const ArsivSayfasi(),
                          ),
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
                          MaterialPageRoute(
                            builder: (c) => const SettingsSayfasi(),
                          ),
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
                    reportButtonKey: _guideRaporButtonKey,
                    onProjectTap: (projectId) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (c) =>
                              ProjectDetailsScreen(projectId: projectId),
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
                                builder: (c) =>
                                    ProjectArchiveScreen(companyId: _companyId),
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
                              MaterialPageRoute(
                                builder: (c) => const ArsivSayfasi(),
                              ),
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
                          reportButtonKey: _guideRaporButtonKey,
                          onProjectTap: (projectId) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (c) =>
                                    ProjectDetailsScreen(projectId: projectId),
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
                    key: _guideYeniProjeButtonKey,
                    onPressed: () async {
                      if (!mounted) return;
                      final projectId = await Navigator.push<String?>(
                        context,
                        MaterialPageRoute(
                          builder: (c) =>
                              NewProjectScreen(companyId: _companyId),
                        ),
                      );
                      if (!mounted || projectId == null) return;
                      await Navigator.push<void>(
                        context,
                        MaterialPageRoute(
                          builder: (c) =>
                              ProjectDetailsScreen(projectId: projectId),
                        ),
                      );
                    },
                    backgroundColor: AppTheme.primaryColor,
                    tooltip: 'Yeni Proje',
                    child: const Icon(Icons.add),
                  )
                : FloatingActionButton.extended(
                    key: _guideYeniProjeButtonKey,
                    onPressed: () async {
                      if (!mounted) return;
                      // ignore: use_build_context_synchronously
                      final projectId = await Navigator.push<String?>(
                        context,
                        MaterialPageRoute(
                          builder: (c) =>
                              NewProjectScreen(companyId: _companyId),
                        ),
                      );
                      if (!mounted || projectId == null) return;
                      // ignore: use_build_context_synchronously
                      await Navigator.push<void>(
                        context,
                        MaterialPageRoute(
                          builder: (c) =>
                              ProjectDetailsScreen(projectId: projectId),
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
                  key: _guideYeniTeklifButtonKey,
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
                  key: _guideYeniTeklifButtonKey,
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
                  key: _guideYeniCariButtonKey,
                    onPressed: () => _yeniCariDialogGlobal(context),
                    backgroundColor: AppTheme.primaryColor,
                    tooltip: 'Cari Ekle',
                    child: const Icon(Icons.add),
                  )
                : FloatingActionButton.extended(
                  key: _guideYeniCariButtonKey,
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
                RadioGroup<String>(
                  groupValue: tip,
                  onChanged: (v) {
                    if (v != null) {
                      setState(() => tip = v);
                    }
                  },
                  child: Row(
                    children: [
                      Expanded(
                        child: RadioListTile<String>(
                          title: const Text(
                            'Müşteri',
                            style: TextStyle(fontSize: 13),
                          ),
                          value: 'musteri',
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      Expanded(
                        child: RadioListTile<String>(
                          title: const Text(
                            'Tedarikçi',
                            style: TextStyle(fontSize: 13),
                          ),
                          value: 'tedarikci',
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
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

                await FirebaseFirestore.instance
                    .collection('cari_hesaplar')
                    .add({
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
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final Offset offset = button.localToGlobal(Offset.zero, ancestor: overlay);
    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromLTWH(
        offset.dx,
        offset.dy + button.size.height,
        button.size.width,
        0,
      ),
      Offset.zero & overlay.size,
    );

    showMenu<int>(
      context: context,
      position: position,
      items: [
        PopupMenuItem(
          enabled: false,
          child: SizedBox(
            width: (MediaQuery.of(context).size.width - 24)
                .clamp(260, 360)
                .toDouble(),
            child: StreamBuilder<QuerySnapshot>(
              stream: _bildirimStream,
              builder: (ctx, snap) {
                if (snap.hasError || !snap.hasData || snap.data!.docs.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.notifications_off_outlined,
                          size: 40,
                          color: Colors.grey.shade300,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Bildirim yok',
                          style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: TextButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const BildirimlerScreen(),
                                ),
                              );
                            },
                            icon: const Icon(Icons.list_alt, size: 16),
                            label: const Text(
                              'Tüm Bildirimleri Görüntüle',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                final okunmamis = BildirimServisi.okunmamisBildirimler(
                  snap.data!,
                );
                final tumYetkiliBildirimler = snap.data!.docs.where((doc) {
                  final b = doc.data() as Map<String, dynamic>;
                  return BildirimServisi.yetkiliMi(b);
                }).toList();
                final onizlemeBildirimleri = tumYetkiliBildirimler
                    .take(3)
                    .toList();
                final kalanBildirimSayisi =
                    tumYetkiliBildirimler.length - onizlemeBildirimleri.length;

                if (tumYetkiliBildirimler.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.check_circle_outline,
                          size: 40,
                          color: Colors.green.shade300,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Gösterilecek bildirim yok',
                          style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: TextButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const BildirimlerScreen(),
                                ),
                              );
                            },
                            icon: const Icon(Icons.list_alt, size: 16),
                            label: const Text(
                              'Tüm Bildirimleri Görüntüle',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
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
                          const Icon(
                            Icons.notifications_active,
                            size: 18,
                            color: Colors.deepOrange,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Bildirimler',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.deepOrange,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${okunmamis.length}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 1, color: Colors.grey.shade200),
                    const SizedBox(height: 4),
                    ListView.builder(
                      shrinkWrap: true,
                      itemCount: onizlemeBildirimleri.length,
                      itemBuilder: (ctx, i) {
                        final doc = onizlemeBildirimleri[i];
                        final b = doc.data() as Map<String, dynamic>;
                        final baslik = b['baslik'] ?? '';
                        final mesaj = b['mesaj'] ?? '';
                        final gonderen = b['gonderen'] ?? '';
                        final projeId = b['projeId'] ?? '';
                        final tarih = b['tarih'] as Timestamp?;
                        final okunmus = BildirimServisi.okunduMu(
                          b,
                          email: SistemYoneticisi().girisYapanEmail,
                          docId: doc.id,
                        );
                        final modulRenk = BildirimServisi.bildirimRenk(b);
                        final modulIkon = BildirimServisi.bildirimIkon(b);

                        // Zaman farkı
                        String zamanStr = '';
                        if (tarih != null) {
                          final fark = DateTime.now().difference(
                            tarih.toDate(),
                          );
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
                          onTap: () {
                            Navigator.pop(context);
                            // Arka planda okundu işaretle (UI'ı bloklamaz)
                            unawaited(
                              BildirimServisi.okunduIsaretleDoc(doc.id),
                            );
                            if (!mounted) return;
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (c) =>
                                    ProjectDetailsScreen(projectId: projeId),
                              ),
                            );
                          },
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 3),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: modulRenk.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(8),
                              border: Border(
                                left: BorderSide(color: modulRenk, width: 3),
                              ),
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
                                  child: Icon(
                                    modulIkon,
                                    size: 16,
                                    color: modulRenk,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          if (!okunmus)
                                            Container(
                                              width: 7,
                                              height: 7,
                                              margin: const EdgeInsets.only(
                                                right: 6,
                                              ),
                                              decoration: BoxDecoration(
                                                color: modulRenk,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                          Expanded(
                                            child: Text(
                                              baslik,
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12,
                                                color: modulRenk,
                                              ),
                                            ),
                                          ),
                                          if (zamanStr.isNotEmpty)
                                            Text(
                                              zamanStr,
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: Colors.grey.shade500,
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        mesaj,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Colors.black87,
                                        ),
                                      ),
                                      if (gonderen.toString().isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 4,
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.person_outline,
                                                size: 12,
                                                color: Colors.grey.shade500,
                                              ),
                                              const SizedBox(width: 3),
                                              Text(
                                                gonderen.toString(),
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  color: Colors.grey.shade600,
                                                ),
                                              ),
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
                    if (kalanBildirimSayisi > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 4, bottom: 2),
                        child: Text(
                          '$kalanBildirimSayisi daha bildirim',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    Divider(height: 1, color: Colors.grey.shade200),
                    const SizedBox(height: 4),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const BildirimlerScreen(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.list_alt, size: 16),
                        label: const Text(
                          'Tüm Bildirimleri Görüntüle',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
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
              Expanded(
                child: _filtreButomu('musteri', 'Müşteriler', Icons.people),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _filtreButomu(
                  'tedarikci',
                  'Tedarikçiler',
                  Icons.business,
                ),
              ),
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
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
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
            stream: FirebaseFirestore.instance
                .collection('cari_hesaplar')
                .where(
                  'sirketId',
                  isEqualTo: SistemYoneticisi().aktifSirket?.id ?? '',
                )
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                if (SistemYoneticisi().cikisYapiliyor)
                  return const SizedBox.shrink();
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
                bool aramaFiltre =
                    _arama.isEmpty || ad.contains(_arama.toLowerCase());
                return tipFiltre && aramaFiltre;
              }).toList();

              if (docs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.account_balance_wallet_outlined,
                        size: 48,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _arama.isNotEmpty
                            ? 'Sonuç bulunamadı'
                            : 'Henüz cari hesap kaydı yok',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Colors.grey.shade600,
                        ),
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
                  final ikon = tip == 'musteri'
                      ? Icons.person_outline
                      : Icons.business_outlined;

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
                          builder: (c) =>
                              CariDetayScreen(cariId: doc.id, cariAd: ad),
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
                                  colors: [
                                    renk.withValues(alpha: 0.2),
                                    renk.withValues(alpha: 0.1),
                                  ],
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
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.w600,
                                          color: AppTheme.primaryColor,
                                        ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (telefon.toString().isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      telefon,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Colors.grey.shade600,
                                          ),
                                    ),
                                  ],
                                  if (email.toString().isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      email,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: Colors.grey.shade600,
                                          ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  bakiye == 0
                                      ? 'Dengede'
                                      : (alacak ? 'Alınan' : 'Ödenen'),
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
            Icon(
              ikon,
              size: 18,
              color: aktif
                  ? AppTheme.primaryColor
                  : Colors.white.withValues(alpha: 0.7),
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                etiket,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: aktif
                      ? AppTheme.primaryColor
                      : Colors.white.withValues(alpha: 0.7),
                  fontWeight: aktif ? FontWeight.w600 : FontWeight.normal,
                  fontSize: 12,
                ),
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
  String _durumFiltre =
      'teklif'; // Filtre: 'teklif', 'anlasildi', 'tamamlandi', 'all'

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
                    borderSide: BorderSide(
                      color: AppTheme.primaryColor,
                      width: 2,
                    ),
                  ),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
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
                    onSelected: (v) =>
                        setState(() => _durumFiltre = 'tamamlandi'),
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
                      .where(
                        'sirketId',
                        isEqualTo: SistemYoneticisi().aktifSirket?.id ?? '',
                      )
                      .orderBy('tarih', descending: true)
                      .limit(50)
                      .snapshots()
                : FirebaseFirestore.instance
                      .collection('teklifler')
                      .where(
                        'sirketId',
                        isEqualTo: SistemYoneticisi().aktifSirket?.id ?? '',
                      )
                      .where('durum', isEqualTo: _durumFiltre)
                      .orderBy('tarih', descending: true)
                      .limit(50)
                      .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                if (SistemYoneticisi().cikisYapiliyor)
                  return const SizedBox.shrink();
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
                final mahalle = (data['mahalle'] ?? '')
                    .toString()
                    .toLowerCase();
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
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      leading: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppTheme.primaryColor.withValues(alpha: 0.8),
                              AppTheme.primaryColor,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.description_outlined,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      title: Text(
                        "${data['ilce']} / ${data['mahalle']}",
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: AppTheme.primaryColor,
                            ),
                      ),
                      subtitle: Text(
                        "Ada: ${data['ada']} | Parsel: ${data['parsel']} | ${tarih.day}.${tarih.month}.${tarih.year}",
                        style: Theme.of(context).textTheme.bodySmall,
                      ),

                      trailing: IconButton(
                        icon: Icon(
                          Icons.arrow_forward_ios,
                          size: 14,
                          color: AppTheme.primaryColor.withValues(alpha: 0.6),
                        ),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (c) => TeklifSayfasi(
                                mevcutTeklifData: data,
                                mevcutDocId: doc.id,
                              ),
                            ),
                          );
                        },
                      ),

                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (c) => TeklifSayfasi(
                              mevcutTeklifData: data,
                              mevcutDocId: doc.id,
                            ),
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
  final Key? reportButtonKey;

  const _ProjectsTab({
    required this.companyId,
    required this.onProjectTap,
    this.reportButtonKey,
  });

  @override
  State<_ProjectsTab> createState() => _ProjectsTabState();
}

class _ProjectsTabState extends State<_ProjectsTab> {
  final _firebase = FirebaseService();
  final _searchController = TextEditingController();
  String _searchQuery = '';
  bool _filtersExpandedOnMobile = false;
  String _muteahhitFilterText = '';
  String _adaParselFilterText = '';
  String _ruhsatMaddeFilterText = '';
  String _ruhsatDurumFilter = 'devam'; // tum | baslamadi | devam | tamamlandi
  List<String> _muteahhitSecenekleri = [];
  List<String> _adaParselSecenekleri = [];
  List<String> _ruhsatMaddeSecenekleri = [];
  // Projelerin akış diyagramı cache
  final Map<String, List<Map<String, dynamic>>> _akisCache = {};
  final Map<String, Map<String, dynamic>> _akisMetaCache = {};
  bool _akisCacheLoaded = false;
  // Ruhsat özet cache (FutureBuilder'ı ortadan kaldırmak için)
  final Map<String, Map<String, dynamic>> _ruhsatOzetCache = {};
  // Finans cache
  final Map<String, ProjectFinance> _financeCache = {};
  bool _financeCacheLoaded = false;
  bool _preloadInProgress = false;

  @override
  void initState() {
    super.initState();
    // Pasif proje bildirimleri artık günlük rapor (07:00 cloud function) ile gönderiliyor.
    // Uygulama içinden ekstra bildirim atmıyoruz.
    // _pasifBildirimKontrolleri();
  }

  Future<void> _loadAkisCache(List<Project> projects) async {
    final uncached = projects
        .where((p) => !_akisCache.containsKey(p.id))
        .toList();
    if (uncached.isEmpty) {
      _akisCacheLoaded = true;
      return;
    }
    _akisCacheLoaded = true;
    // Tüm projeleri paralel oku
    await Future.wait(
      uncached.map((p) async {
        try {
          final snap = await FirebaseFirestore.instance
              .collection('ruhsat')
              .doc(p.id)
              .collection('akis_diyagrami')
              .get();
          // Meta dokümanı ayrı cache'le
          for (final d in snap.docs) {
            if (d.id == '_meta') {
              _akisMetaCache[p.id] = d.data();
              break;
            }
          }
          _akisCache[p.id] = snap.docs
              .where(
                (d) =>
                    d.id != 'karar_kontrol' &&
                    d.id != 'yola_terk_kontrol' &&
                    d.id != '_meta',
              )
              .map((d) => d.data())
              .toList();
        } catch (_) {
          _akisCache[p.id] = [];
        }
      }),
    );
  }

  /// Tüm projelerin ruhsat özet + finans verilerini ön-yükle
  Future<void> _preloadProjectData(List<Project> projects) async {
    if (_preloadInProgress) return;
    _preloadInProgress = true;
    bool changed = false;

    try {
      // 1) Akış cache'i (ruhsat özeti için gerekli)
      if (!_akisCacheLoaded) {
        await _loadAkisCache(projects);
        if (!mounted) return;
        changed = true;
      }

      // 2) Ruhsat özetlerini cache'den hesapla (Firestore okuması yok)
      for (final p in projects) {
        if (!_ruhsatOzetCache.containsKey(p.id)) {
          _ruhsatOzetCache[p.id] = _hesaplaRuhsatOzet(p.id);
          changed = true;
        }
      }

      // 3) Finans verilerini toplu yükle (cari hareketlerinden hesapla)
      if (!_financeCacheLoaded && SistemYoneticisi().yetkiVarMi('muhasebe')) {
        _financeCacheLoaded = true;
        final uncached = projects
            .where((p) => !_financeCache.containsKey(p.id))
            .toList();
        if (uncached.isNotEmpty) {
          changed = true;
          final sirketId = SistemYoneticisi().aktifSirket?.id ?? '';
          final projectIds = uncached.map((p) => p.id).toList();
          final summaries = await _firebase.getAllProjectFinanceSummaries(
            sirketId,
            projectIds,
          );
          if (!mounted) return;
          _financeCache.addAll(summaries);
          // project_finance'da olmayan projeler için boş kayıt ekle
          for (final p in uncached) {
            _financeCache.putIfAbsent(
              p.id,
              () => ProjectFinance(projectId: p.id),
            );
          }
        }
      }

      if (changed && mounted) setState(() {});
    } finally {
      _preloadInProgress = false;
    }
  }

  String _normalizeFilterValue(String value) => value.trim().toLowerCase();

  List<String> _uniqueSortedValues(Iterable<String> values) {
    final normalizedToOriginal = <String, String>{};
    for (final raw in values) {
      final value = raw.trim();
      if (value.isEmpty) continue;
      final key = _normalizeFilterValue(value);
      normalizedToOriginal.putIfAbsent(key, () => value);
    }
    final result = normalizedToOriginal.values.toList();
    result.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return result;
  }

  String _projectMetaValue(
    Project project,
    String? directValue,
    int partIndex,
  ) {
    final nameParts = project.name
        .split(' / ')
        .map((part) => part.trim())
        .toList();
    if (nameParts.length > partIndex) {
      final parsed = nameParts[partIndex];
      if (parsed.isNotEmpty) return parsed;
    }

    final value = (directValue ?? '').trim();
    if (value.isNotEmpty) return value;
    return '';
  }

  String _projectAdaParsel(Project project) {
    return _projectMetaValue(project, project.adaParsel, 1);
  }

  String _projectMuteahhit(Project project) {
    return _projectMetaValue(project, project.muteahhit, 2);
  }

  bool _isExactFilterMatch(String filter, List<String> options) {
    if (filter.isEmpty) return false;
    return options.any((option) => _normalizeFilterValue(option) == filter);
  }

  bool _matchesSmartFilter({
    required String value,
    required String filter,
    required bool exactMatch,
  }) {
    if (filter.isEmpty) return true;
    if (exactMatch) return value == filter;

    if (value.startsWith(filter)) {
      return true;
    }

    final tokens = value
        .split(RegExp(r'[\s/|,.-]+'))
        .where((token) => token.isNotEmpty);
    return tokens.any((token) => token.startsWith(filter));
  }

  String _normalizeRuhsatMadde(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll('i̇', 'i')
        .replaceAll('ı', 'i')
        .replaceAll('İ', 'i')
        .replaceAll('I', 'i');
  }

  int? _resolveRuhsatSira(String maddeFilter) {
    final filter = _normalizeRuhsatMadde(maddeFilter);
    if (filter.isEmpty) return null;

    // 1) Tam eşleşme
    for (final entry in _akisNodeNames.entries) {
      if (_normalizeRuhsatMadde(entry.value) == filter) return entry.key;
    }

    // 2) Başlangıç eşleşmesi
    for (final entry in _akisNodeNames.entries) {
      final v = _normalizeRuhsatMadde(entry.value);
      if (v.startsWith(filter)) return entry.key;
    }

    // 3) Token başlangıcı eşleşmesi
    for (final entry in _akisNodeNames.entries) {
      final tokens = _normalizeRuhsatMadde(
        entry.value,
      ).split(RegExp(r'[\s/|,.-]+')).where((token) => token.isNotEmpty);
      if (tokens.any((token) => token.startsWith(filter))) return entry.key;
    }

    return null;
  }

  int _projeRuhsatMaddeDurumu(Project project, String maddeFilter) {
    final sira = _resolveRuhsatSira(maddeFilter);
    if (sira == null) return -1;

    final docs = _akisCache[project.id] ?? const <Map<String, dynamic>>[];
    for (final data in docs) {
      final nodeSira = data['sira'] as int?;
      if (nodeSira == sira) {
        return data['durum'] as int? ?? 0;
      }
    }

    // Doküman yoksa başlanmadı kabul edilir.
    return 0;
  }

  bool _matchesRuhsatDurumFilter(int durum, String filter) {
    if (filter == 'tum') return true;
    if (filter == 'baslamadi') return durum == 0;
    if (filter == 'devam') return durum == 1;
    if (filter == 'tamamlandi') return durum == 2;
    return true;
  }

  /// Akış cache'inden ruhsat özeti hesapla (Firestore okuması yapmaz)
  Map<String, dynamic> _hesaplaRuhsatOzet(String projectId) {
    final docs = _akisCache[projectId] ?? [];
    final meta = _akisMetaCache[projectId];
    final baslatildi = meta?['baslatildi'] == true;
    final ruhsatTamamlandi = meta?['ruhsatTamamlandi'] == true;
    int tamamlanan = 0;
    int devamEden = 0;
    DateTime? sonIslemTarihi;
    String? aktifMadde;

    for (var data in docs) {
      final sira = data['sira'] as int? ?? 0;
      if (!_akisNodeNames.containsKey(sira)) continue;

      final durum = data['durum'] as int? ?? 0;
      if (durum == 2) tamamlanan++;
      if (durum == 1) {
        devamEden++;
        aktifMadde ??= _akisNodeNames[sira] ?? data['madde'] as String?;
      }
      final gt = data['guncellendiTarihi'];
      if (gt != null) {
        DateTime? t;
        if (gt is Timestamp) {
          t = gt.toDate();
        } else if (gt is DateTime) {
          t = gt;
        }
        if (t != null &&
            (sonIslemTarihi == null || t.isAfter(sonIslemTarihi))) {
          sonIslemTarihi = t;
        }
      }
    }
    // Meta'daki sonGuncellemeTarihi daha güncel olabilir
    final metaGun = meta?['sonGuncellemeTarihi'] ?? meta?['baslatmaTarihi'];
    DateTime? metaDate;
    if (metaGun is Timestamp) {
      metaDate = metaGun.toDate();
    } else if (metaGun is DateTime) {
      metaDate = metaGun;
    }
    if (metaDate != null &&
        (sonIslemTarihi == null || metaDate.isAfter(sonIslemTarihi))) {
      sonIslemTarihi = metaDate;
    }
    return {
      'tamamlanan': tamamlanan,
      'devamEden': devamEden,
      'toplam': _akisNodeNames.length,
      'aktifMadde': aktifMadde,
      'sonIslemTarihi': sonIslemTarihi,
      'baslatildi': baslatildi,
      'ruhsatTamamlandi': ruhsatTamamlandi,
    };
  }

  bool _projeFiltreyeUygunMu(Project project) {
    final muteahhit = _normalizeFilterValue(_projectMuteahhit(project));
    final adaParsel = _normalizeFilterValue(_projectAdaParsel(project));

    final muteahhitFilter = _normalizeFilterValue(_muteahhitFilterText);
    final adaParselFilter = _normalizeFilterValue(_adaParselFilterText);
    final muteahhitExactMatch = _isExactFilterMatch(
      muteahhitFilter,
      _muteahhitSecenekleri,
    );
    final adaParselExactMatch = _isExactFilterMatch(
      adaParselFilter,
      _adaParselSecenekleri,
    );

    if (!_matchesSmartFilter(
      value: muteahhit,
      filter: muteahhitFilter,
      exactMatch: muteahhitExactMatch,
    )) {
      return false;
    }
    if (!_matchesSmartFilter(
      value: adaParsel,
      filter: adaParselFilter,
      exactMatch: adaParselExactMatch,
    )) {
      return false;
    }

    final ruhsatMaddeFilter = _ruhsatMaddeFilterText.trim();
    if (ruhsatMaddeFilter.isNotEmpty) {
      final durum = _projeRuhsatMaddeDurumu(project, ruhsatMaddeFilter);
      if (durum < 0 || !_matchesRuhsatDurumFilter(durum, _ruhsatDurumFilter)) {
        return false;
      }
    }

    return true;
  }

  int _muteahhitFiltreProjeSayisi(List<Project> projects) {
    final muteahhitFilter = _normalizeFilterValue(_muteahhitFilterText);
    if (muteahhitFilter.isEmpty) return 0;

    final muteahhitExactMatch = _isExactFilterMatch(
      muteahhitFilter,
      _muteahhitSecenekleri,
    );
    return projects.where((project) {
      final muteahhit = _normalizeFilterValue(_projectMuteahhit(project));
      return _matchesSmartFilter(
        value: muteahhit,
        filter: muteahhitFilter,
        exactMatch: muteahhitExactMatch,
      );
    }).length;
  }

  Future<void> _ensureAkisCacheForProjects(List<Project> projects) async {
    final missing = projects
        .where((p) => !_akisCache.containsKey(p.id))
        .toList();
    if (missing.isEmpty) return;
    await _loadAkisCache(missing);
  }

  List<Map<String, String>> _raporIcinRuhsatMaddeleri(Project project) {
    final docs = _akisCache[project.id] ?? const <Map<String, dynamic>>[];
    final seciliMadde = _ruhsatMaddeFilterText.trim();
    final seciliSira = seciliMadde.isEmpty
        ? null
        : _resolveRuhsatSira(seciliMadde);
    final maddeler = <Map<String, String>>[];

    for (final data in docs) {
      final sira = data['sira'] as int?;
      final durum = data['durum'] as int? ?? 0;
      if (sira == null || !_akisNodeNames.containsKey(sira)) continue;

      if (seciliSira != null) {
        if (sira != seciliSira) continue;
      } else if (durum != 1) {
        continue;
      }

      if (!_matchesRuhsatDurumFilter(durum, _ruhsatDurumFilter)) continue;

      final baslik =
          _akisNodeNames[sira] ?? (data['madde'] as String? ?? 'Madde $sira');
      final not = (data['not'] as String? ?? '').trim();
      maddeler.add({'sira': sira.toString(), 'baslik': baslik, 'not': not});
    }

    maddeler.sort((a, b) {
      final aSira = int.tryParse(a['sira'] ?? '') ?? 0;
      final bSira = int.tryParse(b['sira'] ?? '') ?? 0;
      return aSira.compareTo(bSira);
    });
    return maddeler;
  }

  Future<void> _filtreliProjeleriPdfRaporla(List<Project> projects) async {
    if (projects.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Rapor için listelenecek proje bulunamadı.'),
        ),
      );
      return;
    }

    try {
      await _ensureAkisCacheForProjects(projects);

      final pdf = pw.Document();
      final font = await PdfGoogleFonts.notoSansRegular();
      final fontBold = await PdfGoogleFonts.notoSansBold();
      final now = DateTime.now();
      final tarih =
          '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

      String excelSafe(String value) {
        final v = value.trim();
        return v.isEmpty ? '-' : v;
      }

      (String, String) splitAdaParsel(String raw) {
        final normalized = raw.trim();
        if (normalized.isEmpty) return ('-', '-');
        final parts = normalized
            .split('/')
            .map((p) => p.trim())
            .where((p) => p.isNotEmpty)
            .toList();
        if (parts.isEmpty) return ('-', '-');
        if (parts.length == 1) return (parts.first, '-');
        return (parts.first, parts.sublist(1).join(' / '));
      }

      final filtreMetni = <String>[
        if (_muteahhitFilterText.trim().isNotEmpty)
          'Müteahhit: ${_muteahhitFilterText.trim()}',
        if (_adaParselFilterText.trim().isNotEmpty)
          'Ada/Parsel: ${_adaParselFilterText.trim()}',
        if (_ruhsatMaddeFilterText.trim().isNotEmpty)
          'Ruhsat: ${_ruhsatMaddeFilterText.trim()} (${_ruhsatDurumFilter == 'devam'
              ? 'Devam Ediyor'
              : _ruhsatDurumFilter == 'baslamadi'
              ? 'Başlamadı'
              : _ruhsatDurumFilter == 'tamamlandi'
              ? 'Tamamlandı'
              : 'Tümü'})',
      ].join(' | ');

      final ruhsatDurumLabel = _ruhsatDurumFilter == 'devam'
          ? 'Devam Ediyor'
          : _ruhsatDurumFilter == 'baslamadi'
          ? 'Başlamadı'
          : _ruhsatDurumFilter == 'tamamlandi'
          ? 'Tamamlandı'
          : 'Tümü';

      final raporBaslikParcalari = <String>[
        if (_ruhsatMaddeFilterText.trim().isNotEmpty)
          _ruhsatMaddeFilterText.trim(),
        if (_ruhsatMaddeFilterText.trim().isNotEmpty) ruhsatDurumLabel,
        if (_muteahhitFilterText.trim().isNotEmpty) _muteahhitFilterText.trim(),
        if (_adaParselFilterText.trim().isNotEmpty) _adaParselFilterText.trim(),
      ];
      final raporBasligi = raporBaslikParcalari.isEmpty
          ? 'Proje Ruhsat Raporu'
          : '${raporBaslikParcalari.join(' | ')} Raporu';

      final satirlar = <List<String>>[];
      for (var i = 0; i < projects.length; i++) {
        final project = projects[i];
        final devamMaddeler = _raporIcinRuhsatMaddeleri(project);
        final adaParsel = _projectAdaParsel(project);
        final (ada, parsel) = splitAdaParsel(adaParsel);
        final etiket = project.isSharedWithMe ? 'Paylaşılan' : 'Kendi';
        final muteahhit = excelSafe(_projectMuteahhit(project));
        final projeAdi = excelSafe(project.name);

        if (devamMaddeler.isEmpty) {
          satirlar.add([
            '${i + 1}',
            projeAdi,
            etiket,
            ada,
            parsel,
            muteahhit,
            '-',
            '-',
          ]);
          continue;
        }

        for (var j = 0; j < devamMaddeler.length; j++) {
          final madde = devamMaddeler[j];
          satirlar.add([
            '${i + 1}',
            projeAdi,
            etiket,
            ada,
            parsel,
            muteahhit,
            excelSafe(madde['baslik'] ?? ''),
            excelSafe(madde['not'] ?? ''),
          ]);
        }
      }

      pw.Widget hucre(
        String text, {
        bool header = false,
        pw.TextAlign align = pw.TextAlign.left,
      }) {
        return pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          child: pw.Text(
            text,
            textAlign: align,
            style: pw.TextStyle(
              font: header ? fontBold : font,
              fontSize: header ? 9.5 : 9,
              color: header ? PdfColors.white : PdfColors.black,
            ),
          ),
        );
      }

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(24),
          build: (context) {
            final tableRows = <pw.TableRow>[
              pw.TableRow(
                decoration: const pw.BoxDecoration(
                  color: PdfColor.fromInt(0xFF2C3E50),
                ),
                children: [
                  hucre('No', header: true, align: pw.TextAlign.center),
                  hucre('Proje', header: true),
                  hucre('Etiket', header: true, align: pw.TextAlign.center),
                  hucre('Ada', header: true, align: pw.TextAlign.center),
                  hucre('Parsel', header: true, align: pw.TextAlign.center),
                  hucre('Müteahhit', header: true),
                  hucre('Ruhsat (Devam Eden)', header: true),
                  hucre('Not', header: true),
                ],
              ),
            ];

            for (var i = 0; i < satirlar.length; i++) {
              final row = satirlar[i];
              final zebra = i.isEven ? PdfColors.grey100 : PdfColors.white;
              tableRows.add(
                pw.TableRow(
                  decoration: pw.BoxDecoration(color: zebra),
                  children: [
                    hucre(row[0], align: pw.TextAlign.center),
                    hucre(row[1]),
                    hucre(row[2], align: pw.TextAlign.center),
                    hucre(row[3], align: pw.TextAlign.center),
                    hucre(row[4], align: pw.TextAlign.center),
                    hucre(row[5]),
                    hucre(row[6]),
                    hucre(row[7]),
                  ],
                ),
              );
            }

            return [
              pw.Text(
                raporBasligi,
                style: pw.TextStyle(font: fontBold, fontSize: 15),
              ),
              pw.SizedBox(height: 5),
              pw.Text(
                'Tarih: $tarih',
                style: pw.TextStyle(font: font, fontSize: 9),
              ),
              if (filtreMetni.isNotEmpty) ...[
                pw.SizedBox(height: 3),
                pw.Text(
                  'Aktif Filtreler: $filtreMetni',
                  style: pw.TextStyle(font: font, fontSize: 9),
                ),
              ],
              pw.SizedBox(height: 3),
              pw.Text(
                'Toplam Proje: ${projects.length} | Toplam Satır: ${satirlar.length}',
                style: pw.TextStyle(font: fontBold, fontSize: 9.5),
              ),
              pw.SizedBox(height: 10),
              pw.Table(
                border: pw.TableBorder.all(
                  color: PdfColors.grey500,
                  width: 0.5,
                ),
                columnWidths: {
                  0: const pw.FlexColumnWidth(0.9),
                  1: const pw.FlexColumnWidth(2.7),
                  2: const pw.FlexColumnWidth(1.2),
                  3: const pw.FlexColumnWidth(1.2),
                  4: const pw.FlexColumnWidth(1.2),
                  5: const pw.FlexColumnWidth(2.2),
                  6: const pw.FlexColumnWidth(3.1),
                  7: const pw.FlexColumnWidth(3.0),
                },
                children: tableRows,
              ),
            ];
          },
        ),
      );

      final fileName =
          'ruhsat_raporu_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}.pdf';
      final bytes = await pdf.save();
      await Printing.sharePdf(bytes: bytes, filename: fileName);

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('PDF raporu oluşturuldu.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('PDF raporu oluşturulamadı: $e')));
    }
  }

  Future<void> _projeIsimDuzenle(Project project) async {
    // Mevcut değerleri Firestore'dan oku
    String mevcutMalSahibi = '';
    String mevcutAdaParsel = '';
    String mevcutMuteahhit = '';
    try {
      final doc = await FirebaseFirestore.instance
          .collection('projects')
          .doc(project.id)
          .get();
      final data = doc.data() ?? {};
      mevcutMalSahibi = (data['malSahibi'] ?? '').toString();
      mevcutAdaParsel = (data['adaParsel'] ?? '').toString();
      mevcutMuteahhit = (data['muteahhit'] ?? '').toString();
    } catch (_) {}

    final malCtrl = TextEditingController(text: mevcutMalSahibi);
    final adaCtrl = TextEditingController(text: mevcutAdaParsel);
    final mutCtrl = TextEditingController(text: mevcutMuteahhit);
    final formKey = GlobalKey<FormState>();

    if (!mounted) return;
    final sonuc = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Proje Bilgilerini Düzenle',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: AppTheme.primaryColor,
          ),
        ),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: malCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Mal Sahibi *',
                    prefixIcon: Icon(Icons.person),
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Mal sahibi gerekli'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: adaCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Ada / Parsel *',
                    hintText: 'Örn: 1234 / 56',
                    prefixIcon: Icon(Icons.grid_on),
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Ada / parsel gerekli'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: mutCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Müteahhit *',
                    prefixIcon: Icon(Icons.engineering),
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Müteahhit gerekli'
                      : null,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () {
              if (!(formKey.currentState?.validate() ?? false)) return;
              Navigator.pop(context, {
                'malSahibi': malCtrl.text.trim(),
                'adaParsel': adaCtrl.text.trim(),
                'muteahhit': mutCtrl.text.trim(),
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
            ),
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
    malCtrl.dispose();
    adaCtrl.dispose();
    mutCtrl.dispose();
    if (sonuc != null && mounted) {
      try {
        final yeniIsim =
            '${sonuc['malSahibi']} / ${sonuc['adaParsel']} / ${sonuc['muteahhit']}';
        await _firebase.updateProject(project.id, {
          'name': yeniIsim,
          'malSahibi': sonuc['malSahibi'],
          'adaParsel': sonuc['adaParsel'],
          'muteahhit': sonuc['muteahhit'],
        });
        if (!mounted) return;
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Proje bilgileri güncellendi')),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(hataCevir(e)), backgroundColor: Colors.red),
        );
      }
    }
  }

  static const Map<int, String> _akisNodeNames = {
    1: 'Lihkap',
    2: 'İmar Durumu',
    3: 'Harita Arazi Randevusu Alınacaklar',
    4: 'İstikamet , Kot İmzalanacaklar',
    5: 'Folyo',
    6: 'Folyo Dilekçesi Verilenler',
    7: 'Encümene Girenler',
    8: 'Kadastro',
    9: 'Tapu Müdürlüğü',
    10: 'Etüt Yapılacaklar',
    11: 'Mimari Proje Çizilecekler',
    12: 'İski',
    13: 'Statik Taslak',
    14: 'Zemin Değeri Beklenenler',
    15: 'Statik Proje Yapılacaklar',
    16: 'Müellif Taahhütnameleri',
    17: 'Ruhsat Dilekçesi Verilenler',
  };

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobileView = screenWidth < 600;
    final hasMetaFilter =
        _muteahhitFilterText.trim().isNotEmpty ||
        _adaParselFilterText.trim().isNotEmpty ||
        _ruhsatMaddeFilterText.trim().isNotEmpty;
    final hasAnyFilter = hasMetaFilter || _searchQuery.trim().isNotEmpty;
    final ruhsatDurumLabel = _ruhsatDurumFilter == 'devam'
        ? 'Devam Ediyor'
        : _ruhsatDurumFilter == 'baslamadi'
        ? 'Başlamadı'
        : _ruhsatDurumFilter == 'tamamlandi'
        ? 'Tamamlandı'
        : 'Tümü';
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
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
            onChanged: (v) => setState(() => _searchQuery = v),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isMobileView)
                OutlinedButton.icon(
                  onPressed: () {
                    setState(
                      () =>
                          _filtersExpandedOnMobile = !_filtersExpandedOnMobile,
                    );
                  },
                  icon: Icon(
                    _filtersExpandedOnMobile
                        ? Icons.expand_less
                        : Icons.tune,
                  ),
                  label: Text(
                    _filtersExpandedOnMobile
                        ? 'Filtreleri Gizle'
                        : 'Filtreleri Göster',
                  ),
                ),
              if (!isMobileView || _filtersExpandedOnMobile)
                LayoutBuilder(
                  builder: (context, constraints) {
                    final fieldWidth = isMobileView
                        ? constraints.maxWidth
                        : null; // null → fixed width kullanılır
                    final seciliRuhsatMaddesi =
                        _ruhsatMaddeSecenekleri.contains(
                              _ruhsatMaddeFilterText,
                            )
                        ? _ruhsatMaddeFilterText
                        : null;
                    return Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _FilterTextField(
                          width: fieldWidth ?? 220,
                          label: 'Müteahhit',
                          value: _muteahhitFilterText,
                          options: _muteahhitSecenekleri,
                          onChanged: (v) =>
                              setState(() => _muteahhitFilterText = v),
                        ),
                        _FilterTextField(
                          width: fieldWidth ?? 240,
                          label: 'Ada / Parsel',
                          value: _adaParselFilterText,
                          options: _adaParselSecenekleri,
                          onChanged: (v) =>
                              setState(() => _adaParselFilterText = v),
                        ),
                        SizedBox(
                          width: fieldWidth ?? 300,
                          child: DropdownButtonFormField<String>(
                            initialValue: seciliRuhsatMaddesi,
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: 'Ruhsat Maddesi',
                              hintText: 'Madde seçin',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              filled: true,
                              fillColor: Colors.grey.shade50,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                            ),
                            items: _ruhsatMaddeSecenekleri
                                .map(
                                  (madde) => DropdownMenuItem<String>(
                                    value: madde,
                                    child: Text(
                                      madde,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) =>
                                setState(() => _ruhsatMaddeFilterText = v ?? ''),
                          ),
                        ),
                        if (_ruhsatMaddeFilterText.trim().isNotEmpty)
                          SizedBox(
                            width: fieldWidth ?? double.infinity,
                            child: Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                ChoiceChip(
                                  label: const Text('Devam Ediyor'),
                                  selected: _ruhsatDurumFilter == 'devam',
                                  onSelected: (_) => setState(
                                    () => _ruhsatDurumFilter = 'devam',
                                  ),
                                ),
                                ChoiceChip(
                                  label: const Text('Başlamadı'),
                                  selected: _ruhsatDurumFilter == 'baslamadi',
                                  onSelected: (_) => setState(
                                    () => _ruhsatDurumFilter = 'baslamadi',
                                  ),
                                ),
                                ChoiceChip(
                                  label: const Text('Tamamlandı'),
                                  selected: _ruhsatDurumFilter == 'tamamlandi',
                                  onSelected: (_) => setState(
                                    () => _ruhsatDurumFilter = 'tamamlandi',
                                  ),
                                ),
                                ChoiceChip(
                                  label: const Text('Tümü'),
                                  selected: _ruhsatDurumFilter == 'tum',
                                  onSelected: (_) =>
                                      setState(() => _ruhsatDurumFilter = 'tum'),
                                ),
                              ],
                            ),
                          ),
                      ],
                    );
                  },
                ),
            ],
          ),
        ),
        if (hasAnyFilter)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (_searchQuery.trim().isNotEmpty)
                  InputChip(
                    label: Text('Arama: $_searchQuery'),
                    onDeleted: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                  ),
                if (_muteahhitFilterText.trim().isNotEmpty)
                  InputChip(
                    label: Text('Müteahhit: $_muteahhitFilterText'),
                    onDeleted: () => setState(() => _muteahhitFilterText = ''),
                  ),
                if (_adaParselFilterText.trim().isNotEmpty)
                  InputChip(
                    label: Text('Ada/Parsel: $_adaParselFilterText'),
                    onDeleted: () => setState(() => _adaParselFilterText = ''),
                  ),
                if (_ruhsatMaddeFilterText.trim().isNotEmpty)
                  InputChip(
                    label: Text('Ruhsat: $_ruhsatMaddeFilterText'),
                    onDeleted: () => setState(() {
                      _ruhsatMaddeFilterText = '';
                      _ruhsatDurumFilter = 'devam';
                    }),
                  ),
                if (_ruhsatMaddeFilterText.trim().isNotEmpty)
                  InputChip(
                    label: Text('Durum: $ruhsatDurumLabel'),
                    onDeleted: () =>
                        setState(() => _ruhsatDurumFilter = 'devam'),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.clear_all, size: 16),
                  label: const Text('Tümünü Temizle'),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _searchQuery = '';
                      _muteahhitFilterText = '';
                      _adaParselFilterText = '';
                      _ruhsatMaddeFilterText = '';
                      _ruhsatDurumFilter = 'devam';
                    });
                  },
                ),
              ],
            ),
          ),
        Expanded(
          child: StreamBuilder<List<Project>>(
            stream: _firebase.getVisibleProjectsStream(
              companyId: widget.companyId,
              userEmail: SistemYoneticisi().girisYapanEmail ?? '',
            ),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                if (SistemYoneticisi().cikisYapiliyor)
                  return const SizedBox.shrink();
                return const Center(child: Text('Projeler yüklenemedi.'));
              }

              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.folder_open_outlined,
                        size: 48,
                        color: Colors.grey,
                      ),
                      const SizedBox(height: 12),
                      const Text('Henüz proje yok'),
                    ],
                  ),
                );
              }

              final allProjects = snapshot.data!;
              var projects = _searchQuery.isEmpty
                  ? allProjects
                  : allProjects
                        .where(
                          (p) => p.name.toLowerCase().contains(
                            _searchQuery.toLowerCase(),
                          ),
                        )
                        .toList();

              // Tüm proje verilerini ön-yükle (akış + finans)
              _preloadProjectData(allProjects);

              // Filtre seçeneklerini güncelle (setState çağırmadan direkt ata)
              final newMuteahhit = _uniqueSortedValues(
                allProjects.map(_projectMuteahhit),
              );
              final newAdaParsel = _uniqueSortedValues(
                allProjects.map(_projectAdaParsel),
              );
              final newRuhsatMaddeleri = _akisNodeNames.entries.toList()
                ..sort((a, b) => a.key.compareTo(b.key));
              final newRuhsatSecenekleri = newRuhsatMaddeleri
                  .map((e) => e.value)
                  .toList();
              if (!listEquals(newMuteahhit, _muteahhitSecenekleri)) {
                _muteahhitSecenekleri = newMuteahhit;
              }
              if (!listEquals(newAdaParsel, _adaParselSecenekleri)) {
                _adaParselSecenekleri = newAdaParsel;
              }
              if (!listEquals(newRuhsatSecenekleri, _ruhsatMaddeSecenekleri)) {
                _ruhsatMaddeSecenekleri = newRuhsatSecenekleri;
              }

              final filtered = projects
                  .where((p) => _projeFiltreyeUygunMu(p))
                  .toList();
              final muteahhitFilterAktif = _muteahhitFilterText
                  .trim()
                  .isNotEmpty;
              final ruhsatFilterAktif = _ruhsatMaddeFilterText
                  .trim()
                  .isNotEmpty;
              final muteahhitToplamProje = muteahhitFilterAktif
                  ? _muteahhitFiltreProjeSayisi(allProjects)
                  : 0;
              if (filtered.isEmpty) {
                return Center(
                  child: Text(
                    hasMetaFilter
                        ? 'Filtreyle eşleşen proje bulunamadı'
                        : 'Aramayla eşleşen proje bulunamadı',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                );
              }
              return Column(
                children: [
                  Container(
                    key: widget.reportButtonKey,
                    width: double.infinity,
                    margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                    child: ElevatedButton.icon(
                      onPressed: () => _filtreliProjeleriPdfRaporla(filtered),
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: Text(
                        hasMetaFilter ? 'Rapor Al (PDF)' : 'Tüm Projeleri Raporla (PDF)',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  if (muteahhitFilterAktif)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: AppTheme.primaryColor.withValues(alpha: 0.18),
                        ),
                      ),
                      child: Text(
                        'Müteahhit filtresi: $_muteahhitFilterText | Toplam proje: $muteahhitToplamProje',
                        style: TextStyle(
                          color: AppTheme.primaryColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  if (ruhsatFilterAktif)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Colors.orange.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Text(
                        'Ruhsat filtresi: $_ruhsatMaddeFilterText (${_ruhsatDurumFilter == 'devam'
                            ? 'Devam Ediyor'
                            : _ruhsatDurumFilter == 'baslamadi'
                            ? 'Başlamadı'
                            : _ruhsatDurumFilter == 'tamamlandi'
                            ? 'Tamamlandı'
                            : 'Tümü'})',
                        style: TextStyle(
                          color: Colors.orange.shade800,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  Expanded(child: _buildProjectList(filtered)),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildProjectList(List<Project> projects) {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: projects.length,
      itemBuilder: (context, index) {
        final project = projects[index];
        final finance = _financeCache[project.id];

        return Card(
          elevation: 1,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.grey.shade200),
          ),
          child: InkWell(
            onTap: () => widget.onProjectTap(project.id),
            onLongPress: SistemYoneticisi().isAdminKullanici
                ? () => _projeIsimDuzenle(project)
                : null,
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
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.primaryColor,
                                  ),
                            ),
                            if (project.isSharedWithMe)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.teal.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                      color: Colors.teal.withValues(
                                        alpha: 0.45,
                                      ),
                                    ),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.folder_shared_outlined,
                                        size: 14,
                                        color: Colors.teal,
                                      ),
                                      SizedBox(width: 6),
                                      Text(
                                        'Paylasilan Proje',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.teal,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            const SizedBox(height: 6),
                            Text(
                              '${project.startDate.day}.${project.startDate.month}.${project.startDate.year}',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: Colors.grey.shade600),
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
                            color: _getStatusColor(
                              project.status,
                            ).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _getStatusColor(
                                project.status,
                              ).withValues(alpha: 0.5),
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
                  if (finance != null &&
                      SistemYoneticisi().yetkiVarMi('muhasebe'))
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
                    Builder(
                      builder: (context) {
                        final r = _ruhsatOzetCache[project.id];
                        if (r == null) return const SizedBox.shrink();
                        final tamamlanan = r['tamamlanan'] as int;
                        final devamEden = r['devamEden'] as int;
                        final toplam = r['toplam'] as int;
                        final aktifMadde = r['aktifMadde'] as String?;
                        final baslatildi = r['baslatildi'] == true;
                        final ruhsatTamamlandi = r['ruhsatTamamlandi'] == true;

                        // Süreç hiç başlatılmamışsa kart gösterme
                        if (!baslatildi && tamamlanan == 0 && devamEden == 0) {
                          return const SizedBox.shrink();
                        }

                        final aktifMaddeStr = aktifMadde;
                        final tamamlandi = ruhsatTamamlandi;

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
                                      tamamlandi
                                          ? Icons.verified
                                          : Icons.description_outlined,
                                      size: 15,
                                      color: tamamlandi
                                          ? Colors.green.shade700
                                          : Colors.orange.shade700,
                                    ),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        'Ruhsat: $tamamlanan/$toplam',
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: tamamlandi
                                              ? Colors.green.shade700
                                              : Colors.orange.shade700,
                                        ),
                                      ),
                                    ),
                                    if (devamEden > 0) ...[
                                      const SizedBox(width: 6),
                                      Text(
                                        '($devamEden devam ediyor)',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.orange.shade600,
                                        ),
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
                                      tamamlandi
                                          ? Colors.green.shade500
                                          : Colors.orange.shade500,
                                    ),
                                    minHeight: 5,
                                  ),
                                ),
                                if (aktifMaddeStr != null && !tamamlandi) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    '▸ $aktifMaddeStr',
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

class _FilterTextField extends StatefulWidget {
  final double width;
  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  const _FilterTextField({
    required this.width,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  State<_FilterTextField> createState() => _FilterTextFieldState();
}

class _FilterTextFieldState extends State<_FilterTextField> {
  late final TextEditingController _ctrl;
  late final FocusNode _focusNode;
  OverlayEntry? _overlay;
  final LayerLink _layerLink = LayerLink();
  bool _isSelectingSuggestion = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value);
    _focusNode = FocusNode();
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus) {
        // Give suggestion taps time to run before hiding the overlay.
        Future.delayed(const Duration(milliseconds: 120), () {
          if (!mounted) return;
          if (!_focusNode.hasFocus && !_isSelectingSuggestion) _hideOverlay();
        });
      }
    });
  }

  void _selectSuggestion(String opt) {
    _isSelectingSuggestion = true;
    _ctrl.value = TextEditingValue(
      text: opt,
      selection: TextSelection.collapsed(offset: opt.length),
    );
    widget.onChanged(opt);
    _hideOverlay();

    // Unfocus after selection to keep UX consistent.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.unfocus();
    });

    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _isSelectingSuggestion = false;
    });
  }

  @override
  void didUpdateWidget(covariant _FilterTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sadece dışarıdan değiştirildiğinde (örn. temizle butonu) controller'ı güncelle
    if (widget.value != _ctrl.text) {
      _ctrl.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
      if (widget.value.isEmpty) _hideOverlay();
    }
  }

  @override
  void dispose() {
    _hideOverlay();
    _ctrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _hideOverlay() {
    _overlay?.remove();
    _overlay = null;
  }

  void _showOverlay(BuildContext ctx, List<String> suggestions) {
    _hideOverlay();
    if (suggestions.isEmpty) return;
    _overlay = OverlayEntry(
      builder: (_) => Positioned(
        width: widget.width,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: const Offset(0, 52),
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 4),
                shrinkWrap: true,
                itemCount: suggestions.length,
                itemBuilder: (_, i) {
                  final opt = suggestions[i];
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (_) => _selectSuggestion(opt),
                    child: ListTile(
                      dense: true,
                      title: Text(opt, overflow: TextOverflow.ellipsis),
                      onTap: () => _selectSuggestion(opt),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    Overlay.of(ctx, rootOverlay: true).insert(_overlay!);
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: SizedBox(
        width: widget.width,
        child: TextField(
          controller: _ctrl,
          focusNode: _focusNode,
          textInputAction: TextInputAction.search,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: widget.label,
            hintText: 'Yazarak ara',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            filled: true,
            fillColor: Colors.grey.shade50,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
            suffixIcon: _ctrl.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () {
                      _ctrl.clear();
                      widget.onChanged('');
                      _hideOverlay();
                    },
                  )
                : null,
          ),
          onChanged: (v) {
            widget.onChanged(v);
            if (!mounted) return;
            final q = v.trim().toLowerCase();
            final sug = q.isEmpty
                ? <String>[]
                : widget.options
                      .where((o) => o.toLowerCase().contains(q))
                      .take(6)
                      .toList();
            _showOverlay(context, sug);
          },
        ),
      ),
    );
  }
}
