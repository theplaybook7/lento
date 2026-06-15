import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import '../models/project_model.dart';
import '../services/firebase_service.dart';
import '../utils/format_utils.dart' as format_utils;
import '../theme/app_theme.dart';
import '../utils/error_handler.dart';
import '../utils/upload_helper.dart';
import '../project_core.dart';
import '../notification_service.dart';
import '../utils/responsive_utils.dart' as resp;
import '../web/web_utils.dart' as web_utils;
import 'cari_hesap_screen.dart';
import 'paywall_screen.dart';
import '../payment_service.dart';

class ProjectDetailsScreen extends StatefulWidget {
  final String projectId;
  const ProjectDetailsScreen({super.key, required this.projectId});

  @override
  State<ProjectDetailsScreen> createState() => _ProjectDetailsScreenState();
}

String _mimeTypeFromExtension(String ext) {
  switch (ext.toLowerCase()) {
    case 'pdf':
      return 'application/pdf';
    case 'doc':
      return 'application/msword';
    case 'docx':
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    case 'xls':
      return 'application/vnd.ms-excel';
    case 'xlsx':
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    case 'png':
      return 'image/png';
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'gif':
      return 'image/gif';
    case 'webp':
      return 'image/webp';
    default:
      return 'application/octet-stream';
  }
}

class _AkisStepDefinition {
  final int sira;
  final String id;
  final String title;

  const _AkisStepDefinition({
    required this.sira,
    required this.id,
    required this.title,
  });
}

class _AkisFlowDefinition {
  final int version;
  final List<_AkisStepDefinition> steps;

  const _AkisFlowDefinition({required this.version, required this.steps});

  Map<int, _AkisStepDefinition> get bySira => {
    for (final step in steps) step.sira: step,
  };

  Map<String, _AkisStepDefinition> get byId => {
    for (final step in steps) step.id: step,
  };

  _AkisStepDefinition get firstStep => steps.first;
  _AkisStepDefinition get lastStep => steps.last;
}

const int _defaultAkisFlowVersion = 1;
const _AkisFlowDefinition _akisFlowV1 = _AkisFlowDefinition(
  version: 1,
  steps: [
    _AkisStepDefinition(sira: 1, id: 'lihkap', title: 'Lihkap'),
    _AkisStepDefinition(sira: 2, id: 'imar_durumu', title: 'İmar Durumu'),
    _AkisStepDefinition(
      sira: 3,
      id: 'harita_arazi_randevusu',
      title: 'Harita Arazi Randevusu Alınacaklar',
    ),
    _AkisStepDefinition(
      sira: 4,
      id: 'istikamet_kot_imza',
      title: 'İstikamet , Kot İmzalanacaklar',
    ),
    _AkisStepDefinition(sira: 5, id: 'folyo', title: 'Folyo'),
    _AkisStepDefinition(
      sira: 6,
      id: 'folyo_dilekcesi',
      title: 'Folyo Dilekçesi Verilenler',
    ),
    _AkisStepDefinition(
      sira: 7,
      id: 'encumene_girenler',
      title: 'Encümene Girenler',
    ),
    _AkisStepDefinition(sira: 8, id: 'kadastro', title: 'Kadastro'),
    _AkisStepDefinition(sira: 9, id: 'tapu_mudurlugu', title: 'Tapu Müdürlüğü'),
    _AkisStepDefinition(
      sira: 10,
      id: 'etut_yapilacaklar',
      title: 'Etüt Yapılacaklar',
    ),
    _AkisStepDefinition(
      sira: 11,
      id: 'mimari_proje_cizilecekler',
      title: 'Mimari Proje Çizilecekler',
    ),
    _AkisStepDefinition(sira: 12, id: 'iski', title: 'İski'),
    _AkisStepDefinition(sira: 13, id: 'statik_taslak', title: 'Statik Taslak'),
    _AkisStepDefinition(
      sira: 14,
      id: 'zemin_degeri_beklenenler',
      title: 'Zemin Değeri Beklenenler',
    ),
    _AkisStepDefinition(
      sira: 15,
      id: 'statik_proje_yapilacaklar',
      title: 'Statik Proje Yapılacaklar',
    ),
    _AkisStepDefinition(
      sira: 16,
      id: 'muellif_taahhutnameleri',
      title: 'Müellif Taahhütnameleri',
    ),
    _AkisStepDefinition(
      sira: 17,
      id: 'ruhsat_dilekcesi_verilenler',
      title: 'Ruhsat Dilekçesi Verilenler',
    ),
  ],
);

final Map<int, _AkisFlowDefinition> _akisFlowDefinitions = {
  _akisFlowV1.version: _akisFlowV1,
};

