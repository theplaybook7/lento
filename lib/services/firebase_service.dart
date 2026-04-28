import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../models/project_model.dart';
import 'dart:developer' as developer;

class FirebaseService {
  static final FirebaseService _instance = FirebaseService._internal();
  factory FirebaseService() => _instance;
  FirebaseService._internal();

  final _db = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;

  // Firebase Storage referansı al
  Reference getStorageRef(String path) {
    return _storage.ref().child(path);
  }

  // ============== PROJE İŞLEMLERİ ==============

  /// Yeni proje oluştur
  Future<String> createProject({
    required String companyId,
    required String name,
    String? description,
    required DateTime startDate,
    DateTime? endDate,
    double totalBudget = 0,
    required String malSahibi,
    required String adaParsel,
    required String muteahhit,
  }) async {
    try {
      final docRef = await _db.collection('projects').add({
        'companyId': companyId,
        'name': name,
        'description': description,
        'startDate': startDate,
        'endDate': endDate,
        'status': ProjectStatus.planning.name,
        'currentPhase': 'planning',
        'totalBudget': totalBudget,
        'malSahibi': malSahibi,
        'adaParsel': adaParsel,
        'muteahhit': muteahhit,
        'createdAt': DateTime.now(),
        'isArchived': false,
      });

      // Yardımcı dokümanları paralel oluştur
      await Future.wait([
        _db.collection('project_finance').doc(docRef.id).set({
          'projectId': docRef.id,
          'totalIncome': 0,
          'totalExpenses': 0,
          'budgetedAmount': totalBudget,
        }),
        _db.collection('ruhsat').doc(docRef.id).set({
          'projectId': docRef.id,
          'createdAt': DateTime.now(),
          'documents': [],
        }),
        _db.collection('santiye').doc(docRef.id).set({
          'projectId': docRef.id,
          'createdAt': DateTime.now(),
          'photos': [],
          'documents': [],
        }),
      ]);

      // Şirket finansmanını arka planda güncelle (beklemeden)
      unawaited(_updateCompanyFinance(companyId));

      developer.log('Proje oluşturuldu: ${docRef.id}');
      return docRef.id;
    } catch (e) {
      developer.log('Proje oluşturma hatası: $e');
      rethrow;
    }
  }

  /// Projeleri listele
  Future<List<Project>> getProjects(String companyId) async {
    try {
      final snapshot = await _db
          .collection('projects')
          .where('companyId', isEqualTo: companyId)
          .where('isArchived', isEqualTo: false)
          .orderBy('createdAt', descending: true)
          .get();

      return snapshot.docs
          .map((doc) => Project.fromMap(doc.data(), doc.id))
          .toList();
    } catch (e) {
      developer.log('Projeler yükleme hatası: $e');
      rethrow;
    }
  }

  /// Proje detayını al
  Future<Project?> getProject(String projectId) async {
    try {
      final doc = await _db.collection('projects').doc(projectId).get();
      if (doc.exists) {
        return Project.fromMap(doc.data() as Map<String, dynamic>, doc.id);
      }
      return null;
    } catch (e) {
      developer.log('Proje yükleme hatası: $e');
      rethrow;
    }
  }

  /// Projeyi güncelle
  Future<void> updateProject(String projectId, Map<String, dynamic> data) async {
    try {
      await _db.collection('projects').doc(projectId).update(data);
      developer.log('Proje güncellendi: $projectId');
    } catch (e) {
      developer.log('Proje güncelleme hatası: $e');
      rethrow;
    }
  }

  /// Projeyi arşivle
  Future<void> archiveProject(String projectId) async {
    try {
      await _db.collection('projects').doc(projectId).update({
        'isArchived': true,
      });
      developer.log('Proje arşivlendi: $projectId');
    } catch (e) {
      developer.log('Proje arşivleme hatası: $e');
      rethrow;
    }
  }

