// ignore_for_file: prefer_const_constructors, use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../main.dart';
import 'community_detail_screen.dart';
import '../../services/app_localizations.dart'; // IMPORT LOCALIZATION

class BrowseCommunitiesScreen extends StatelessWidget {
  const BrowseCommunitiesScreen({super.key});

  // --- LOGIC: FOLLOW ---
  Future<void> _followCommunity(String communityId, String userId) async {
    try {
      await FirebaseFirestore.instance
          .collection('communities')
          .doc(communityId)
          .update({
        'followers': FieldValue.arrayUnion([userId])
      });
      // Tidak perlu setState karena StreamBuilder akan otomatis refresh UI
    } catch (e) {
      debugPrint("Error following community: $e");
    }
  }

  // --- LOGIC: UNFOLLOW ---
  Future<void> _unfollowCommunity(String communityId, String userId) async {
    try {
      await FirebaseFirestore.instance
          .collection('communities')
          .doc(communityId)
          .update({
        'followers': FieldValue.arrayRemove([userId])
      });
    } catch (e) {
      debugPrint("Error unfollowing community: $e");
    }
  }

  // --- LOGIC: SHOW CONFIRMATION DIALOG ---
  void _showUnfollowDialog(BuildContext context, String communityId, String communityName, String userId) {
    // LOCALIZATION fallback simple
    // Jika Anda ingin menggunakan t.translate di sini, Anda perlu passing instance 't' ke fungsi ini
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Unfollow $communityName?"),
        content: Text("Apakah Anda yakin ingin berhenti mengikuti komunitas ini?"), // Ganti dengan t.translate jika perlu
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text("Batal", style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx); // Tutup dialog
              _unfollowCommunity(communityId, userId); // Eksekusi unfollow
            },
            child: Text("Unfollow", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    // LOCALIZATION
    var t = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(t.translate('comm_explore_title'))), // "Explore Channels"
      // Menggunakan SafeArea untuk menghindari masalah layout di edge screen saat transisi
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('communities').snapshots(),
          builder: (context, snapshot) {
            // Tampilkan loading yang memiliki ukuran pasti, bukan shrink
            if (!snapshot.hasData) {
              return Center(child: CircularProgressIndicator());
            }

            final allDocs = snapshot.data!.docs;
            
            // Sorting logic
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
              // PENTING: PageStorageKey mencegah list di-rebuild ulang dari nol saat navigasi kembali
              key: const PageStorageKey('browse_communities_list'),
              padding: EdgeInsets.all(16),
              // Physics memastikan scroll view selalu punya constraints yang valid
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: sortedDocs.length,
              itemBuilder: (context, index) {
                final doc = sortedDocs[index];
                final data = doc.data() as Map<String, dynamic>;
                
                final String name = data['name'] ?? 'Unnamed';
                final String? imageUrl = data['imageUrl'];
                final String category = data['category'] ?? 'casual';
                final List followers = data['followers'] ?? [];
                
                // Cek status follow
                final bool isFollowing = user != null && followers.contains(user.uid);

                IconData badgeIcon = Icons.tag_faces;
                Color badgeColor = Colors.grey;
                if (category == 'pnj_official') { 
                  badgeIcon = Icons.account_balance; 
                  badgeColor = TwitterTheme.blue; 
                } else if (category == 'partner_official') { 
                  badgeIcon = Icons.verified; 
                  badgeColor = Colors.blueGrey; 
                }

                // RepaintBoundary mengisolasi render item agar tidak crash saat transisi halaman
                return RepaintBoundary(
                  child: Card(
                    margin: EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: ListTile(
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4), // Sedikit penyesuaian padding
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
                          Text("${followers.length} ${t.translate('comm_followers_count')}", style: TextStyle(fontSize: 12)),
                        ],
                      ),
                      // --- BAGIAN UTAMA YANG DIMODIFIKASI ---
                      trailing: isFollowing 
                        ? IconButton(
                            tooltip: "Unfollow",
                            icon: Icon(Icons.check_circle, color: Colors.green, size: 28),
                            onPressed: () {
                              if (user != null) {
                                _showUnfollowDialog(context, doc.id, name, user.uid);
                              }
                            },
                          )
                        : IconButton(
                            tooltip: "Follow",
                            // Menggunakan icon Add (+) sesuai request
                            icon: Icon(Icons.add_circle, color: TwitterTheme.blue, size: 28),
                            onPressed: () {
                              if (user != null) {
                                _followCommunity(doc.id, user.uid);
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text("Please login to follow channels"))
                                );
                              }
                            },
                          ),
                      // --- END MODIFIKASI ---
                      onTap: () {
                        // Menggunakan push biasa agar animasi default platform digunakan (lebih stabil)
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