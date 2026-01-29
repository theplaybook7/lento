import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../models/project_model.dart';
import '../models/payment_model.dart';
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

      // Firestore otomatik ID ile koleksiyon oluştur
      await _db.collection('project_finance').doc(docRef.id).set({
        'projectId': docRef.id,
        'totalIncome': 0,
        'totalExpenses': 0,
        'budgetedAmount': totalBudget,
      });

      // Ruhsat dosyası oluştur
      await _db.collection('ruhsat').doc(docRef.id).set({
        'projectId': docRef.id,
        'createdAt': DateTime.now(),
        'documents': [],
      });

      // Şantiye dosyası oluştur
      await _db.collection('santiye').doc(docRef.id).set({
        'projectId': docRef.id,
        'createdAt': DateTime.now(),
        'photos': [],
        'documents': [],
      });

      // Şirket finansmanını güncelle
      await _updateCompanyFinance(companyId);

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

  /// Proje aşamasını ekle
  Future<void> addProjectPhase(String projectId, ProjectPhase phase) async {
    try {
      final phases = await _getProjectPhases(projectId);
      phases.add(phase);

      await _db.collection('project_phases').doc(projectId).set({
        'phases': phases.map((p) => p.toMap()).toList(),
      });

      developer.log('Aşama eklendi: ${phase.name}');
    } catch (e) {
      developer.log('Aşama ekleme hatası: $e');
      rethrow;
    }
  }

  /// Proje aşamalarını al
  Future<List<ProjectPhase>> getProjectPhases(String projectId) async {
    try {
      return await _getProjectPhases(projectId);
    } catch (e) {
      developer.log('Aşamalar yükleme hatası: $e');
      rethrow;
    }
  }

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

      await _db.collection('project_finance').doc(projectId).update({
        'totalIncome': totalIncome,
        'totalExpenses': totalExpenses,
      });
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
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .where((doc) {
              final data = doc.data();
              // İstemci tarafında isArchived filtrelemesi
              return (data['isArchived'] ?? false) == false;
            })
            .map((doc) => Project.fromMap(doc.data(), doc.id))
            .toList());
  }

  // ============== ÖDEME PLANI İŞLEMLERİ ==============

  /// Yeni ödeme planı oluştur
  Future<String> createPaymentPlan({
    required String projectId,
    required String firstName,
    required String lastName,
    required double totalAmount,
    required int installmentCount,
    required List<DateTime> installmentDates,
    required List<double> installmentPercentages,
  }) async {
    try {
      final docRef = await _db.collection('payment_plans').add({
        'projectId': projectId,
        'firstName': firstName,
        'lastName': lastName,
        'totalAmount': totalAmount,
        'installmentCount': installmentCount,
        'createdAt': DateTime.now(),
        'status': PaymentStatus.pending.name,
        'paidAmount': 0,
      });

      // Taksitleri oluştur (her biri için farklı yüzde)
      for (int i = 0; i < installmentCount; i++) {
        final installmentAmount = (totalAmount * installmentPercentages[i]) / 100;
        await _db.collection('payment_installments').add({
          'paymentPlanId': docRef.id,
          'projectId': projectId,
          'installmentNumber': i + 1,
          'amount': installmentAmount,
          'installmentPercentage': installmentPercentages[i],
          'dueDate': installmentDates[i],
          'paidDate': null,
          'isPaid': false,
          'notes': '',
          'createdAt': DateTime.now(),
        });
      }

      developer.log('Ödeme planı oluşturuldu: ${docRef.id}');
      return docRef.id;
    } catch (e) {
      developer.log('Ödeme planı oluşturma hatası: $e');
      rethrow;
    }
  }

  /// Proje için ödeme planlarını getir
  Future<List<PaymentPlan>> getProjectPaymentPlans(String projectId) async {
    try {
      final snapshot = await _db
          .collection('payment_plans')
          .where('projectId', isEqualTo: projectId)
          .orderBy('createdAt', descending: true)
          .get();

      return snapshot.docs
          .map((doc) => PaymentPlan.fromMap(doc.data(), doc.id))
          .toList();
    } catch (e) {
      developer.log('Ödeme planları yükleme hatası: $e');
      rethrow;
    }
  }

  /// Ödeme planının taksitlerini getir
  Future<List<PaymentInstallment>> getPaymentInstallments(String paymentPlanId) async {
    try {
      final snapshot = await _db
          .collection('payment_installments')
          .where('paymentPlanId', isEqualTo: paymentPlanId)
          .orderBy('installmentNumber', descending: false)
          .get();

      return snapshot.docs
          .map((doc) => PaymentInstallment.fromMap(doc.data(), doc.id))
          .toList();
    } catch (e) {
      developer.log('Taksitleri yükleme hatası: $e');
      rethrow;
    }
  }

  /// Taksiti ödendi olarak işaretle
  Future<void> markInstallmentAsPaid({
    required String installmentId,
    required String paymentPlanId,
    required String projectId,
    required double paidAmount,
    List<String>? photoUrls,
  }) async {
    try {
      final now = DateTime.now();
      
      // Mevcut taksiti al
      final currentInst = await _db.collection('payment_installments').doc(installmentId).get();
      final currentData = currentInst.data() as Map<String, dynamic>;
      final amount = (currentData['amount'] as num?)?.toDouble() ?? 0;
      final currentPaidAmount = (currentData['paidAmount'] as num?)?.toDouble() ?? 0;
      final newPaidAmount = currentPaidAmount + paidAmount;
      final isPaidComplete = newPaidAmount >= amount;
      
      // Taksiti güncelle
      await _db.collection('payment_installments').doc(installmentId).update({
        'isPaid': isPaidComplete,
        'paidAmount': newPaidAmount,
        'paidDate': isPaidComplete ? now : null,
        'photoUrls': photoUrls ?? [],
      });

      // Ödeme planının toplam ödenen tutarını güncelle
      final installments = await _db
          .collection('payment_installments')
          .where('paymentPlanId', isEqualTo: paymentPlanId)
          .get();

      double totalPaid = 0;
      for (var doc in installments.docs) {
        totalPaid += (doc.data()['paidAmount'] as num?)?.toDouble() ?? 0;
      }

      // Plan durumunu güncelle
      final plan = await _db.collection('payment_plans').doc(paymentPlanId).get();
      final planData = plan.data() as Map<String, dynamic>;
      final totalAmount = (planData['totalAmount'] as num?)?.toDouble() ?? 0;

      final newStatus = totalPaid >= totalAmount
          ? PaymentStatus.completed.name
          : PaymentStatus.partialPaid.name;

      await _db.collection('payment_plans').doc(paymentPlanId).update({
        'paidAmount': totalPaid,
        'status': newStatus,
      });

      // Proje gelirini güncelle
      await _updateProjectIncome(projectId, paidAmount);

      developer.log('Taksit ödendi işaretlendi: $installmentId, Tutar: $paidAmount');
    } catch (e) {
      developer.log('Taksit güncellemesi hatası: $e');
      rethrow;
    }
  }

  /// Proje gelirini güncelle
  Future<void> _updateProjectIncome(String projectId, double amount) async {
    try {
      final financeRef = _db.collection('project_finance').doc(projectId);
      final doc = await financeRef.get();
      
      if (doc.exists) {
        final currentIncome = (doc.data()?['totalIncome'] as num?)?.toDouble() ?? 0;
        await financeRef.update({
          'totalIncome': currentIncome + amount,
        });
      }

      developer.log('Proje geliri güncellendi: $projectId, Tutar: $amount');
    } catch (e) {
      developer.log('Proje geliri güncelleme hatası: $e');
      // Hata olsa da devam et, ana işlem yapıldı
    }
  }

  /// Yaklaşan taksitleri getir (bildirim için)
  Future<List<PaymentInstallment>> getUpcomingInstallments(String projectId, {int daysAhead = 7}) async {
    try {
      final now = DateTime.now();
      final futureDate = now.add(Duration(days: daysAhead));

      final snapshot = await _db
          .collection('payment_installments')
          .where('projectId', isEqualTo: projectId)
          .where('isPaid', isEqualTo: false)
          .get();

      return snapshot.docs
          .map((doc) => PaymentInstallment.fromMap(doc.data(), doc.id))
          .where((inst) => 
              inst.dueDate.isAfter(now) && 
              inst.dueDate.isBefore(futureDate) ||
              inst.dueDate.isAtSameMomentAs(now))
          .toList();
    } catch (e) {
      developer.log('Yaklaşan taksitleri yükleme hatası: $e');
      rethrow;
    }
  }

  /// Ödeme planına yeni taksit ekle
  Future<void> addPaymentInstallment(
    String paymentPlanId,
    int installmentNumber,
    double installmentPercentage,
    DateTime dueDate,
  ) async {
    try {
      // Ödeme planını al
      final planDoc = await _db.collection('payment_plans').doc(paymentPlanId).get();
      
      if (!planDoc.exists) {
        throw Exception('Ödeme planı bulunamadı');
      }

      final planData = planDoc.data() as Map<String, dynamic>;
      final projectId = planData['projectId'] as String?;
      final totalBudget = planData['totalAmount'] as double? ?? 0.0;

      // Yeni taksit için tutarı yüzde üzerinden hesapla
      final amount = (totalBudget * installmentPercentage) / 100;

      // Taksiti ekle
      await _db.collection('payment_installments').add({
        'paymentPlanId': paymentPlanId,
        'projectId': projectId,
        'installmentNumber': installmentNumber,
        'amount': amount,
        'installmentPercentage': installmentPercentage,
        'dueDate': dueDate,
        'isPaid': false,
        'paidAmount': 0.0,
        'paidDate': null,
        'photoUrls': [],
        'createdAt': DateTime.now(),
      });

      developer.log('Taksit eklendi: $installmentNumber');
    } catch (e) {
      developer.log('Taksit ekleme hatası: $e');
      rethrow;
    }
  }

  /// Ödeme planını sil

  Future<void> deletePaymentPlan(String paymentPlanId) async {
    try {
      // Taksitleri sil - paralel
      final installments = await _db
          .collection('payment_installments')
          .where('paymentPlanId', isEqualTo: paymentPlanId)
          .get();

      final deleteFutures = [
        // Taksitleri paralel sil
        for (var doc in installments.docs)
          doc.reference.delete(),
        // Planı sil
        _db.collection('payment_plans').doc(paymentPlanId).delete(),
      ];

      await Future.wait(deleteFutures);

      developer.log('Ödeme planı silindi: $paymentPlanId');
    } catch (e) {
      developer.log('Ödeme planı silme hatası: $e');
      rethrow;
    }
  }
}

