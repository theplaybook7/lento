import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../project_core.dart';
import '../notification_service.dart';
import '../theme/app_theme.dart';
import 'project_details_screen.dart';

class BildirimlerScreen extends StatefulWidget {
  const BildirimlerScreen({super.key});

  @override
  State<BildirimlerScreen> createState() => _BildirimlerScreenState();
}

class _BildirimlerScreenState extends State<BildirimlerScreen> {
  final List<QueryDocumentSnapshot> _bildirimler = [];
  final Set<String> _localOkunanlar = {}; // Yerel okundu takibi
  DocumentSnapshot? _sonDoc;
  bool _yukleniyor = false;
  bool _dahaBildirimVar = true;
  String _filtre = 'tumu'; // tumu, okunmamis, okunmus
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _bildirimleriYukle();
    _scrollController.addListener(_scrollListener);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollListener() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      if (!_yukleniyor && _dahaBildirimVar) {
        _bildirimleriYukle();
      }
    }
  }

  Future<void> _bildirimleriYukle() async {
    if (_yukleniyor || !_dahaBildirimVar) return;
    setState(() => _yukleniyor = true);

    try {
      final snapshot = await BildirimServisi.tumBildirimleriGetir(
        sonDoc: _sonDoc,
        limit: 30,
      );

      if (snapshot.docs.isEmpty) {
        setState(() {
          _dahaBildirimVar = false;
          _yukleniyor = false;
        });
        return;
      }

      setState(() {
        _bildirimler.addAll(snapshot.docs);
        _sonDoc = snapshot.docs.last;
        _dahaBildirimVar = snapshot.docs.length == 30;
        _yukleniyor = false;
      });
    } catch (_) {
      setState(() => _yukleniyor = false);
    }
  }

  Future<void> _yenile() async {
    setState(() {
      _bildirimler.clear();
      _localOkunanlar.clear();
      _sonDoc = null;
      _dahaBildirimVar = true;
    });
    await _bildirimleriYukle();
  }

  List<QueryDocumentSnapshot> get _filtreliBildirimler {
    final email = SistemYoneticisi().girisYapanEmail;
    return _bildirimler.where((doc) {
      final b = doc.data() as Map<String, dynamic>;
      // Yetki + hedefEmail kontrolü
      if (!BildirimServisi.yetkiliMi(b)) {
        return false;
      }
      // Filtre kontrolü
      final okunmus = BildirimServisi.okunduMu(
        b,
        email: email,
        docId: doc.id,
        localOkunanlar: _localOkunanlar,
      );
      if (_filtre == 'okunmamis') return !okunmus;
      if (_filtre == 'okunmus') return okunmus;
      return true;
    }).toList();
  }

  Future<void> _okunduIsaretle(QueryDocumentSnapshot doc) async {
    await BildirimServisi.okunduIsaretleDoc(doc.id);
  }

  List<QueryDocumentSnapshot> get _okunmamisYetkiliBildirimler {
    final email = SistemYoneticisi().girisYapanEmail;
    return _bildirimler.where((doc) {
      final b = doc.data() as Map<String, dynamic>;
      if (!BildirimServisi.yetkiliMi(b)) {
        return false;
      }
      final okunmus = BildirimServisi.okunduMu(
        b,
        email: email,
        docId: doc.id,
        localOkunanlar: _localOkunanlar,
      );
      return !okunmus;
    }).toList();
  }

  Future<void> _hepsiniOkunduIsaretle() async {
    final okunmamislar = _okunmamisYetkiliBildirimler;
    if (okunmamislar.isEmpty) return;

    await BildirimServisi.tumunuOkunduIsaretle(okunmamislar);
    if (!mounted) return;

    setState(() {
      _localOkunanlar.addAll(okunmamislar.map((d) => d.id));
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${okunmamislar.length} bildirim okundu olarak işaretlendi')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final liste = _filtreliBildirimler;
    final email = SistemYoneticisi().girisYapanEmail;
    final okunmamisSayisi = _okunmamisYetkiliBildirimler.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tüm Bildirimler'),
        actions: [
          if (okunmamisSayisi > 0)
            IconButton(
              icon: const Icon(Icons.done_all),
              tooltip: 'Hepsini okundu işaretle',
              onPressed: _hepsiniOkunduIsaretle,
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list),
            tooltip: 'Filtrele',
            onSelected: (val) => setState(() => _filtre = val),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'tumu',
                child: Row(
                  children: [
                    Icon(Icons.all_inbox, size: 18, color: _filtre == 'tumu' ? AppTheme.primaryColor : Colors.grey),
                    const SizedBox(width: 8),
                    const Text('Tümü'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'okunmamis',
                child: Row(
                  children: [
                    Icon(Icons.markunread, size: 18, color: _filtre == 'okunmamis' ? Colors.deepOrange : Colors.grey),
                    const SizedBox(width: 8),
                    const Text('Okunmamış'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'okunmus',
                child: Row(
                  children: [
                    Icon(Icons.drafts, size: 18, color: _filtre == 'okunmus' ? Colors.green : Colors.grey),
                    const SizedBox(width: 8),
                    const Text('Okunmuş'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _yenile,
        child: liste.isEmpty && !_yukleniyor
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.notifications_off_outlined, size: 56, color: Colors.grey.shade300),
                    const SizedBox(height: 12),
                    Text(
                      _filtre == 'okunmamis'
                          ? 'Okunmamış bildirim yok'
                          : _filtre == 'okunmus'
                              ? 'Okunmuş bildirim yok'
                              : 'Henüz bildirim yok',
                      style: TextStyle(color: Colors.grey.shade500, fontSize: 15),
                    ),
                  ],
                ),
              )
            : ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                itemCount: liste.length + (_dahaBildirimVar ? 1 : 0),
                itemBuilder: (ctx, i) {
                  if (i == liste.length) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                    );
                  }

                  final doc = liste[i];
                  final b = doc.data() as Map<String, dynamic>;
                  final baslik = b['baslik'] ?? '';
                  final mesaj = b['mesaj'] ?? '';
                  final gonderen = b['gonderen'] ?? '';
                  final projeId = b['projeId'] ?? '';
                  final tip = BildirimServisi.bildirimTipi(b);
                  final tarih = b['tarih'] as Timestamp?;
                  final okunmus = BildirimServisi.okunduMu(
                    b,
                    email: email,
                    docId: doc.id,
                    localOkunanlar: _localOkunanlar,
                  );
                  final modulRenk = BildirimServisi.bildirimRenk(b);
                  final modulIkon = BildirimServisi.bildirimIkon(b);

                  String zamanStr = '';
                  if (tarih != null) {
                    final t = tarih.toDate();
                    final fark = DateTime.now().difference(t);
                    if (fark.inMinutes < 1) {
                      zamanStr = 'Az önce';
                    } else if (fark.inMinutes < 60) {
                      zamanStr = '${fark.inMinutes} dk önce';
                    } else if (fark.inHours < 24) {
                      zamanStr = '${fark.inHours} saat önce';
                    } else if (fark.inDays < 7) {
                      zamanStr = '${fark.inDays} gün önce';
                    } else {
                      zamanStr = '${t.day.toString().padLeft(2, '0')}.${t.month.toString().padLeft(2, '0')}.${t.year}';
                    }
                  }

                  return Card(
                    elevation: okunmus ? 0 : 1,
                    color: okunmus ? Colors.grey.shade50 : Colors.white,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(
                        color: okunmus ? Colors.grey.shade200 : modulRenk.withValues(alpha: 0.3),
                      ),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () async {
                        if (!okunmus) {
                          _localOkunanlar.add(doc.id);
                          _okunduIsaretle(doc);
                          setState(() {});
                        }
                        if (!mounted) return;
                        if (projeId.toString().isNotEmpty) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (c) => ProjectDetailsScreen(projectId: projeId),
                            ),
                          );
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: (okunmus ? Colors.grey : modulRenk).withValues(alpha: 0.12),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(modulIkon, size: 20, color: okunmus ? Colors.grey : modulRenk),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      if (!okunmus)
                                        Container(
                                          width: 8,
                                          height: 8,
                                          margin: const EdgeInsets.only(right: 6),
                                          decoration: BoxDecoration(
                                            color: modulRenk,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                      Expanded(
                                        child: Text(
                                          baslik,
                                          style: TextStyle(
                                            fontWeight: okunmus ? FontWeight.normal : FontWeight.bold,
                                            fontSize: 13,
                                            color: okunmus ? Colors.grey.shade600 : modulRenk,
                                          ),
                                        ),
                                      ),
                                      if (!okunmus)
                                        Container(
                                          margin: const EdgeInsets.only(left: 6),
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: modulRenk.withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            tip.toUpperCase(),
                                            style: TextStyle(
                                              fontSize: 9,
                                              fontWeight: FontWeight.w700,
                                              color: modulRenk,
                                            ),
                                          ),
                                        ),
                                      if (zamanStr.isNotEmpty)
                                        Text(zamanStr, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    mesaj,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: okunmus ? Colors.grey.shade500 : Colors.black87,
                                    ),
                                  ),
                                  if (gonderen.toString().isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: Row(
                                        children: [
                                          Icon(Icons.person_outline, size: 13, color: Colors.grey.shade400),
                                          const SizedBox(width: 4),
                                          Text(gonderen.toString(), style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
