// ignore_for_file: prefer_const_constructors
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'create_community_screen.dart';
import 'community_detail_screen.dart';
import 'browse_communities_screen.dart';
import '../../widgets/blog_post_card.dart';
import '../../main.dart';

class CommunityListTab extends StatelessWidget {
  const CommunityListTab({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final theme = Theme.of(context);
    if (user == null) return Center(child: Text("Login required"));

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CustomScrollView(
        slivers: [
          // 1. HEADER (Browse & Create Buttons)
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + kToolbarHeight, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BrowseCommunitiesScreen())),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          color: theme.cardColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: TwitterTheme.blue.withOpacity(0.3)),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: Offset(0, 4))],
                        ),
                        child: Column(
                          children: [
                            Icon(Icons.explore, color: TwitterTheme.blue, size: 28),
                            SizedBox(height: 8),
                            Text("Discover", style: TextStyle(fontWeight: FontWeight.bold, color: TwitterTheme.blue)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CreateCommunityScreen())),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          color: theme.cardColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.green.withOpacity(0.3)),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: Offset(0, 4))],
                        ),
                        child: Column(
                          children: [
                            Icon(Icons.group_add_rounded, color: Colors.green, size: 28),
                            SizedBox(height: 8),
                            Text("Create Channel", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 2. MY CHANNELS (Managed by Me)
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('communities')
                .where('ownerId', isEqualTo: user.uid)
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return SliverToBoxAdapter(child: SizedBox.shrink());
              }

              final myCommunities = snapshot.data!.docs;

              return SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                      child: Text("Your Channels", style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    ),
                    SizedBox(
                      height: 110,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        itemCount: myCommunities.length,
                        itemBuilder: (context, index) {
                          final doc = myCommunities[index];
                          final data = doc.data() as Map<String, dynamic>;
                          final String name = data['name'] ?? 'Channel';
                          final String? imageUrl = data['imageUrl'];

                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8.0),
                            child: GestureDetector(
                              onTap: () {
                                Navigator.push(context, MaterialPageRoute(
                                  builder: (_) => CommunityDetailScreen(communityId: doc.id, communityData: data)
                                ));
                              },
                              child: Column(
                                children: [
                                  Container(
                                    padding: EdgeInsets.all(2),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(color: TwitterTheme.blue, width: 2),
                                    ),
                                    child: CircleAvatar(
                                      radius: 30,
                                      backgroundColor: TwitterTheme.blue.withOpacity(0.1),
                                      backgroundImage: imageUrl != null ? CachedNetworkImageProvider(imageUrl) : null,
                                      child: imageUrl == null ? Text(name[0].toUpperCase(), style: TextStyle(fontWeight: FontWeight.bold, color: TwitterTheme.blue)) : null,
                                    ),
                                  ),
                                  SizedBox(height: 6),
                                  SizedBox(
                                    width: 70,
                                    child: Text(
                                      name, 
                                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500), 
                                      overflow: TextOverflow.ellipsis, 
                                      textAlign: TextAlign.center,
                                      maxLines: 1,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    Divider(height: 24, thickness: 8, color: theme.dividerColor.withOpacity(0.1)),
                  ],
                ),
              );
            },
          ),

          // 3. COMMUNITY POSTS FEED HEADER
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Text("Broadcasts Feed", style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            ),
          ),

          // 4. FEED CONTENT
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('communities').where('followers', arrayContains: user.uid).snapshots(),
            builder: (context, communitySnap) {
              if (!communitySnap.hasData) return SliverToBoxAdapter(child: Center(child: CircularProgressIndicator()));
              
              final followedCommunityIds = communitySnap.data!.docs.map((doc) => doc.id).toList();
              
              if (followedCommunityIds.isEmpty) {
                return SliverToBoxAdapter(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Column(
                        children: [
                          Icon(Icons.feed_outlined, size: 48, color: Colors.grey),
                          SizedBox(height: 16),
                          Text("Join channels to see broadcasts here.", style: TextStyle(color: Colors.grey)),
                        ],
                      ),
                    ),
                  ),
                );
              }

              return StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('posts')
                    .orderBy('timestamp', descending: true)
                    .limit(50) 
                    .snapshots(),
                builder: (context, postSnap) {
                  if (postSnap.connectionState == ConnectionState.waiting) return SliverToBoxAdapter(child: Center(child: CircularProgressIndicator()));
                  
                  final allPosts = postSnap.data?.docs ?? [];
                  final communityPosts = allPosts.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    return data['communityId'] != null && followedCommunityIds.contains(data['communityId']);
                  }).toList();

                  if (communityPosts.isEmpty) {
                    return SliverToBoxAdapter(
                      child: Center(
                        child: Padding(
                          padding: EdgeInsets.all(32), 
                          child: Text("No recent broadcasts from your channels.", style: TextStyle(color: Colors.grey))
                        )
                      )
                    );
                  }

                  return SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final post = communityPosts[index];
                        final pData = post.data() as Map<String, dynamic>;
                        return BlogPostCard(
                          postId: post.id,
                          postData: pData,
                          isOwner: pData['userId'] == user.uid, 
                          heroContextId: 'community_feed',
                        );
                      },
                      childCount: communityPosts.length,
                    ),
                  );
                },
              );
            },
          ),
          
          SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }
}