  /// Projeyi sil
  Future<void> deleteProject(String projectId) async {
    try {
      // İşlemleri al
      final transactions = await _db
          .collection('project_finance')
          .doc(projectId)
          .collection('transactions')
          .get();
      
      // Tüm silme işlemlerini paralel yap
      final deleteFutures = [
        // Proje finansmanını sil
        _db.collection('project_finance').doc(projectId).delete(),
        
        // Proje aşamalarını sil
        _db.collection('project_phases').doc(projectId).delete(),
        
        // İşlemleri paralel sil
        for (var doc in transactions.docs)
          doc.reference.delete(),
        
        // Projeyi sil
        _db.collection('projects').doc(projectId).delete(),
      ];
      
      await Future.wait(deleteFutures);
      
      developer.log('Proje silindi: $projectId');
    } catch (e) {
      developer.log('Proje silme hatası: $e');
      rethrow;
    }
  }

  /// Arşivlenmiş projeleri getir
  Future<List<Project>> getArchivedProjects(String companyId) async {
    try {
      final snapshot = await _db
          .collection('projects')
          .where('companyId', isEqualTo: companyId)
          .where('isArchived', isEqualTo: true)
          .orderBy('createdAt', descending: true)
          .get();

      return snapshot.docs
          .map((doc) => Project.fromMap(doc.data(), doc.id))
          .toList();
    } catch (e) {
      developer.log('Arşiv yükleme hatası: $e');
      rethrow;
    }
  }

  // ============== PROJE AŞAMALARI ==============

