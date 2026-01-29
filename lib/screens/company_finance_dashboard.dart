import 'package:flutter/material.dart';
import '../models/project_model.dart';
import '../services/firebase_service.dart';
import '../project_core.dart';

class CompanyFinanceDashboard extends StatefulWidget {
  final String companyId;
  const CompanyFinanceDashboard({super.key, required this.companyId});

  @override
  State<CompanyFinanceDashboard> createState() => _CompanyFinanceDashboardState();
}

class _CompanyFinanceDashboardState extends State<CompanyFinanceDashboard> {
  late FirebaseService _firebase;

  @override
  void initState() {
    super.initState();
    _firebase = FirebaseService();
  }

  @override
  Widget build(BuildContext context) {
    final sistem = SistemYoneticisi();
    final yetkiVar = sistem.yetkiVarMi('muhasebe');

    if (!yetkiVar) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Şirket Muhasebesi'),
          backgroundColor: Colors.blueGrey.shade700,
          foregroundColor: Colors.white,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline, size: 64, color: Colors.grey.shade400),
                const SizedBox(height: 16),
                Text(
                  "Bu sayfayı görüntülemek için yetkiniz yok.",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Şirket Muhasebesi'),
        backgroundColor: Colors.blueGrey.shade700,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<List<Project>>(
        stream: _firebase.getProjectsStream(widget.companyId),
        builder: (context, projectsSnap) {
          if (projectsSnap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!projectsSnap.hasData || projectsSnap.data!.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.folder_open_outlined, size: 48, color: Colors.grey),
                  SizedBox(height: 12),
                  Text('Henüz proje yok'),
                ],
              ),
            );
          }

          final projects = projectsSnap.data!;

          return FutureBuilder<List<ProjectFinance>>(
            future: Future.wait(
              projects.map((p) => _firebase.getProjectFinance(p.id)).toList(),
            ),
            builder: (context, financeSnap) {
              if (financeSnap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              // Toplam hesapla
              double totalIncome = 0;
              double totalExpenses = 0;
              
              if (financeSnap.hasData) {
                for (var finance in financeSnap.data!) {
                  totalIncome += finance.totalIncome;
                  totalExpenses += finance.totalExpenses;
                }
              }

              final calculatedProfit = totalIncome - totalExpenses;
              final calculatedMargin = totalIncome > 0 ? (calculatedProfit / totalIncome) * 100 : 0.0;

              return SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Özet Kartları
                    Row(
                      children: [
                        Expanded(
                          child: _SummaryCard(
                            title: 'Toplam Gelir',
                            amount: totalIncome,
                            color: Colors.green,
                            icon: Icons.trending_up,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _SummaryCard(
                            title: 'Toplam Gider',
                            amount: totalExpenses,
                            color: Colors.red,
                            icon: Icons.trending_down,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    Row(
                      children: [
                        Expanded(
                          child: _SummaryCard(
                            title: 'Toplam Kâr',
                            amount: calculatedProfit,
                            color: calculatedProfit >= 0 ? Colors.blue : Colors.orange,
                            icon: Icons.paid,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _SummaryCard(
                            title: 'Kâr Marjı',
                            amount: calculatedMargin,
                            color: Colors.purple,
                            icon: Icons.pie_chart,
                            isPercentage: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Proje Bilgileri
                    Text(
                      'Aktif Projeler (${projects.length})',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),

                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: projects.length,
                      itemBuilder: (context, index) {
                        final project = projects[index];
                        final projectFin = financeSnap.hasData && index < financeSnap.data!.length 
                            ? financeSnap.data![index] 
                            : null;

                        return Card(
                          elevation: 2,
                          margin: const EdgeInsets.only(bottom: 12),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            project.name,
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '${project.startDate.day}.${project.startDate.month}.${project.startDate.year}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey.shade600,
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
                                        color: _getStatusColor(project.status).withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        project.status.name.toUpperCase(),
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: _getStatusColor(project.status),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                if (projectFin != null) ...[
                                  const SizedBox(height: 12),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      _InfoChip('Gelir: ${formatNumber(projectFin.totalIncome)} ₺', Colors.green),
                                      _InfoChip('Gider: ${formatNumber(projectFin.totalExpenses)} ₺', Colors.red),
                                      _InfoChip('Kâr: ${formatNumber(projectFin.profit)} ₺', Colors.blue),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Color _getStatusColor(ProjectStatus status) {
    switch (status) {
      case ProjectStatus.planning:
        return Colors.blue;
      case ProjectStatus.ongoing:
        return Colors.orange;
      case ProjectStatus.completed:
        return Colors.green;
      case ProjectStatus.cancelled:
        return Colors.red;
    }
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final double amount;
  final Color color;
  final IconData icon;
  final bool isPercentage;

  const _SummaryCard({
    required this.title,
    required this.amount,
    required this.color,
    required this.icon,
    this.isPercentage = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withValues(alpha: 0.2), color.withValues(alpha: 0.05)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(icon, color: color, size: 20),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            isPercentage ? '${amount.toStringAsFixed(1)}%' : '${formatNumber(amount)} ₺',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final Color color;

  const _InfoChip(this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(
        label,
        style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.bold),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      backgroundColor: color.withValues(alpha: 0.1),
      side: BorderSide(color: color.withValues(alpha: 0.3)),
    );
  }
}
