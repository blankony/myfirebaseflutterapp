// ignore_for_file: prefer_const_constructors
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../main.dart';
import '../../services/overlay_service.dart';
import 'community_detail_screen.dart';

class BrowseCommunitiesScreen extends StatelessWidget {
  const BrowseCommunitiesScreen({super.key});

  Future<void> _joinCommunity(BuildContext context, String communityId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await FirebaseFirestore.instance.collection('communities').doc(communityId).update({
        'members': FieldValue.arrayUnion([user.uid])
      });
      OverlayService().showTopNotification(context, "Joined successfully!", Icons.check_circle, (){}, color: Colors.green);
    } catch (e) {
      OverlayService().showTopNotification(context, "Failed to join", Icons.error, (){}, color: Colors.red);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text("Explore Communities", style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('communities').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }

          // Filter: Hanya tampilkan komunitas yang USER BELUM JOIN
          final allDocs = snapshot.data?.docs ?? [];
          final notJoinedDocs = allDocs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final List members = (data['members'] is List) ? data['members'] : [];
            return !members.contains(user?.uid);
          }).toList();

          if (notJoinedDocs.isEmpty) {
            return Center(child: Text("No new communities to join."));
          }

          return ListView.builder(
            padding: EdgeInsets.all(16),
            itemCount: notJoinedDocs.length,
            itemBuilder: (context, index) {
              final doc = notJoinedDocs[index];
              final data = doc.data() as Map<String, dynamic>;
              
              final String name = data['name'] ?? 'Unnamed';
              final String? imageUrl = data['imageUrl'];
              final int memberCount = (data['members'] is List) ? (data['members'] as List).length : 0;

              return Card(
                margin: EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: CircleAvatar(
                    radius: 24,
                    backgroundColor: TwitterTheme.blue.withOpacity(0.1),
                    backgroundImage: imageUrl != null ? CachedNetworkImageProvider(imageUrl) : null,
                    child: imageUrl == null ? Text(name[0].toUpperCase(), style: TextStyle(color: TwitterTheme.blue, fontWeight: FontWeight.bold)) : null,
                  ),
                  title: Text(name, style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text("$memberCount members"),
                  trailing: ElevatedButton(
                    onPressed: () => _joinCommunity(context, doc.id),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: TwitterTheme.blue,
                      foregroundColor: Colors.white,
                      shape: StadiumBorder(),
                      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    ),
                    child: Text("Join"),
                  ),
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(
                      builder: (_) => CommunityDetailScreen(communityId: doc.id, communityData: data)
                    ));
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}