import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';

double parseFormatted(String? value) {
  if (value == null || value.isEmpty) return 0.0;
  return double.tryParse(value.replaceAll('.', '').replaceAll(',', '.')) ?? 0.0;
}

String formatNumber(dynamic value) {
  if (value == null) return "";
  double number = value is String ? parseFormatted(value) : (value is num ? value.toDouble() : 0);
  if (number == 0) return "0";
  return number.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]}.');
}

class BinlikInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.isEmpty) return newValue;
    String clean = newValue.text.replaceAll(RegExp(r'[^0-9]'), ''); 
    if (clean.isEmpty) return oldValue;
    final double number = double.parse(clean);
    final String newText = formatNumber(number);
    return TextEditingValue(text: newText, selection: TextSelection.collapsed(offset: newText.length));
  }
}

class PersonelYetki {
  String email;
  bool adminMi;
  bool goruntulemeRuhsat;
  bool goruntulemeSantiye;
  bool goruntulemeMuhasebe;

  PersonelYetki({
    required this.email,
    this.adminMi = false,
    this.goruntulemeRuhsat = true,
    this.goruntulemeSantiye = true,
    this.goruntulemeMuhasebe = true,
  });

  Map<String, dynamic> toMap() => {
    'email': email,
    'adminMi': adminMi,
    'ruhsat': goruntulemeRuhsat,
    'santiye': goruntulemeSantiye,
    'muhasebe': goruntulemeMuhasebe,
  };

  factory PersonelYetki.fromMap(Map<String, dynamic> map) {
    return PersonelYetki(
      email: map['email'] ?? "",
      adminMi: map['adminMi'] ?? false,
      goruntulemeRuhsat: map['ruhsat'] ?? true,
      goruntulemeSantiye: map['santiye'] ?? true,
      goruntulemeMuhasebe: map['muhasebe'] ?? true,
    );
  }
}

class Sirket {
  String id;
  String ad;
  Uint8List? logo;
  String? logoUrl;
  String yoneticiEposta;
  String? telefon;
  String? adres;
  bool aktif;
  List<PersonelYetki> personelListesi;
  
  // Ödeme & Subscription bilgileri
  bool odemePaid;
  DateTime? odemeDate;
  String? odemeTransactionId;
  
  // Subscription
  String? subscriptionType;       // 'yearly' | 'monthly' | 'trial'
  DateTime? subscriptionEndDate;  // Abonelik bitiş tarihi
  bool autoRenew;                 // Otomatik yenileme
  List<Map<String, dynamic>> paymentHistory; // Ödeme geçmişi

  Sirket({
    required this.id,
    required this.ad,
    this.logo,
    this.logoUrl,
    required this.yoneticiEposta,
    this.telefon,
    this.adres,
    this.aktif = true,
    required this.personelListesi,
    this.odemePaid = false,
    this.odemeDate,
    this.odemeTransactionId,
    this.subscriptionType,
    this.subscriptionEndDate,
    this.autoRenew = true,
    this.paymentHistory = const [],
  });

  factory Sirket.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> m = doc.data() as Map<String, dynamic>;
    var pList = m['personelListesi'] as List<dynamic>? ?? [];
    List<PersonelYetki> yetkiler = [];
    for (var e in pList) {
      if (e is Map<String, dynamic>) {
        yetkiler.add(PersonelYetki.fromMap(e));
      }
    }

    return Sirket(
      id: doc.id,
      ad: m['ad'],
      logo: m['logo'] != null ? base64Decode(m['logo']) : null,
      logoUrl: m['logoUrl'] as String?,
      yoneticiEposta: m['yoneticiEposta'],
      telefon: m['telefon'] as String?,
      adres: m['adres'] as String?,
      aktif: m['aktif'] as bool? ?? true,
      personelListesi: yetkiler,
      odemePaid: m['odemePaid'] as bool? ?? false,
      odemeDate: m['odemeDate'] != null ? (m['odemeDate'] as Timestamp).toDate() : null,
      odemeTransactionId: m['odemeTransactionId'] as String?,
      subscriptionType: m['subscriptionType'] as String?,
      subscriptionEndDate: m['subscriptionEndDate'] != null ? (m['subscriptionEndDate'] as Timestamp).toDate() : null,
      autoRenew: m['autoRenew'] as bool? ?? true,
      paymentHistory: List<Map<String, dynamic>>.from(m['paymentHistory'] as List? ?? []),
    );
  }
}

class SistemYoneticisi {
  static final SistemYoneticisi _instance = SistemYoneticisi._internal();
  factory SistemYoneticisi() => _instance;
  SistemYoneticisi._internal();

  Sirket? aktifSirket;
  PersonelYetki? aktifKullaniciYetkileri;
  String? girisYapanEmail;
  bool cikisYapiliyor = false;

  void temizle() {
    cikisYapiliyor = true;
    aktifSirket = null;
    aktifKullaniciYetkileri = null;
    girisYapanEmail = null;
  }

