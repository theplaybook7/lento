import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../models/project_model.dart';
import '../project_core.dart';
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

  /// Proje finansmanı özetini al (gerçek cari hareketlerinden hesapla)
  Future<ProjectFinance> getProjectFinanceSummary(String projectId) async {
    try {
      final doc = await _db.collection('project_finance').doc(projectId).get();
      final data = doc.data() ?? {};

      // Bu projeye bağlı tüm carileri bul
      final sirketId = SistemYoneticisi().aktifSirket?.id ?? '';
      final cariSnap = await _db
          .collection('cari_hesaplar')
          .where('sirketId', isEqualTo: sirketId)
          .get();

      double totalIncome = 0;
      double totalExpenses = 0;

      // Her carinin bu projeye ait hareketlerini say
      for (final cariDoc in cariSnap.docs) {
        final cariData = cariDoc.data();
        final pids = List<String>.from(cariData['projectIds'] ?? []);
        final pid = cariData['projectId'] ?? '';
        if (!pids.contains(projectId) && pid != projectId) continue;

        final hareketSnap = await _db
            .collection('cari_hesaplar')
            .doc(cariDoc.id)
            .collection('hareketler')
            .where('projeId', isEqualTo: projectId)
            .get();

        for (final hDoc in hareketSnap.docs) {
          final hData = hDoc.data();
          final tutarTL = ((hData['tutarTL'] ?? hData['tutar'] ?? 0.0) as num).toDouble();
          final tip = hData['tip'] ?? 'borc';
          if (tip == 'alacak') {
            totalIncome += tutarTL;
          } else if (tip == 'borc') {
            totalExpenses += tutarTL;
          }
        }
      }

      // Cached değerleri güncelle
      final cachedIncome = (data['totalIncome'] ?? 0).toDouble();
      final cachedExpenses = (data['totalExpenses'] ?? 0).toDouble();
      if ((cachedIncome - totalIncome).abs() > 0.01 || (cachedExpenses - totalExpenses).abs() > 0.01) {
        _db.collection('project_finance').doc(projectId).set({
          'totalIncome': totalIncome,
          'totalExpenses': totalExpenses,
          'budgetedAmount': data['budgetedAmount'] ?? 0,
        }, SetOptions(merge: true));
      }

      return ProjectFinance(
        projectId: projectId,
        totalIncome: totalIncome,
        totalExpenses: totalExpenses,
        budgetedAmount: (data['budgetedAmount'] ?? 0).toDouble(),
      );
    } catch (e) {
      developer.log('Proje finansmanı özet yükleme hatası: $e');
      rethrow;
    }
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

            // Her proje için ruhsat son işlem tarihini al (islemler + akis_diyagrami)
            final Map<String, DateTime?> sonIslemMap = {};
            await Future.wait(projects.map((p) async {
              try {
                DateTime? sonIslem;
                // Hem islemler hem akis_diyagrami koleksiyonlarını kontrol et
                final results = await Future.wait([
                  _db.collection('ruhsat').doc(p.id).collection('islemler').get(),
                  _db.collection('ruhsat').doc(p.id).collection('akis_diyagrami').get(),
                ]);
                for (final snap in results) {
                  for (final doc in snap.docs) {
                    final gt = doc.data()['guncellendiTarihi'];
                    DateTime? t;
                    if (gt is Timestamp) t = gt.toDate();
                    if (t != null && (sonIslem == null || t.isAfter(sonIslem))) {
                      sonIslem = t;
                    }
                  }
                }
                sonIslemMap[p.id] = sonIslem;
              } catch (_) {
                sonIslemMap[p.id] = null;
              }
            }));

            // Hiç işlem yapılmamış en üstte, sonra en eski işlem tarihi en üstte
            projects.sort((a, b) {
              final aDate = sonIslemMap[a.id];
              final bDate = sonIslemMap[b.id];
              if (aDate == null && bDate == null) return 0;
              if (aDate == null) return -1; // a hiç işlem yok → üstte
              if (bDate == null) return 1;  // b hiç işlem yok → üstte
              return aDate.compareTo(bDate); // eski tarih üstte
            });

            return projects;
        });
  }
}

