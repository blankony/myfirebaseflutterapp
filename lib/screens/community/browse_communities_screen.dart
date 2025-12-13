// ignore_for_file: prefer_const_constructors
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../main.dart';
import 'community_detail_screen.dart';

class BrowseCommunitiesScreen extends StatelessWidget {
  const BrowseCommunitiesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(title: Text("Explore Channels")),
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('communities').snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return Center(child: CircularProgressIndicator());
            }

            final allDocs = snapshot.data!.docs;
            
            final sortedDocs = allDocs.toList()..sort((a, b) {
              final dataA = a.data() as Map<String, dynamic>;
              final dataB = b.data() as Map<String, dynamic>;
              
              final catA = dataA['category'] ?? 'casual';
              final catB = dataB['category'] ?? 'casual';
              
              // Priority Map
              final priority = {'pnj_official': 3, 'partner_official': 2, 'casual': 1};
              
              return (priority[catB] ?? 0).compareTo(priority[catA] ?? 0);
            });

            return ListView.builder(
              key: const PageStorageKey('browse_communities_list'),
              padding: EdgeInsets.all(16),
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: sortedDocs.length,
              itemBuilder: (context, index) {
                final doc = sortedDocs[index];
                final data = doc.data() as Map<String, dynamic>;
                
                final String name = data['name'] ?? 'Unnamed';
                final String? imageUrl = data['imageUrl'];
                final String category = data['category'] ?? 'casual';
                final List followers = data['followers'] ?? [];
                final bool isFollowing = followers.contains(user?.uid);

                IconData badgeIcon = Icons.tag_faces;
                Color badgeColor = Colors.grey;
                if (category == 'pnj_official') { 
                  badgeIcon = Icons.account_balance; 
                  badgeColor = TwitterTheme.blue; 
                } else if (category == 'partner_official') { 
                  badgeIcon = Icons.verified; 
                  badgeColor = Colors.blueGrey; 
                }

                return RepaintBoundary(
                  child: Card(
                    margin: EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: ListTile(
                      contentPadding: EdgeInsets.all(12),
                      leading: CircleAvatar(
                        radius: 28,
                        backgroundColor: badgeColor.withOpacity(0.1),
                        backgroundImage: imageUrl != null ? CachedNetworkImageProvider(imageUrl) : null,
                        child: imageUrl == null ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: TextStyle(color: badgeColor, fontWeight: FontWeight.bold)) : null,
                      ),
                      title: Row(
                        children: [
                          Expanded(child: Text(name, style: TextStyle(fontWeight: FontWeight.bold))),
                          if (category == 'pnj_official') Icon(Icons.verified, size: 16, color: TwitterTheme.blue),
                        ],
                      ),
                      subtitle: Row(
                        children: [
                          Icon(badgeIcon, size: 12, color: badgeColor),
                          SizedBox(width: 4),
                          Text("${followers.length} Followers", style: TextStyle(fontSize: 12)),
                        ],
                      ),
                      trailing: isFollowing 
                        ? Icon(Icons.check_circle, color: Colors.green)
                        : Icon(Icons.add_circle_outline, color: TwitterTheme.blue),
                      onTap: () {
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => CommunityDetailScreen(communityId: doc.id, communityData: data)
                        ));
                      },
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}