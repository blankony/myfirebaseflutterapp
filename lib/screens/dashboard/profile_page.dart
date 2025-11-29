// ignore_for_file: prefer_const_constructors
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';

// Ensure these imports match your actual file structure
import '../../widgets/blog_post_card.dart';
import '../../widgets/comment_tile.dart';
import '../../main.dart';
import '../edit_profile_screen.dart';
import '../image_viewer_screen.dart';
import 'settings_page.dart';
import '../../services/overlay_service.dart';
import '../../services/cloudinary_service.dart';

final FirebaseAuth _auth = FirebaseAuth.instance;
final FirebaseFirestore _firestore = FirebaseFirestore.instance;
final CloudinaryService _cloudinaryService = CloudinaryService();

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

class _ProfilePageState extends State<ProfilePage> with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late TabController _tabController;
  final ScrollController _scrollController = ScrollController();
  
  late final User? _user;
  late final String _userId;
  
  bool _isScrolled = false;
  bool _isBioExpanded = false;

  // Optimistic Pinning State
  String? _optimisticPinnedPostId; 

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _user = _auth.currentUser;
    _userId = widget.userId ?? _user!.uid;
    
    int initialIndex = 0;
    try {
      final savedIndex = PageStorage.of(context).readState(context, identifier: 'tab_index_$_userId');
      if (savedIndex != null && savedIndex is int) {
        initialIndex = savedIndex;
      }
    } catch (_) {}

    _tabController = TabController(
      length: 3, 
      vsync: this, 
      initialIndex: initialIndex, 
    );

    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        PageStorage.of(context).writeState(
          context, 
          _tabController.index, 
          identifier: 'tab_index_$_userId'
        );
      }
    });
    
    _scrollController.addListener(_scrollListener);
  }
  
  void _scrollListener() {
    if (_scrollController.hasClients) {
      final bool scrolled = _scrollController.offset > (120.0 - kToolbarHeight);
      if (scrolled != _isScrolled) {
        setState(() {
          _isScrolled = scrolled;
        });
      }
    }
  }

  // --- HANDLERS ---

  void _handlePinToggle(String postId, bool isPinned) {
    setState(() {
      _optimisticPinnedPostId = isPinned ? postId : ''; 
    });
  }

  void _openFullImage(BuildContext context, String url, String heroTag) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (_, __, ___) => ImageViewerScreen(
          imageUrl: url,
          heroTag: heroTag,
          mediaType: 'image', 
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        }
      ),
    );
  }

  OverlayEntry _showUploadingOverlay() {
    OverlayEntry entry = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + 10,
        left: 16,
        right: 16,
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(12),
          color: Theme.of(context).cardColor,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: TwitterTheme.blue)),
                    SizedBox(width: 12),
                    Text("Uploading media...", style: TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                SizedBox(height: 10),
                LinearProgressIndicator(backgroundColor: TwitterTheme.blue.withOpacity(0.1), valueColor: AlwaysStoppedAnimation(TwitterTheme.blue)),
              ],
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(entry);
    return entry;
  }

  Future<void> _updateAllPastContent(String newImageUrl) async {
    try {
      final batch = _firestore.batch();
      final postsQuery = await _firestore.collection('posts').where('userId', isEqualTo: _userId).get();
      for (var doc in postsQuery.docs) batch.update(doc.reference, {'profileImageUrl': newImageUrl});
      final commentsQuery = await _firestore.collectionGroup('comments').where('userId', isEqualTo: _userId).get();
      for (var doc in commentsQuery.docs) batch.update(doc.reference, {'profileImageUrl': newImageUrl});
      await batch.commit();
    } catch (e) { debugPrint("Sync fail: $e"); }
  }

  Future<void> _pickAndUploadImage({required bool isBanner}) async {
    final picker = ImagePicker();
    final XFile? pickedFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (pickedFile == null) return;

    final croppedFile = await ImageCropper().cropImage(
      sourcePath: pickedFile.path,
      compressQuality: 70,
      aspectRatio: isBanner ? CropAspectRatio(ratioX: 3, ratioY: 1) : CropAspectRatio(ratioX: 1, ratioY: 1),
      uiSettings: [
        AndroidUiSettings(toolbarTitle: isBanner ? 'Crop Banner' : 'Crop Avatar', toolbarColor: TwitterTheme.blue, toolbarWidgetColor: Colors.white, initAspectRatio: isBanner ? CropAspectRatioPreset.ratio3x2 : CropAspectRatioPreset.square, lockAspectRatio: true),
        IOSUiSettings(title: isBanner ? 'Crop Banner' : 'Crop Avatar', aspectRatioLockEnabled: true),
      ],
    );
    if (croppedFile == null) return;

    final OverlayEntry loadingOverlay = _showUploadingOverlay();
    try {
      final String? downloadUrl = await _cloudinaryService.uploadImage(File(croppedFile.path));
      loadingOverlay.remove();
      if (downloadUrl != null) {
        final Map<String, dynamic> updateData = {};
        if (isBanner) updateData['bannerImageUrl'] = downloadUrl;
        else { updateData['profileImageUrl'] = downloadUrl; updateData['avatarIconId'] = -1; }
        
        await _firestore.collection('users').doc(_userId).update(updateData);
        if (!isBanner) _updateAllPastContent(downloadUrl);
        if (mounted) OverlayService().showTopNotification(context, "Updated successfully!", Icons.check_circle, (){}, color: Colors.green);
      }
    } catch (e) {
      try { loadingOverlay.remove(); } catch(_) {}
      if (mounted) OverlayService().showTopNotification(context, "Upload failed", Icons.error, (){}, color: Colors.red);
    }
  }

  void _showBannerOptions(BuildContext context, String? currentBannerUrl, String heroTag) {
    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(height: 12),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
              SizedBox(height: 16),
              if (currentBannerUrl != null && currentBannerUrl.isNotEmpty)
                ListTile(
                  leading: Icon(Icons.visibility_outlined, color: TwitterTheme.blue),
                  title: Text("View Banner"),
                  onTap: () { Navigator.pop(context); _openFullImage(context, currentBannerUrl, heroTag); },
                ),
              ListTile(
                leading: Icon(Icons.photo_library_outlined, color: TwitterTheme.blue),
                title: Text("Change Banner"),
                onTap: () { Navigator.pop(context); _pickAndUploadImage(isBanner: true); },
              ),
              SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  void _showProfileOptions(BuildContext context, String? currentImageUrl, String heroTag) {
    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(height: 12),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
              SizedBox(height: 16),
              if (currentImageUrl != null && currentImageUrl.isNotEmpty)
                ListTile(
                  leading: Icon(Icons.visibility_outlined, color: TwitterTheme.blue),
                  title: Text("View Photo"),
                  onTap: () { Navigator.pop(context); _openFullImage(context, currentImageUrl, heroTag); },
                ),
              ListTile(
                leading: Icon(Icons.photo_library_outlined, color: TwitterTheme.blue),
                title: Text("Change Photo"),
                onTap: () { Navigator.pop(context); _pickAndUploadImage(isBanner: false); },
              ),
              SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  // Follow/Unfollow/Share/Block/SignOut
  Future<void> _followUser() async {
    if (_user == null) return;
    try {
      final batch = _firestore.batch();
      final myDocRef = _firestore.collection('users').doc(_user!.uid);
      final targetDocRef = _firestore.collection('users').doc(_userId);
      batch.update(myDocRef, {'following': FieldValue.arrayUnion([_userId])});
      batch.update(targetDocRef, {'followers': FieldValue.arrayUnion([_user!.uid])});
      await batch.commit();
      _firestore.collection('users').doc(_userId).collection('notifications').doc('follow_${_user!.uid}').set({
        'type': 'follow', 'senderId': _user!.uid, 'timestamp': FieldValue.serverTimestamp(), 'isRead': false,
      });
    } catch (e) { if(mounted) OverlayService().showTopNotification(context, "Failed to follow", Icons.error, (){}, color: Colors.red); }
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
      _firestore.collection('users').doc(_userId).collection('notifications').doc('follow_${_user!.uid}').delete();
    } catch (e) { if(mounted) OverlayService().showTopNotification(context, "Failed to unfollow", Icons.error, (){}, color: Colors.red); }
  }

  void _shareProfile(String name) { Share.share("Check out $name's profile on Sapa PNJ!"); }
  void _blockUser(String name) { OverlayService().showTopNotification(context, 'Blocked $name', Icons.block, (){}); }
  Future<void> _signOut(BuildContext context) async {
    final didConfirm = await showDialog<bool>(context: context, builder: (context) => AlertDialog(title: Text('Sign Out'), content: Text('Are you sure?'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancel')), TextButton(onPressed: () => Navigator.pop(context, true), child: Text('Sign Out', style: TextStyle(color: Colors.red)))])) ?? false;
    if (didConfirm) { await _auth.signOut(); if (context.mounted) Navigator.of(context).popUntil((route) => route.isFirst); }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String _formatJoinedDate(Timestamp? timestamp) {
    if (timestamp == null) return 'Joined date unknown';
    return 'Joined ${DateFormat('MMMM yyyy').format(timestamp.toDate())}';
  }

  Future<void> _handleRefresh() async {
    await Future.delayed(Duration(seconds: 1));
    if (mounted) setState(() {}); 
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_userId == null) return Center(child: Text("Not logged in."));
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    
    final double topPadding = MediaQuery.of(context).padding.top;
    final double pinnedHeaderHeight = topPadding + kToolbarHeight;

    Widget content = RefreshIndicator(
      onRefresh: _handleRefresh,
      color: TwitterTheme.blue,
      edgeOffset: pinnedHeaderHeight,
      // Allow pull down to trigger from top
      notificationPredicate: (notification) => true,
      child: NestedScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            StreamBuilder<DocumentSnapshot>(
              stream: _firestore.collection('users').doc(_userId).snapshots(),
              builder: (context, snapshot) {
                final data = snapshot.data?.data() as Map<String, dynamic>? ?? {};
                
                return SliverAppBar(
                  pinned: true,
                  elevation: 0,
                  scrolledUnderElevation: 0,
                  // Height = Banner (150) + Avatar Overhang (120 top + 98 height - 150 banner = 68)
                  // Total ~ 218.0
                  expandedHeight: 218.0, 
                  backgroundColor: isDarkMode ? Color(0xFF15202B) : TwitterTheme.white,
                  iconTheme: IconThemeData(color: isDarkMode ? TwitterTheme.white : TwitterTheme.blue),
                  automaticallyImplyLeading: widget.includeScaffold,
                  
                  title: AnimatedOpacity(
                    opacity: _isScrolled ? 1.0 : 0.0,
                    duration: Duration(milliseconds: 200),
                    child: Text(
                      data['name'] ?? '', 
                      style: TextStyle(
                        color: isDarkMode ? TwitterTheme.white : TwitterTheme.black, 
                        fontWeight: FontWeight.bold
                      )
                    ),
                  ),
                  centerTitle: false,
                  actions: [
                     _buildActionMenu(context, data, _user?.uid == _userId),
                  ],
                  flexibleSpace: FlexibleSpaceBar(
                    background: _buildHeaderFlexibleSpace(context, data, _user?.uid == _userId),
                  ),
                );
              }
            ),

            // Profile Info (Name, Bio, Stats)
            StreamBuilder<DocumentSnapshot>(
              stream: _firestore.collection('users').doc(_userId).snapshots(),
              builder: (context, snapshot) {
                final data = snapshot.data?.data() as Map<String, dynamic>? ?? {};
                return SliverToBoxAdapter(
                  child: _buildProfileInfoBody(context, data),
                );
              }
            ),

            SliverPersistentHeader(
              pinned: true,
              delegate: _SliverAppBarDelegate(
                TabBar(
                  controller: _tabController,
                  tabs: const [Tab(text: 'Posts'), Tab(text: 'Reposts'), Tab(text: 'Replies')],
                  labelColor: theme.primaryColor,
                  unselectedLabelColor: theme.hintColor,
                  indicatorColor: theme.primaryColor,
                  overlayColor: WidgetStateProperty.all(Colors.transparent),
                  dividerColor: Colors.transparent, 
                ),
                isDarkMode ? Color(0xFF15202B) : TwitterTheme.white,
              ),
            ),
          ];
        },
        body: TabBarView(
          controller: _tabController,
          children: [
            Builder(builder: (context) => _buildMyPosts(context, _userId)),
            Builder(builder: (context) => _buildMyReposts(context, _userId)),
            Builder(builder: (context) => _buildMyReplies(context, _userId)),
          ],
        ),
      ),
    );

    return widget.includeScaffold ? Scaffold(extendBodyBehindAppBar: true, body: content) : content;
  }

  // --- Header Components ---

  Widget _buildActionMenu(BuildContext context, Map<String, dynamic> data, bool isMyProfile) {
    final name = data['name'] ?? '';
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert),
      onSelected: (value) {
        if (value == 'share') _shareProfile(name);
        if (value == 'settings') Navigator.push(context, MaterialPageRoute(builder: (_) => SettingsPage()));
        if (value == 'logout') _signOut(context);
        if (value == 'block') _blockUser(name);
      },
      itemBuilder: (context) => isMyProfile 
        ? [PopupMenuItem(value: 'share', child: Text('Share Profile')), PopupMenuItem(value: 'settings', child: Text('Settings')), PopupMenuItem(value: 'logout', child: Text('Logout', style: TextStyle(color: Colors.red)))]
        : [PopupMenuItem(value: 'share', child: Text('Share Account')), PopupMenuItem(value: 'block', child: Text('Block', style: TextStyle(color: Colors.red)))],
    );
  }

  Widget _buildHeaderFlexibleSpace(BuildContext context, Map<String, dynamic> data, bool isMyProfile) {
    final theme = Theme.of(context);
    final String? bannerImageUrl = data['bannerImageUrl'];
    final String? profileImageUrl = data['profileImageUrl'];
    final String? dept = data['department'];
    final String? prodi = data['studyProgram'];
    final String? deptCode = data['departmentCode'];
    
    return Stack(
      children: [
        // 1. Banner Layer
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 150,
          child: GestureDetector(
            onTap: () { 
              if(isMyProfile) _showBannerOptions(context, bannerImageUrl, 'banner'); 
              else if(bannerImageUrl!=null) _openFullImage(context, bannerImageUrl, 'banner'); 
            },
            child: Hero(
              tag: 'banner', 
              child: Container(
                color: TwitterTheme.darkGrey, 
                child: bannerImageUrl != null 
                  ? CachedNetworkImage(imageUrl: bannerImageUrl, fit: BoxFit.cover) 
                  : (isMyProfile ? Center(child: Icon(Icons.camera_alt, color: Colors.white)) : null)
              )
            ),
          ),
        ),
        
        // 2. Avatar Layer
        Positioned(
          top: 120, 
          left: 16,
          child: GestureDetector(
            onTap: () { if(isMyProfile) _showProfileOptions(context, profileImageUrl, 'avatar'); else if(profileImageUrl!=null) _openFullImage(context, profileImageUrl, 'avatar'); },
            child: Hero(tag: 'avatar', child: Stack(children: [
              CircleAvatar(radius: 49, backgroundColor: theme.scaffoldBackgroundColor, child: _buildAvatarImage(data)),
              if (isMyProfile) Positioned(bottom: 0, right: 0, child: Container(padding: EdgeInsets.all(6), decoration: BoxDecoration(color: TwitterTheme.blue, shape: BoxShape.circle, border: Border.all(color: theme.scaffoldBackgroundColor, width: 2)), child: Icon(Icons.camera_alt, size: 14, color: Colors.white)))
            ])),
          ),
        ),

        // 3. Action Buttons & Badges
        Positioned(
          top: 156,
          right: 16,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center, 
            children: [
              if (deptCode != null) ...[
                _buildDepartmentBadge(deptCode, dept, prodi),
                SizedBox(width: 8),
              ],
              isMyProfile 
              ? OutlinedButton(onPressed: () async { if(await Navigator.push(context, MaterialPageRoute(builder: (_) => EditProfileScreen())) == true) setState((){}); }, child: Text("Edit Profile"), style: OutlinedButton.styleFrom(shape: StadiumBorder()))
              : _buildFollowButton(data['followers'] ?? [])
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProfileInfoBody(BuildContext context, Map<String, dynamic> data) {
    final theme = Theme.of(context);
    final String name = data['name'] ?? 'Name';
    final String handle = "@${(data['email'] ?? '').split('@')[0]}";
    final String displayBio = _isBioExpanded ? (data['bio'] ?? '') : ((data['bio'] ?? '').length > 100 ? (data['bio'] ?? '').substring(0, 100) + '...' : (data['bio'] ?? ''));

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(name, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, fontSize: 22)),
        Text(handle, style: theme.textTheme.titleSmall),
        SizedBox(height: 8),
        Text(displayBio.isEmpty ? "No bio set." : displayBio, style: theme.textTheme.bodyLarge),
        if ((data['bio'] ?? '').length > 100) GestureDetector(onTap: () => setState(() => _isBioExpanded = !_isBioExpanded), child: Text(_isBioExpanded ? "Show less" : "Read more", style: TextStyle(color: TwitterTheme.blue, fontWeight: FontWeight.bold))),
        SizedBox(height: 8),
        Row(children: [Icon(Icons.calendar_today, size: 14, color: theme.hintColor), SizedBox(width: 4), Text(_formatJoinedDate(data['createdAt']), style: theme.textTheme.titleSmall)]),
        SizedBox(height: 8),
        Row(children: [_buildStatText(context, (data['following'] ?? []).length, "Following"), SizedBox(width: 16), _buildStatText(context, (data['followers'] ?? []).length, "Followers")]),
        SizedBox(height: 16),
      ])
    );
  }

  // --- Department Badge Logic ---
  void _showBadgeInfo(BuildContext context, String dept, String prodi) {
    showDialog(context: context, builder: (context) => AlertDialog(title: Text("Academic Info"), content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [Text("Department", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)), Text(dept, style: TextStyle(fontSize: 16)), SizedBox(height: 16), Text("Study Program", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)), Text(prodi, style: TextStyle(fontSize: 16))]), actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text("Close", style: TextStyle(color: TwitterTheme.blue)))]));
  }

  Widget _buildDepartmentBadge(String code, String? fullDeptName, String? fullProdiName) {
    final parts = code.split('-');
    if (parts.length < 2) return SizedBox.shrink();
    final dept = parts[0]; final prodi = parts[1]; 
    Color deptColor = (dept.toUpperCase() == 'TE') ? Color(0xFF00008B) : (dept.toUpperCase() == 'TS' ? Color(0xFF5D4037) : Colors.primaries[dept.hashCode.abs() % Colors.primaries.length]);
    Color prodiColor = (prodi.toUpperCase() == 'BM') ? Colors.orange : Colors.primaries[prodi.hashCode.abs() % Colors.primaries.length];
    return GestureDetector(
      onTap: () { if (fullDeptName != null && fullProdiName != null) _showBadgeInfo(context, fullDeptName, fullProdiName); },
      child: Row(mainAxisSize: MainAxisSize.min, children: [Container(padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: deptColor, borderRadius: BorderRadius.circular(4)), child: Text(dept, style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))), SizedBox(width: 4), Container(padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: prodiColor, borderRadius: BorderRadius.circular(4)), child: Text(prodi, style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)))]),
    );
  }

  Widget _buildAvatarImage(Map<String, dynamic> data) {
    if (data['profileImageUrl'] != null) return CircleAvatar(radius: 45, backgroundImage: CachedNetworkImageProvider(data['profileImageUrl']));
    return CircleAvatar(radius: 45, backgroundColor: AvatarHelper.getColor(data['avatarHex']), child: Icon(AvatarHelper.getIcon(data['avatarIconId']??0), size: 50, color: Colors.white));
  }

  Widget _buildFollowButton(List followers) {
    return followers.contains(_user?.uid) 
      ? OutlinedButton(onPressed: _unfollowUser, child: Text("Unfollow"))
      : ElevatedButton(onPressed: _followUser, child: Text("Follow"), style: ElevatedButton.styleFrom(backgroundColor: TwitterTheme.blue, foregroundColor: Colors.white));
  }

  Widget _buildStatText(BuildContext context, int count, String label) => Row(children: [Text("$count", style: TextStyle(fontWeight: FontWeight.bold)), SizedBox(width: 4), Text(label, style: TextStyle(color: Theme.of(context).hintColor))]);

  // --- POSTS LISTS ---

  Widget _buildMyPosts(BuildContext context, String userId) {
    return FutureBuilder<DocumentSnapshot>(
      future: _firestore.collection('users').doc(userId).get(),
      builder: (context, userSnapshot) {
        final firestorePinned = (userSnapshot.data?.data() as Map<String, dynamic>?)?['pinnedPostId'];
        final activePinnedId = _optimisticPinnedPostId == '' ? null : (_optimisticPinnedPostId ?? firestorePinned);

        return StreamBuilder<QuerySnapshot>(
          stream: _firestore.collection('posts').where('userId', isEqualTo: userId).orderBy('timestamp', descending: true).snapshots(),
          builder: (context, snapshot) {
            List<Widget> slivers = [];
            
            if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
              slivers.add(SliverFillRemaining(child: Center(child: CircularProgressIndicator())));
            } else {
              final docs = snapshot.data?.docs ?? [];
              if (docs.isEmpty) {
                slivers.add(SliverFillRemaining(child: Center(child: Text("No posts yet."))));
              } else {
                if (activePinnedId != null) {
                  final index = docs.indexWhere((d) => d.id == activePinnedId);
                  if (index != -1) {
                    final pinned = docs.removeAt(index);
                    docs.insert(0, pinned);
                  }
                }
                slivers.add(SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final doc = docs[index];
                      // FIX: Removed Column wrapper
                      return BlogPostCard(
                        postId: doc.id,
                        postData: doc.data() as Map<String, dynamic>,
                        isOwner: doc['userId'] == _auth.currentUser?.uid,
                        heroContextId: 'profile_posts',
                        isPinned: doc.id == activePinnedId,
                        onPinToggle: (id, isPinned) => _handlePinToggle(id, isPinned),
                      );
                    },
                    childCount: docs.length,
                  ),
                ));
                slivers.add(SliverToBoxAdapter(child: SizedBox(height: 80)));
              }
            }

            return CustomScrollView(
              key: PageStorageKey('posts_$userId'),
              physics: const AlwaysScrollableScrollPhysics(), 
              slivers: slivers,
            );
          },
        );
      }
    );
  }

  Widget _buildMyReplies(BuildContext context, String userId) {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collectionGroup('comments').where('userId', isEqualTo: userId).orderBy('timestamp', descending: true).snapshots(),
      builder: (context, snapshot) {
        List<Widget> slivers = [];

        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          slivers.add(SliverFillRemaining(child: Center(child: CircularProgressIndicator())));
        } else {
          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            slivers.add(SliverFillRemaining(child: Center(child: Text("No replies yet."))));
          } else {
            slivers.add(SliverList(delegate: SliverChildBuilderDelegate((context, index) {
              final doc = docs[index];
              // FIX: Removed Column, added Theme to remove padding/gaps for seamless connection
              return Theme(
                data: Theme.of(context).copyWith(
                  listTileTheme: ListTileThemeData(
                    minVerticalPadding: 0,
                    visualDensity: VisualDensity.compact,
                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                  ),
                ),
                child: CommentTile(
                  commentId: doc.id, 
                  commentData: doc.data() as Map<String, dynamic>, 
                  postId: doc.reference.parent.parent!.id, 
                  isOwner: true, 
                  showPostContext: true, 
                  heroContextId: 'profile_replies'
                ),
              );
            }, childCount: docs.length)));
            slivers.add(SliverToBoxAdapter(child: SizedBox(height: 80)));
          }
        }

        return CustomScrollView(
          key: PageStorageKey('replies_$userId'),
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: slivers,
        );
      },
    );
  }

  Widget _buildMyReposts(BuildContext context, String userId) {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('posts').where('repostedBy', arrayContains: userId).orderBy('timestamp', descending: true).snapshots(),
      builder: (context, snapshot) {
        List<Widget> slivers = [];

        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          slivers.add(SliverFillRemaining(child: Center(child: CircularProgressIndicator())));
        } else {
          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            slivers.add(SliverFillRemaining(child: Center(child: Text("No reposts yet."))));
          } else {
            slivers.add(SliverList(delegate: SliverChildBuilderDelegate((context, index) {
              final doc = docs[index];
              // FIX: Removed Column wrapper
              return BlogPostCard(
                postId: doc.id, 
                postData: doc.data() as Map<String, dynamic>, 
                isOwner: doc['userId'] == _auth.currentUser?.uid, 
                heroContextId: 'profile_reposts'
              );
            }, childCount: docs.length)));
            slivers.add(SliverToBoxAdapter(child: SizedBox(height: 80)));
          }
        }

        return CustomScrollView(
          key: PageStorageKey('reposts_$userId'),
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: slivers,
        );
      },
    );
  }
}

class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar _tabBar;
  final Color backgroundColor;
  
  _SliverAppBarDelegate(this._tabBar, this.backgroundColor);
  
  @override double get minExtent => _tabBar.preferredSize.height;
  @override double get maxExtent => _tabBar.preferredSize.height;
  @override Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => Container(color: backgroundColor, child: _tabBar);
  @override bool shouldRebuild(_SliverAppBarDelegate oldDelegate) => true;
}