  bool yetkiVarMi(String modul) {
    if (aktifSirket != null && aktifSirket!.yoneticiEposta == girisYapanEmail) return true;
    if (aktifKullaniciYetkileri == null) return false;
    if (aktifKullaniciYetkileri!.adminMi) return true; 
    
    if (modul == 'ruhsat') return aktifKullaniciYetkileri!.goruntulemeRuhsat;
    if (modul == 'santiye') return aktifKullaniciYetkileri!.goruntulemeSantiye;
    if (modul == 'muhasebe') return aktifKullaniciYetkileri!.goruntulemeMuhasebe;
    
    return true;
  }
}

class BolumModel {
  String tip;
  TextEditingController adetCtrl;
  TextEditingController m2Ctrl;        
  TextEditingController ustKatM2Ctrl;  
  TextEditingController altKatM2Ctrl;  
  TextEditingController toprakParasiCtrl;
  String sahip; 
  bool isOrtakAlan;
  int daireHibeSayisi;
  int daireKrediSayisi;
  int dukkanHibeSayisi;
  int dukkanKrediSayisi;

  BolumModel({
    required this.tip,
    required this.adetCtrl,
    required this.m2Ctrl,
    required this.toprakParasiCtrl,
    this.sahip = "Mal Sahibi",
    this.isOrtakAlan = false,
    this.daireHibeSayisi = 0,
    this.daireKrediSayisi = 0,
    this.dukkanHibeSayisi = 0,
    this.dukkanKrediSayisi = 0,
    TextEditingController? ustCtrl,
    TextEditingController? altCtrl,
  }) : 
    ustKatM2Ctrl = ustCtrl ?? TextEditingController(),
    altKatM2Ctrl = altCtrl ?? TextEditingController();

  Map<String, dynamic> toMap() {
    return {
      'tip': tip,
      'adet': adetCtrl.text,
      'm2': m2Ctrl.text,
      'ustM2': ustKatM2Ctrl.text,
      'altM2': altKatM2Ctrl.text,
      'toprakParasi': toprakParasiCtrl.text,
      'sahip': sahip,
      'isOrtakAlan': isOrtakAlan,
      'daireHibe': daireHibeSayisi,
      'daireKredi': daireKrediSayisi,
      'dukkanHibe': dukkanHibeSayisi,
      'dukkanKredi': dukkanKrediSayisi,
    };
  }

  factory BolumModel.fromMap(Map<String, dynamic> map) {
    return BolumModel(
      tip: map['tip'] ?? "Daire",
      adetCtrl: TextEditingController(text: map['adet']),
      m2Ctrl: TextEditingController(text: map['m2']),
      toprakParasiCtrl: TextEditingController(text: map['toprakParasi']),
      sahip: map['sahip'] ?? "Mal Sahibi",
      isOrtakAlan: map['isOrtakAlan'] ?? false,
      daireHibeSayisi: map['daireHibe'] ?? 0,
      daireKrediSayisi: map['daireKredi'] ?? 0,
      dukkanHibeSayisi: map['dukkanHibe'] ?? 0,
      dukkanKrediSayisi: map['dukkanKredi'] ?? 0,
      ustCtrl: TextEditingController(text: map['ustM2']),
      altCtrl: TextEditingController(text: map['altM2']),
    );
  }

  int get girilenAdet => int.tryParse(adetCtrl.text.replaceAll('.', '')) ?? 0;
  
  double get girilenM2 {
    double ana = parseFormatted(m2Ctrl.text);
    // Dubleks: sadece ana kat (üst kat ayrıca hesaplanır)
    // Ters Dubleks ve Depolu Dükkan: sadece ana kat (alt kat ayrıca hesaplanır)
    return ana;
  }
  
  double get toplamMetrekare {
    double ana = parseFormatted(m2Ctrl.text);
    if (tip == 'Dubleks') {
      double ust = parseFormatted(ustKatM2Ctrl.text);
      return ana + ust;
    } else if (tip == 'Ters Dubleks' || tip == 'Depolu Dükkan') {
      double alt = parseFormatted(altKatM2Ctrl.text);
      return ana + alt;
    }
    return ana;
  }
  
  double get girilenToprakParasi => parseFormatted(toprakParasiCtrl.text);
  bool get hakKullanildi => (daireHibeSayisi + daireKrediSayisi + dukkanHibeSayisi + dukkanKrediSayisi) > 0;
}

class KatModel {
  String ad;
  TextEditingController katBrutAlanCtrl;
  List<BolumModel> bolumler;

  KatModel({required this.ad, required this.katBrutAlanCtrl, required this.bolumler});
  
  Map<String, dynamic> toMap() {
    return {
      'ad': ad,
      'katBrutAlan': katBrutAlanCtrl.text,
      'bolumler': bolumler.map((b) => b.toMap()).toList(),
    };
  }

  factory KatModel.fromMap(Map<String, dynamic> map) {
    var list = map['bolumler'] as List;
    List<BolumModel> bolumListesi = list.map((i) => BolumModel.fromMap(i)).toList();
    return KatModel(
      ad: map['ad'],
      katBrutAlanCtrl: TextEditingController(text: map['katBrutAlan']),
      bolumler: bolumListesi
    );
  }

  double get girilenKatAlani => parseFormatted(katBrutAlanCtrl.text);
}