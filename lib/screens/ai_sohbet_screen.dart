import 'package:flutter/material.dart';
import '../services/gemini_service.dart';
import '../theme/app_theme.dart';

class AiSohbetScreen extends StatefulWidget {
  const AiSohbetScreen({super.key});

  @override
  State<AiSohbetScreen> createState() => _AiSohbetScreenState();
}

class _AiSohbetScreenState extends State<AiSohbetScreen> {
  final GeminiService _gemini = GeminiService();
  final TextEditingController _mesajCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final List<_ChatMesaj> _mesajlar = [];
  bool _yukleniyor = false;
  bool _hazir = false;

  @override
  void initState() {
    super.initState();
    _baslat();
  }

  Future<void> _baslat() async {
    final ok = await _gemini.baslat();
    setState(() => _hazir = ok);

    if (!ok) {
      _mesajlar.add(_ChatMesaj(
        metin: 'AI servisi başlatılamadı.',
        benMi: false,
        hata: true,
      ));
    } else {
      // Karşılama mesajı
      setState(() => _yukleniyor = true);
      final cevap = await _gemini.mesajGonder('merhaba');
      setState(() {
        _yukleniyor = false;
        _mesajlar.add(_ChatMesaj(metin: cevap, benMi: false));
      });
    }
  }

  Future<void> _gonder() async {
    final metin = _mesajCtrl.text.trim();
    if (metin.isEmpty || !_hazir || _yukleniyor) return;

    setState(() {
      _mesajlar.add(_ChatMesaj(metin: metin, benMi: true));
      _mesajCtrl.clear();
      _yukleniyor = true;
    });
    _scrollAlt();

    final cevap = await _gemini.mesajGonder(metin);

    if (mounted) {
      setState(() {
        _mesajlar.add(_ChatMesaj(metin: cevap, benMi: false));
        _yukleniyor = false;
      });
      _scrollAlt();
    }
  }

  void _scrollAlt() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sohbetiSifirla() {
    _gemini.sifirla();
    setState(() {
      _mesajlar.clear();
      _mesajlar.add(_ChatMesaj(
        metin: 'Sohbet sıfırlandı. Yeni bir konuşma başlayabilirsiniz.',
        benMi: false,
      ));
    });
  }

  Future<void> _apiKeyDialog() async {
    final ctrl = TextEditingController(text: await GeminiService.getApiKey() ?? '');
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Gemini API Anahtarı'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(
                labelText: 'API Key',
                border: OutlineInputBorder(),
                hintText: 'AIza...',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Google AI Studio\'dan ücretsiz alabilirsiniz:\naistudio.google.com/apikey',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              ctrl.dispose();
              Navigator.pop(ctx);
            },
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () async {
              final key = ctrl.text.trim();
              if (key.isNotEmpty) {
                await GeminiService.setApiKey(key);
                ctrl.dispose();
                Navigator.pop(ctx);
                // Yeniden başlat
                setState(() {
                  _mesajlar.clear();
                  _hazir = false;
                });
                await _baslat();
              }
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _mesajCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.smart_toy, size: 22),
            const SizedBox(width: 8),
            Text(_gemini.yerelModAktif ? 'AI Asistan (Yerleşik)' : 'AI Asistan'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Sohbeti Sıfırla',
            onPressed: _sohbetiSifirla,
          ),
          IconButton(
            icon: const Icon(Icons.key),
            tooltip: 'API Anahtarı',
            onPressed: _apiKeyDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          // Mesaj listesi
          Expanded(
            child: _mesajlar.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.chat_bubble_outline,
                            size: 64, color: Colors.grey.shade300),
                        const SizedBox(height: 16),
                        Text(
                          'AI Asistanınız hazırlanıyor...',
                          style: TextStyle(
                              color: Colors.grey.shade500, fontSize: 16),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.all(12),
                    itemCount: _mesajlar.length + (_yukleniyor ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _mesajlar.length && _yukleniyor) {
                        return _buildYaziyorGostergesi();
                      }
                      return _buildMesajBalonu(_mesajlar[index]);
                    },
                  ),
          ),
          // Hızlı öneriler
          if (_mesajlar.length <= 1 && _hazir)
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  _buildOneriChip('5 katlı bina maliyeti ne olur?'),
                  _buildOneriChip('Kadıköy\'de kat karşılığı analizi'),
                  _buildOneriChip('Hibe ve kredi avantajları neler?'),
                  _buildOneriChip('Müteahhit daire alırsa ne değişir?'),
                ],
              ),
            ),
          // Giriş alanı
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.shade300,
                  offset: const Offset(0, -1),
                  blurRadius: 4,
                ),
              ],
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _mesajCtrl,
                      enabled: _hazir && !_yukleniyor,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _gonder(),
                      maxLines: null,
                      decoration: InputDecoration(
                        hintText: _hazir
                            ? 'İnşaat hakkında sorunuzu yazın...'
                            : 'API anahtarı gerekli',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    backgroundColor:
                        _hazir ? AppTheme.primaryColor : Colors.grey,
                    child: IconButton(
                      icon: const Icon(Icons.send, color: Colors.white, size: 20),
                      onPressed: _hazir && !_yukleniyor ? _gonder : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMesajBalonu(_ChatMesaj mesaj) {
    final benMi = mesaj.benMi;
    return Align(
      alignment: benMi ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: mesaj.hata
              ? Colors.red.shade50
              : benMi
                  ? AppTheme.primaryColor
                  : Colors.grey.shade100,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(benMi ? 16 : 4),
            bottomRight: Radius.circular(benMi ? 4 : 16),
          ),
        ),
        child: SelectableText(
          mesaj.metin,
          style: TextStyle(
            color: mesaj.hata
                ? Colors.red.shade800
                : benMi
                    ? Colors.white
                    : Colors.black87,
            fontSize: 14,
            height: 1.4,
          ),
        ),
      ),
    );
  }

  Widget _buildYaziyorGostergesi() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomRight: Radius.circular(16),
            bottomLeft: Radius.circular(4),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.grey.shade500,
              ),
            ),
            const SizedBox(width: 8),
            Text('Düşünüyor...',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _buildOneriChip(String metin) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ActionChip(
        label: Text(metin, style: const TextStyle(fontSize: 12)),
        onPressed: () {
          _mesajCtrl.text = metin;
          _gonder();
        },
        backgroundColor: Colors.purple.shade50,
        side: BorderSide(color: Colors.purple.shade200),
      ),
    );
  }
}

class _ChatMesaj {
  final String metin;
  final bool benMi;
  final bool hata;

  _ChatMesaj({
    required this.metin,
    required this.benMi,
    this.hata = false,
  });
}
