// ignore_for_file: prefer_const_constructors
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../widgets/blog_post_card.dart'; 
import '../../widgets/comment_tile.dart'; 
import '../../main.dart'; 
import '../edit_profile_screen.dart'; // ### IMPOR BARU ###

final FirebaseAuth _auth = FirebaseAuth.instance;
final FirebaseFirestore _firestore = FirebaseFirestore.instance;

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> with TickerProviderStateMixin {
  // ### Hapus _bioController dan _isEditingBio ###
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  // ### Hapus _saveBio ###

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
              // Setel kembali ke tinggi yang stabil
              expandedHeight: 330.0, 
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
                    // Ganti ke StreamBuilder agar profil otomatis update setelah diedit
                    StreamBuilder<DocumentSnapshot>(
                      stream: _firestore.collection('users').doc(user.uid).snapshots(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return Container(
                            height: 330, 
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        final data = snapshot.data!.data() as Map<String, dynamic>;
                        
                        // ### Hapus logika sinkronisasi bio ###
                        
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
            _buildMyReplies(user),
          ],
        ),
      ),
    );
  }

  // --- Widget Header (Banner, Avatar, Tombol Edit) ---
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
            // ### PERBARUI ONPRESSED ###
            child: OutlinedButton(
              onPressed: () {
                // Arahkan ke halaman Edit Profile yang baru
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => EditProfileScreen()),
                );
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
                child: Text(name.isNotEmpty ? name[0].toUpperCase() : "A", style: TextStyle(fontSize: 30)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- Widget Info (Nama, Handle, Bio, Stats) ---
  Widget _buildProfileInfo(BuildContext context, User user, Map<String, dynamic> data) {
    final theme = Theme.of(context);
    final String name = data['name'] ?? 'Name not set';
    final String email = user.email ?? 'Email not found';
    final String nim = data['nim'] ?? 'NIM not set'; 
    final String handle = "@${email.split('@')[0]}";
    final String bio = data['bio'] ?? 'No bio set.'; // Ambil bio terbaru
    
    final String joinedDate = "Joined March 2020"; // Placeholder

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

          // ### HAPUS LOGIKA TEXTFIELD ###
          // Tampilkan bio terbaru dari data snapshot
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
        ],
      ),
    );
  }

  // --- Widget Builder Tab (Posts & Replies) ---
  // (Tidak berubah)

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
}