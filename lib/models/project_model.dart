import 'package:cloud_firestore/cloud_firestore.dart';

// Proje Aşaması Enum
enum ProjectPhaseStatus { planning, ongoing, completed, delayed }

enum ProjectStatus { planning, ongoing, completed, cancelled }

enum FinanceCategory { income, labor, materials, equipment, other }

// Proje Modeli
class Project {
  final String id;
  final String name;
  final String? description;
  final DateTime startDate;
  final DateTime? endDate;
  final ProjectStatus status;
  final String currentPhase;
  final double totalBudget;
  final DateTime createdAt;
  final String companyId;
  final bool isArchived;

  Project({
    required this.id,
    required this.name,
    this.description,
    required this.startDate,
    this.endDate,
    this.status = ProjectStatus.planning,
    this.currentPhase = 'planning',
    this.totalBudget = 0,
    required this.createdAt,
    required this.companyId,
    this.isArchived = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'description': description,
      'startDate': startDate,
      'endDate': endDate,
      'status': status.name,
      'currentPhase': currentPhase,
      'totalBudget': totalBudget,
      'createdAt': createdAt,
      'companyId': companyId,
      'isArchived': isArchived,
    };
  }

  factory Project.fromMap(Map<String, dynamic> map, String id) {
    return Project(
      id: id,
      name: map['name'] ?? '',
      description: map['description'],
      startDate: (map['startDate'] as Timestamp).toDate(),
      endDate: map['endDate'] != null ? (map['endDate'] as Timestamp).toDate() : null,
      status: ProjectStatus.values.firstWhere(
        (e) => e.name == map['status'],
        orElse: () => ProjectStatus.planning,
      ),
      currentPhase: map['currentPhase'] ?? 'planning',
      totalBudget: (map['totalBudget'] ?? 0).toDouble(),
      createdAt: (map['createdAt'] as Timestamp).toDate(),
      companyId: map['companyId'] ?? '',
      isArchived: map['isArchived'] ?? false,
    );
  }
}

// Proje Aşaması Modeli
class ProjectPhase {
  final String id;
  final String name;
  final DateTime startDate;
  final DateTime? endDate;
  final ProjectPhaseStatus status;
  final double progress; // 0-100
  final String? description;

  ProjectPhase({
    required this.id,
    required this.name,
    required this.startDate,
    this.endDate,
    this.status = ProjectPhaseStatus.planning,
    this.progress = 0,
    this.description,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'startDate': startDate,
      'endDate': endDate,
      'status': status.name,
      'progress': progress,
      'description': description,
    };
  }

  factory ProjectPhase.fromMap(Map<String, dynamic> map) {
    return ProjectPhase(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      startDate: (map['startDate'] as Timestamp).toDate(),
      endDate: map['endDate'] != null ? (map['endDate'] as Timestamp).toDate() : null,
      status: ProjectPhaseStatus.values.firstWhere(
        (e) => e.name == map['status'],
        orElse: () => ProjectPhaseStatus.planning,
      ),
      progress: (map['progress'] ?? 0).toDouble(),
      description: map['description'],
    );
  }
}

// Finansal İşlem Modeli
class FinanceTransaction {
  final String id;
  final DateTime date;
  final String description;
  final double amount;
  final FinanceCategory category;
  final String type; // 'income' or 'expense'
  final String? reference; // Teklif, İş Takip vb.
  final DateTime createdAt;

  FinanceTransaction({
    required this.id,
    required this.date,
    required this.description,
    required this.amount,
    required this.category,
    required this.type,
    this.reference,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'date': date,
      'description': description,
      'amount': amount,
      'category': category.name,
      'type': type,
      'reference': reference,
      'createdAt': createdAt,
    };
  }

  factory FinanceTransaction.fromMap(Map<String, dynamic> map) {
    return FinanceTransaction(
      id: map['id'] ?? '',
      date: (map['date'] as Timestamp).toDate(),
      description: map['description'] ?? '',
      amount: (map['amount'] ?? 0).toDouble(),
      category: FinanceCategory.values.firstWhere(
        (e) => e.name == map['category'],
        orElse: () => FinanceCategory.other,
      ),
      type: map['type'] ?? 'expense',
      reference: map['reference'],
      createdAt: (map['createdAt'] as Timestamp).toDate(),
    );
  }
}

// Proje Finansman Özeti
class ProjectFinance {
  final String projectId;
  final double totalIncome;
  final double totalExpenses;
  final double budgetedAmount;
  final List<FinanceTransaction> transactions;

  ProjectFinance({
    required this.projectId,
    this.totalIncome = 0,
    this.totalExpenses = 0,
    this.budgetedAmount = 0,
    this.transactions = const [],
  });

  double get profit => totalIncome - totalExpenses;
  double get profitMargin => totalIncome > 0 ? (profit / totalIncome) * 100 : 0;
  double get budgetUsage => budgetedAmount > 0 ? (totalExpenses / budgetedAmount) * 100 : 0;

  Map<String, dynamic> toMap() {
    return {
      'projectId': projectId,
      'totalIncome': totalIncome,
      'totalExpenses': totalExpenses,
      'budgetedAmount': budgetedAmount,
      'profit': profit,
      'profitMargin': profitMargin,
    };
  }
}

// Şirket Finansman Özeti
class CompanyFinance {
  final String companyId;
  final double totalIncome;
  final double totalExpenses;
  final List<String> projectIds;
  final DateTime lastUpdated;

  CompanyFinance({
    required this.companyId,
    this.totalIncome = 0,
    this.totalExpenses = 0,
    this.projectIds = const [],
    required this.lastUpdated,
  });

  double get profit => totalIncome - totalExpenses;
  double get profitMargin => totalIncome > 0 ? (profit / totalIncome) * 100 : 0;
  int get activeProjects => projectIds.length;

  Map<String, dynamic> toMap() {
    return {
      'companyId': companyId,
      'totalIncome': totalIncome,
      'totalExpenses': totalExpenses,
      'projectIds': projectIds,
      'profit': profit,
      'profitMargin': profitMargin,
      'lastUpdated': lastUpdated,
    };
  }

  factory CompanyFinance.fromMap(Map<String, dynamic> map) {
    return CompanyFinance(
      companyId: map['companyId'] ?? '',
      totalIncome: (map['totalIncome'] ?? 0).toDouble(),
      totalExpenses: (map['totalExpenses'] ?? 0).toDouble(),
      projectIds: List<String>.from(map['projectIds'] ?? []),
      lastUpdated: (map['lastUpdated'] as Timestamp).toDate(),
    );
  }
}
