import 'package:flutter/material.dart';
import '../models/project_model.dart';
import '../services/firebase_service.dart';
import '../project_core.dart';
import '../theme/app_theme.dart';
import 'project_details_screen.dart';

class ProjectArchiveScreen extends StatefulWidget {
  final String companyId;
  const ProjectArchiveScreen({super.key, required this.companyId});

  @override
  State<ProjectArchiveScreen> createState() => _ProjectArchiveScreenState();
}

class _ProjectArchiveScreenState extends State<ProjectArchiveScreen> {
  final _firebase = FirebaseService();

  Future<void> _unarchiveProject(String projectId) async {
    try {
      await _firebase.updateProject(projectId, {'isArchived': false});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Proje arşivden çıkarıldı')),
      );
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Proje Arşivi'),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        elevation: 1,
      ),
      body: FutureBuilder<List<Project>>(
        future: _firebase.getArchivedProjects(widget.companyId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'Hata: ${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Colors.red,
                  ),
                ),
              ),
            );
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.archive_outlined, size: 48, color: Colors.grey),
                  const SizedBox(height: 12),
                  const Text('Arşivlenmiş proje bulunamadı'),
                ],
              ),
            );
          }

          final projects = snapshot.data!;

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: projects.length,
            itemBuilder: (context, index) {
              final project = projects[index];

              return FutureBuilder<ProjectFinance>(
                future: _firebase.getProjectFinance(project.id),
                builder: (context, financeSnap) {
                  final finance = financeSnap.data;

                  return Card(
                    elevation: 2,
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.orange.withValues(alpha: 0.2),
                        child: const Icon(Icons.archive_outlined, color: Colors.orange),
                      ),
                      title: Text(
                        project.name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${project.startDate.day}.${project.startDate.month}.${project.startDate.year}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          if (finance != null)
                            Text(
                              'Kâr: ${formatNumber(finance.profit)} ₺',
                              style: TextStyle(
                                fontSize: 12,
                                color: finance.profit >= 0 ? Colors.green : Colors.red,
                              ),
                            ),
                        ],
                      ),
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'unarchive') {
                            _unarchiveProject(project.id);
                          } else if (value == 'view') {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (c) => ProjectDetailsScreen(projectId: project.id),
                              ),
                            );
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'view',
                            child: Row(
                              children: [
                                Icon(Icons.visibility_outlined),
                                SizedBox(width: 8),
                                Text('Görüntüle'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'unarchive',
                            child: Row(
                              children: [
                                Icon(Icons.unarchive_outlined, color: Colors.blue),
                                SizedBox(width: 8),
                                Text('Arşivden Çıkar'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
