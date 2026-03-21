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
import '../main.dart' show AuthGate;
import '../utils/format_utils.dart' as format_utils;

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
    _companyId = SistemYoneticisi().aktifSirket?.id ?? 'default';
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
        title: const Text('Lento'),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        elevation: 1,
        actions: [
          StreamBuilder<QuerySnapshot>(
            stream: BildirimServisi.bildirimleriDinle(),
            builder: (context, snapshot) {
              int okunmayanSayisi = 0;
              if (snapshot.hasData) {
                okunmayanSayisi = snapshot.data!.docs.where((doc) {
                  final b = doc.data() as Map<String, dynamic>;
                  final okuyanlar = (b['okuyanlar'] as List?)?.cast<String>() ?? [];
                  return !okuyanlar.contains(SistemYoneticisi().girisYapanEmail);
                }).length;
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
                } else if (value == 'logout') {
                  SistemYoneticisi().temizle();
                  await FirebaseAuth.instance.signOut();
                }
              },
              itemBuilder: (context) => const [
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
                NavigationRail(
                  selectedIndex: navIndex,
                  onDestinationSelected: (i) => setState(() => _navIndex = i),
                  backgroundColor: Colors.white,
                  destinations: [
                    const NavigationRailDestination(
                      icon: Icon(Icons.home_outlined),
                      selectedIcon: Icon(Icons.home),
                      label: Text('Projeler'),
                    ),
                    const NavigationRailDestination(
                      icon: Icon(Icons.description_outlined),
                      selectedIcon: Icon(Icons.description),
                      label: Text('Teklifler'),
                    ),
                    const NavigationRailDestination(
                      icon: Icon(Icons.account_balance_wallet_outlined),
                      selectedIcon: Icon(Icons.account_balance_wallet),
                      label: Text('Cariler'),
                    ),
                    if (canMuhasebe)
                      const NavigationRailDestination(
                        icon: Icon(Icons.assessment_outlined),
                        selectedIcon: Icon(Icons.assessment),
                        label: Text('Muhasebe'),
                      ),
                  ],
                  trailing: Column(
                    children: [
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
          ? FloatingActionButton.extended(
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
            )
            : navIndex == 1
              ? FloatingActionButton.extended(
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
                )
              : navIndex == 2
                ? FloatingActionButton.extended(
                    onPressed: () => _yeniCariDialogGlobal(context),
                    icon: const Icon(Icons.add),
                    label: const Text('Cari Ekle'),
                    backgroundColor: AppTheme.primaryColor,
                  )
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
                if (!snap.hasData || snap.data!.docs.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Bildirim yok'),
                  );
                }

                final okunmamis = snap.data!.docs.where((doc) {
                  final b = doc.data() as Map<String, dynamic>;
                  final okuyanlar = (b['okuyanlar'] as List?)?.cast<String>() ?? [];
                  return !okuyanlar.contains(SistemYoneticisi().girisYapanEmail);
                }).toList();

                if (okunmamis.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Bildirim yok'),
                  );
                }

                return ListView.builder(
                  shrinkWrap: true,
                  itemCount: okunmamis.length,
                  itemBuilder: (ctx, i) {
                    final doc = okunmamis[i];
                    final b = doc.data() as Map<String, dynamic>;
                    final baslik = b['baslik'] ?? '';
                    final mesaj = b['mesaj'] ?? '';
                    final gonderen = b['gonderen'] ?? '';
                    final projeId = b['projeId'] ?? '';

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
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(baslik, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            const SizedBox(height: 6),
                            Text(mesaj, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                            if (gonderen.toString().isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  'Yapan: $gonderen',
                                  style: const TextStyle(fontSize: 11, color: Colors.black54),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
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
                return Center(child: Text('Hata: ${snapshot.error}'));
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
                            const SizedBox(width: 16),
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
                                  bakiye == 0 ? 'Dengede' : (alacak ? 'Alacak' : 'Borç'),
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
                    label: const Text("Tamamlandı"),
                    selected: _durumFiltre == 'tamamlandi',
                    onSelected: (v) => setState(() => _durumFiltre = 'tamamlandi'),
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
                      "Veriler yüklenemedi.\nLütfen Firebase Console'da INDEX oluşturun.\n\nHata: ${snapshot.error}",
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

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Project>>(
      stream: _firebase.getProjectsStream(widget.companyId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          if (SistemYoneticisi().cikisYapiliyor) return const SizedBox.shrink();
          return Center(
            child: Text('Hata: ${snapshot.error}'),
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

        final projects = snapshot.data!;

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
