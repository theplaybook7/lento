/// Cache Management - Firestore query optimization
library;
import 'package:cloud_firestore/cloud_firestore.dart';

class QueryCache {
  static final Map<String, QuerySnapshot> _cache = {};
  static final Map<String, DateTime> _cacheTime = {};
  
  /// Cache time-to-live (5 dakika)
  static const Duration cacheExpiry = Duration(minutes: 5);
  
  /// Cache'den sorgu sonucunu al
  static QuerySnapshot? get(String key) {
    if (_cache.containsKey(key)) {
      final cacheDate = _cacheTime[key];
      if (cacheDate != null && 
          DateTime.now().difference(cacheDate) < cacheExpiry) {
        return _cache[key];
      } else {
        _cache.remove(key);
        _cacheTime.remove(key);
      }
    }
    return null;
  }
  
  /// Sonucu cache'e koy
  static void set(String key, QuerySnapshot snapshot) {
    _cache[key] = snapshot;
    _cacheTime[key] = DateTime.now();
  }
  
  /// Cache'i temizle
  static void clear([String? key]) {
    if (key != null) {
      _cache.remove(key);
      _cacheTime.remove(key);
    } else {
      _cache.clear();
      _cacheTime.clear();
    }
  }
}

/// Optimized Firestore queries
extension OptimizedQueries on FirebaseFirestore {
  /// Cariler sorgusu - projectId'ye göre filtrelenmiş
  Query carilerByProject(String projectId) {
    return collection('cari_hesaplar')
        .where('projectId', isEqualTo: projectId)
        .orderBy('ad');
  }
  
  /// Giderler sorgusu - proje için
  Query giderlerByProject(String projectId) {
    return collection('giderler')
        .where('projectId', isEqualTo: projectId)
        .orderBy('tarih', descending: true)
        .limit(100);
  }
  
  /// Gelirler sorgusu - proje için
  Query gelirlerByProject(String projectId) {
    return collection('teklifler')
        .doc(projectId)
        .collection('gelirler')
        .orderBy('tarih', descending: true);
  }
}
