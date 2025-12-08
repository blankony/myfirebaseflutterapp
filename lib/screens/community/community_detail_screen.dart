// ignore_for_file: prefer_const_constructors
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../widgets/blog_post_card.dart';
import '../../main.dart';
import 'community_settings_screen.dart'; 
import '../create_post_screen.dart'; 
import '../../services/overlay_service.dart';

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
  
  Future<void> _handleJoinAction(bool isMember, bool isPending) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      if (isMember) {
        // LEAVE (Langsung keluar)
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text("Leave Community?"),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text("Cancel")),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text("Leave", style: TextStyle(color: Colors.red))),
            ],
          )
        ) ?? false;

        if (!confirm) return;

        await FirebaseFirestore.instance.collection('communities').doc(widget.communityId).update({
          'members': FieldValue.arrayRemove([user.uid]),
          'admins': FieldValue.arrayRemove([user.uid]) // Hapus admin privilege jika ada
        });
        if(mounted) {
          OverlayService().showTopNotification(context, "Left community", Icons.output, (){});
          Navigator.pop(context);
        }
      } else if (isPending) {
        // CANCEL REQUEST
        await FirebaseFirestore.instance.collection('communities').doc(widget.communityId).update({
          'pendingMembers': FieldValue.arrayRemove([user.uid])
        });
        if(mounted) OverlayService().showTopNotification(context, "Request cancelled", Icons.close, (){});
      } else {
        // SEND REQUEST (Masuk ke pendingMembers)
        await FirebaseFirestore.instance.collection('communities').doc(widget.communityId).update({
          'pendingMembers': FieldValue.arrayUnion([user.uid])
        });
        if(mounted) OverlayService().showTopNotification(context, "Request sent to Admin", Icons.send, (){}, color: Colors.blue);
      }
    } catch (e) {
      if(mounted) OverlayService().showTopNotification(context, "Action failed", Icons.error, (){}, color: Colors.red);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('communities').doc(widget.communityId).snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.hasData && snapshot.data!.exists 
            ? snapshot.data!.data() as Map<String, dynamic> 
            : widget.communityData;

        final ownerId = data['ownerId'];
        final List admins = (data['admins'] is List) ? data['admins'] : [];
        final List members = (data['members'] is List) ? data['members'] : [];
        final List pendingMembers = (data['pendingMembers'] is List) ? data['pendingMembers'] : [];
        
        final bool isOwner = user?.uid == ownerId;
        final bool isAdmin = admins.contains(user?.uid);
        final bool isMember = members.contains(user?.uid);
        final bool isPending = pendingMembers.contains(user?.uid);
        final bool canModerate = isOwner || isAdmin;

        return Scaffold(
          appBar: AppBar(
            title: Text(data['name'] ?? 'Community', style: TextStyle(fontWeight: FontWeight.bold)),
            actions: [
              if (canModerate)
                IconButton(
                  icon: Stack(
                    children: [
                      Icon(Icons.settings_outlined),
                      // Tampilkan dot merah jika ada pending request
                      if (pendingMembers.isNotEmpty)
                        Positioned(
                          right: 0, top: 0,
                          child: Container(
                            width: 8, height: 8,
                            decoration: BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                          ),
                        )
                    ],
                  ),
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
                    
                    // TOMBOL ACTION
                    SizedBox(
                      width: double.infinity,
                      child: isOwner 
                        ? OutlinedButton(onPressed: null, child: Text("You are Owner"))
                        : ElevatedButton(
                            onPressed: () => _handleJoinAction(isMember, isPending),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isMember 
                                  ? Colors.red.withOpacity(0.1) 
                                  : (isPending ? Colors.grey.shade300 : TwitterTheme.blue),
                              foregroundColor: isMember 
                                  ? Colors.red 
                                  : (isPending ? Colors.grey.shade700 : Colors.white),
                              elevation: 0,
                            ),
                            child: Text(
                              isMember 
                                ? "Leave Community" 
                                : (isPending ? "Request Pending (Tap to Cancel)" : "Request to Join")
                            ),
                          ),
                    ),
                  ],
                ),
              ),
              
              // FEED (Hanya tampil jika member)
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
                            final pData = post.data() as Map<String, dynamic>;
                            final bool isPostOwner = pData['userId'] == user?.uid;
                            return BlogPostCard(
                              postId: post.id,
                              postData: pData,
                              isOwner: isPostOwner || canModerate,
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