// ignore_for_file: prefer_const_constructors
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'create_community_screen.dart';
import 'community_detail_screen.dart';
import 'browse_communities_screen.dart'; // IMPORT FILE BARU
import '../../main.dart';

class CommunityListTab extends StatelessWidget {
  const CommunityListTab({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return Center(child: Text("Login required"));

    final double topContentPadding = MediaQuery.of(context).padding.top + kToolbarHeight;

    return Scaffold(
      backgroundColor: Colors.transparent, 
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 100.0),
        child: FloatingActionButton.extended(
          onPressed: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => CreateCommunityScreen()));
          },
          label: Text("Create Community"),
          icon: Icon(Icons.add),
          backgroundColor: TwitterTheme.blue,
          elevation: 4,
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('communities')
                  .where('members', arrayContains: user.uid)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return Center(child: CircularProgressIndicator());

                final docs = snapshot.data?.docs ?? [];
                
                // HEADER BUTTON: Browse/Explore (Selalu muncul di paling atas list)
                Widget browseButton = Padding(
                  padding: EdgeInsets.only(top: topContentPadding, left: 16, right: 16, bottom: 10),
                  child: InkWell(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BrowseCommunitiesScreen())),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: TwitterTheme.blue.withOpacity(0.5)),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.explore, color: TwitterTheme.blue),
                          SizedBox(width: 8),
                          Text("Browse & Join Communities", style: TextStyle(fontWeight: FontWeight.bold, color: TwitterTheme.blue, fontSize: 16)),
                        ],
                      ),
                    ),
                  ),
                );

                if (docs.isEmpty) {
                  return Stack(
                    children: [
                      // Tombol Browse tetap ada walau kosong
                      Align(alignment: Alignment.topCenter, child: browseButton),
                      
                      Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(height: 60), // Spasi agar tidak numpuk tombol browse
                            Icon(Icons.groups_2_outlined, size: 80, color: Colors.grey.withOpacity(0.5)),
                            SizedBox(height: 16),
                            Text("You haven't joined any communities.", style: TextStyle(color: Colors.grey)),
                          ],
                        ),
                      ),
                    ],
                  );
                }

                return ListView.builder(
                  padding: EdgeInsets.only(bottom: 80),
                  itemCount: docs.length + 1, // +1 untuk header browse
                  itemBuilder: (context, index) {
                    // Item pertama adalah tombol Browse
                    if (index == 0) return browseButton;

                    final doc = docs[index - 1];
                    final data = doc.data() as Map<String, dynamic>;
                    
                    final String name = data['name'] ?? 'Unnamed';
                    final String? imageUrl = data['imageUrl'];
                    final int memberCount = (data['members'] is List) ? (data['members'] as List).length : 0;

                    return Card(
                      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: ListTile(
                        contentPadding: EdgeInsets.all(12),
                        leading: CircleAvatar(
                          radius: 28,
                          backgroundColor: TwitterTheme.blue.withOpacity(0.1),
                          backgroundImage: imageUrl != null ? CachedNetworkImageProvider(imageUrl) : null,
                          child: imageUrl == null ? Text(name[0].toUpperCase(), style: TextStyle(color: TwitterTheme.blue, fontWeight: FontWeight.bold)) : null,
                        ),
                        title: Text(name, style: TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text("$memberCount Members"),
                        trailing: Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
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
          ),
        ],
      ),
    );
  }
}