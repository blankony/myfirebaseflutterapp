// ignore_for_file: prefer_const_constructors
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../widgets/blog_post_card.dart';
import '../../main.dart';
import 'community_settings_screen.dart'; 
import '../create_post_screen.dart'; 
import '../../services/overlay_service.dart'; // Add this

class CommunityDetailScreen extends StatefulWidget {
  final String communityId;
  final Map<String, dynamic> communityData;

  const CommunityDetailScreen({
    super.key,
    required this.communityId,
    required this.communityData,
  });

  @override
  State<CommunityDetailScreen> createState() => _CommunityDetailScreenState();
}

class _CommunityDetailScreenState extends State<CommunityDetailScreen> {
  
  Future<void> _toggleJoin(bool isMember) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      if (isMember) {
        // LEAVE
        await FirebaseFirestore.instance.collection('communities').doc(widget.communityId).update({
          'members': FieldValue.arrayRemove([user.uid])
        });
        if(mounted) OverlayService().showTopNotification(context, "Left community", Icons.output, (){});
        Navigator.pop(context); // Keluar dari halaman setelah leave
      } else {
        // JOIN
        await FirebaseFirestore.instance.collection('communities').doc(widget.communityId).update({
          'members': FieldValue.arrayUnion([user.uid])
        });
        if(mounted) OverlayService().showTopNotification(context, "Joined community!", Icons.check_circle, (){}, color: Colors.green);
      }
    } catch (e) {
      if(mounted) OverlayService().showTopNotification(context, "Action failed", Icons.error, (){}, color: Colors.red);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    
    // Gunakan StreamBuilder untuk detail agar update member realtime
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('communities').doc(widget.communityId).snapshots(),
      builder: (context, snapshot) {
        // Gunakan data realtime jika ada, jika tidak pakai data awal
        final data = snapshot.hasData && snapshot.data!.exists 
            ? snapshot.data!.data() as Map<String, dynamic> 
            : widget.communityData;

        final ownerId = data['ownerId'];
        final List admins = (data['admins'] is List) ? data['admins'] : [];
        final List members = (data['members'] is List) ? data['members'] : [];
        
        final bool isOwner = user?.uid == ownerId;
        final bool isAdmin = admins.contains(user?.uid);
        final bool isMember = members.contains(user?.uid);
        final bool canModerate = isOwner || isAdmin;

        return Scaffold(
          appBar: AppBar(
            title: Text(data['name'] ?? 'Community', style: TextStyle(fontWeight: FontWeight.bold)),
            actions: [
              if (canModerate)
                IconButton(
                  icon: Icon(Icons.settings_outlined),
                  onPressed: () {
                    Navigator.push(context, MaterialPageRoute(
                      builder: (_) => CommunitySettingsScreen(
                        communityId: widget.communityId,
                        communityData: data,
                        isOwner: isOwner,
                        isAdmin: isAdmin,
                      )
                    ));
                  },
                )
            ],
          ),
          
          // FAB hanya muncul jika sudah jadi MEMBER
          floatingActionButton: isMember ? FloatingActionButton(
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(
                builder: (_) => CreatePostScreen(initialData: {'communityId': widget.communityId})
              ));
            },
            backgroundColor: TwitterTheme.blue,
            child: Icon(Icons.post_add, color: Colors.white),
          ) : null,
          
          body: Column(
            children: [
              // Header Info
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 32,
                          backgroundColor: TwitterTheme.blue,
                          backgroundImage: data['imageUrl'] != null ? CachedNetworkImageProvider(data['imageUrl']) : null,
                          child: data['imageUrl'] == null ? Text((data['name']??'C')[0], style: TextStyle(fontSize: 28, color: Colors.white)) : null,
                        ),
                        SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(data['description'] ?? "", style: TextStyle(color: Colors.grey[600])),
                              SizedBox(height: 8),
                              Text("${members.length} Members", style: TextStyle(fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 16),
                    // TOMBOL JOIN / LEAVE
                    SizedBox(
                      width: double.infinity,
                      child: isOwner 
                        ? OutlinedButton(onPressed: null, child: Text("You are Owner")) // Owner ga bisa leave
                        : ElevatedButton(
                            onPressed: () => _toggleJoin(isMember),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isMember ? Colors.red.withOpacity(0.1) : TwitterTheme.blue,
                              foregroundColor: isMember ? Colors.red : Colors.white,
                              elevation: 0,
                            ),
                            child: Text(isMember ? "Leave Community" : "Join Community"),
                          ),
                    ),
                  ],
                ),
              ),
              
              // FEED
              Expanded(
                child: isMember 
                  ? StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('posts')
                          .where('communityId', isEqualTo: widget.communityId)
                          .orderBy('timestamp', descending: true)
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) return Center(child: CircularProgressIndicator());
                        final docs = snapshot.data?.docs ?? [];
                        if (docs.isEmpty) return Center(child: Text("No posts yet."));

                        return ListView.builder(
                          padding: EdgeInsets.only(bottom: 80),
                          itemCount: docs.length,
                          itemBuilder: (context, index) {
                            final post = docs[index];
                            final postData = post.data() as Map<String, dynamic>;
                            
                            final bool isPostOwner = postData['userId'] == user?.uid;
                            final bool showDeleteOption = isPostOwner || canModerate;

                            return BlogPostCard(
                              postId: post.id,
                              postData: postData,
                              isOwner: showDeleteOption,
                              heroContextId: 'community_${widget.communityId}', 
                            );
                          },
                        );
                      },
                    )
                  : Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.lock_outline, size: 64, color: Colors.grey),
                          SizedBox(height: 16),
                          Text("Join to see posts", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
              ),
            ],
          ),
        );
      }
    );
  }
}