// ignore_for_file: prefer_const_constructors
import 'dart:io'; 
import 'dart:typed_data'; 
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart'; 
import '../../widgets/blog_post_card.dart'; 
import '../../widgets/comment_tile.dart'; 
import '../../main.dart'; 
import '../edit_profile_screen.dart'; 

final FirebaseAuth _auth = FirebaseAuth.instance;
final FirebaseFirestore _firestore = FirebaseFirestore.instance;

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> with TickerProviderStateMixin {
  late TabController _tabController;
  Uint8List? _localImageBytes;
  String? _selectedAvatarIconName;
  final User? _user = _auth.currentUser;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadLocalAvatar(); 
  }

  Future<void> _loadLocalAvatar() async {
    if (_user == null) return;
    final prefs = await SharedPreferences.getInstance();
    final String? imagePath = prefs.getString('profile_picture_path_${_user!.uid}');
    final String? iconName = prefs.getString('profile_avatar_icon_${_user!.uid}');
    
    if (mounted) {
      if (imagePath != null) {
        final file = File(imagePath);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          setState(() {
            _localImageBytes = bytes;
            _selectedAvatarIconName = null;
          });
        } else {
          await prefs.remove('profile_picture_path_${_user!.uid}');
          setState(() {
            _localImageBytes = null;
            _selectedAvatarIconName = iconName; 
          });
        }
      } else if (iconName != null) {
        setState(() {
          _localImageBytes = null;
          _selectedAvatarIconName = iconName;
        });
      } else {
        setState(() {
          _localImageBytes = null;
          _selectedAvatarIconName = null;
        });
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _formatJoinedDate(Timestamp? timestamp) {
    if (timestamp == null) {
      return 'Joined date unknown';
    }
    final DateTime date = timestamp.toDate();
    final String formattedDate = DateFormat('MMMM yyyy').format(date);
    return 'Joined $formattedDate';
  }

  IconData _getIconDataFromString(String? iconName) {
    switch (iconName) {
      case 'face':
        return Icons.face;
      case 'rocket':
        return Icons.rocket_launch;
      case 'pet':
        return Icons.pets;
      default:
        return Icons.person; 
    }
  }

  @override
  Widget build(BuildContext context) {
    final User? user = _auth.currentUser;
    if (user == null) {
      return Scaffold(body: Center(child: Text("Not logged in.")));
    }
    final theme = Theme.of(context);

    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            SliverAppBar(
              expandedHeight: 360.0, 
              pinned: true, 
              elevation: 0,
              backgroundColor: theme.scaffoldBackgroundColor,
              flexibleSpace: FlexibleSpaceBar(
                title: innerBoxIsScrolled 
                    ? Text('Profile', style: theme.textTheme.titleLarge) 
                    : null,
                centerTitle: false,
                collapseMode: CollapseMode.pin,
                background: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    StreamBuilder<DocumentSnapshot>(
                      stream: _firestore.collection('users').doc(user.uid).snapshots(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return Container(
                            height: 360, 
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        final data = snapshot.data!.data() as Map<String, dynamic>;
                        
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildProfileHeader(context, user, data),
                            _buildProfileInfo(context, user, data),
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
                  Tab(text: 'Reposts'), 
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
            _buildMyPosts(user),
            _buildMyReposts(user), 
            _buildMyReplies(user),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileHeader(BuildContext context, User user, Map<String, dynamic> data) {
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
            child: OutlinedButton(
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => EditProfileScreen()),
                );
                _loadLocalAvatar(); 
              },
              child: Text("Edit Profile"),
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.textTheme.bodyLarge?.color,
                side: BorderSide(color: theme.dividerColor),
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
                backgroundImage: _localImageBytes != null ? MemoryImage(_localImageBytes!) : null,
                child: (_localImageBytes == null && _selectedAvatarIconName != null)
                  ? Icon(
                      _getIconDataFromString(_selectedAvatarIconName),
                      size: 45,
                      color: TwitterTheme.blue,
                    )
                  : (_localImageBytes == null && _selectedAvatarIconName == null)
                    ? Text(name.isNotEmpty ? name[0].toUpperCase() : "A", style: TextStyle(fontSize: 30))
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileInfo(BuildContext context, User user, Map<String, dynamic> data) {
    final theme = Theme.of(context);
    final String name = data['name'] ?? 'Name not set';
    final String email = user.email ?? 'Email not found';
    final String nim = data['nim'] ?? 'NIM not set'; 
    final String handle = "@${email.split('@')[0]}";
    final String bio = data['bio'] ?? 'No bio set.';
    
    final Timestamp? createdAt = data['createdAt'] as Timestamp?;
    final String joinedDate = _formatJoinedDate(createdAt);

    final List<dynamic> followingList = data['following'] ?? [];
    final List<dynamic> followersList = data['followers'] ?? [];
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
          Text(
            bio.isEmpty ? "No bio set." : bio,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontStyle: bio.isEmpty ? FontStyle.italic : FontStyle.normal
            ),
          ),

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


  Widget _buildMyPosts(User user) {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('posts')
          .where('userId', isEqualTo: user.uid) 
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return Center(child: CircularProgressIndicator());
        if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
        if (snapshot.data!.docs.isEmpty) {
          return Center(child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text('You have not created any posts yet.'),
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
              isOwner: true, 
            );
          },
        );
      },
    );
  }

  Widget _buildMyReplies(User user) {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collectionGroup('comments')
          .where('userId', isEqualTo: user.uid)
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return Center(child: CircularProgressIndicator());
        if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
        if (snapshot.data!.docs.isEmpty) {
          return Center(child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text('You have not replied to any posts yet.'),
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
              isOwner: true, 
              showPostContext: true, 
            );
          },
        );
      },
    );
  }

  Widget _buildMyReposts(User user) {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('posts')
          .where('repostedBy', arrayContains: user.uid)
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return Center(child: CircularProgressIndicator());
        
        if (snapshot.hasError) {
          if (snapshot.error.toString().contains('firestore/failed-precondition') || 
              snapshot.error.toString().contains('requires an index')) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'Loading reposts failed. Please check Firestore index settings.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.red),
                ),
              ),
            );
          }
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        
        if (snapshot.data!.docs.isEmpty) {
          return Center(child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text('You have not reposted anything yet.'),
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
              isOwner: data['userId'] == user.uid,
            );
          },
        );
      },
    );
  }
}