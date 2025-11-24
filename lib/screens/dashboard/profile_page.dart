// ignore_for_file: prefer_const_constructors
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart'; 
import 'package:shared_preferences/shared_preferences.dart';
import '../../widgets/blog_post_card.dart';
import '../../widgets/comment_tile.dart';
import '../../main.dart';
import '../edit_profile_screen.dart';

final FirebaseAuth _auth = FirebaseAuth.instance;
final FirebaseFirestore _firestore = FirebaseFirestore.instance;

class ProfilePage extends StatefulWidget {
  final String? userId;
  final bool includeScaffold; 

  const ProfilePage({
    super.key, 
    this.userId,
    this.includeScaffold = false, 
  });

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> with TickerProviderStateMixin {
  late TabController _tabController;
  final ScrollController _scrollController = ScrollController();
  
  Uint8List? _localImageBytes;
  String? _selectedAvatarIconName;
  late final User? _user;
  late final String _userId;
  
  bool _isScrolled = false;

  @override
  void initState() {
    super.initState();
    _user = _auth.currentUser;
    _userId = widget.userId ?? _user!.uid;
    _tabController = TabController(length: 3, vsync: this);
    
    _scrollController.addListener(_scrollListener);
    _loadLocalAvatar();
  }
  
  void _scrollListener() {
    if (_scrollController.hasClients) {
      final bool scrolled = _scrollController.offset > 100;
      if (scrolled != _isScrolled) {
        setState(() {
          _isScrolled = scrolled;
        });
      }
    }
  }

  Future<void> _loadLocalAvatar() async {
    if (_userId == null) return;
    final prefs = await SharedPreferences.getInstance();
    final String? imagePath = prefs.getString('profile_picture_path_$_userId');
    final String? iconName = prefs.getString('profile_avatar_icon_$_userId');

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
          await prefs.remove('profile_picture_path_$_userId');
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

  Future<void> _followUser() async {
    if (_user == null) return;
    try {
      final batch = _firestore.batch();
      final myDocRef = _firestore.collection('users').doc(_user!.uid);
      final targetDocRef = _firestore.collection('users').doc(_userId);
      batch.update(myDocRef, {'following': FieldValue.arrayUnion([_userId])});
      batch.update(targetDocRef, {'followers': FieldValue.arrayUnion([_user!.uid])});
      await batch.commit();
      _firestore.collection('users').doc(_userId).collection('notifications').add({
        'type': 'follow', 'senderId': _user!.uid, 'timestamp': FieldValue.serverTimestamp(), 'isRead': false,
      });
    } catch (e) { if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to follow: $e'))); }
  }

  Future<void> _unfollowUser() async {
    if (_user == null) return;
    try {
      final batch = _firestore.batch();
      final myDocRef = _firestore.collection('users').doc(_user!.uid);
      final targetDocRef = _firestore.collection('users').doc(_userId);
      batch.update(myDocRef, {'following': FieldValue.arrayRemove([_userId])});
      batch.update(targetDocRef, {'followers': FieldValue.arrayRemove([_user!.uid])});
      await batch.commit();
    } catch (e) { if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to unfollow: $e'))); }
  }

  void _shareProfile(String name) {
    Share.share("Check out $name's profile on PNJ Media: https://github.com/blankony/myfirebaseflutterapp");
  }

  void _blockUser(String name) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Blocked $name. You will no longer see their posts.')),
    );
  }

  void _showMoreOptions(BuildContext context, String name, bool isMyProfile) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: Icon(Icons.share_outlined),
                title: Text('Share Account'),
                onTap: () {
                  Navigator.pop(context);
                  _shareProfile(name);
                },
              ),
              if (!isMyProfile)
                ListTile(
                  leading: Icon(Icons.block_outlined, color: Colors.red),
                  title: Text('Block @$name', style: TextStyle(color: Colors.red)),
                  onTap: () {
                    Navigator.pop(context);
                    _blockUser(name);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scrollController.removeListener(_scrollListener);
    _scrollController.dispose();
    super.dispose();
  }

  String _formatJoinedDate(Timestamp? timestamp) {
    if (timestamp == null) return 'Joined date unknown';
    final DateTime date = timestamp.toDate();
    final String formattedDate = DateFormat('MMMM yyyy').format(date);
    return 'Joined $formattedDate';
  }

  IconData _getIconDataFromString(String? iconName) {
    switch (iconName) {
      case 'face': return Icons.face;
      case 'rocket': return Icons.rocket_launch;
      case 'pet': return Icons.pets;
      default: return Icons.person;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_userId == null) {
      return Center(child: Text("Not logged in."));
    }
    
    final theme = Theme.of(context);

    Widget scrollView = DefaultTabController(
      length: 3,
      child: NestedScrollView(
        controller: _scrollController,
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            SliverToBoxAdapter(
              child: StreamBuilder<DocumentSnapshot>(
                stream: _firestore.collection('users').doc(_userId).snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return SizedBox(height: 300, child: Center(child: CircularProgressIndicator()));
                  
                  final data = snapshot.data!.data() as Map<String, dynamic>;
                  final bool isMyProfile = _user?.uid == _userId;
                  
                  return _buildUnifiedProfileHeader(context, data, isMyProfile);
                },
              ),
            ),
            SliverPersistentHeader(
              delegate: _SliverAppBarDelegate(
                TabBar(
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
              pinned: true,
            ),
          ];
        },
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildMyPosts(_userId),
            _buildMyReposts(_userId),
            _buildMyReplies(_userId),
          ],
        ),
      ),
    );

