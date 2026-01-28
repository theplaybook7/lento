import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'teklif_screen.dart';

class ArsivSayfasi extends StatelessWidget {
  const ArsivSayfasi({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Teklif Arşivi"),
        backgroundColor: Colors.blueGrey.shade800,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('teklifler')
            .orderBy('tarih', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          
          if (snapshot.data!.docs.isEmpty) {
            return const Center(child: Text("Henüz kaydedilmiş bir teklif yok."));
          }

          return ListView.builder(
            itemCount: snapshot.data!.docs.length,
            itemBuilder: (context, index) {
              var doc = snapshot.data!.docs[index];
              var data = doc.data() as Map<String, dynamic>;
              
              DateTime tarih;
              try {
                tarih = (data['tarih'] as Timestamp).toDate();
              } catch (e) {
                tarih = DateTime.now();
              }

              return Card(
                margin: const EdgeInsets.all(10),
                child: ListTile(
                  leading: const Icon(Icons.folder, color: Colors.amber, size: 40),
                  title: Text("${data['ilce']} / ${data['mahalle']}", style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text("${data['ada']} / ${data['parsel']} - ${tarih.day}.${tarih.month}.${tarih.year}"),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.blue),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => TeklifSayfasi(
                                mevcutTeklifData: data,
                                mevcutDocId: doc.id,
                              ),
                            ),
                          );
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () async {
                          bool? confirm = await showDialog(
                            context: context, 
                            builder: (c) => AlertDialog(
                              title: const Text("Sil?"), 
                              content: const Text("Bu teklif kalıcı olarak silinecek."),
                              actions: [
                                TextButton(onPressed: ()=>Navigator.pop(c, false), child: const Text("İPTAL")),
                                TextButton(onPressed: ()=>Navigator.pop(c, true), child: const Text("SİL")),
                              ],
                            )
                          );
                          
                          if(confirm == true) {
                            await doc.reference.delete();
                          }
                        },
                      )
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}