class _ProjectDetailsScreenState extends State<ProjectDetailsScreen>
    with SingleTickerProviderStateMixin {
  late FirebaseService _firebase;
  late TabController _tabController;

  // Ruhsat işlem sırası durum yönetimi
  final Map<int, int> _ruhsatDurumlari =
      {}; // sıra -> durum (0: başlamadı, 1: devam ediyor, 2: tamamlandı)
  final Map<int, String> _ruhsatNotlari = {}; // sıra -> not metni

  // Belgeler
  final List<Map<String, String>> _yuklenenBelgeler =
      []; // {başlık, tarih, type}

  final String _belgeArama = '';

  // Akış Diyagramı durum yönetimi
  final Map<int, int> _akisDurumlari = {};
  final Map<int, String> _akisNotlari = {};
  final TextEditingController _akisNotEditController = TextEditingController();
  // ignore: unused_field
  bool _tapuSureciGerekli =
      false; // Karar Kontrolü Evet/Hayır - Firestore'dan yüklenir
  // ignore: unused_field
  bool _yolaTerkMi = false; // Yola Terk Kontrolü - Firestore'dan yüklenir
  // ignore: unused_field
  bool _yolaTerkKararVerildi =
      false; // Karar verildi mi? - Firestore'dan yüklenir
  // Yeni sade akış diyagramı meta
  bool _akisBaslatildi = false;
  DateTime? _akisBaslatmaTarihi;
  DateTime? _akisSonGuncelleme;
  bool _akisRuhsatTamamlandi = false;
  DateTime? _akisTamamlanmaTarihi;
  int _akisFlowVersion = _defaultAkisFlowVersion;
  int _akisSecilenSira = 1;

  // Proje adı
  String _projeAdi = '';

  // Şantiye durum yönetimi
  int _santiyeKatSayisi = 0; // Kullanıcının girdiği kat sayısı
  final Map<int, int> _santiyeDurumlari =
      {}; // sıra -> durum (0: başlamadı, 1: devam ediyor, 2: tamamlandı)
  final Map<int, List<Map<String, String>>> _santiyeFotograflar =
      {}; // sıra -> [{url, tarih}]

  bool _paylasimYukleniyor = true;
  bool _paylasimOverrideAktif = false;
  bool _paylasimDuzenlemeYetkisi = true;
  Map<String, bool> _paylasimModulYetkileri = {
    'muhasebe': true,
    'ruhsat': true,
    'santiye': true,
  };
  Map<String, bool> _paylasimModulDuzenlemeYetkileri = {
    'muhasebe': true,
    'ruhsat': true,
    'santiye': true,
  };

  @override
  void initState() {
    super.initState();
    _firebase = FirebaseService();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _projeAdiniYukle();
    _projePaylasimYetkisiYukle();
    _ruhsatVerileriniYukle();
    _belgeleriYukle();
    _akisDiyagramiYukle();
    _santiyeVerileriniYukle();
  }

  String _normalizeEmail(String value) => value.trim().toLowerCase();

  bool get _duzenlemeYetkisiVar =>
      !_paylasimOverrideAktif || _paylasimDuzenlemeYetkisi;

  String? _aktifModulAnahtari() {
    if (!_paylasimOverrideAktif) return null;
    switch (_tabController.index) {
      case 0:
        return 'ruhsat';
      case 1:
        return 'santiye';
      case 2:
        return 'muhasebe';
      default:
        return null;
    }
  }

  bool _duzenlemeYetkisiKontrolEt([String? modul]) {
    final hedefModul = modul ?? _aktifModulAnahtari();
    final yetkiVar =
        _duzenlemeYetkisiVar &&
        (hedefModul == null ||
            !_paylasimOverrideAktif ||
            (_paylasimModulDuzenlemeYetkileri[hedefModul] ?? false));
    if (yetkiVar) return true;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            hedefModul == null
                ? 'Bu proje size salt okunur olarak paylasildi. Duzenleme yapamazsiniz.'
                : 'Bu proje paylasiminda $hedefModul duzenleme yetkiniz bulunmuyor.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
    }
    return false;
  }

  bool _modulYetkisiVarMi(String modul) {
    if (_paylasimOverrideAktif) {
      return _paylasimModulYetkileri[modul] ?? false;
    }
    return SistemYoneticisi().yetkiVarMi(modul);
  }

  Future<void> _projePaylasimYetkisiYukle() async {
    try {
      final email = _normalizeEmail(SistemYoneticisi().girisYapanEmail ?? '');
      if (email.isEmpty) {
        if (mounted) {
          setState(() {
            _paylasimYukleniyor = false;
          });
        }
        return;
      }

      final projectDoc = await FirebaseFirestore.instance
          .collection('projects')
          .doc(widget.projectId)
          .get();
      final data = projectDoc.data() ?? <String, dynamic>{};
      final raw = List<Map<String, dynamic>>.from(
        (data['paylasimlar'] as List?)?.map(
              (e) => Map<String, dynamic>.from(e as Map),
            ) ??
            const [],
      );

      Map<String, dynamic>? benimKaydim;
      for (final kayit in raw) {
        if (_normalizeEmail((kayit['email'] ?? '').toString()) == email) {
          benimKaydim = kayit;
          break;
        }
      }

      if (!mounted) return;
      final kayit = benimKaydim;
      if (kayit != null) {
        final canEdit = kayit['canEdit'] == true;
        bool modulDuzenlemeYetkisi(String key) {
          if (kayit.containsKey(key)) {
            return kayit[key] == true;
          }
          return canEdit;
        }

        setState(() {
          _paylasimOverrideAktif = true;
          _paylasimDuzenlemeYetkisi = canEdit;
          _paylasimModulYetkileri = {
            'muhasebe': kayit['muhasebe'] == true,
            'ruhsat': kayit['ruhsat'] == true,
            'santiye': kayit['santiye'] == true,
          };
          _paylasimModulDuzenlemeYetkileri = {
            'muhasebe': modulDuzenlemeYetkisi('editMuhasebe'),
            'ruhsat': modulDuzenlemeYetkisi('editRuhsat'),
            'santiye': modulDuzenlemeYetkisi('editSantiye'),
          };
          _paylasimYukleniyor = false;
        });
      } else {
        setState(() {
          _paylasimOverrideAktif = false;
          _paylasimDuzenlemeYetkisi = true;
          _paylasimModulYetkileri = {
            'muhasebe': true,
            'ruhsat': true,
            'santiye': true,
          };
          _paylasimModulDuzenlemeYetkileri = {
            'muhasebe': true,
            'ruhsat': true,
            'santiye': true,
          };
          _paylasimYukleniyor = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _paylasimYukleniyor = false;
        });
      }
    }
  }

  Future<void> _projePaylasimDialoguAc() async {
    final sirket = SistemYoneticisi().aktifSirket;
    if (sirket == null) return;
    if (!sirket.planLimitleri.projePaylasabilir) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Proje paylasimi sadece Buyuk Isletme planinda kullanilabilir.',
            ),
            backgroundColor: Colors.orange,
            action:
                PaymentService().isPaymentSupported &&
                    sirket.aktifPlan != PlanTier.enterprise
                ? SnackBarAction(
                    label: 'Aboneligi Yukselt',
                    textColor: Colors.white,
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const PaywallScreen(
                            mode: PaywallMode.subscription,
                          ),
                        ),
                      );
                    },
                  )
                : null,
          ),
        );
      }
      return;
    }

    final mevcutDoc = await FirebaseFirestore.instance
        .collection('projects')
        .doc(widget.projectId)
        .get();
    final mevcutData = mevcutDoc.data() ?? <String, dynamic>{};
    final paylasimlar = List<Map<String, dynamic>>.from(
      (mevcutData['paylasimlar'] as List?)?.map(
            (e) => Map<String, dynamic>.from(e as Map),
          ) ??
          const [],
    );

    final emailCtrl = TextEditingController();
    bool kaydediliyor = false;
    bool canEdit = false;
    bool ruhsat = true;
    bool santiye = true;
    bool muhasebe = false;
    bool editRuhsat = false;
    bool editSantiye = false;
    bool editMuhasebe = false;
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Proje Paylasimi'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: emailCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Paylasilacak hesap e-postasi',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  value: ruhsat,
                  onChanged: (v) => setDialogState(() {
                    ruhsat = v ?? false;
                    if (!ruhsat) editRuhsat = false;
                  }),
                  title: const Text('Ruhsat goruntuleyebilsin'),
                  contentPadding: EdgeInsets.zero,
                ),
                CheckboxListTile(
                  value: santiye,
                  onChanged: (v) => setDialogState(() {
                    santiye = v ?? false;
                    if (!santiye) editSantiye = false;
                  }),
                  title: const Text('Santiye goruntuleyebilsin'),
                  contentPadding: EdgeInsets.zero,
                ),
                CheckboxListTile(
                  value: muhasebe,
                  onChanged: (v) => setDialogState(() {
                    muhasebe = v ?? false;
                    if (!muhasebe) editMuhasebe = false;
                  }),
                  title: const Text('Muhasebe goruntuleyebilsin'),
                  contentPadding: EdgeInsets.zero,
                ),
                const Divider(),
                SwitchListTile(
                  value: canEdit,
                  onChanged: (v) => setDialogState(() {
                    canEdit = v;
                    if (v) {
                      // Duzenleme acildiginda secili moduller icin duzenlemeyi varsayilan ac.
                      editRuhsat = ruhsat;
                      editSantiye = santiye;
                      editMuhasebe = muhasebe;
                    } else {
                      editRuhsat = false;
                      editSantiye = false;
                      editMuhasebe = false;
                    }
                  }),
                  title: const Text(
                    'Duzenleme izni ver (modul secimi asagida)',
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
                if (canEdit) ...[
                  CheckboxListTile(
                    value: editRuhsat,
                    onChanged: (v) => setDialogState(() {
                      editRuhsat = v ?? false;
                      if (editRuhsat) ruhsat = true;
                    }),
                    title: const Text('Ruhsatta duzenleyebilsin'),
                    contentPadding: EdgeInsets.zero,
                  ),
                  CheckboxListTile(
                    value: editSantiye,
                    onChanged: (v) => setDialogState(() {
                      editSantiye = v ?? false;
                      if (editSantiye) santiye = true;
                    }),
                    title: const Text('Santiyede duzenleyebilsin'),
                    contentPadding: EdgeInsets.zero,
                  ),
                  CheckboxListTile(
                    value: editMuhasebe,
                    onChanged: (v) => setDialogState(() {
                      editMuhasebe = v ?? false;
                      if (editMuhasebe) muhasebe = true;
                    }),
                    title: const Text('Muhasebede duzenleyebilsin'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
                if (paylasimlar.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Mevcut paylasimlar:',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  ...paylasimlar.map((p) {
                    final pEmail = (p['email'] ?? '').toString();
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(pEmail),
                      subtitle: Text(
                        'R:${p['ruhsat'] == true ? 'E' : 'H'} S:${p['santiye'] == true ? 'E' : 'H'} M:${p['muhasebe'] == true ? 'E' : 'H'} | Duzenleme:${p['canEdit'] == true ? 'Evet' : 'Hayir'} (R:${p['editRuhsat'] == true ? 'E' : 'H'} S:${p['editSantiye'] == true ? 'E' : 'H'} M:${p['editMuhasebe'] == true ? 'E' : 'H'})',
                      ),
                      trailing: IconButton(
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Colors.red,
                        ),
                        onPressed: () async {
                          paylasimlar.removeWhere(
                            (x) =>
                                _normalizeEmail(
                                  (x['email'] ?? '').toString(),
                                ) ==
                                _normalizeEmail(pEmail),
                          );
                          final paylasilanEmailler = paylasimlar
                              .map(
                                (x) => _normalizeEmail(
                                  (x['email'] ?? '').toString(),
                                ),
                              )
                              .where((x) => x.isNotEmpty)
                              .toSet()
                              .toList();
                          await FirebaseFirestore.instance
                              .collection('projects')
                              .doc(widget.projectId)
                              .set({
                                'paylasimlar': paylasimlar,
                                'paylasilanEmailler': paylasilanEmailler,
                              }, SetOptions(merge: true));
                          setDialogState(() {});
                          await _projePaylasimYetkisiYukle();
                        },
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: kaydediliyor ? null : () => Navigator.pop(ctx),
              child: const Text('Kapat'),
            ),
            ElevatedButton(
              onPressed: kaydediliyor
                  ? null
                  : () async {
                      final messenger = ScaffoldMessenger.of(context);
                      final normalizedEmail = _normalizeEmail(emailCtrl.text);
                      if (normalizedEmail.isEmpty) {
                        messenger.showSnackBar(
                          const SnackBar(
                            content: Text('Lutfen e-posta girin.'),
                          ),
                        );
                        return;
                      }

                      if (!ruhsat && !santiye && !muhasebe) {
                        messenger.showSnackBar(
                          const SnackBar(
                            content: Text('En az bir bolum secmelisiniz.'),
                          ),
                        );
                        return;
                      }

                      setDialogState(() {
                        kaydediliyor = true;
                      });

                      try {
                        if (!ruhsat) editRuhsat = false;
                        if (!santiye) editSantiye = false;
                        if (!muhasebe) editMuhasebe = false;

                        paylasimlar.removeWhere(
                          (x) =>
                              _normalizeEmail((x['email'] ?? '').toString()) ==
                              normalizedEmail,
                        );
                        paylasimlar.add({
                          'email': normalizedEmail,
                          'ruhsat': ruhsat,
                          'santiye': santiye,
                          'muhasebe': muhasebe,
                          'canEdit': canEdit,
                          'editRuhsat': canEdit && editRuhsat,
                          'editSantiye': canEdit && editSantiye,
                          'editMuhasebe': canEdit && editMuhasebe,
                          'sharedBy': _normalizeEmail(
                            SistemYoneticisi().girisYapanEmail ?? '',
                          ),
                          'updatedAt': Timestamp.fromDate(DateTime.now()),
                        });

                        final paylasilanEmailler = paylasimlar
                            .map(
                              (x) => _normalizeEmail(
                                (x['email'] ?? '').toString(),
                              ),
                            )
                            .where((x) => x.isNotEmpty)
                            .toSet()
                            .toList();

                        await FirebaseFirestore.instance
                            .collection('projects')
                            .doc(widget.projectId)
                            .set({
                              'paylasimlar': paylasimlar,
                              'paylasilanEmailler': paylasilanEmailler,
                            }, SetOptions(merge: true));

                        await _projePaylasimYetkisiYukle();
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                        messenger.showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Proje paylasim yetkisi guncellendi.',
                            ),
                          ),
                        );
                      } catch (e) {
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text('Kaydetme hatasi: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      } finally {
                        if (ctx.mounted) {
                          setDialogState(() {
                            kaydediliyor = false;
                          });
                        }
                      }
                    },
              child: kaydediliyor
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );
  }

  _AkisFlowDefinition get _aktifAkisFlow =>
      _akisFlowDefinitions[_akisFlowVersion] ??
      _akisFlowDefinitions[_defaultAkisFlowVersion]!;

  int _resolveAkisFlowVersion(int? flowVersion) {
    if (flowVersion != null && _akisFlowDefinitions.containsKey(flowVersion)) {
      return flowVersion;
    }
    return _defaultAkisFlowVersion;
  }

  _AkisStepDefinition? _aktifAkisAdimi(int sira) => _aktifAkisFlow.bySira[sira];

  String _akisAdimBaslik(int sira) => _aktifAkisAdimi(sira)?.title ?? '';

  String _akisAdimId(int sira) => _aktifAkisAdimi(sira)?.id ?? 'madde_$sira';

  String _akisDocId(int sira) {
    final adim = _aktifAkisAdimi(sira);
    if (adim == null) return 'madde_$sira';
    if (_aktifAkisFlow.version == 1) {
      return 'madde_${adim.sira}';
    }
    return adim.id;
  }

  _AkisStepDefinition? _akisAdimiCoz(Map<String, dynamic> data, String docId) {
    final stepId = data['stepId'] as String?;
    if (stepId != null) {
      final fromId = _aktifAkisFlow.byId[stepId];
      if (fromId != null) return fromId;
    }

    final sira = data['sira'];
    if (sira is int) {
      final fromSira = _aktifAkisFlow.bySira[sira];
      if (fromSira != null) return fromSira;
    }

    if (docId.startsWith('madde_')) {
      final legacySira = int.tryParse(docId.substring('madde_'.length));
      if (legacySira != null) {
        return _aktifAkisFlow.bySira[legacySira];
      }
    }

    return null;
  }

  void _akisSecimiDogrula() {
    if (_aktifAkisAdimi(_akisSecilenSira) == null) {
      _akisSecilenSira = _aktifAkisFlow.firstStep.sira;
    }
  }

  bool _isAkisSonMadde(int sira) {
    final adim = _aktifAkisAdimi(sira);
    return adim != null && adim.id == _aktifAkisFlow.lastStep.id;
  }

  void _projeAdiniYukle() async {
    try {
      final project = await _firebase.getProject(widget.projectId);
      if (project != null && mounted) {
        setState(() => _projeAdi = project.name);
      }
    } catch (_) {}
  }

  void _akisDiyagramiYukle() async {
    try {
      final ruhsatRootDoc = await FirebaseFirestore.instance
          .collection('ruhsat')
          .doc(widget.projectId)
          .get();
      final rootData = ruhsatRootDoc.data() ?? <String, dynamic>{};

      final snapshot = await FirebaseFirestore.instance
          .collection('ruhsat')
          .doc(widget.projectId)
          .collection('akis_diyagrami')
          .get();
      int resolvedFlowVersion = _resolveAkisFlowVersion(
        rootData['flowVersion'] as int?,
      );
      final stepDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];

      for (var doc in snapshot.docs) {
        final data = doc.data();
        if (doc.id == '_meta') {
          resolvedFlowVersion = _resolveAkisFlowVersion(
            data['flowVersion'] as int? ?? resolvedFlowVersion,
          );
          if (mounted) {
            setState(() {
              _akisFlowVersion = resolvedFlowVersion;
              _akisSecimiDogrula();
              _akisBaslatildi = data['baslatildi'] == true;
              final bt = data['baslatmaTarihi'];
              if (bt is Timestamp) _akisBaslatmaTarihi = bt.toDate();
              final sg = data['sonGuncellemeTarihi'];
              if (sg is Timestamp) _akisSonGuncelleme = sg.toDate();
              _akisRuhsatTamamlandi = data['ruhsatTamamlandi'] == true;
              final tt = data['tamamlanmaTarihi'];
              if (tt is Timestamp) _akisTamamlanmaTarihi = tt.toDate();
            });
          }
          continue;
        }
        if (doc.id == 'karar_kontrol') {
          if (mounted) {
            setState(() {
              _tapuSureciGerekli = data['tapuGerekli'] == true;
            });
          }
          continue;
        }
        if (doc.id == 'yola_terk_kontrol') {
          if (mounted) {
            setState(() {
              _yolaTerkMi = data['yolaTerk'] == true;
              _yolaTerkKararVerildi = data['kararVerildi'] == true;
            });
          }
          continue;
        }
        stepDocs.add(doc);
      }

      if (mounted) {
        setState(() {
          _akisFlowVersion = resolvedFlowVersion;
          _akisSecimiDogrula();
          _akisDurumlari.clear();
          _akisNotlari.clear();
          for (final doc in stepDocs) {
            final data = doc.data();
            final step = _akisAdimiCoz(data, doc.id);
            final sira = step?.sira;
            final durum = data['durum'] as int?;
            final not = data['not'] as String?;
            if (sira != null) {
              if (durum != null) _akisDurumlari[sira] = durum;
              if (not != null && not.isNotEmpty) _akisNotlari[sira] = not;
            }
          }
        });
      }
    } catch (e) {
      developer.log('Akış diyagramı yükleme hatası: $e');
    }
  }

  // ── Yeni sade akış diyagramı yardımcıları ──
  Future<void> _akisBaslat() async {
    if (!_duzenlemeYetkisiKontrolEt()) return;
    final now = DateTime.now();
    try {
      await FirebaseFirestore.instance
          .collection('ruhsat')
          .doc(widget.projectId)
          .set({'flowVersion': _akisFlowVersion}, SetOptions(merge: true));
      await FirebaseFirestore.instance
          .collection('ruhsat')
          .doc(widget.projectId)
          .collection('akis_diyagrami')
          .doc('_meta')
          .set({
            'flowVersion': _akisFlowVersion,
            'baslatildi': true,
            'baslatmaTarihi': Timestamp.fromDate(now),
            'sonGuncellemeTarihi': Timestamp.fromDate(now),
            'ruhsatTamamlandi': false,
          }, SetOptions(merge: true));
      if (mounted) {
        setState(() {
          _akisBaslatildi = true;
          _akisBaslatmaTarihi = now;
          _akisSonGuncelleme = now;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Başlatma hatası: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _akisSonGuncellemeYenile() async {
    if (_akisRuhsatTamamlandi) return; // tamamlandıysa sayaç durur
    final now = DateTime.now();
    try {
      await FirebaseFirestore.instance
          .collection('ruhsat')
          .doc(widget.projectId)
          .collection('akis_diyagrami')
          .doc('_meta')
          .set({
            'sonGuncellemeTarihi': Timestamp.fromDate(now),
          }, SetOptions(merge: true));
      if (mounted) setState(() => _akisSonGuncelleme = now);
    } catch (_) {}
  }

  Future<void> _akisNotKaydetYeni(int sira, String not) async {
    if (!_duzenlemeYetkisiKontrolEt()) return;
    try {
      final baslik = _akisAdimBaslik(sira);
      await FirebaseFirestore.instance
          .collection('ruhsat')
          .doc(widget.projectId)
          .collection('akis_diyagrami')
          .doc(_akisDocId(sira))
          .set({
            'sira': sira,
            'stepId': _akisAdimId(sira),
            'flowVersion': _akisFlowVersion,
            'not': not,
            'madde': baslik,
            'titleSnapshot': baslik,
            'guncellendiTarihi': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
      if (mounted) {
        setState(() {
          if (not.isEmpty) {
            _akisNotlari.remove(sira);
          } else {
            _akisNotlari[sira] = not;
          }
        });
      }
      await _akisSonGuncellemeYenile();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Not kaydetme hatası: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _akisDurumDegistirYeni(int sira, int yeniDurum) async {
    if (!_duzenlemeYetkisiKontrolEt()) return;
    try {
      final isSonMadde = _isAkisSonMadde(sira);
      final baslik = _akisAdimBaslik(sira);
      await FirebaseFirestore.instance
          .collection('ruhsat')
          .doc(widget.projectId)
          .collection('akis_diyagrami')
          .doc(_akisDocId(sira))
          .set({
            'sira': sira,
            'stepId': _akisAdimId(sira),
            'flowVersion': _akisFlowVersion,
            'durum': yeniDurum,
            'madde': baslik,
            'titleSnapshot': baslik,
            'guncellendiTarihi': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
      if (mounted) setState(() => _akisDurumlari[sira] = yeniDurum);

      // Ruhsat Yazımı tamamlandıysa sayaç durur
      if (isSonMadde && yeniDurum == 2) {
        final now = DateTime.now();
        await FirebaseFirestore.instance
            .collection('ruhsat')
            .doc(widget.projectId)
            .collection('akis_diyagrami')
            .doc('_meta')
            .set({
              'flowVersion': _akisFlowVersion,
              'ruhsatTamamlandi': true,
              'tamamlanmaTarihi': Timestamp.fromDate(now),
            }, SetOptions(merge: true));
        if (mounted) {
          setState(() {
            _akisRuhsatTamamlandi = true;
            _akisTamamlanmaTarihi = now;
          });
        }
      } else if (isSonMadde && yeniDurum != 2 && _akisRuhsatTamamlandi) {
        // Tekrar devam ediyora döndüyse tamamlandı bayrağını kaldır
        await FirebaseFirestore.instance
            .collection('ruhsat')
            .doc(widget.projectId)
            .collection('akis_diyagrami')
            .doc('_meta')
            .set({
              'ruhsatTamamlandi': false,
              'tamamlanmaTarihi': null,
            }, SetOptions(merge: true));
        if (mounted) {
          setState(() {
            _akisRuhsatTamamlandi = false;
            _akisTamamlanmaTarihi = null;
          });
        }
        await _akisSonGuncellemeYenile();
      } else {
        await _akisSonGuncellemeYenile();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Durum güncelleme hatası: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _ruhsatVerileriniYukle() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('ruhsat')
          .doc(widget.projectId)
          .collection('islemler')
          .get();

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final sira = data['sira'] as int?;
        final durum = data['durum'] as int?;
        final not = data['not'] as String?;

        if (sira != null && mounted) {
          setState(() {
            if (durum != null) _ruhsatDurumlari[sira] = durum;
            if (not != null && not.isNotEmpty) _ruhsatNotlari[sira] = not;
          });
        }
      }
    } catch (e) {
      developer.log('Ruhsat verileri yükleme hatası: $e');
    }
  }

  void _belgeleriYukle() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('ruhsat')
          .doc(widget.projectId)
          .collection('belgeler')
          .get();

      final belgeler = <Map<String, String>>[];
      for (var doc in snapshot.docs) {
        final data = doc.data();
        belgeler.add({
          'başlık': data['başlık'] ?? '',
          'tarih': data['tarih'] ?? '',
          'firebaseUrl': data['firebaseUrl'] ?? data['firbaseUrl'] ?? '',
        });
      }

      if (mounted) {
        setState(() {
          _yuklenenBelgeler.clear();
          _yuklenenBelgeler.addAll(belgeler);
        });
      }
    } catch (e) {
      developer.log('Belgeler yükleme hatası: $e');
    }
  }

  void _santiyeVerileriniYukle() async {
    try {
      // Kat sayısını yükle
      final santiyeDoc = await FirebaseFirestore.instance
          .collection('santiye')
          .doc(widget.projectId)
          .get();

      if (santiyeDoc.exists) {
        final data = santiyeDoc.data();
        if (mounted && data != null) {
          setState(() {
            _santiyeKatSayisi = data['katSayisi'] ?? 0;
          });
        }
      }

      // İşlem durumlarını yükle
      final snapshot = await FirebaseFirestore.instance
          .collection('santiye')
          .doc(widget.projectId)
          .collection('islemler')
          .get();

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final sira = data['sira'] as int?;
        final durum = data['durum'] as int?;

        if (sira != null && durum != null && mounted) {
          setState(() {
            _santiyeDurumlari[sira] = durum;
          });
        }
      }

      // Fotoğrafları yükle
      final fotografSnapshot = await FirebaseFirestore.instance
          .collection('santiye')
          .doc(widget.projectId)
          .collection('fotograflar')
          .get();

      for (var doc in fotografSnapshot.docs) {
        final data = doc.data();
        final sira = data['sira'] as int?;
        final url = data['url'] as String?;
        final tarih = data['tarih'] as String?;
        final aciklama = data['aciklama'] as String?;

        if (sira != null && url != null && mounted) {
          if (!_santiyeFotograflar.containsKey(sira)) {
            _santiyeFotograflar[sira] = [];
          }
          setState(() {
            _santiyeFotograflar[sira]!.add({
              'url': url,
              'tarih': tarih ?? '',
              'id': doc.id,
              'aciklama': aciklama ?? '',
            });
          });
        }
      }
    } catch (e) {
      developer.log('Şantiye verileri yükleme hatası: $e');
    }
  }

  Future<void> _projeIsimDuzenle() async {
    if (!_duzenlemeYetkisiKontrolEt()) return;
    // Mevcut değerleri Firestore'dan oku
    String mevcutMalSahibi = '';
    String mevcutAdaParsel = '';
    String mevcutMuteahhit = '';
    try {
      final doc = await FirebaseFirestore.instance
          .collection('projects')
          .doc(widget.projectId)
          .get();
      final data = doc.data() ?? {};
      mevcutMalSahibi = (data['malSahibi'] ?? '').toString();
      mevcutAdaParsel = (data['adaParsel'] ?? '').toString();
      mevcutMuteahhit = (data['muteahhit'] ?? '').toString();
    } catch (_) {}

    if (!mounted) return;
    final malCtrl = TextEditingController(text: mevcutMalSahibi);
    final adaCtrl = TextEditingController(text: mevcutAdaParsel);
    final mutCtrl = TextEditingController(text: mevcutMuteahhit);
    final formKey = GlobalKey<FormState>();

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
        await _firebase.updateProject(widget.projectId, {
          'name': yeniIsim,
          'malSahibi': sonuc['malSahibi'],
          'adaParsel': sonuc['adaParsel'],
          'muteahhit': sonuc['muteahhit'],
        });
        if (!mounted) return;
        setState(() => _projeAdi = yeniIsim);
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

  @override
  void dispose() {
    _tabController.dispose();
    _akisNotEditController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text(_projeAdi.isNotEmpty ? _projeAdi : 'Proje Detayları'),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        elevation: 1,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Row(
            children: List.generate(3, (i) {
              final isSelected = _tabController.index == i;
              final labels = ['Muhasebe', 'Ruhsat', 'Şantiye'];
              final icons = [
                Icons.info_outline,
                Icons.description_outlined,
                Icons.construction_outlined,
              ];
              final activeColors = [
                Colors.blue.shade700,
                Colors.red.shade700,
                Colors.orange.shade800,
              ];
              return Expanded(
                child: GestureDetector(
                  onTap: () => _tabController.animateTo(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.white : Colors.transparent,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(10),
                        topRight: Radius.circular(10),
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          icons[i],
                          size: resp.isMobile(context) ? 18 : 20,
                          color: isSelected ? activeColors[i] : Colors.white70,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          labels[i],
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: isSelected
                                ? activeColors[i]
                                : Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
        actions: [
          if (SistemYoneticisi().isAdminKullanici)
            PopupMenuButton<String>(
              onSelected: (value) async {
                if (value == 'share') {
                  await _projePaylasimDialoguAc();
                } else if (value == 'rename') {
                  await _projeIsimDuzenle();
                } else if (value == 'archive') {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text(
                        'Projeyi Arşivle',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryColor,
                        ),
                      ),
                      content: const Text(
                        'Bu projeyi arşivlemek istediğinizden emin misiniz?',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('İptal'),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(context, true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryColor,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Arşivle'),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true && mounted) {
                    try {
                      await _firebase.archiveProject(widget.projectId);
                      if (!mounted) return;
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Proje arşivlendi')),
                      );
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(hataCevir(e)),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                } else if (value == 'delete') {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Projeyi Sil'),
                      content: const Text(
                        'Bu projeyi kalıcı olarak silmek istediğinizden emin misiniz?\n\nBu işlem geri alınamaz!',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('İptal'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.red,
                          ),
                          child: const Text('Sil'),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true && mounted) {
                    try {
                      await _firebase.deleteProject(widget.projectId);
                      if (!mounted) return;
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Proje silindi')),
                      );
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(hataCevir(e)),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                }
              },
              itemBuilder: (context) => [
                if ((SistemYoneticisi()
                        .aktifSirket
                        ?.planLimitleri
                        .projePaylasabilir ??
                    false))
                  const PopupMenuItem(
                    value: 'share',
                    child: Row(
                      children: [
                        Icon(Icons.share_outlined, color: Colors.teal),
                        SizedBox(width: 8),
                        Text('Paylasim Yetkileri'),
                      ],
                    ),
                  ),
                const PopupMenuItem(
                  value: 'rename',
                  child: Row(
                    children: [
                      Icon(Icons.edit_outlined, color: Colors.blue),
                      SizedBox(width: 8),
                      Text('İsim Düzenle'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'archive',
                  child: Row(
                    children: [
                      Icon(Icons.archive_outlined, color: Colors.orange),
                      SizedBox(width: 8),
                      Text('Arşivle'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Sil', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Muhasebe Tab
          _buildYetkiKontrolluTab('muhasebe', _buildMuhasebeTab()),
          // Ruhsat Tab
          _buildYetkiKontrolluTab('ruhsat', _buildRuhsatTab()),
          // Şantiye Tab
          _buildYetkiKontrolluTab('santiye', _buildSantiyeTab()),
        ],
      ),
    );
  }

  Widget _buildYetkiKontrolluTab(String modul, Widget content) {
    if (_paylasimYukleniyor) {
      return const Center(child: CircularProgressIndicator());
    }

    final yetkiVar = _modulYetkisiVarMi(modul);

    if (!yetkiVar) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline, size: 64, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              Text(
                "Bu sekmeyi görüntülemek için yetkiniz yok.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      );
    }

    return content;
  }

  Widget _buildMuhasebeTab() {
    return FutureBuilder<Project?>(
      future: _firebase.getProject(widget.projectId),
      builder: (context, projectSnap) {
        if (projectSnap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!projectSnap.hasData || projectSnap.data == null) {
          return const Center(child: Text('Proje bulunamadı'));
        }

        return SingleChildScrollView(
          child: Column(
            children: [
              // Ön Muhasebe Özeti
              FutureBuilder<ProjectFinance>(
                future: _firebase.getProjectFinanceSummary(widget.projectId),
                builder: (context, financeSnap) {
                  if (financeSnap.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(),
                    );
                  }

                  if (!financeSnap.hasData) {
                    return const SizedBox();
                  }

                  final finance = financeSnap.data!;

                  return Column(
                    children: [
                      Padding(
                        padding: EdgeInsets.all(
                          resp.responsivePadding(context),
                        ),
                        child: Column(
                          children: [
                            const Text(
                              'Ön Muhasebe Özeti',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: _FinanceCard(
                                    title: 'Gelir',
                                    amount: finance.totalIncome,
                                    color: Colors.green,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _FinanceCard(
                                    title: 'Gider',
                                    amount: finance.totalExpenses,
                                    color: Colors.red,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            _FinanceCard(
                              title: 'Kâr',
                              amount: finance.profit,
                              color: finance.profit >= 0
                                  ? Colors.blue
                                  : Colors.orange,
                            ),
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Kâr Marjı',
                                        style: TextStyle(
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                      Text(
                                        '${finance.profitMargin.toStringAsFixed(1)}%',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Bütçe Kullanımı',
                                        style: TextStyle(
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                      Text(
                                        '${finance.budgetUsage.toStringAsFixed(1)}%',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),

              // Cariler Başlığı ve Ekle Butonu
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Cariler',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _yeniCariDialog(context),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Cari Ekle'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Cariler Listesi
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('cari_hesaplar')
                    .where(
                      'sirketId',
                      isEqualTo: SistemYoneticisi().aktifSirket?.id ?? '',
                    )
                    .snapshots(),
                builder: (context, cariSnap) {
                  if (!cariSnap.hasData) {
                    return const SizedBox();
                  }

                  // Hem eski projectId hem yeni projectIds formatını destekle
                  final cariler = cariSnap.data!.docs.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final pids = List<String>.from(data['projectIds'] ?? []);
                    final pid = data['projectId'] ?? '';
                    return pids.contains(widget.projectId) ||
                        pid == widget.projectId;
                  }).toList();

                  if (cariler.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Center(
                        child: Text(
                          'Henüz cari hesap eklenmedi',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ),
                    );
                  }

                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 0),
                      itemCount: cariler.length,
                      itemBuilder: (context, index) {
                        final cariDoc = cariler[index];
                        final cariData = cariDoc.data() as Map<String, dynamic>;
                        final ad = cariData['ad'] ?? 'İsimsiz';
                        final tip = cariData['tip'] ?? 'musteri';
                        final ikon = tip == 'musteri'
                            ? Icons.person
                            : Icons.business;

                        return FutureBuilder<QuerySnapshot>(
                          future: FirebaseFirestore.instance
                              .collection('cari_hesaplar')
                              .doc(cariDoc.id)
                              .collection('hareketler')
                              .where('projeId', isEqualTo: widget.projectId)
                              .get(),
                          builder: (context, hareketSnap) {
                            double bakiye = 0;
                            if (hareketSnap.hasData) {
                              for (var h in hareketSnap.data!.docs) {
                                final hData = h.data() as Map<String, dynamic>;
                                final tutarTL =
                                    ((hData['tutarTL'] ?? hData['tutar'] ?? 0.0)
                                            as num)
                                        .toDouble();
                                final hTip = hData['tip'] ?? 'borc';
                                bakiye += hTip == 'alacak' ? tutarTL : -tutarTL;
                              }
                            }
                            final renk = bakiye > 0
                                ? Colors.green
                                : (bakiye < 0 ? Colors.red : Colors.grey);

                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: InkWell(
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (c) => CariDetayScreen(
                                      cariId: cariDoc.id,
                                      cariAd: ad,
                                      projectId: widget.projectId,
                                    ),
                                  ),
                                ),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: renk.withValues(
                                      alpha: (renk.a * 255.0 * 0.1).clamp(
                                        0,
                                        255,
                                      ),
                                    ),
                                    child: Icon(ikon, color: renk),
                                  ),
                                  title: Text(
                                    ad,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: Text(
                                    bakiye == 0
                                        ? 'Dengede'
                                        : (bakiye > 0 ? 'Alınan' : 'Ödenen'),
                                    style: TextStyle(color: renk, fontSize: 12),
                                  ),
                                  trailing: Text(
                                    format_utils.formatTL(bakiye.abs()),
                                    style: TextStyle(
                                      color: renk,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRuhsatTab() {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          TabBar(
            tabs: const [
              Tab(text: 'Akış Diyagramı'),
              Tab(text: 'Belgeler'),
            ],
            indicatorColor: AppTheme.primaryColor,
            labelColor: AppTheme.primaryColor,
            labelStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
            unselectedLabelStyle: const TextStyle(fontSize: 12),
          ),
          // Tab Content
          Expanded(
            child: TabBarView(
              children: [_buildAkisDiyagramiTab(), _buildBelgeYuklemeTab()],
            ),
          ),
        ],
      ),
    );
  }

  // ==================== AKIŞ DİYAGRAMI (AĞAÇ GÖRÜNÜMÜ) ====================

  Widget _buildAkisDiyagramiTab() {
    // Başlatılmamışsa: merkezi Başlat butonu
    if (!_akisBaslatildi) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [Colors.blue.shade400, Colors.blue.shade700],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blue.shade200.withValues(alpha: 0.6),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.rocket_launch_rounded,
                  size: 72,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Ruhsat Sürecini Başlat',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Başlat\'a basarak akış diyagramını aktifleştirin.\nGün sayacı bu andan itibaren başlar.',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              LayoutBuilder(
                builder: (context, constraints) {
                  final buttonWidth = constraints.maxWidth < 320
                      ? double.infinity
                      : 220.0;
                  return SizedBox(
                    width: buttonWidth,
                    child: ElevatedButton.icon(
                      onPressed: _akisBaslat,
                      icon: const Icon(Icons.play_arrow_rounded, size: 26),
                      label: const Text(
                        'BAŞLAT',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade600,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 4,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      );
    }

    // Sayaç hesapla
    final now = DateTime.now();
    final baslatmaGun = _akisBaslatmaTarihi != null
        ? now.difference(_akisBaslatmaTarihi!).inDays
        : 0;
    final sonGuncellemeGun = _akisSonGuncelleme != null
        ? now.difference(_akisSonGuncelleme!).inDays
        : baslatmaGun;
    final sayacDurdu = _akisRuhsatTamamlandi;
    final sayacGun = sayacDurdu
        ? (_akisTamamlanmaTarihi != null && _akisBaslatmaTarihi != null
              ? _akisTamamlanmaTarihi!.difference(_akisBaslatmaTarihi!).inDays
              : baslatmaGun)
        : sonGuncellemeGun;

    final tamamlanan = _akisDurumlari.values.where((d) => d == 2).length;
    final toplam = _aktifAkisFlow.steps.length;
    final yuzde = toplam > 0 ? tamamlanan / toplam : 0.0;

    Color sayacRenk;
    if (sayacDurdu) {
      sayacRenk = Colors.green;
    } else if (sayacGun >= 14) {
      sayacRenk = Colors.red;
    } else if (sayacGun >= 7) {
      sayacRenk = Colors.orange;
    } else if (sayacGun >= 2) {
      sayacRenk = Colors.amber.shade700;
    } else {
      sayacRenk = Colors.blue;
    }

    return Column(
      children: [
        // ── Üst durum kartı ──
        Container(
          margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: sayacDurdu
                  ? [Colors.green.shade50, Colors.green.shade100]
                  : [Colors.white, sayacRenk.withValues(alpha: 0.08)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: sayacRenk.withValues(alpha: 0.3)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: sayacRenk.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      sayacDurdu
                          ? Icons.verified_rounded
                          : Icons.timer_outlined,
                      color: sayacRenk,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          sayacDurdu
                              ? 'Ruhsat Tamamlandı'
                              : (sayacGun == 0
                                    ? 'Bugün işlem yapıldı'
                                    : '$sayacGun gün önce işlem yapıldı'),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: sayacRenk.withValues(alpha: 0.95),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          sayacDurdu
                              ? 'Sayaç durduruldu — süreç $sayacGun günde tamamlandı'
                              : 'Başlangıç: ${_tarihBicim(_akisBaslatmaTarihi)} • Toplam $baslatmaGun gün',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$tamamlanan/$toplam',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: yuzde,
                  minHeight: 6,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    sayacDurdu ? Colors.green : Colors.blue.shade500,
                  ),
                ),
              ),
            ],
          ),
        ),

        // ── Ana içerik: Sol not paneli + sağ adım listesi ──
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 720;
              if (isWide) {
                final notPanel = _buildAkisNotPanel();
                final adimListesi = _buildAkisAdimListesi(isMobile: false);
                return Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 5, child: notPanel),
                      const SizedBox(width: 12),
                      Expanded(flex: 4, child: adimListesi),
                    ],
                  ),
                );
              }
              // Mobilde: yalnız liste; bir adıma tıklanınca alt sayfa (bottom sheet) açılır
              return Padding(
                padding: const EdgeInsets.all(8),
                child: _buildAkisAdimListesi(isMobile: true),
              );
            },
          ),
        ),
      ],
    );
  }

  String _tarihBicim(DateTime? d) {
    if (d == null) return '-';
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  }

  void _akisNotBottomSheetAc() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocalState) {
            final viewInsets = MediaQuery.of(ctx).viewInsets.bottom;
            return Padding(
              padding: EdgeInsets.only(bottom: viewInsets),
              child: DraggableScrollableSheet(
                expand: false,
                initialChildSize: 0.75,
                minChildSize: 0.4,
                maxChildSize: 0.95,
                builder: (ctx, scrollCtrl) {
                  return Container(
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(20),
                      ),
                    ),
                    child: Column(
                      children: [
                        Container(
                          margin: const EdgeInsets.only(top: 8, bottom: 4),
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade400,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        Expanded(
                          child: SingleChildScrollView(
                            controller: scrollCtrl,
                            padding: const EdgeInsets.all(12),
                            child: _buildAkisNotPanel(),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildAkisNotPanel() {
    final sira = _akisSecilenSira;
    final baslik = _akisAdimBaslik(sira);
    final mevcutNot = _akisNotlari[sira] ?? '';
    final durum = _akisDurumlari[sira] ?? 0;
    // Her seçimde controller'ı güncelle (tek seferlik uyum için setState'den ayrı tutuyoruz)
    if (_akisNotEditController.text != mevcutNot &&
        !_akisNotEditController.selection.isValid) {
      _akisNotEditController.text = mevcutNot;
    }
    Color durumRenk = durum == 2
        ? Colors.green
        : (durum == 1 ? Colors.orange : Colors.blueGrey.shade400);
    String durumText = durum == 2
        ? 'Tamamlandı'
        : (durum == 1 ? 'Devam Ediyor' : 'Başlamadı');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: durumRenk.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  '$sira',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: durumRenk,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  baslik,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: durumRenk.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  durumText,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: durumRenk,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Durum seçimi
          Row(
            children: [
              _akisDurumButton(
                0,
                'Başlamadı',
                Colors.blueGrey.shade400,
                sira,
                durum,
              ),
              const SizedBox(width: 6),
              _akisDurumButton(
                1,
                'Devam Ediyor',
                Colors.orange.shade600,
                sira,
                durum,
              ),
              const SizedBox(width: 6),
              _akisDurumButton(
                2,
                'Tamamlandı',
                Colors.green.shade600,
                sira,
                durum,
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Notlar',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: TextField(
              controller: _akisNotEditController,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              decoration: InputDecoration(
                hintText: 'Bu adıma ait notları yazın...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                contentPadding: const EdgeInsets.all(10),
                filled: true,
                fillColor: Colors.grey.shade50,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: () {
                  _akisNotEditController.text = mevcutNot;
                  setState(() {});
                },
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Geri Al', style: TextStyle(fontSize: 12)),
              ),
              const SizedBox(width: 6),
              ElevatedButton.icon(
                onPressed: () {
                  _akisNotKaydetYeni(sira, _akisNotEditController.text.trim());
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Not kaydedildi, sayaç sıfırlandı'),
                      backgroundColor: Colors.green,
                      duration: Duration(seconds: 2),
                    ),
                  );
                  if (Navigator.of(context).canPop() &&
                      ModalRoute.of(context)?.isCurrent != true) {
                    Navigator.of(context).pop();
                  }
                },
                icon: const Icon(Icons.save_outlined, size: 16),
                label: const Text('Kaydet'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _akisDurumButton(
    int durumDegeri,
    String label,
    Color color,
    int sira,
    int aktifDurum,
  ) {
    final secili = aktifDurum == durumDegeri;
    return Expanded(
      child: InkWell(
        onTap: () {
          _akisDurumDegistirYeni(sira, durumDegeri);
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: secili ? color : color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: color.withValues(alpha: secili ? 1 : 0.3),
            ),
          ),
          child: Center(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: secili ? Colors.white : color,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAkisAdimListesi({bool isMobile = false}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                Icon(
                  Icons.list_alt_rounded,
                  size: 18,
                  color: Colors.grey.shade700,
                ),
                const SizedBox(width: 6),
                const Text(
                  'Adımlar',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: _aktifAkisFlow.steps.length,
              separatorBuilder: (context, _) =>
                  Divider(height: 1, indent: 54, color: Colors.grey.shade100),
              itemBuilder: (c, i) {
                final step = _aktifAkisFlow.steps[i];
                final sira = step.sira;
                final ad = step.title;
                final durum = _akisDurumlari[sira] ?? 0;
                final not = _akisNotlari[sira] ?? '';
                final secili = _akisSecilenSira == sira;
                Color circleColor;
                IconData? circleIcon;
                if (durum == 2) {
                  circleColor = Colors.green;
                  circleIcon = Icons.check;
                } else if (durum == 1) {
                  circleColor = Colors.orange;
                  circleIcon = null;
                } else {
                  circleColor = Colors.blueGrey.shade300;
                  circleIcon = null;
                }
                final isSonMadde = step.id == _aktifAkisFlow.lastStep.id;
                return Material(
                  color: secili ? Colors.blue.shade50 : Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _akisSecilenSira = sira;
                        _akisNotEditController.text = _akisNotlari[sira] ?? '';
                        _akisNotEditController.selection =
                            TextSelection.collapsed(
                              offset: _akisNotEditController.text.length,
                            );
                      });
                      if (isMobile) {
                        _akisNotBottomSheetAc();
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: circleColor,
                              shape: BoxShape.circle,
                              boxShadow: secili
                                  ? [
                                      BoxShadow(
                                        color: circleColor.withValues(
                                          alpha: 0.45,
                                        ),
                                        blurRadius: 8,
                                        spreadRadius: 1,
                                      ),
                                    ]
                                  : null,
                            ),
                            alignment: Alignment.center,
                            child: circleIcon != null
                                ? Icon(
                                    circleIcon,
                                    size: 16,
                                    color: Colors.white,
                                  )
                                : Text(
                                    '$sira',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                    ),
                                  ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        ad,
                                        style: TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: secili
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                          color: durum == 2
                                              ? Colors.grey.shade600
                                              : Colors.black87,
                                          decoration: durum == 2
                                              ? TextDecoration.lineThrough
                                              : null,
                                        ),
                                      ),
                                    ),
                                    if (isSonMadde)
                                      Container(
                                        margin: const EdgeInsets.only(left: 6),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.purple.shade50,
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        child: Text(
                                          'SON',
                                          style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.purple.shade700,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                if (not.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    not,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade600,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (not.isNotEmpty)
                            Icon(
                              Icons.sticky_note_2_outlined,
                              size: 14,
                              color: Colors.amber.shade700,
                            ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.chevron_right,
                            size: 18,
                            color: Colors.grey.shade400,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Lejant Noktası ──

  // ── Satır İçi Durum Seçici ──

  // ── Bağımlılık Uyarısı ──

  // ── Satır İçi Not Alanı ──

  Widget _buildBelgeYuklemeTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton.icon(
            onPressed: () {
              _tumBelgeleriYukle();
            },
            icon: const Icon(Icons.upload_file),
            label: const Text('Belge Yükle'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
            ),
          ),
        ),
        if (_yuklenenBelgeler.isEmpty)
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.file_upload_outlined,
                    size: 64,
                    color: Colors.grey.shade300,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Henüz belge yüklenmedi',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Belgeler bölümünde görüntülenmek için\nyukarıdaki butona tıklayarak belge yükleyin',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          )
        else
          Expanded(
            child: Builder(
              builder: (context) {
                final filtrelenmis = <MapEntry<int, Map<String, String>>>[];
                for (int i = 0; i < _yuklenenBelgeler.length; i++) {
                  final belge = _yuklenenBelgeler[i];
                  if (_belgeArama.isEmpty ||
                      (belge['başlık']?.toLowerCase().contains(_belgeArama) ??
                          false) ||
                      (belge['tarih']?.toLowerCase().contains(_belgeArama) ??
                          false)) {
                    filtrelenmis.add(MapEntry(i, belge));
                  }
                }
                if (filtrelenmis.isEmpty && _belgeArama.isNotEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.search_off,
                          size: 48,
                          color: Colors.grey.shade300,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '"$_belgeArama" için belge bulunamadı',
                          style: TextStyle(color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: filtrelenmis.length,
                  itemBuilder: (context, index) {
                    final entry = filtrelenmis[index];
                    return _buildBelgeKarti(entry.value, entry.key);
                  },
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildBelgeKarti(Map<String, String> belge, int index) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.file_present,
                  size: 32,
                  color: AppTheme.primaryColor,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        belge['başlık'] ?? 'Belge',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        belge['tarih'] ?? '',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildBelgeIslemButonu(
                  Icons.preview,
                  'Önizle',
                  AppTheme.primaryColor,
                  () {
                    _belgeOnizle(belge);
                  },
                ),
                _buildBelgeIslemButonu(
                  Icons.download,
                  'İndir',
                  Colors.green.shade700,
                  () {
                    _belgeIndir(belge);
                  },
                ),
                _buildBelgeIslemButonu(
                  Icons.delete,
                  'Sil',
                  Colors.red.shade700,
                  () {
                    _belgeySil(index);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBelgeIslemButonu(
    IconData icon,
    String label,
    Color color,
    VoidCallback onPressed,
  ) {
    return InkWell(
      onTap: onPressed,
      child: Column(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  void _tumBelgeleriYukle() async {
    try {
      // Dosya seç
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
        withData: true,
      );

      if (result == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Dosya seçimi iptal edildi')),
        );
        return;
      }

      final file = result.files.single;

      if (file.bytes == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Dosya okunamadı. Lütfen tekrar deneyin.'),
          ),
        );
        return;
      }

      // Yükleniyor göstergesi
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Belge yükleniyor...'),
          duration: const Duration(seconds: 30),
        ),
      );

      // Firebase Storage'a yükle
      final fileName = file.name;
      final fileExtension = fileName.split('.').last;
      final uniqueFileName =
          '${DateTime.now().millisecondsSinceEpoch}_$fileName';

      final storageRef = FirebaseStorage.instance
          .ref()
          .child('ruhsat_belgeler')
          .child(widget.projectId)
          .child(uniqueFileName);

      // Dosyayı yükle
      final contentType = _mimeTypeFromExtension(fileExtension);
      final downloadUrl = await uploadToStorage(
        storageRef,
        file.bytes!,
        SettableMetadata(contentType: contentType),
      );

      // Firestore'a kaydet
      final yeniBelge = {
        'başlık': fileName,
        'tarih': DateTime.now().toString().split(' ')[0],
        'type': fileExtension,
        'firebaseUrl': downloadUrl,
        // Geriye uyumluluk için bir süre daha eski alanı da yazıyoruz.
        'firbaseUrl': downloadUrl,
        'boyut': file.size,
        'yuklenmeTarihi': DateTime.now(),
      };

      // Local state'e ekle
      setState(() {
        _yuklenenBelgeler.add({
          'başlık': yeniBelge['başlık'] as String,
          'tarih': yeniBelge['tarih'] as String,
          'firebaseUrl': yeniBelge['firebaseUrl'] as String,
        });
      });

      // Firestore'a kaydet
      await FirebaseFirestore.instance
          .collection('ruhsat')
          .doc(widget.projectId)
          .collection('belgeler')
          .add(yeniBelge);

      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Belge "$fileName" başarıyla yüklenmiştir'),
          backgroundColor: Colors.green.shade700,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(hataCevir(e)),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  void _belgeySil(int index) async {
    try {
      final belge = _yuklenenBelgeler[index];

      // Local state'ten sil
      setState(() {
        _yuklenenBelgeler.removeAt(index);
      });

      // Firestore'dan sil (başlık eşleşen ilk belgeyi sil)
      final ruhsatDoc = await FirebaseFirestore.instance
          .collection('ruhsat')
          .doc(widget.projectId)
          .collection('belgeler')
          .where('başlık', isEqualTo: belge['başlık'])
          .limit(1)
          .get();

      if (ruhsatDoc.docs.isNotEmpty) {
        await ruhsatDoc.docs.first.reference.delete();
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Belge başarıyla silindi'),
          backgroundColor: Colors.green.shade700,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(hataCevir(e)),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  void _belgeOnizle(Map<String, String> belge) async {
    try {
      final url = belge['firebaseUrl'];
      final dosyaAdi = belge['başlık'] ?? '';

      if (url == null || url.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Belge URL bulunamadı'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // Dosya türünü belirle
      final dosyaTipi = dosyaAdi.toLowerCase();
      final isPdf = dosyaTipi.endsWith('.pdf');
      final isImage =
          dosyaTipi.endsWith('.jpg') ||
          dosyaTipi.endsWith('.jpeg') ||
          dosyaTipi.endsWith('.png') ||
          dosyaTipi.endsWith('.gif');

      // Dialog ile önizleme göster
      showDialog(
        context: context,
        builder: (context) => Dialog(
          child: SizedBox(
            width: resp.dialogWidth(context),
            height: resp.dialogHeight(context),
            child: Column(
              children: [
                // Başlık ve Kapat butonu
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(4),
                      topRight: Radius.circular(4),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          dosyaAdi,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            overflow: TextOverflow.ellipsis,
                          ),
                          maxLines: 1,
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: () {
                          _belgeIndir(belge);
                        },
                        icon: const Icon(Icons.download, size: 18),
                        label: const Text('İndir'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            vertical: 8,
                            horizontal: 12,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                // Önizleme alanı
                Expanded(
                  child: Container(
                    color: Colors.grey.shade100,
                    child: (isPdf || isImage)
                        ? _buildPreviewFromUrl(
                            url: url,
                            isPdf: isPdf,
                            isImage: isImage,
                          )
                        : _buildPreviewUnsupported(),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(hataCevir(e)),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  Widget _buildPreviewFromUrl({
    required String url,
    required bool isPdf,
    required bool isImage,
  }) {
    try {
      if (isPdf) {
        if (kIsWeb) {
          // Web'de tarayıcının kendi PDF görüntüleyicisi en stabil davranışı veriyor.
          return web_utils.buildWebPreviewFromUrl(
            url: url,
            isPdf: true,
            fileName: 'preview.pdf',
          );
        }
        return SfPdfViewer.network(url);
      }

      if (isImage) {
        return InteractiveViewer(
          child: Image.network(
            url,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) =>
                _buildPreviewError(message: 'Gorsel onizlenemedi'),
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return const Center(child: CircularProgressIndicator());
            },
          ),
        );
      }

      return _buildPreviewUnsupported();
    } catch (e) {
      developer.log('_buildPreviewFromUrl hatasi: $e');
      return _buildPreviewError(message: e.toString());
    }
  }

  Widget _buildPreviewError({String? message}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 56, color: Colors.red.shade400),
            const SizedBox(height: 12),
            Text(
              'Önizleme yüklenemedi',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.red.shade400,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            if (message != null && message.isNotEmpty)
              Text(
                message,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                textAlign: TextAlign.center,
              ),
            const SizedBox(height: 6),
            Text(
              'Lütfen indirme butonunu kullanın.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewUnsupported() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.file_present, size: 64, color: AppTheme.primaryColor),
            const SizedBox(height: 16),
            Text(
              'Bu dosya türü için önizleme yok',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppTheme.primaryColor,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'İndirme butonu ile dosyayı açabilirsiniz.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  void _belgeIndir(Map<String, String> belge) async {
    try {
      final url = belge['firebaseUrl'];
      if (url == null || url.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Belge URL bulunamadı'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final baslik = belge['başlık'] ?? 'belge';
      // Başlıkta uzantı yoksa URL'den (path veya content-type) çıkarmaya çalış
      String fileName = baslik;
      if (!RegExp(r'\.[A-Za-z0-9]{1,5}$').hasMatch(baslik)) {
        final lowerUrl = url.toLowerCase();
        String ext = '';
        if (lowerUrl.contains('.pdf')) {
          ext = '.pdf';
        } else if (lowerUrl.contains('.png')) {
          ext = '.png';
        } else if (lowerUrl.contains('.jpeg')) {
          ext = '.jpeg';
        } else if (lowerUrl.contains('.jpg')) {
          ext = '.jpg';
        } else if (lowerUrl.contains('.webp')) {
          ext = '.webp';
        }
        fileName = '$baslik$ext';
      }
      if (kIsWeb) {
        await web_utils.downloadFile(url, fileName);
      } else {
        // iOS/Android: önce harici uygulamada açmayı dene, olmazsa varsayılan moda düş.
        final uri = Uri.parse(url);
        final launchedExternal = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        if (!launchedExternal) {
          final launchedDefault = await launchUrl(uri);
          if (!launchedDefault) {
            throw Exception('Dosya acilamadi');
          }
        }
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            kIsWeb ? '$fileName indiriliyor...' : '$fileName aciliyor...',
          ),
          backgroundColor: Colors.green.shade700,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(hataCevir(e)),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  Widget _buildSantiyeTab() {
    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.all(resp.responsivePadding(context)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Kat sayısı seçimi
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Zemin Üstü Kat Sayısı',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _santiyeKatSayisi > 0
                                ? '$_santiyeKatSayisi kat'
                                : 'Henüz belirlenmedi',
                            style: TextStyle(
                              fontSize: 14,
                              color: _santiyeKatSayisi > 0
                                  ? Colors.green.shade700
                                  : Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: _katSayisiDialog,
                      icon: Icon(
                        _santiyeKatSayisi > 0 ? Icons.edit : Icons.add,
                      ),
                      label: Text(
                        _santiyeKatSayisi > 0 ? 'Değiştir' : 'Belirle',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade700,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // İşlemler listesi
            if (_santiyeKatSayisi > 0) ...[
              const Text(
                'Yapım Aşamaları',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              ..._getSantiyeIslemleri().asMap().entries.map((entry) {
                final sira = entry.key + 1;
                final islem = entry.value;
                return _buildSantiyeKanbanCard(sira, islem);
              }),
            ] else
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    children: [
                      Icon(
                        Icons.construction,
                        size: 64,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Başlamak için kat sayısını belirleyin',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<String> _getSantiyeIslemleri() {
    final islemler = <String>[
      'Hafriyat yapılacak alanın işaretlenmesi',
      'Hafriyat',
      'Hafriyat zeminine düşük dansiteli beton',
      'Temel atılması için kalıp, demir bağlantıları',
      'Hazır beton ile temel atılması',
      'Perde duvarlı bodrum kat (varsa) kalıp, demir ve su basmanı katı döşeme kalıp ve demir işlemleri',
      'Su basmanı betonu',
      'Zemin kat kalıp, demir işlemleri',
      'Hazır betonla Zemin kat betonu',
    ];

    // Kat sayısına göre dinamik maddeler ekle
    for (int i = 1; i <= _santiyeKatSayisi; i++) {
      islemler.add('$i. kat kalıp ve demir işleri');
      islemler.add('$i. kat beton dökülmesi');
    }

    // Kalan maddeler
    islemler.addAll([
      'Bodrum katın toprakla örtülecek kısmının su izolasyonunun yapılması',
      'Çatı katı ve çatının beton yada taşıyıcı tuğla ile taşıyıcı sisteminin yapılması',
      'Çatının kiremit altı ahşap kurulumundan önce oturacağı yüzeye demir ve betonla hatıl yapılması',
      'Kaliteli kereste ile 10×10 ve 5×10 kereste ile çatı kurulumu üzerine kiremit altı döşeme tahtalarının çakılması',
      'Çatıda Su izolasyonu',
      'Çatıda Isı izolasyonu',
      'Kiremit çıtalarının ısı izolasyonu levhaları üzerine çakılması',
      'Kiremit döşenmesi',
      'Çinko olukların ve yağmur inişlerinin hazırlanması',
      'Binada dış ve iç duvarların tuğla ile örülmesi',
      'İskele kurulması',
      'Dış sıvaya başlanması',
      'İç sıvaya başlanması',
      'İçeride su, elektrik, kalorifer, telefon, televizyon, sıhhi tesisata başlanması',
      'İç duvarlarda ve tavanlarda İnce sıva ve kaba alçıya başlanması',
      'Dışarıda duvarlara dıştan izolasyona başlanması',
      'Pencerelere antipas sürülmüş profil demirden kör kasaların takılması',
      'Dış Kapının ve Pencerelerin takılması',
      'Dış cephe boyası, yağmur boruları inişleri yapılması ve iskelenin sökülmesi',
      'İçeride tüm tesisatın kontrolunü takiben şap yapılmaya başlanması',
      'Seramik kaplanacak banyo, tuvalet ve diğer yerlerin yapılması',
      'İçeride ince alçı ve boyaya başlanması',
      'Korkulukların montajı',
      'Elektrik priz ve anahtarlarının montajı',
      'Kombi ve radyatörlerin montajı, testi',
      'Banyo ve tuvaletler vitrifiye ve bataryalar montajı',
      'Yer döşemesi, merdiven basamakları döşemesi',
      'İç kapıların montajı',
      'Balkon yer döşemeleri',
      'Mutfak kurulumu',
      'Dolapların montajı',
      'Çevre düzenlemesi',
      'İnşaat temizliği',
    ]);

    return islemler;
  }

  Widget _buildSantiyeKanbanCard(int sira, String islem) {
    final durum = _santiyeDurumlari[sira] ?? 0;
    final fotograflar = _santiyeFotograflar[sira] ?? [];

    Color bgColor;
    String durumText;
    IconData icon;

    switch (durum) {
      case 0:
        bgColor = Colors.grey.shade300;
        durumText = 'Başlamadı';
        icon = Icons.radio_button_unchecked;
        break;
      case 1:
        bgColor = Colors.yellow.shade300;
        durumText = 'Devam Ediyor';
        icon = Icons.access_time;
        break;
      case 2:
        bgColor = Colors.green.shade300;
        durumText = 'Tamamlandı';
        icon = Icons.check_circle;
        break;
      default:
        bgColor = Colors.grey.shade300;
        durumText = 'Başlamadı';
        icon = Icons.radio_button_unchecked;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          InkWell(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(12),
              topRight: Radius.circular(12),
            ),
            onTap: () => _santiyeDurumSecDialog(sira, islem),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 4,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        '$sira',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                          color: AppTheme.primaryColor,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          islem,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(icon, size: 16, color: Colors.white),
                            const SizedBox(width: 6),
                            Text(
                              durumText,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w500,
                                  ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                ],
              ),
            ),
          ),
          // Fotoğraf bölümü
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(12),
                bottomRight: Radius.circular(12),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.photo_library,
                      size: 18,
                      color: Colors.grey,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Fotoğraflar (${fotograflar.length})',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey,
                      ),
                    ),
                    const Spacer(),
                    ElevatedButton.icon(
                      onPressed: () => _santiyeFotografYukle(sira),
                      icon: const Icon(Icons.add_a_photo, size: 16),
                      label: const Text('Ekle'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade600,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ),
                if (fotograflar.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 120,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: fotograflar.length,
                      itemBuilder: (context, index) {
                        final foto = fotograflar[index];
                        final aciklama = foto['aciklama'] ?? '';
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: GestureDetector(
                            onTap: () =>
                                _santiyeFotografOnizle(fotograflar, index),
                            child: Stack(
                              children: [
                                Column(
                                  children: [
                                    Container(
                                      width: 80,
                                      height: 80,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(8),
                                        image: DecorationImage(
                                          image: NetworkImage(foto['url']!),
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                    ),
                                    if (aciklama.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      SizedBox(
                                        width: 80,
                                        child: Text(
                                          aciklama,
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.grey.shade700,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                Positioned(
                                  top: 2,
                                  right: 2,
                                  child: GestureDetector(
                                    onTap: () => _santiyeFotografSil(
                                      sira,
                                      foto['id']!,
                                      foto['url']!,
                                    ),
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: Colors.red.shade700,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.close,
                                        size: 14,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _katSayisiDialog() async {
    if (!_duzenlemeYetkisiKontrolEt()) return;
    final ctrl = TextEditingController(
      text: _santiyeKatSayisi > 0 ? '$_santiyeKatSayisi' : '',
    );

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Zemin Üstü Kat Sayısı'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Kat Sayısı',
            hintText: 'Örn: 2',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () async {
              final katSayisi = int.tryParse(ctrl.text) ?? 0;
              if (katSayisi <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Lütfen geçerli bir sayı girin'),
                  ),
                );
                return;
              }

              // Firestore'a kaydet
              await FirebaseFirestore.instance
                  .collection('santiye')
                  .doc(widget.projectId)
                  .set({'katSayisi': katSayisi}, SetOptions(merge: true));

              setState(() {
                _santiyeKatSayisi = katSayisi;
              });

              Navigator.pop(ctx);
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
  }

  Future<void> _santiyeDurumSecDialog(int sira, String islem) async {
    if (!_duzenlemeYetkisiKontrolEt()) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$sira. $islem'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildSantiyeStatusOption(
              ctx,
              sira,
              0,
              'Başlamadı',
              Colors.grey.shade300,
              Icons.radio_button_unchecked,
            ),
            const SizedBox(height: 8),
            _buildSantiyeStatusOption(
              ctx,
              sira,
              1,
              'Devam Ediyor',
              Colors.yellow.shade300,
              Icons.access_time,
            ),
            const SizedBox(height: 8),
            _buildSantiyeStatusOption(
              ctx,
              sira,
              2,
              'Tamamlandı',
              Colors.green.shade300,
              Icons.check_circle,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSantiyeStatusOption(
    BuildContext ctx,
    int sira,
    int durum,
    String label,
    Color color,
    IconData icon,
  ) {
    final isSelected = (_santiyeDurumlari[sira] ?? 0) == durum;

    return InkWell(
      onTap: () async {
        // Firestore'a kaydet
        await FirebaseFirestore.instance
            .collection('santiye')
            .doc(widget.projectId)
            .collection('islemler')
            .doc('madde_$sira')
            .set({'sira': sira, 'durum': durum}, SetOptions(merge: true));

        setState(() {
          _santiyeDurumlari[sira] = durum;
        });

        // Proje adını al ve bildirim gönder
        final projeDoc = await FirebaseFirestore.instance
            .collection('projects')
            .doc(widget.projectId)
            .get();
        final projeAdi = projeDoc.data()?['name'] ?? 'Proje';

        // İşlem adını al
        final islemler = _getSantiyeIslemleri();
        final islemAdi = sira <= islemler.length
            ? islemler[sira - 1]
            : 'İşlem $sira';

        await BildirimServisi.bildirimGonder(
          baslik: 'Şantiye Durumu Güncellendi',
          mesaj: '$projeAdi - $islemAdi: $label',
          projeId: widget.projectId,
          modul: 'santiye',
        );

        developer.log('✅ Bildirim gönderildi: $projeAdi - $islemAdi: $label');

        Navigator.pop(ctx);
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
          border: isSelected ? Border.all(color: Colors.blue, width: 3) : null,
        ),
        child: Row(
          children: [
            Icon(icon, size: 24),
            const SizedBox(width: 12),
            Text(
              label,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _santiyeFotografYukle(int sira) async {
    if (!_duzenlemeYetkisiKontrolEt()) return;
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: true,
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      // Her fotoğraf için açıklama girme dialogu
      final fotografBilgileri = <Map<String, dynamic>>[];

      for (final file in result.files) {
        if (file.bytes == null) {
          developer.log('Fotograf okunamadi: ${file.name}');
          continue;
        }

        final aciklamaCtrl = TextEditingController();
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('Fotoğraf Açıklaması'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: 150,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(file.bytes!, fit: BoxFit.cover),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: aciklamaCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Açıklama (isteğe bağlı)',
                    hintText: 'Örn: Zemin kat kalıp işlemi başlandı',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Atla'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Devam'),
              ),
            ],
          ),
        );

        if (confirmed == false) continue;

        fotografBilgileri.add({'file': file, 'aciklama': aciklamaCtrl.text});
      }

      if (fotografBilgileri.isEmpty) return;

      // Yükleniyor göstergesi
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Text('${fotografBilgileri.length} fotoğraf yükleniyor...'),
              ],
            ),
            duration: const Duration(seconds: 60),
            backgroundColor: Colors.blue.shade700,
          ),
        );
      }

      // Fotoğrafları yükle
      for (final fotoBilgi in fotografBilgileri) {
        final file = fotoBilgi['file'] as PlatformFile;
        final aciklama = fotoBilgi['aciklama'] as String;

        // Firebase Storage'a yükle
        final fileName =
            '${DateTime.now().millisecondsSinceEpoch}_${file.name}';
        final storageRef = FirebaseStorage.instance.ref().child(
          'santiye_fotograflar/${widget.projectId}/$fileName',
        );

        final ext = file.name.split('.').last.toLowerCase();
        final contentType = (ext == 'png') ? 'image/png' : 'image/jpeg';
        final downloadUrl = await uploadToStorage(
          storageRef,
          file.bytes!,
          SettableMetadata(contentType: contentType),
        );

        // Firestore'a kaydet
        final docRef = await FirebaseFirestore.instance
            .collection('santiye')
            .doc(widget.projectId)
            .collection('fotograflar')
            .add({
              'sira': sira,
              'url': downloadUrl,
              'tarih': DateTime.now().toIso8601String(),
              'aciklama': aciklama,
            });

        // State'e ekle
        if (!_santiyeFotograflar.containsKey(sira)) {
          _santiyeFotograflar[sira] = [];
        }

        setState(() {
          _santiyeFotograflar[sira]!.add({
            'url': downloadUrl,
            'tarih': DateTime.now().toIso8601String(),
            'id': docRef.id,
            'aciklama': aciklama,
          });
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${fotografBilgileri.length} fotoğraf yüklendi'),
            backgroundColor: Colors.green.shade700,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(hataCevir(e)),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  Future<void> _santiyeFotografSil(int sira, String docId, String url) async {
    if (!_duzenlemeYetkisiKontrolEt()) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Fotoğraf Sil'),
        content: const Text('Bu fotoğrafı silmek istediğinize emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Sil'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      // Firestore'dan sil
      await FirebaseFirestore.instance
          .collection('santiye')
          .doc(widget.projectId)
          .collection('fotograflar')
          .doc(docId)
          .delete();

      // Firebase Storage'dan sil
      try {
        final ref = FirebaseStorage.instance.refFromURL(url);
        await ref.delete();
      } catch (e) {
        developer.log('Storage silme hatası: $e');
      }

      // State'den sil
      setState(() {
        _santiyeFotograflar[sira]?.removeWhere((f) => f['id'] == docId);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Fotoğraf silindi'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(hataCevir(e)), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _santiyeFotografOnizle(
    List<Map<String, String>> fotograflar,
    int baslangicIndex,
  ) async {
    await showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            PageView.builder(
              controller: PageController(initialPage: baslangicIndex),
              itemCount: fotograflar.length,
              itemBuilder: (context, index) {
                final foto = fotograflar[index];
                final aciklama = foto['aciklama'] ?? '';
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(
                      child: InteractiveViewer(
                        child: Image.network(
                          foto['url']!,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) {
                            return const Center(
                              child: Icon(
                                Icons.error,
                                color: Colors.white,
                                size: 64,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          if (aciklama.isNotEmpty) ...[
                            Text(
                              aciklama,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                          ],
                          if (foto['tarih']!.isNotEmpty)
                            Text(
                              DateTime.parse(
                                foto['tarih']!,
                              ).toString().substring(0, 16),
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
            Positioned(
              top: 16,
              right: 16,
              child: IconButton(
                onPressed: () => Navigator.pop(ctx),
                icon: const Icon(Icons.close, color: Colors.white, size: 32),
                style: IconButton.styleFrom(backgroundColor: Colors.black54),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _yeniCariDialog(BuildContext context) async {
    if (!_duzenlemeYetkisiKontrolEt()) return;
    if (!mounted) return;

    // İlk dialog: Var olan cari seç veya yeni oluştur
    final secim = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cari Hesap Ekle'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('İptal'),
          ),
        ],
        actionsAlignment: MainAxisAlignment.start,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Var olan bir cari hesabı bu projeye atayabilir veya yeni bir cari hesap oluşturabilirsiniz.',
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(ctx, 'mevcut'),
              icon: const Icon(Icons.search),
              label: const Text('Var Olandan Seç'),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(ctx, 'yeni'),
              icon: const Icon(Icons.add),
              label: const Text('Yeni Oluştur'),
            ),
          ],
        ),
      ),
    );

    if (secim == null || !mounted) return;

    if (secim == 'mevcut') {
      await _mevcutCariSec(context);
    } else {
      await _yeniCariOlustur(context);
    }
  }

  Future<void> _mevcutCariSec(BuildContext context) async {
    if (!_duzenlemeYetkisiKontrolEt()) return;
    String arama = '';

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Cari Seç'),
          content: SizedBox(
            width: double.maxFinite,
            height: (MediaQuery.of(context).size.height * 0.5).clamp(200, 400),
            child: Column(
              children: [
                TextField(
                  decoration: InputDecoration(
                    hintText: 'Cari ara...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    isDense: true,
                  ),
                  onChanged: (v) =>
                      setState(() => arama = v.trim().toLowerCase()),
                ),
                const SizedBox(height: 12),
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
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      // Projede zaten olan carileri filtrele
                      var docs = snapshot.data!.docs.where((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        final pids = List<String>.from(
                          data['projectIds'] ?? [],
                        );
                        // Eski format desteği
                        final pid = data['projectId'] ?? '';
                        // Bu projede zaten olan carileri gösterme
                        if (pids.contains(widget.projectId) ||
                            pid == widget.projectId) {
                          return false;
                        }
                        final ad = (data['ad'] ?? '').toString().toLowerCase();
                        return arama.isEmpty || ad.contains(arama);
                      }).toList();

                      if (docs.isEmpty) {
                        return Center(
                          child: Text(
                            arama.isNotEmpty
                                ? 'Sonuç bulunamadı'
                                : 'Mevcut cari hesap yok',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        );
                      }

                      return ListView.builder(
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          final doc = docs[index];
                          final data = doc.data() as Map<String, dynamic>;
                          final ad = data['ad'] ?? 'İsimsiz';
                          final tip = data['tip'] ?? 'musteri';
                          final telefon = data['telefon'] ?? '';
                          final ikon = tip == 'musteri'
                              ? Icons.person_outline
                              : Icons.business_outlined;

                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: AppTheme.primaryColor.withValues(
                                alpha: 0.1,
                              ),
                              child: Icon(
                                ikon,
                                color: AppTheme.primaryColor,
                                size: 20,
                              ),
                            ),
                            title: Text(
                              ad,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: telefon.toString().isNotEmpty
                                ? Text(telefon)
                                : null,
                            trailing: Text(
                              tip == 'musteri' ? 'Müşteri' : 'Tedarikçi',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            onTap: () async {
                              // Cari'nin projectIds listesine bu projeyi ekle
                              await FirebaseFirestore.instance
                                  .collection('cari_hesaplar')
                                  .doc(doc.id)
                                  .update({
                                    'projectIds': FieldValue.arrayUnion([
                                      widget.projectId,
                                    ]),
                                  });

                              if (ctx.mounted) {
                                Navigator.pop(ctx);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('$ad bu projeye eklendi'),
                                  ),
                                );
                              }
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('İptal'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _yeniCariOlustur(BuildContext context) async {
    if (!_duzenlemeYetkisiKontrolEt()) return;
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

                try {
                  final sirket = SistemYoneticisi().aktifSirket;
                  final sirketId = sirket?.id ?? '';
                  if (sirketId.isEmpty) {
                    throw Exception(
                      'Sirket bilgisi bulunamadi. Lutfen tekrar giris yapin.',
                    );
                  }

                  final tier = planTierFromRaw(
                    sirket?.planTier,
                    subscriptionType: sirket?.subscriptionType,
                    subscriptionEndDate: sirket?.subscriptionEndDate,
                  );
                  final limitler = planLimitleriFor(tier);
                  if (limitler.maxCariSayisi != null) {
                    final countResult = await FirebaseFirestore.instance
                        .collection('cari_hesaplar')
                        .where('sirketId', isEqualTo: sirketId)
                        .count()
                        .get();
                    final toplamCari = countResult.count ?? 0;
                    if (toplamCari >= limitler.maxCariSayisi!) {
                      throw Exception(
                        'Ucretsiz planda en fazla ${limitler.maxCariSayisi} cari hesap olusturabilirsiniz. Daha fazla cari icin planinizi yukseltin.',
                      );
                    }
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
                        'projectId': widget.projectId,
                        'projectIds': [widget.projectId],
                        'olusturmaTarihi': FieldValue.serverTimestamp(),
                        'sirketId': sirketId,
                      });

                  if (context.mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Cari hesap oluşturuldu')),
                    );
                  }
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(
                      ctx,
                    ).showSnackBar(SnackBar(content: Text(hataCevir(e))));
                  }
                }
              },
              child: const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );
  }
}

class _FinanceCard extends StatelessWidget {
  final String title;
  final double amount;
  final Color color;

  const _FinanceCard({
    required this.title,
    required this.amount,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withValues(alpha: 0.08),
            color.withValues(alpha: 0.03),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.08),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '${format_utils.formatNumber(amount)} ₺',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
