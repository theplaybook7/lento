import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/payment_model.dart';
import '../services/firebase_service.dart';
import '../services/payment_notification_service.dart';
import 'payment_plan_details_screen.dart';
import 'create_payment_plan_screen.dart';

class PaymentPlansScreen extends StatefulWidget {
  final String projectId;
  final String projectName;

  const PaymentPlansScreen({
    required this.projectId,
    required this.projectName,
    super.key,
  });

  @override
  State<PaymentPlansScreen> createState() => _PaymentPlansScreenState();
}

class _PaymentPlansScreenState extends State<PaymentPlansScreen> {
  final _firebase = FirebaseService();
  final _notificationService = PaymentNotificationService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ödeme Planları'),
        backgroundColor: Colors.blueGrey.shade800,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_active),
            tooltip: 'Bildirim Kontrolü (Test)',
            onPressed: () {
              _notificationService.checkAndNotifyUpcomingInstallments(widget.projectId);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Yaklaşan taksitler kontrol edildi')),
              );
            },
          ),
        ],
      ),
      body: FutureBuilder<List<PaymentPlan>>(
        future: _firebase.getProjectPaymentPlans(widget.projectId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Text('Hata: ${snapshot.error}'),
            );
          }

          final plans = snapshot.data ?? [];

          if (plans.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.receipt_long_outlined, size: 48, color: Colors.grey),
                  const SizedBox(height: 12),
                  const Text('Henüz ödeme planı yok'),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () => _createNewPlan(),
                    icon: const Icon(Icons.add),
                    label: const Text('Yeni Ödeme Planı'),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: plans.length,
            itemBuilder: (context, index) {
              final plan = plans[index];
              final statusColor = _getStatusColor(plan.status);
              final statusText = _getStatusText(plan.status);

              return Card(
                elevation: 2,
                margin: const EdgeInsets.only(bottom: 12),
                child: InkWell(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (c) => PaymentPlanDetailsScreen(
                        paymentPlanId: plan.id,
                        planName: '${plan.firstName} ${plan.lastName}',
                      ),
                    ),
                  ).then((refresh) {
                    if (refresh == true) setState(() {});
                  }),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Başlık
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${plan.firstName} ${plan.lastName}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${plan.installmentCount} Taksit',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                statusText,
                                style: TextStyle(
                                  color: statusColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Tutar Bilgisi
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Toplam Tutar',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey,
                                  ),
                                ),
                                Text(
                                  '₺${NumberFormat('#,##0.00', 'tr_TR').format(plan.totalAmount)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Ödenen',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey,
                                  ),
                                ),
                                Text(
                                  '₺${NumberFormat('#,##0.00', 'tr_TR').format(plan.paidAmount)}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: Colors.green,
                                  ),
                                ),
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Kalan',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey,
                                  ),
                                ),
                                Text(
                                  '₺${NumberFormat('#,##0.00', 'tr_TR').format(plan.totalAmount - plan.paidAmount)}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: Colors.orange,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // İlerleme Çubuğu
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: plan.totalAmount > 0
                                ? (plan.paidAmount / plan.totalAmount).clamp(0, 1)
                                : 0,
                            minHeight: 6,
                            backgroundColor: Colors.grey[300],
                            valueColor: AlwaysStoppedAnimation<Color>(
                              plan.status == PaymentStatus.completed
                                  ? Colors.green
                                  : Colors.blue,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createNewPlan(),
        icon: const Icon(Icons.add),
        label: const Text('Yeni Ödeme Planı'),
        backgroundColor: Colors.blueGrey.shade700,
      ),
    );
  }

  void _createNewPlan() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (c) => CreatePaymentPlanScreen(
          projectId: widget.projectId,
          projectName: widget.projectName,
        ),
      ),
    );

    if (result == true) {
      setState(() {});
    }
  }

  Color _getStatusColor(PaymentStatus status) {
    switch (status) {
      case PaymentStatus.pending:
        return Colors.orange;
      case PaymentStatus.partialPaid:
        return Colors.blue;
      case PaymentStatus.completed:
        return Colors.green;
      case PaymentStatus.overdue:
        return Colors.red;
    }
  }

  String _getStatusText(PaymentStatus status) {
    switch (status) {
      case PaymentStatus.pending:
        return 'Beklemede';
      case PaymentStatus.partialPaid:
        return 'Kısmen Ödendi';
      case PaymentStatus.completed:
        return 'Tamamlandı';
      case PaymentStatus.overdue:
        return 'Gecikmiş';
    }
  }
}
