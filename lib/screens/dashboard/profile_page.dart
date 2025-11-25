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
  
  // NEW: State for Bio Expansion
  bool _isBioExpanded = false;

  @override
  void initState() {
    super.initState();
    _user = _auth.currentUser;
    _userId = widget.userId ?? _user!.uid;
    _tabController = TabController(length: 3, vsync: this);
    
    _scrollController.addListener(_scrollListener);
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

  Future<void> _handleRefresh() async {
    // Simulate refresh wait
    await Future.delayed(Duration(seconds: 1));
    if (mounted) {
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
      child: DefaultTabController(
        length: 3,
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
                      IconButton(
                        icon: Icon(Icons.more_vert, color: iconColor),
                        onPressed: () => _showMoreOptions(context, name, isMyProfile),
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
    final List<dynamic> following = data['following'] ?? [];
    final List<dynamic> followers = data['followers'] ?? [];
    final String? bannerImageUrl = data['bannerImageUrl']; 

    const double bannerHeight = 150.0;
    const double avatarRadius = 45.0;
    const double headerStackHeight = bannerHeight + 60.0;

    // Bio Logic
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
                child: isMyProfile
                    ? OutlinedButton(
                        onPressed: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(builder: (context) => EditProfileScreen()),
                          );
                          if (mounted) setState(() {});
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
              
              // UPDATED BIO DISPLAY
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
        if (!snapshot.hasData) return Center(child: CircularProgressIndicator());
        if (snapshot.data!.docs.isEmpty) return Center(child: Text('No posts yet.'));

        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 100), 
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
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

  Widget _buildMyReplies(String userId) {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collectionGroup('comments').where('userId', isEqualTo: userId).orderBy('timestamp', descending: true).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return Center(child: CircularProgressIndicator());
        if (snapshot.data!.docs.isEmpty) return Center(child: Text('No replies yet.'));

        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 100),
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
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

  // MODIFIED: Uses CustomScrollView to fetch BOTH reposted posts AND reposted comments
  Widget _buildMyReposts(String userId) {
    return CustomScrollView(
      key: PageStorageKey('reposts_tab'),
      slivers: [
        // 1. Reposted Posts
        StreamBuilder<QuerySnapshot>(
          stream: _firestore.collection('posts').where('repostedBy', arrayContains: userId).orderBy('timestamp', descending: true).snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return SliverToBoxAdapter(child: SizedBox(height: 50, child: Center(child: CircularProgressIndicator())));
            if (snapshot.data!.docs.isEmpty) return SliverToBoxAdapter(child: SizedBox.shrink());

            return SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final doc = snapshot.data!.docs[index];
                  final data = doc.data() as Map<String, dynamic>;
                  return BlogPostCard(
                    postId: doc.id,
                    postData: data,
                    isOwner: data['userId'] == _auth.currentUser?.uid,
                  );
                },
                childCount: snapshot.data!.docs.length,
              ),
            );
          },
        ),

        // 2. Reposted Comments (Replies)
        StreamBuilder<QuerySnapshot>(
          stream: _firestore.collectionGroup('comments').where('repostedBy', arrayContains: userId).orderBy('timestamp', descending: true).snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return SliverToBoxAdapter(child: SizedBox.shrink());
            if (snapshot.data!.docs.isEmpty) return SliverToBoxAdapter(child: SizedBox.shrink());

            return SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
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
                childCount: snapshot.data!.docs.length,
              ),
            );
          },
        ),

        // 3. Fallback Empty State (if both are empty, tricky to show one "Empty" msg centered in sliver, so we append padding)
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