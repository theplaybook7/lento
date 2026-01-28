import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

/// Mevcut tüm projelere isArchived: false field'ı ekler
Future<void> main() async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  final db = FirebaseFirestore.instance;
  
  print('Projeler kontrol ediliyor...');
  
  final projectsSnapshot = await db.collection('projects').get();
  print('Toplam ${projectsSnapshot.docs.length} proje bulundu.');
  
  int updated = 0;
  int skipped = 0;
  
  for (var doc in projectsSnapshot.docs) {
    final data = doc.data();
    
    // Eğer isArchived field'ı yoksa ekle
    if (!data.containsKey('isArchived')) {
      await doc.reference.update({'isArchived': false});
      print('✓ ${doc.id} güncellendi');
      updated++;
    } else {
      print('- ${doc.id} zaten isArchived field\'ına sahip');
      skipped++;
    }
  }
  
  print('\n=== Özet ===');
  print('Güncellenen: $updated');
  print('Atlanan: $skipped');
  print('Toplam: ${projectsSnapshot.docs.length}');
}
