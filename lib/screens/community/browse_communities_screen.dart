// ignore_for_file: prefer_const_constructors
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../main.dart';
import 'community_detail_screen.dart';
import '../../services/app_localizations.dart';

class BrowseCommunitiesScreen extends StatelessWidget {
  const BrowseCommunitiesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    var t = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(t.translate('comm_explore_title')), // "Jelajahi Komunitas"
        elevation: 0,
      ),
      // SafeArea memastikan konten tidak tertutup notch/status bar
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('communities').snapshots(),
          builder: (context, snapshot) {
            // Loading state sederhana
            if (!snapshot.hasData) {
              return Center(child: CircularProgressIndicator());
            }

            final allDocs = snapshot.data!.docs;
            
            // Logic Sorting: PNJ Official -> Partner -> Casual
            final sortedDocs = allDocs.toList()..sort((a, b) {
              final dataA = a.data() as Map<String, dynamic>;
              final dataB = b.data() as Map<String, dynamic>;
              
              final catA = dataA['category'] ?? 'casual';
              final catB = dataB['category'] ?? 'casual';
              
              final priority = {'pnj_official': 3, 'partner_official': 2, 'casual': 1};
              
              return (priority[catB] ?? 0).compareTo(priority[catA] ?? 0);
            });

            if (sortedDocs.isEmpty) {
              return Center(child: Text("Belum ada komunitas."));
            }

            return ListView.builder(
              // PENTING: Key ini menjaga posisi scroll saat navigasi Back
              key: const PageStorageKey('browse_communities_list'),
              padding: EdgeInsets.all(16),
              // Physics memastikan Viewport selalu valid
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

                // FIX: RepaintBoundary sangat penting untuk mencegah error layout saat navigasi
                return RepaintBoundary(
                  child: Card(
                    elevation: 2, // Sedikit elevation agar terlihat terpisah
                    margin: EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: InkWell(
                      // Gunakan InkWell untuk efek tap yang proper
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        // Navigasi standar tanpa custom transition yang aneh-aneh
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => CommunityDetailScreen(communityId: doc.id, communityData: data)
                        ));
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Row(
                          children: [
                            // Avatar
                            CircleAvatar(
                              radius: 28,
                              backgroundColor: badgeColor.withOpacity(0.1),
                              backgroundImage: imageUrl != null ? CachedNetworkImageProvider(imageUrl) : null,
                              child: imageUrl == null ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: TextStyle(color: badgeColor, fontWeight: FontWeight.bold)) : null,
                            ),
                            SizedBox(width: 12),
                            // Info Text
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          name, 
                                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (category == 'pnj_official') ...[
                                        SizedBox(width: 4),
                                        Icon(Icons.verified, size: 16, color: TwitterTheme.blue),
                                      ]
                                    ],
                                  ),
                                  SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Icon(badgeIcon, size: 12, color: badgeColor),
                                      SizedBox(width: 4),
                                      Text(
                                        "${followers.length} ${t.translate('comm_followers_count')}", 
                                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            // Action Button/Icon
                            if (isFollowing)
                              Icon(Icons.check_circle, color: Colors.green)
                            else
                              Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                          ],
                        ),
                      ),
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