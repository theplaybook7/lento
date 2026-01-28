import 'package:cloud_firestore/cloud_firestore.dart';

enum PaymentStatus { pending, partialPaid, completed, overdue }

/// Ödeme Planı
class PaymentPlan {
  final String id;
  final String projectId;
  final String firstName;
  final String lastName;
  final double totalAmount;
  final int installmentCount;
  final DateTime createdAt;
  final PaymentStatus status;
  final double paidAmount;

  PaymentPlan({
    required this.id,
    required this.projectId,
    required this.firstName,
    required this.lastName,
    required this.totalAmount,
    required this.installmentCount,
    required this.createdAt,
    this.status = PaymentStatus.pending,
    this.paidAmount = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      'projectId': projectId,
      'firstName': firstName,
      'lastName': lastName,
      'totalAmount': totalAmount,
      'installmentCount': installmentCount,
      'createdAt': createdAt,
      'status': status.name,
      'paidAmount': paidAmount,
    };
  }

  factory PaymentPlan.fromMap(Map<String, dynamic> data, String id) {
    return PaymentPlan(
      id: id,
      projectId: data['projectId'] as String? ?? '',
      firstName: data['firstName'] as String? ?? '',
      lastName: data['lastName'] as String? ?? '',
      totalAmount: (data['totalAmount'] as num?)?.toDouble() ?? 0,
      installmentCount: data['installmentCount'] as int? ?? 0,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      status: PaymentStatus.values.firstWhere(
        (e) => e.name == data['status'],
        orElse: () => PaymentStatus.pending,
      ),
      paidAmount: (data['paidAmount'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// Ödeme Taksiti
class PaymentInstallment {
  final String id;
  final String paymentPlanId;
  final String projectId;
  final int installmentNumber;
  final double amount;
  final double installmentPercentage;
  final double paidAmount; // Kısmi ödeme için
  final DateTime dueDate;
  final DateTime? paidDate;
  final bool isPaid;
  final String notes;
  final List<String> photoUrls; // Ödeme kanıtı fotoğrafları

  PaymentInstallment({
    required this.id,
    required this.paymentPlanId,
    required this.projectId,
    required this.installmentNumber,
    required this.amount,
    required this.installmentPercentage,
    required this.dueDate,
    this.paidAmount = 0,
    this.paidDate,
    this.isPaid = false,
    this.notes = '',
    this.photoUrls = const [],
  });

  Map<String, dynamic> toMap() {
    return {
      'paymentPlanId': paymentPlanId,
      'projectId': projectId,
      'installmentNumber': installmentNumber,
      'amount': amount,
      'installmentPercentage': installmentPercentage,
      'paidAmount': paidAmount,
      'dueDate': dueDate,
      'paidDate': paidDate,
      'isPaid': isPaid,
      'notes': notes,
      'photoUrls': photoUrls,
    };
  }

  factory PaymentInstallment.fromMap(Map<String, dynamic> data, String id) {
    return PaymentInstallment(
      id: id,
      paymentPlanId: data['paymentPlanId'] as String? ?? '',
      projectId: data['projectId'] as String? ?? '',
      installmentNumber: data['installmentNumber'] as int? ?? 0,
      amount: (data['amount'] as num?)?.toDouble() ?? 0,
      installmentPercentage: (data['installmentPercentage'] as num?)?.toDouble() ?? 0,
      dueDate: (data['dueDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      paidAmount: (data['paidAmount'] as num?)?.toDouble() ?? 0,
      paidDate: (data['paidDate'] as Timestamp?)?.toDate(),
      isPaid: data['isPaid'] as bool? ?? false,
      notes: data['notes'] as String? ?? '',
      photoUrls: (data['photoUrls'] as List<dynamic>?)?.map((e) => e as String).toList() ?? [],
    );
  }

  bool isOverdue() {
    return !isPaid && DateTime.now().isAfter(dueDate);
  }
}
