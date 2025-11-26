// ignore_for_file: prefer_const_constructors
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart'; 
import 'package:cached_network_image/cached_network_image.dart'; 
import '../../widgets/blog_post_card.dart';
import '../../widgets/comment_tile.dart';
import '../../main.dart';
import '../edit_profile_screen.dart';
import 'settings_page.dart'; 

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
  
  late final User? _user;
  late final String _userId;
  
  bool _isScrolled = false;
  bool _isBioExpanded = false;

  @override
  void initState() {
    super.initState();
    _user = _auth.currentUser;
    _userId = widget.userId ?? _user!.uid;
    
    // Inisialisasi normal (index 0 = Posts)
    _tabController = TabController(length: 3, vsync: this, initialIndex: 0);
    
    _scrollController.addListener(_scrollListener);
  }
  
  // Hapus fungsi _resetTabController yang lama (Nuclear Reset) karena bisa bikin glitch

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

  Future<void> _handleRefresh() async {
    // 1. Scroll ke paling atas dulu agar NestedScrollView tidak bingung
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }

    // 2. Tunggu sebentar (simulasi network)
    await Future.delayed(Duration(seconds: 1));
    
    if (mounted) {
      // 3. Pindahkan ke Tab 0 (Posts) dengan aman
      if (_tabController.index != 0) {
        _tabController.animateTo(0);
      }
      setState(() {});
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
    Share.share("Check out $name's profile on Sapa PNJ!");
  }

  void _blockUser(String name) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Blocked $name. You will no longer see their posts.')),
    );
  }

  Future<void> _signOut(BuildContext context) async {
    final didConfirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Sign Out'),
        content: Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: Text('Sign Out', style: TextStyle(color: Colors.red))),
        ],
      ),
    ) ?? false;

    if (didConfirm) {
      await _auth.signOut();
      if (context.mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    }
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

  @override
  Widget build(BuildContext context) {
    if (_userId == null) {
      return Center(child: Text("Not logged in."));
    }
    
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    Widget content = RefreshIndicator(
      onRefresh: _handleRefresh,
      notificationPredicate: (notification) {
        return notification.depth == 0; 
      },
      child: NestedScrollView(
        controller: _scrollController,
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            StreamBuilder<DocumentSnapshot>(
              stream: _firestore.collection('users').doc(_userId).snapshots(),
              builder: (context, snapshot) {
                final data = snapshot.data?.data() as Map<String, dynamic>? ?? {};
                final String name = data['name'] ?? '';
                final bool isMyProfile = _user?.uid == _userId;
                
                final Color appBarBgColor = isDarkMode ? Color(0xFF15202B) : TwitterTheme.white;
                final Color iconColor = isDarkMode ? TwitterTheme.white : TwitterTheme.blue;
                final Color titleColor = isDarkMode ? TwitterTheme.white : TwitterTheme.black;

                return SliverAppBar(
                  pinned: true,
                  elevation: 0,
                  backgroundColor: _isScrolled ? appBarBgColor : appBarBgColor, 
                  systemOverlayStyle: isDarkMode ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
                  automaticallyImplyLeading: widget.includeScaffold,
                  iconTheme: IconThemeData(
                    color: iconColor, 
                  ),
                  title: AnimatedOpacity(
                    opacity: _isScrolled ? 1.0 : 0.0,
                    duration: Duration(milliseconds: 200),
                    child: Text(
                      name, 
                      style: TextStyle(
                        color: titleColor,
                        fontWeight: FontWeight.bold
                      )
                    ),
                  ),
                  centerTitle: false,
                  actions: [
                    PopupMenuButton<String>(
                      icon: Icon(Icons.more_vert, color: iconColor),
                      onSelected: (value) {
                        if (value == 'share') _shareProfile(name);
                        if (value == 'settings') Navigator.of(context).push(MaterialPageRoute(builder: (_) => SettingsPage()));
                        if (value == 'logout') _signOut(context);
                        if (value == 'block') _blockUser(name);
                      },
                      itemBuilder: (BuildContext context) {
                        if (isMyProfile) {
                          return [
                            PopupMenuItem(
                              value: 'share',
                              child: Row(children: [Icon(Icons.share_outlined, color: theme.iconTheme.color), SizedBox(width: 8), Text('Share Profile')]),
                            ),
                            PopupMenuItem(
                              value: 'settings',
                              child: Row(children: [Icon(Icons.settings_outlined, color: theme.iconTheme.color), SizedBox(width: 8), Text('Settings')]),
                            ),
                            PopupMenuItem(
                              value: 'logout',
                              child: Row(children: [Icon(Icons.logout, color: Colors.red), SizedBox(width: 8), Text('Logout', style: TextStyle(color: Colors.red))]),
                            ),
                          ];
                        } else {
                          return [
                            PopupMenuItem(
                              value: 'share',
                              child: Row(children: [Icon(Icons.share_outlined, color: theme.iconTheme.color), SizedBox(width: 8), Text('Share Account')]),
                            ),
                            PopupMenuItem(
                              value: 'block',
                              child: Row(children: [Icon(Icons.block_outlined, color: Colors.red), SizedBox(width: 8), Text('Block @$name', style: TextStyle(color: Colors.red))]),
                            ),
                          ];
                        }
                      },
                    ),
                  ],
                );
              },
            ),

            SliverToBoxAdapter(
              child: StreamBuilder<DocumentSnapshot>(
                stream: _firestore.collection('users').doc(_userId).snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return SizedBox(height: 200, child: Center(child: CircularProgressIndicator()));
                  
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

    if (widget.includeScaffold) {
      return Scaffold(
        extendBodyBehindAppBar: true, 
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
    final String? departmentCode = data['departmentCode']; 
    final String? departmentName = data['department'];
    final String? studyProgramName = data['studyProgram'];
    
    final List<dynamic> following = data['following'] ?? [];
    final List<dynamic> followers = data['followers'] ?? [];
    final String? bannerImageUrl = data['bannerImageUrl']; 

    const double bannerHeight = 150.0;
    const double avatarRadius = 45.0;
    const double headerStackHeight = bannerHeight + 60.0;

    final bool isLongBio = bio.length > 100;
    final String displayBio = _isBioExpanded ? bio : (isLongBio ? bio.substring(0, 100) + '...' : bio);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: headerStackHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                height: bannerHeight,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: TwitterTheme.darkGrey, 
                ),
                child: bannerImageUrl != null && bannerImageUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: bannerImageUrl,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(color: TwitterTheme.darkGrey),
                      errorWidget: (context, url, error) => Container(color: TwitterTheme.darkGrey),
                    )
                  : null,
              ),
              
              Positioned(
                top: bannerHeight - avatarRadius,
                left: 16,
                child: CircleAvatar(
                  radius: avatarRadius + 4,
                  backgroundColor: theme.scaffoldBackgroundColor,
                  child: _buildAvatarImage(data),
                ),
              ),

              Positioned(
                top: bannerHeight + 16,
                right: 16,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (departmentCode != null) ...[
                      _buildDepartmentBadge(departmentCode, departmentName, studyProgramName),
                      SizedBox(width: 12), 
                    ],
                    isMyProfile
                        ? OutlinedButton(
                            onPressed: () async {
                              final result = await Navigator.of(context).push(
                                MaterialPageRoute(builder: (context) => EditProfileScreen()),
                              );
                              
                              if (mounted) {
                                if (result == true) {
                                  // Logika pindah ke tab 0 setelah save edit
                                  _tabController.animateTo(0); 
                                }
                                setState(() {});
                              }
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: theme.textTheme.bodyLarge?.color,
                              side: BorderSide(color: theme.dividerColor),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                              visualDensity: VisualDensity.compact,
                            ),
                            child: Text("Edit Profile"),
                          )
                        : _buildFollowButton(followers),
                  ],
                ),
              ),
            ],
          ),
        ),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, fontSize: 22)),
              Text("@${email.split('@')[0]}", style: theme.textTheme.titleSmall),
              SizedBox(height: 4),
              Text(nim, style: theme.textTheme.titleSmall),
              SizedBox(height: 8),
              
              Text(
                displayBio.isEmpty ? "No bio set." : displayBio,
                style: theme.textTheme.bodyLarge?.copyWith(fontStyle: bio.isEmpty ? FontStyle.italic : FontStyle.normal),
              ),
              if (isLongBio)
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _isBioExpanded = !_isBioExpanded;
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Text(
                      _isBioExpanded ? "Show less" : "Read more",
                      style: TextStyle(color: TwitterTheme.blue, fontWeight: FontWeight.bold),
                    ),
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
              SizedBox(height: 16),
            ],
          ),
        ),
      ],
    );
  }

  void _showBadgeInfo(BuildContext context, String dept, String prodi) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Academic Info"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Department", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
            Text(dept, style: TextStyle(fontSize: 16)),
            SizedBox(height: 16),
            Text("Study Program", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
            Text(prodi, style: TextStyle(fontSize: 16)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("Close", style: TextStyle(color: TwitterTheme.blue)),
          ),
        ],
      ),
    );
  }

  Widget _buildDepartmentBadge(String code, String? fullDeptName, String? fullProdiName) {
    final parts = code.split('-');
    if (parts.length < 2) return SizedBox.shrink();

    final dept = parts[0]; 
    final prodi = parts[1]; 
    
    Color deptColor;
    if (dept.toUpperCase() == 'TE') {
       deptColor = Color(0xFF00008B); 
    } else if (dept.toUpperCase() == 'TS') {
       deptColor = Color(0xFF5D4037); 
    } else {
       deptColor = Colors.primaries[dept.hashCode.abs() % Colors.primaries.length];
    }
    
    Color prodiColor;
    if (prodi.toUpperCase() == 'BM') {
      prodiColor = Colors.orange; 
    } else {
      prodiColor = Colors.primaries[prodi.hashCode.abs() % Colors.primaries.length];
    }

    return GestureDetector(
      onTap: () {
        if (fullDeptName != null && fullProdiName != null) {
          _showBadgeInfo(context, fullDeptName, fullProdiName);
        }
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: deptColor, 
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(dept, style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
          ),
          SizedBox(width: 4), 
          Container(
            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: prodiColor,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(prodi, style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatarImage(Map<String, dynamic> data) {
    final int iconId = data['avatarIconId'] ?? 0;
    final String? colorHex = data['avatarHex'];
    final String? profileImageUrl = data['profileImageUrl']; 
    final Color bgColor = AvatarHelper.getColor(colorHex);
    
    if (profileImageUrl != null && profileImageUrl.isNotEmpty) {
      return CircleAvatar(
        radius: 45,
        backgroundColor: Colors.grey,
        backgroundImage: CachedNetworkImageProvider(profileImageUrl), 
      );
    }

    return CircleAvatar(
      radius: 45,
      backgroundColor: bgColor,
      child: Icon(
        AvatarHelper.getIcon(iconId),
        size: 50,
        color: Colors.white,
      ),
    );
  }

  Widget _buildFollowButton(List<dynamic> followers) {
    final bool amIFollowing = followers.contains(_user?.uid);
    return amIFollowing
      ? OutlinedButton(
          onPressed: _unfollowUser,
          child: Text("Unfollow"),
        )
      : ElevatedButton(
          onPressed: _followUser,
          style: ElevatedButton.styleFrom(
            backgroundColor: TwitterTheme.blue,
            foregroundColor: Colors.white,
          ),
          child: Text("Follow"),
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
      stream: _firestore.collection('posts').where('userId', isEqualTo: userId).orderBy('timestamp', descending: true).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return Center(child: CircularProgressIndicator());
        }
        
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) return Center(child: Text('No posts yet.'));

        return ListView.builder(
          key: const PageStorageKey('profile_posts_list'),
          padding: const EdgeInsets.only(bottom: 100), 
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data() as Map<String, dynamic>;
            return BlogPostCard(
              postId: doc.id,
              postData: data,
              isOwner: data['userId'] == _auth.currentUser?.uid,
              heroContextId: 'profile_posts', 
            );
          },
        );
      },
    );
  }

  Widget _buildMyReplies(String userId) {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collectionGroup('comments').where('userId', isEqualTo: userId).orderBy('timestamp', descending: true).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return Center(child: CircularProgressIndicator());
        }
        
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) return Center(child: Text('No replies yet.'));

        return ListView.builder(
          key: const PageStorageKey('profile_replies_list'),
          padding: const EdgeInsets.only(bottom: 100),
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data() as Map<String, dynamic>;
            final String originalPostId = doc.reference.parent.parent!.id;

            return CommentTile(
              commentId: doc.id,
              commentData: data,
              postId: originalPostId,
              isOwner: true,
              showPostContext: true,
              heroContextId: 'profile_replies', 
            );
          },
        );
      },
    );
  }

  Widget _buildMyReposts(String userId) {
    return CustomScrollView(
      key: const PageStorageKey('profile_reposts_list'),
      slivers: [
        StreamBuilder<QuerySnapshot>(
          stream: _firestore.collection('posts').where('repostedBy', arrayContains: userId).orderBy('timestamp', descending: true).snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
              return SliverToBoxAdapter(child: SizedBox(height: 50, child: Center(child: CircularProgressIndicator())));
            }
            final docs = snapshot.data?.docs ?? [];
            if (docs.isEmpty) return SliverToBoxAdapter(child: SizedBox.shrink());

            return SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final doc = docs[index];
                  final data = doc.data() as Map<String, dynamic>;
                  return BlogPostCard(
                    postId: doc.id,
                    postData: data,
                    isOwner: data['userId'] == _auth.currentUser?.uid,
                    heroContextId: 'profile_reposts', 
                  );
                },
                childCount: docs.length,
              ),
            );
          },
        ),
        StreamBuilder<QuerySnapshot>(
          stream: _firestore.collectionGroup('comments').where('repostedBy', arrayContains: userId).orderBy('timestamp', descending: true).snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
               return SliverToBoxAdapter(child: SizedBox.shrink());
            }
            final docs = snapshot.data?.docs ?? [];
            if (docs.isEmpty) return SliverToBoxAdapter(child: SizedBox.shrink());

            return SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final doc = docs[index];
                  final data = doc.data() as Map<String, dynamic>;
                  final String originalPostId = doc.reference.parent.parent!.id;
                  
                  return CommentTile(
                    commentId: doc.id,
                    commentData: data,
                    postId: originalPostId,
                    isOwner: data['userId'] == _auth.currentUser?.uid,
                    showPostContext: true,
                    heroContextId: 'profile_reposts', 
                  );
                },
                childCount: docs.length,
              ),
            );
          },
        ),
        SliverToBoxAdapter(child: SizedBox(height: 100)),
      ],
    );
  }
}

class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  _SliverAppBarDelegate(this._tabBar);
  final TabBar _tabBar;
  @override double get minExtent => _tabBar.preferredSize.height;
  @override double get maxExtent => _tabBar.preferredSize.height;
  @override Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(color: Theme.of(context).scaffoldBackgroundColor, child: _tabBar);
  }
  @override bool shouldRebuild(_SliverAppBarDelegate oldDelegate) => false;
}