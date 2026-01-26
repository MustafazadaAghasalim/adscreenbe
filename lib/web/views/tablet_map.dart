import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class TabletMapView extends StatelessWidget {
  const TabletMapView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Live Tablet Status'), automaticallyImplyLeading: false),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('active_tablets').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return const Center(child: Text('No active tablets found.'));
          }

          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              final tabletId = docs[index].id;
              final battery = data['battery_percent'] ?? 0;
              final isOnline = data['status'] == 'online'; // Or check last_seen timestamp
              final lastSeen = (data['last_seen'] as Timestamp?)?.toDate();

              // Simple "Online" check: last seen within 2 minutes
              final bool actuallyOnline = lastSeen != null && 
                  DateTime.now().difference(lastSeen).inMinutes < 2;

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: actuallyOnline ? Colors.green : Colors.grey,
                    child: Icon(Icons.tablet_android, color: Colors.white),
                  ),
                  title: Text(tabletId, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(
                    'Battery: $battery% | ${actuallyOnline ? "Online" : "Offline"}\n'
                    'Last Seen: ${lastSeen?.toString() ?? "Never"}',
                  ),
                  trailing: Icon(Icons.chevron_right),
                  isThreeLine: true,
                ),
              );
            },
          );
        },
      ),
    );
  }
}