    Widget floatingAppBar = StreamBuilder<DocumentSnapshot>(
      stream: _firestore.collection('users').doc(_userId).snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data() as Map<String, dynamic>? ?? {};
        final String name = data['name'] ?? '';
        final bool isMyProfile = _user?.uid == _userId;

        return Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: AppBar(
            backgroundColor: _isScrolled ? theme.scaffoldBackgroundColor : Colors.transparent,
            elevation: 0,
            automaticallyImplyLeading: widget.includeScaffold,
            iconTheme: IconThemeData(
              color: _isScrolled ? theme.iconTheme.color : Colors.white,
            ),
            title: AnimatedOpacity(
              opacity: _isScrolled ? 1.0 : 0.0,
              duration: Duration(milliseconds: 200),
              child: Text(
                name, 
                style: TextStyle(
                  color: theme.textTheme.titleLarge?.color,
                  fontWeight: FontWeight.bold
                )
              ),
            ),
            centerTitle: false,
            actions: [
              // Menu is now always available via the floating AppBar
              IconButton(
                icon: Icon(Icons.more_vert),
                onPressed: () => _showMoreOptions(context, name, isMyProfile),
              ),
            ],
          ),
        );
      }
    );

    Widget content = Stack(
      children: [
        scrollView, 
        floatingAppBar,
      ],
    );

    if (widget.includeScaffold) {
      return Scaffold(
        body: content,
      );
    }

    return content;
  }

  Widget _buildUnifiedProfileHeader(BuildContext context, Map<String, dynamic> data, bool isMyProfile) {
    final theme = Theme.of(context);
    final String name = data['name'] ?? 'Name';
    final String email = data['email'] ?? '';
    final String nim = data['nim'] ?? '';
    final String bio = data['bio'] ?? '';
    final List<dynamic> following = data['following'] ?? [];
    final List<dynamic> followers = data['followers'] ?? [];
    final bool amIFollowing = followers.contains(_user?.uid);

    const double bannerHeight = 150.0;
    const double avatarRadius = 45.0;
    final double topPadding = MediaQuery.of(context).padding.top + kToolbarHeight;

    return Column(
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              height: bannerHeight + topPadding, 
              width: double.infinity,
              color: TwitterTheme.darkGrey,
            ),
            Positioned(
              bottom: -avatarRadius, 
              left: 16,
              child: CircleAvatar(
                radius: avatarRadius + 4, 
                backgroundColor: theme.scaffoldBackgroundColor,
                child: _buildAvatarImage(data),
              ),
            ),
          ],
        ),

        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(top: 12.0), 
                  child: isMyProfile
                      ? OutlinedButton(
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
                            visualDensity: VisualDensity.compact,
                          ),
                        )
                      : amIFollowing 
                          ? OutlinedButton(
                              onPressed: _unfollowUser,
                              child: Text("Unfollow"),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: theme.textTheme.bodyLarge?.color,
                                side: BorderSide(color: theme.dividerColor),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                visualDensity: VisualDensity.compact,
                              ),
                            )
                          : ElevatedButton(
                              onPressed: _followUser,
                              child: Text("Follow"),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: TwitterTheme.blue,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                ),
              ),
              
              SizedBox(height: 4), 
              Text(name, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, fontSize: 22)),
              Text("@${email.split('@')[0]}", style: theme.textTheme.titleSmall),
              SizedBox(height: 4),
              Text(nim, style: theme.textTheme.titleSmall),
              SizedBox(height: 8),
              Text(
                bio.isEmpty ? "No bio set." : bio,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontStyle: bio.isEmpty ? FontStyle.italic : FontStyle.normal
                ),
              ),
              SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.calendar_today_outlined, size: 14, color: theme.hintColor),
                  SizedBox(width: 8),
                  Text(_formatJoinedDate(data['createdAt']), style: theme.textTheme.titleSmall),
                ],
              ),
              SizedBox(height: 8),
              Row(
                children: [
                  _buildStatText(context, following.length, "Following"),
                  SizedBox(width: 16),
                  _buildStatText(context, followers.length, "Followers"),
                ],
              ),
              SizedBox(height: 4),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAvatarImage(Map<String, dynamic> data) {
    final String name = data['name'] ?? 'U';
    const double avatarRadius = 45.0;
    
    return CircleAvatar(
      radius: avatarRadius,
      backgroundImage: _localImageBytes != null ? MemoryImage(_localImageBytes!) : null,
      child: (_localImageBytes == null && _selectedAvatarIconName != null)
        ? Icon(
            _getIconDataFromString(_selectedAvatarIconName),
            size: 50,
            color: TwitterTheme.blue,
          )
        : (_localImageBytes == null && _selectedAvatarIconName == null)
          ? Text(name.isNotEmpty ? name[0].toUpperCase() : "A", style: TextStyle(fontSize: 35))
          : null,
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

  // FIX: Use ListView.builder to avoid stripes
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
            child: Text('You have not created any posts yet.'),
          ));
        }

        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 100), 
          physics: const AlwaysScrollableScrollPhysics(), 
          itemCount: snapshot.data!.docs.length,
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

  Widget _buildMyReplies(String userId) {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collectionGroup('comments')
          .where('userId', isEqualTo: userId)
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return Center(child: CircularProgressIndicator());
        if (snapshot.data!.docs.isEmpty) {
          return Center(child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text('You have not replied to any posts yet.'),
          ));
        }

        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 100),
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: snapshot.data!.docs.length,
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

  Widget _buildMyReposts(String userId) {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('posts')
          .where('repostedBy', arrayContains: userId)
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return Center(child: CircularProgressIndicator());
        
        if (snapshot.hasError) return Center(child: Text('No reposts (or missing index).'));
        
        if (snapshot.data!.docs.isEmpty) {
          return Center(child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text('You have not reposted anything yet.'),
          ));
        }

        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 100),
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: snapshot.data!.docs.length,
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
}

class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  _SliverAppBarDelegate(this._tabBar);
  final TabBar _tabBar;

  @override
  double get minExtent => _tabBar.preferredSize.height;
  @override
  double get maxExtent => _tabBar.preferredSize.height;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: _tabBar,
    );
  }

  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) {
    return false;
  }
}