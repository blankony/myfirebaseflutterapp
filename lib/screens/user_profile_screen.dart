// ignore_for_file: prefer_const_constructors
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/blog_post_card.dart'; 
import '../widgets/comment_tile.dart'; 
import '../main.dart'; 

final FirebaseAuth _auth = FirebaseAuth.instance;
final FirebaseFirestore _firestore = FirebaseFirestore.instance;

class UserProfileScreen extends StatefulWidget {
  final String userId;
  const UserProfileScreen({super.key, required this.userId});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> with TickerProviderStateMixin {
  late TabController _tabController;
  final User? _currentUser = _auth.currentUser;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _followUser() async {
    if (_currentUser == null) return;
    
    final batch = _firestore.batch();
    
    final myDocRef = _firestore.collection('users').doc(_currentUser!.uid);
    batch.update(myDocRef, {
      'following': FieldValue.arrayUnion([widget.userId])
    });
    
    final targetDocRef = _firestore.collection('users').doc(widget.userId);
    batch.update(targetDocRef, {
      'followers': FieldValue.arrayUnion([_currentUser!.uid])
    });
    
    try {
      await batch.commit();
    } catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to follow: $e')));
    }
  }

  Future<void> _unfollowUser() async {
    if (_currentUser == null) return;
    
    final batch = _firestore.batch();
    
    final myDocRef = _firestore.collection('users').doc(_currentUser!.uid);
    batch.update(myDocRef, {
      'following': FieldValue.arrayRemove([widget.userId])
    });
    
    final targetDocRef = _firestore.collection('users').doc(widget.userId);
    batch.update(targetDocRef, {
      'followers': FieldValue.arrayRemove([_currentUser!.uid])
    });
    
    try {
      await batch.commit();
    } catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to unfollow: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool isMyProfile = _currentUser?.uid == widget.userId;

    if (_currentUser == null) {
      return Scaffold(body: Center(child: Text("Please log in to view profiles.")));
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: _firestore.collection('users').doc(_currentUser!.uid).snapshots(),
      builder: (context, mySnapshot) {

        if (!mySnapshot.hasData) {
          return Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        
        final myData = mySnapshot.data!.data() as Map<String, dynamic>;
        final List<dynamic> myFollowingList = myData['following'] ?? [];
        final bool amIFollowing = myFollowingList.contains(widget.userId);

        // UI Utama
        return Scaffold(
          appBar: AppBar(
            title: Text("Profile"), 
            elevation: 0,
          ),
          body: NestedScrollView(
            headerSliverBuilder: (context, innerBoxIsScrolled) {
              return [
                SliverAppBar(
                  expandedHeight: 410.0, 
                  pinned: true, 
                  elevation: 0,
                  automaticallyImplyLeading: false, 
                  backgroundColor: theme.scaffoldBackgroundColor,
                  flexibleSpace: FlexibleSpaceBar(
                    collapseMode: CollapseMode.pin,
                    background: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // StreamBuilder DALAM: Memantau data TARGET (profil yg dilihat)
                        StreamBuilder<DocumentSnapshot>(
                          stream: _firestore.collection('users').doc(widget.userId).snapshots(),
                          builder: (context, targetSnapshot) {
                            if (!targetSnapshot.hasData) {
                              return Container(
                                height: 410, 
                                child: Center(child: CircularProgressIndicator()),
                              );
                            }
                            final targetData = targetSnapshot.data!.data() as Map<String, dynamic>;
                            
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildProfileHeader(context, targetData, isMyProfile, amIFollowing),
                                _buildProfileInfo(context, targetData), 
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  bottom: TabBar(
                    controller: _tabController,
                    tabs: [
                      Tab(text: 'Posts'),
                      Tab(text: 'Replies'),
                    ],
                    labelColor: theme.primaryColor,
                    unselectedLabelColor: theme.hintColor,
                    indicatorColor: theme.primaryColor,
                  ),
                ),
              ];
            },
            body: TabBarView(
              controller: _tabController,
              children: [
                _buildMyPosts(widget.userId),
                _buildMyReplies(widget.userId),
              ],
            ),
          ),
        );
      },
    );
  }

  // --- Widget Header (Banner, Avatar, Tombol Follow) ---
  Widget _buildProfileHeader(BuildContext context, Map<String, dynamic> data, bool isMyProfile, bool amIFollowing) {
    // ... (Fungsi ini sudah benar dan tidak berubah)
    final theme = Theme.of(context);
    final String name = data['name'] ?? 'User';

    return Container(
      height: 180, 
      child: Stack(
        clipBehavior: Clip.none, 
        children: [
          Container(
            height: 120,
            color: TwitterTheme.darkGrey, 
          ),
          
          Positioned(
            top: 130,
            right: 16,
            child: isMyProfile
              ? OutlinedButton(
                  onPressed: () {
                    if(Navigator.of(context).canPop()) {
                      Navigator.of(context).pop();
                    }
                  },
                  child: Text("Edit Profile"),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.textTheme.bodyLarge?.color,
                    side: BorderSide(color: theme.dividerColor),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                )
              : amIFollowing
                ? OutlinedButton( // Tombol Unfollow
                    onPressed: _unfollowUser,
                    child: Text("Unfollow"),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.textTheme.bodyLarge?.color,
                      side: BorderSide(color: theme.dividerColor),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                  )
                : ElevatedButton( // Tombol Follow
                    onPressed: _followUser,
                    child: Text("Follow"), 
                    style: ElevatedButton.styleFrom(
                      backgroundColor: TwitterTheme.blue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                  ),
          ),

          Positioned(
            top: 80, 
            left: 16,
            child: CircleAvatar(
              radius: 42, 
              backgroundColor: theme.scaffoldBackgroundColor,
              child: CircleAvatar(
                radius: 40,
                child: Text(name.isNotEmpty ? name[0].toUpperCase() : "A", style: TextStyle(fontSize: 30)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- Widget Info (Nama, Handle, Bio, Stats) ---
  // Fungsi ini HANYA menggunakan parameter 'data' (yaitu targetData)
  Widget _buildProfileInfo(BuildContext context, Map<String, dynamic> data) {
    final theme = Theme.of(context);
    final String name = data['name'] ?? 'Name not set';
    final String email = data['email'] ?? 'Email not found';
    final String nim = data['nim'] ?? 'NIM not set'; 
    final String handle = "@${email.split('@')[0]}";
    final String bio = data['bio'] ?? 'No bio set.';
    final String joinedDate = "Joined March 2020"; // Placeholder

    // Ambil data list HANYA DARI 'data' (data target)
    final List<dynamic> followingList = data['following'] ?? [];
    final List<dynamic> followersList = data['followers'] ?? [];
    
    // Hitung panjang list
    final int followingCount = followingList.length;
    final int followersCount = followersList.length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          Text(handle, style: theme.textTheme.titleSmall),
          SizedBox(height: 4), 
          Text(nim, style: theme.textTheme.titleSmall), 
          SizedBox(height: 12),
          Text(bio, style: theme.textTheme.bodyLarge),
          SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.calendar_today_outlined, size: 14, color: theme.hintColor),
              SizedBox(width: 8),
              Text(joinedDate, style: theme.textTheme.titleSmall),
            ],
          ),
          
          SizedBox(height: 12),
          Row(
            children: [
              _buildStatText(context, followingCount, "Following"),
              SizedBox(width: 16),
              _buildStatText(context, followersCount, "Followers"),
            ],
          ),

          SizedBox(height: 12),
        ],
      ),
    );
  }


  Widget _buildStatText(BuildContext context, int count, String label) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Text(count.toString(), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        SizedBox(width: 4),
        Text(label, style: theme.textTheme.titleSmall),
      ],
    );
  }



  Widget _buildMyPosts(String userId) {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('posts')
          .where('userId', isEqualTo: userId) 
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return Center(child: CircularProgressIndicator());
        if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
        if (snapshot.data!.docs.isEmpty) {
          return Center(child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text('This user has no posts.'),
          ));
        }
        return ListView.separated(
          itemCount: snapshot.data!.docs.length,
          separatorBuilder: (context, index) => Divider(height: 1, thickness: 1),
          itemBuilder: (context, index) {
            final doc = snapshot.data!.docs[index];
            final data = doc.data() as Map<String, dynamic>;
            return BlogPostCard(
              postId: doc.id,
              postData: data,
              isOwner: data['userId'] == _auth.currentUser?.uid,
            );
          },
        );
      },
    );
  }

  Widget _buildMyReplies(String userId) {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collectionGroup('comments')
          .where('userId', isEqualTo: userId)
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return Center(child: CircularProgressIndicator());
        if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
        if (snapshot.data!.docs.isEmpty) {
          return Center(child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text('This user has no replies.'),
          ));
        }
        return ListView.separated(
          itemCount: snapshot.data!.docs.length,
          separatorBuilder: (context, index) => Divider(height: 1, thickness: 1),
          itemBuilder: (context, index) {
            final doc = snapshot.data!.docs[index];
            final data = doc.data() as Map<String, dynamic>;
            final String originalPostId = doc.reference.parent.parent!.id;
            return CommentTile(
              commentId: doc.id,
              commentData: data,
              postId: originalPostId, 
              isOwner: data['userId'] == _auth.currentUser?.uid,
              showPostContext: true, 
            );
          },
        );
      },
    );
  }
}