  Future<List<ProjectPhase>> _getProjectPhases(String projectId) async {
    final doc = await _db.collection('project_phases').doc(projectId).get();
    if (doc.exists) {
      final phases = doc.data()?['phases'] as List<dynamic>? ?? [];
      return phases
          .map((p) => ProjectPhase.fromMap(p as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  // ============== FİNANSMAN İŞLEMLERİ ==============

  /// Finansal işlem ekle
  Future<void> addFinanceTransaction(
    String projectId, {
    required FinanceTransaction transaction,
  }) async {
    try {
      final transRef = _db.collection('project_finance').doc(projectId).collection('transactions').doc(transaction.id);

      await transRef.set(transaction.toMap());

      // Proje finansmanını güncelle
      await _updateProjectFinance(projectId);

      // Şirket finansmanını güncelle
      final project = await getProject(projectId);
      if (project != null) {
        await _updateCompanyFinance(project.companyId);
      }

      developer.log('İşlem eklendi: ${transaction.description}');
    } catch (e) {
      developer.log('İşlem ekleme hatası: $e');
      rethrow;
    }
  }

  /// Proje finansmanı al
  Future<ProjectFinance> getProjectFinance(String projectId) async {
    try {
      final doc = await _db.collection('project_finance').doc(projectId).get();
      if (!doc.exists) {
        return ProjectFinance(projectId: projectId);
      }

      final data = doc.data() as Map<String, dynamic>;
      final snapshot = await _db
          .collection('project_finance')
          .doc(projectId)
          .collection('transactions')
          .get();

      final transactions = snapshot.docs
          .map((doc) {
            try {
              return FinanceTransaction.fromMap(doc.data());
            } catch (e) {
              developer.log('Transaction parsing hatası: $e, Data: ${doc.data()}');
              return null;
            }
          })
          .whereType<FinanceTransaction>()
          .toList();

      return ProjectFinance(
        projectId: projectId,
        totalIncome: (data['totalIncome'] ?? 0).toDouble(),
        totalExpenses: (data['totalExpenses'] ?? 0).toDouble(),
        budgetedAmount: (data['budgetedAmount'] ?? 0).toDouble(),
        transactions: transactions,
      );
    } catch (e) {
      developer.log('Proje finansmanı yükleme hatası: $e');
      rethrow;
    }
  }

  /// Proje finansmanı özetini al (project_finance dokümanından hızlı okuma)
  Future<ProjectFinance> getProjectFinanceSummary(String projectId) async {
    try {
      final doc = await _db.collection('project_finance').doc(projectId).get();
      final data = doc.data() ?? {};
      return ProjectFinance(
        projectId: projectId,
        totalIncome: ((data['totalIncome'] ?? 0) as num).toDouble(),
        totalExpenses: ((data['totalExpenses'] ?? 0) as num).toDouble(),
        budgetedAmount: ((data['budgetedAmount'] ?? 0) as num).toDouble(),
      );
    } catch (e) {
      developer.log('Proje finansmanı özet yükleme hatası: $e');
      return ProjectFinance(projectId: projectId);
    }
  }

  /// Tüm projelerin finans özetlerini cari hareketlerinden toplu hesapla
  /// Tek seferde tüm carileri okur, her carinin hareketlerini projeye göre gruplar
  Future<Map<String, ProjectFinance>> getAllProjectFinanceSummaries(String sirketId, List<String> projectIds) async {
    final result = <String, ProjectFinance>{};
    try {
      // 1) Tüm carileri tek sorguda al
      final cariSnap = await _db
          .collection('cari_hesaplar')
          .where('sirketId', isEqualTo: sirketId)
          .get();

      // 2) Proje başına gelir/gider topla
      final incomeMap = <String, double>{};
      final expenseMap = <String, double>{};

      // 3) Her carinin hareketlerini paralel oku
      await Future.wait(cariSnap.docs.map((cariDoc) async {
        try {
          final cariData = cariDoc.data();
          final pids = List<String>.from(cariData['projectIds'] ?? []);
          final pid = cariData['projectId'] ?? '';
          // Bu carinin projelerle ilişkisi var mı?
          final hasProject = pids.any((id) => projectIds.contains(id)) || projectIds.contains(pid);
          if (!hasProject) return;

          final hareketSnap = await _db
              .collection('cari_hesaplar')
              .doc(cariDoc.id)
              .collection('hareketler')
              .get();

          for (final hDoc in hareketSnap.docs) {
            final hData = hDoc.data();
            final projeId = hData['projeId'] as String? ?? '';
            if (projeId.isEmpty || !projectIds.contains(projeId)) continue;
            final tutarTL = ((hData['tutarTL'] ?? hData['tutar'] ?? 0.0) as num).toDouble();
            final tip = hData['tip'] ?? 'borc';
            if (tip == 'alacak') {
              incomeMap[projeId] = (incomeMap[projeId] ?? 0) + tutarTL;
            } else if (tip == 'borc') {
              expenseMap[projeId] = (expenseMap[projeId] ?? 0) + tutarTL;
            }
          }
        } catch (_) {}
      }));

      // 4) ProjectFinance nesnelerini oluştur
      // Önce mevcut project_finance dokümanlarını paralel oku (budgetedAmount için)
      final existingDocs = <String, Map<String, dynamic>>{};
      await Future.wait(projectIds.map((pid) async {
        try {
          final doc = await _db.collection('project_finance').doc(pid).get();
          if (doc.exists) existingDocs[pid] = doc.data() ?? {};
        } catch (_) {}
      }));

      for (final pid in projectIds) {
        final income = incomeMap[pid] ?? 0;
        final expense = expenseMap[pid] ?? 0;
        final existing = existingDocs[pid] ?? {};
        final budgeted = ((existing['budgetedAmount'] ?? 0) as num).toDouble();
        result[pid] = ProjectFinance(
          projectId: pid,
          totalIncome: income,
          totalExpenses: expense,
          budgetedAmount: budgeted,
        );
        // Sadece değerler değiştiyse project_finance dokümanını güncelle
        final cachedIncome = ((existing['totalIncome'] ?? 0) as num).toDouble();
        final cachedExpense = ((existing['totalExpenses'] ?? 0) as num).toDouble();
        if ((cachedIncome - income).abs() > 0.01 || (cachedExpense - expense).abs() > 0.01) {
          unawaited(_db.collection('project_finance').doc(pid).set({
            'totalIncome': income,
            'totalExpenses': expense,
          }, SetOptions(merge: true)));
        }
      }
    } catch (e) {
      developer.log('Toplu finans hesaplama hatası: $e');
    }
    return result;
  }

  /// Proje finansmanını güncelle
  Future<void> _updateProjectFinance(String projectId) async {
    try {
      final snapshot = await _db
          .collection('project_finance')
          .doc(projectId)
          .collection('transactions')
          .get();

      double totalIncome = 0;
      double totalExpenses = 0;

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final amount = (data['amount'] ?? 0).toDouble();
        if (data['type'] == 'income') {
          totalIncome += amount;
        } else {
          totalExpenses += amount;
        }
      }

      await _db.collection('project_finance').doc(projectId).set({
        'totalIncome': totalIncome,
        'totalExpenses': totalExpenses,
      }, SetOptions(merge: true));
    } catch (e) {
      developer.log('Proje finansmanı güncelleme hatası: $e');
    }
  }

  // ============== ŞİRKET FİNANSMANI ==============

  /// Şirket finansmanı al
  Future<CompanyFinance> getCompanyFinance(String companyId) async {
    try {
      final doc = await _db.collection('company_finance').doc(companyId).get();
      if (doc.exists) {
        return CompanyFinance.fromMap(doc.data() as Map<String, dynamic>);
      }
      return CompanyFinance(
        companyId: companyId,
        lastUpdated: DateTime.now(),
      );
    } catch (e) {
      developer.log('Şirket finansmanı yükleme hatası: $e');
      rethrow;
    }
  }

  /// Şirket finansmanını güncelle
  Future<void> _updateCompanyFinance(String companyId) async {
    try {
      final projects = await _db
          .collection('projects')
          .where('companyId', isEqualTo: companyId)
          .get();

      double totalIncome = 0;
      double totalExpenses = 0;
      List<String> projectIds = [];

      // Tüm project finance dokümantasyonlarını paralel al
      final financeFutures = <Future<DocumentSnapshot>>[
        for (var doc in projects.docs)
          _db.collection('project_finance').doc(doc.id).get()
      ];

      final financeSnapshots = await Future.wait(financeFutures);

      for (int i = 0; i < projects.docs.length; i++) {
        final projectId = projects.docs[i].id;
        projectIds.add(projectId);

        final financeDoc = financeSnapshots[i];
        if (financeDoc.exists) {
          final data = financeDoc.data() as Map<String, dynamic>;
          totalIncome += (data['totalIncome'] ?? 0).toDouble();
          totalExpenses += (data['totalExpenses'] ?? 0).toDouble();
        }
      }

      await _db.collection('company_finance').doc(companyId).set({
        'companyId': companyId,
        'totalIncome': totalIncome,
        'totalExpenses': totalExpenses,
        'projectIds': projectIds,
        'profit': totalIncome - totalExpenses,
        'profitMargin': totalIncome > 0 ? ((totalIncome - totalExpenses) / totalIncome) * 100 : 0,
        'lastUpdated': DateTime.now(),
      });

      developer.log('Şirket finansmanı güncellendi');
    } catch (e) {
      developer.log('Şirket finansmanı güncelleme hatası: $e');
    }
  }

  /// Şirket finansmanı akışı
  Stream<CompanyFinance> getCompanyFinanceStream(String companyId) {
    return _db.collection('company_finance').doc(companyId).snapshots().map((doc) {
      if (doc.exists) {
        return CompanyFinance.fromMap(doc.data() as Map<String, dynamic>);
      }
      return CompanyFinance(companyId: companyId, lastUpdated: DateTime.now());
    });
  }

  /// Projelerin finansmanı akışı
  Stream<List<Project>> getProjectsStream(String companyId) {
    return _db
        .collection('projects')
        .where('companyId', isEqualTo: companyId)
        .snapshots()
        .asyncMap((snapshot) async {
            final projects = snapshot.docs
                .where((doc) {
                  final data = doc.data();
                  return (data['isArchived'] ?? false) == false;
                })
                .map((doc) => Project.fromMap(doc.data(), doc.id))
                .toList();

            // createdAt'e göre sırala (en yeni en üstte) — ağır Firestore okuması kaldırıldı
            projects.sort((a, b) {
              final aDate = a.createdAt;
              final bDate = b.createdAt;
              return bDate.compareTo(aDate);
            });

            return projects;
        });
  }
}

