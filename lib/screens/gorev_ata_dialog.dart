import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../project_core.dart';
import '../notification_service.dart';

/// Görev atama dialogu - personel seç + not ekle + (opsiyonel) proje seç
class GorevAtaDialog extends StatefulWidget {
  final String? varsayilanProjeId;
  final String? varsayilanProjeAdi;
  const GorevAtaDialog({super.key, this.varsayilanProjeId, this.varsayilanProjeAdi});

  @override
  State<GorevAtaDialog> createState() => _GorevAtaDialogState();
}

class _GorevAtaDialogState extends State<GorevAtaDialog> {
  String? _seciliEmail;
  String? _seciliProjeId;
  String? _seciliProjeAdi;
  final _baslikCtrl = TextEditingController();
  final _notCtrl = TextEditingController();
  bool _kaydediyor = false;
  List<Map<String, String>> _projeler = [];
  bool _projelerYukleniyor = true;

  @override
  void initState() {
    super.initState();
    _seciliProjeId = widget.varsayilanProjeId;
    _seciliProjeAdi = widget.varsayilanProjeAdi;
    _projeleriYukle();
  }

  Future<void> _projeleriYukle() async {
    final sirketId = SistemYoneticisi().aktifSirket?.id;
    if (sirketId == null) {
      setState(() => _projelerYukleniyor = false);
      return;
    }
    try {
      final snap = await FirebaseFirestore.instance
          .collection('projects')
          .where('companyId', isEqualTo: sirketId)
          .get();
      final list = snap.docs.map((d) {
        final data = d.data();
        return {
          'id': d.id,
          'ad': (data['name'] ?? data['projeAdi'] ?? data['ad'] ?? 'Proje') as String,
        };
      }).toList();
      list.sort((a, b) => (a['ad'] ?? '').compareTo(b['ad'] ?? ''));
      if (mounted) {
        setState(() {
          _projeler = list;
          _projelerYukleniyor = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _projelerYukleniyor = false);
    }
  }

  @override
  void dispose() {
    _baslikCtrl.dispose();
    _notCtrl.dispose();
    super.dispose();
  }

  Future<void> _kaydet() async {
    if (_seciliEmail == null || _seciliEmail!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen personel seçin')),
      );
      return;
    }
    if (_baslikCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen görev başlığı girin')),
      );
      return;
    }

    setState(() => _kaydediyor = true);
    try {
      final sirketId = SistemYoneticisi().aktifSirket?.id;
      final atayanEmail = SistemYoneticisi().girisYapanEmail ?? '';
      if (sirketId == null) throw 'Aktif şirket yok';

      // 1) gorevler koleksiyonuna kaydet
      await FirebaseFirestore.instance.collection('gorevler').add({
        'sirketId': sirketId,
        'projeId': _seciliProjeId ?? '',
        'projeAdi': _seciliProjeAdi ?? '',
        'baslik': _baslikCtrl.text.trim(),
        'aciklama': _notCtrl.text.trim(),
        'atayanEmail': atayanEmail,
        'atananEmail': _seciliEmail,
        'durum': 'beklemede',
        'olusturmaTarihi': FieldValue.serverTimestamp(),
      });

      // 2) Bildirim oluştur (bell icon + FCM Cloud Function trigger'ı buradan çalışır)
      final mesaj = _notCtrl.text.trim().isEmpty
          ? 'Size yeni bir görev atandı: ${_baslikCtrl.text.trim()}'
          : '${_baslikCtrl.text.trim()}\n${_notCtrl.text.trim()}';
      await BildirimServisi.bildirimGonder(
        baslik: '📋 Yeni Görev: ${_baslikCtrl.text.trim()}',
        mesaj: mesaj,
        projeId: _seciliProjeId ?? '',
        modul: 'gorev',
        hedefEmail: _seciliEmail,
      );

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Görev $_seciliEmail adresine atandı')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _kaydediyor = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sirket = SistemYoneticisi().aktifSirket;
    final me = SistemYoneticisi().girisYapanEmail?.trim().toLowerCase() ?? '';
    // Personel listesi + şirket sahibi (kendisi hariç)
    final emails = <String>{};
    if (sirket != null) {
      if (sirket.yoneticiEposta.trim().toLowerCase() != me) {
        emails.add(sirket.yoneticiEposta);
      }
      for (final p in sirket.personelListesi) {
        if (p.email.trim().toLowerCase() != me) {
          emails.add(p.email);
        }
      }
    }
    final emailListesi = emails.toList()..sort();

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.assignment_turned_in, color: Colors.blue),
          SizedBox(width: 8),
          Text('Görev Ata'),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Personel', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              if (emailListesi.isEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: const Text(
                    'Atama yapılacak personel yok. Ayarlar > Personel bölümünden ekleyebilirsiniz.',
                    style: TextStyle(fontSize: 13),
                  ),
                )
              else
                DropdownButtonFormField<String>(
                  initialValue: _seciliEmail,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  hint: const Text('Personel seçin'),
                  items: emailListesi
                      .map((e) => DropdownMenuItem(value: e, child: Text(e, overflow: TextOverflow.ellipsis)))
                      .toList(),
                  onChanged: (v) => setState(() => _seciliEmail = v),
                ),
              const SizedBox(height: 14),
              const Text('Görev Başlığı', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              TextField(
                controller: _baslikCtrl,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Örn: Ruhsat evraklarını topla',
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
              const SizedBox(height: 14),
              const Text('Not / Açıklama', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              TextField(
                controller: _notCtrl,
                maxLines: 4,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Detayları buraya yazın...',
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
              const SizedBox(height: 14),
              const Text('Proje (opsiyonel)', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              if (_projelerYukleniyor)
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: LinearProgressIndicator(),
                )
              else
                Autocomplete<Map<String, String>>(
                  initialValue: TextEditingValue(text: _seciliProjeAdi ?? ''),
                  optionsBuilder: (TextEditingValue value) {
                    final q = value.text.trim().toLowerCase();
                    if (q.isEmpty) return _projeler.take(50);
                    return _projeler.where((p) =>
                        (p['ad'] ?? '').toLowerCase().contains(q));
                  },
                  displayStringForOption: (p) => p['ad'] ?? '',
                  fieldViewBuilder:
                      (context, controller, focusNode, onSubmitted) {
                    return TextField(
                      controller: controller,
                      focusNode: focusNode,
                      decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        prefixIcon: const Icon(Icons.search),
                        hintText: 'Proje ara... (opsiyonel)',
                        suffixIcon: controller.text.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: () {
                                  controller.clear();
                                  setState(() {
                                    _seciliProjeId = null;
                                    _seciliProjeAdi = null;
                                  });
                                },
                              ),
                      ),
                    );
                  },
                  optionsViewBuilder: (context, onSelected, options) {
                    final list = options.toList();
                    return Align(
                      alignment: Alignment.topLeft,
                      child: Material(
                        elevation: 4,
                        borderRadius: BorderRadius.circular(6),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                              maxHeight: 240, maxWidth: 380),
                          child: ListView.builder(
                            padding: EdgeInsets.zero,
                            shrinkWrap: true,
                            itemCount: list.length,
                            itemBuilder: (_, i) {
                              final p = list[i];
                              return ListTile(
                                dense: true,
                                leading: const Icon(Icons.business_outlined,
                                    size: 18),
                                title: Text(p['ad'] ?? '',
                                    style: const TextStyle(fontSize: 13)),
                                onTap: () => onSelected(p),
                              );
                            },
                          ),
                        ),
                      ),
                    );
                  },
                  onSelected: (p) {
                    setState(() {
                      _seciliProjeId = p['id'];
                      _seciliProjeAdi = p['ad'];
                    });
                  },
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _kaydediyor ? null : () => Navigator.pop(context),
          child: const Text('İptal'),
        ),
        ElevatedButton.icon(
          onPressed: _kaydediyor || emailListesi.isEmpty ? null : _kaydet,
          icon: _kaydediyor
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.send),
          label: const Text('Görevi Ata'),
        ),
      ],
    );
  }
}
