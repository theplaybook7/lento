import 'package:cloud_firestore/cloud_firestore.dart';

/// Sayfalanmış sorgu yönetimi
class PaginationController {
  final Query baseQuery;
  final int pageSize;
  
  late DocumentSnapshot? _lastDocument;
  late List<DocumentSnapshot> _items = [];
  late bool _hasMore = true;
  
  PaginationController({
    required this.baseQuery,
    this.pageSize = 50,
  });

  bool get hasMore => _hasMore;
  List<DocumentSnapshot> get items => _items;

  /// Ilk sayfayı yükle
  Future<List<DocumentSnapshot>> loadFirstPage() async {
    try {
      final snapshot = await baseQuery.limit(pageSize).get();
      _items = snapshot.docs;
      _lastDocument = snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
      _hasMore = snapshot.docs.length >= pageSize;
      return _items;
    } catch (e) {
      print('First page loading error: $e');
      return [];
    }
  }

  /// Sonraki sayfayı yükle
  Future<List<DocumentSnapshot>> loadNextPage() async {
    if (!_hasMore || _lastDocument == null) return [];

    try {
      final snapshot = await baseQuery
          .startAfterDocument(_lastDocument!)
          .limit(pageSize)
          .get();
      
      if (snapshot.docs.isEmpty) {
        _hasMore = false;
        return [];
      }

      _items.addAll(snapshot.docs);
      _lastDocument = snapshot.docs.last;
      _hasMore = snapshot.docs.length >= pageSize;
      
      return snapshot.docs;
    } catch (e) {
      print('Next page loading error: $e');
      return [];
    }
  }

  /// Tüm verileri sıfırla
  void reset() {
    _items = [];
    _lastDocument = null;
    _hasMore = true;
  }
}

/// StreamBuilder ile pagination - real-time updates
class StreamPagination {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Koleksiyon referansı oluştur
  Query buildQuery(
    String collectionPath, {
    List<QueryConstraint> constraints = const [],
    String? orderBy,
    bool descending = true,
  }) {
    Query query = _firestore.collection(collectionPath);

    // Constraints ekle (where clauses)
    for (final constraint in constraints) {
      query = constraint.apply(query);
    }

    // Order by ekle
    if (orderBy != null) {
      query = query.orderBy(orderBy, descending: descending);
    }

    return query;
  }
}

/// Query constraint helper
class QueryConstraint {
  final String field;
  final dynamic value;
  final String operator; // ==, <, >, <=, >=, !=, array-contains

  QueryConstraint({
    required this.field,
    required this.value,
    this.operator = '==',
  });

  Query apply(Query query) {
    switch (operator) {
      case '==':
        return query.where(field, isEqualTo: value);
      case '<':
        return query.where(field, isLessThan: value);
      case '>':
        return query.where(field, isGreaterThan: value);
      case '<=':
        return query.where(field, isLessThanOrEqualTo: value);
      case '>=':
        return query.where(field, isGreaterThanOrEqualTo: value);
      case 'array-contains':
        return query.where(field, arrayContains: value);
      default:
        return query.where(field, isEqualTo: value);
    }
  }
}
