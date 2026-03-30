import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'lib/firebase_options.dart';

void main() async {
  // Firebase başlat
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  print('🔍 Firestore\'da kayıtlı şirketler kontrol ediliyor...\n');

  try {
    final sirketler = await FirebaseFirestore.instance
        .collection('sirketler')
        .get();

    if (sirketler.docs.isEmpty) {
      print('❌ Hiç şirket bulunamadı.');
      return;
    }

    print('✅ Toplam ${sirketler.docs.length} şirket bulundu:\n');
    print('=' * 80);

    for (var doc in sirketler.docs) {
      final data = doc.data();
      print('\n📊 Şirket ID: ${doc.id}');
      print('   Ad: ${data['ad'] ?? 'N/A'}');
      print('   Yönetici: ${data['yoneticiEposta'] ?? 'N/A'}');
      print('   Telefon: ${data['telefon'] ?? 'N/A'}');
      print('   Adres: ${data['adres'] ?? 'N/A'}');
      print('   Aktif: ${data['aktif'] ?? false}');
      
      // Ödeme bilgileri
      print('   --- Ödeme Bilgileri ---');
      print('   Ödeme Yapıldı: ${data['odemePaid'] ?? false}');
      print('   Ödeme Tarihi: ${data['odemeDate']?.toString() ?? 'N/A'}');
      print('   İşlem ID: ${data['odemeTransactionId'] ?? 'N/A'}');
      
      // Subscription bilgileri
      if (data.containsKey('subscriptionType')) {
        print('   --- Subscription ---');
        print('   Tip: ${data['subscriptionType'] ?? 'N/A'}');
        print('   Bitiş: ${data['subscriptionEndDate']?.toString() ?? 'N/A'}');
        print('   Auto Renew: ${data['autoRenew'] ?? false}');
      }
      
      // Personel sayısı
      final personelList = data['personelListesi'] as List? ?? [];
      print('   Personel Sayısı: ${personelList.length}');
      
      if (personelList.isNotEmpty) {
        print('   --- Personel Listesi ---');
        for (var p in personelList) {
          print('      • ${p['email']} - Admin: ${p['adminMi'] ?? false}');
        }
      }
      
      print('   Logo URL: ${data['logoUrl'] ?? 'Yok'}');
      print('-' * 80);
    }

    print('\n✅ Kontrol tamamlandı!');
  } catch (e) {
    print('❌ Hata: $e');
  }
}
