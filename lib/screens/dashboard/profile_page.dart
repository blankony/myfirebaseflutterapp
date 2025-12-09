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

import '../../widgets/blog_post_card.dart';
import '../../widgets/comment_tile.dart';
import '../../widgets/common_error_widget.dart'; 
import '../../main.dart';
import '../edit_profile_screen.dart';
import '../image_viewer_screen.dart';
import 'settings_page.dart';
import '../../services/overlay_service.dart';
import '../../services/cloudinary_service.dart';
import '../../services/moderation_service.dart'; 
import '../follow_list_screen.dart'; 
import '../ktm_verification_screen.dart'; 

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
  
  bool _isBlocked = false;
  String? _optimisticPinnedPostId; 
  
  bool _isProcessingFollow = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _user = _auth.currentUser;
    _userId = widget.userId ?? _user!.uid;
    
    _checkBlockedStatus();

    _tabController = TabController(
      length: 3, 
      vsync: this, 
      initialIndex: 0,
    );
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _tabController.index = 0;
    });
    
    _scrollController.addListener(_scrollListener);
  }

  @override
  void reassemble() {
    super.reassemble();
    if (_tabController.index != 0) {
      _tabController.index = 0;
    }
  }
  
  void _checkBlockedStatus() async {
    if (_user == null) return;
    moderationService.streamBlockedUsers().listen((blockedList) {
      if (mounted) {
        setState(() {
          _isBlocked = blockedList.contains(_userId);
        });
      }
    });
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

  void _handlePinToggle(String postId, bool isPinned) {
    setState(() {
      _optimisticPinnedPostId = isPinned ? postId : ''; 
    });
    
    if (isPinned) {
      OverlayService().showTopNotification(context, "Post pinned to profile", Icons.push_pin, (){});
    } else {
      OverlayService().showTopNotification(context, "Post unpinned", Icons.push_pin_outlined, (){});
    }
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

  void _showImageSourceSelection({required bool isBanner}) {
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
              ListTile(
                leading: Icon(Icons.camera_alt, color: TwitterTheme.blue),
                title: Text("Take from Camera"),
                onTap: () {
                  Navigator.pop(context);
                  _pickAndUploadImage(isBanner: isBanner, source: ImageSource.camera);
                },
              ),
              ListTile(
                leading: Icon(Icons.photo_library, color: TwitterTheme.blue),
                title: Text("Choose from Gallery"),
                onTap: () {
                  Navigator.pop(context);
                  _pickAndUploadImage(isBanner: isBanner, source: ImageSource.gallery);
                },
              ),
              SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickAndUploadImage({required bool isBanner, required ImageSource source}) async {
    final picker = ImagePicker();
    final XFile? pickedFile = await picker.pickImage(source: source, imageQuality: 70);
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
                onTap: () { Navigator.pop(context); _showImageSourceSelection(isBanner: true); },
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
                onTap: () { Navigator.pop(context); _showImageSourceSelection(isBanner: false); },
              ),
              SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  Future<void> _followUser(bool isPrivate) async {
    if (_user == null || _isProcessingFollow) return;
    setState(() => _isProcessingFollow = true);
    
    try {
      if (isPrivate) {
        await _firestore.collection('users').doc(_userId).collection('follow_requests').doc(_user!.uid).set({
          'timestamp': FieldValue.serverTimestamp(),
          'status': 'pending',
        });
        
        await _firestore.collection('users').doc(_userId).collection('notifications').doc('request_${_user!.uid}').set({
          'type': 'follow_request',
          'senderId': _user!.uid,
          'timestamp': FieldValue.serverTimestamp(),
          'isRead': false,
        });
        
        if(mounted) OverlayService().showTopNotification(context, "Follow request sent", Icons.send, (){}, color: Colors.blue);
      } else {
        final batch = _firestore.batch();
        final myDocRef = _firestore.collection('users').doc(_user!.uid);
        final targetDocRef = _firestore.collection('users').doc(_userId);
        batch.update(myDocRef, {'following': FieldValue.arrayUnion([_userId])});
        batch.update(targetDocRef, {'followers': FieldValue.arrayUnion([_user!.uid])});
        await batch.commit();
        
        _firestore.collection('users').doc(_userId).collection('notifications').add({
          'type': 'follow', 'senderId': _user!.uid, 'timestamp': FieldValue.serverTimestamp(), 'isRead': false,
        });
      }
    } catch (e) {
       if(mounted) OverlayService().showTopNotification(context, "Failed to action: $e", Icons.error, (){}, color: Colors.red);
    } finally {
      if(mounted) setState(() => _isProcessingFollow = false);
    }
  }

  Future<void> _unfollowUser(bool isRequestOnly) async {
    if (_user == null || _isProcessingFollow) return;
    setState(() => _isProcessingFollow = true);

    try {
      if (isRequestOnly) {
        await _firestore.collection('users').doc(_userId).collection('follow_requests').doc(_user!.uid).delete();
        await _firestore.collection('users').doc(_userId).collection('notifications').doc('request_${_user!.uid}').delete();
        if(mounted) OverlayService().showTopNotification(context, "Request cancelled", Icons.close, (){});
      } else {
        final batch = _firestore.batch();
        final myDocRef = _firestore.collection('users').doc(_user!.uid);
        final targetDocRef = _firestore.collection('users').doc(_userId);
        batch.update(myDocRef, {'following': FieldValue.arrayRemove([_userId])});
        batch.update(targetDocRef, {'followers': FieldValue.arrayRemove([_user!.uid])});
        await batch.commit();
      }
    } catch (e) { 
      if(mounted) OverlayService().showTopNotification(context, "Action failed", Icons.error, (){}, color: Colors.red); 
    } finally {
      if(mounted) setState(() => _isProcessingFollow = false);
    }
  }

  void _shareProfile(String name) { Share.share("Check out $name's profile on Sapa PNJ!"); }
  
  Future<void> _toggleBlock() async {
    if (_isBlocked) {
      await moderationService.unblockUser(_userId);
      if(mounted) OverlayService().showTopNotification(context, "User unblocked", Icons.check_circle, (){});
    } else {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text("Block User?"),
          content: Text("They will not be able to follow you or see your posts."),
          actions: [
            TextButton(onPressed: ()=>Navigator.pop(ctx, false), child: Text("Cancel")),
            TextButton(onPressed: ()=>Navigator.pop(ctx, true), child: Text("Block", style: TextStyle(color: Colors.red))),
          ],
        )
      ) ?? false;
      if (confirm) {
        await moderationService.blockUser(_userId);
        if(mounted) OverlayService().showTopNotification(context, "User blocked", Icons.block, (){});
      }
    }
  }

  void _reportUser() {
    showDialog(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: Text("Report User"),
          children: [
            SimpleDialogOption(onPressed: () => _submitReport('Spam'), child: Text('Spam Account')),
            SimpleDialogOption(onPressed: () => _submitReport('Impersonation'), child: Text('Impersonation')),
            SimpleDialogOption(onPressed: () => _submitReport('Inappropriate Profile'), child: Text('Inappropriate Profile')),
            Padding(padding: EdgeInsets.all(8), child: TextButton(onPressed: ()=>Navigator.pop(context), child: Text("Cancel"))),
          ],
        );
      }
    );
  }

  void _submitReport(String reason) {
    Navigator.pop(context);
    moderationService.reportContent(
      targetId: _userId, 
      targetType: 'user', 
      reason: reason
    );
    OverlayService().showTopNotification(context, "Report submitted.", Icons.flag, (){});
  }

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

    return StreamBuilder<DocumentSnapshot>(
      stream: _firestore.collection('users').doc(_userId).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(appBar: AppBar(title: Text("Error")), body: Center(child: Text("Something went wrong.")));
        }

        final data = snapshot.data?.data() as Map<String, dynamic>? ?? {};
        final name = data['name'] ?? 'User';
        
        final bool isMyProfile = _user?.uid == _userId;
        final bool isPrivateAccount = data['isPrivate'] ?? false;
        final List<dynamic> followers = data['followers'] ?? [];
        final bool amIFollowing = followers.contains(_user?.uid);
        
        final bool canViewProfile = isMyProfile || !isPrivateAccount || amIFollowing;

        final String verificationStatus = data['verificationStatus'] ?? 'none'; 
        final bool isVerified = verificationStatus == 'verified';

        Widget content = RefreshIndicator(
          onRefresh: _handleRefresh,
          color: TwitterTheme.blue,
          edgeOffset: pinnedHeaderHeight,
          notificationPredicate: (notification) => true,
          child: NestedScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            headerSliverBuilder: (context, innerBoxIsScrolled) {
              return [
                SliverAppBar(
                  pinned: true,
                  elevation: 0,
                  scrolledUnderElevation: 0,
                  expandedHeight: 218.0, 
                  backgroundColor: isDarkMode ? Color(0xFF15202B) : TwitterTheme.white,
                  iconTheme: IconThemeData(color: isDarkMode ? TwitterTheme.white : TwitterTheme.blue),
                  automaticallyImplyLeading: widget.includeScaffold,
                  
                  title: AnimatedOpacity(
                    opacity: _isScrolled ? 1.0 : 0.0,
                    duration: Duration(milliseconds: 200),
                    child: Row(
                      children: [
                        Text(
                          name, 
                          style: TextStyle(
                            color: isDarkMode ? TwitterTheme.white : TwitterTheme.black, 
                            fontWeight: FontWeight.bold
                          )
                        ),
                        if (isVerified) ...[
                          SizedBox(width: 4),
                          Icon(Icons.verified, size: 16, color: TwitterTheme.blue),
                        ] else if (isPrivateAccount) ...[
                          SizedBox(width: 4),
                          Icon(Icons.lock, size: 16, color: isDarkMode ? TwitterTheme.white : TwitterTheme.black),
                        ],
                      ],
                    ),
                  ),
                  centerTitle: false,
                  actions: [
                     _buildActionMenu(context, data, isMyProfile),
                  ],
                  flexibleSpace: FlexibleSpaceBar(
                    background: _buildHeaderFlexibleSpace(context, data, isMyProfile, isPrivateAccount, amIFollowing),
                  ),
                ),

                SliverToBoxAdapter(
                  child: _buildProfileInfoBody(context, data, isMyProfile),
                ),

                if (!_isBlocked && canViewProfile)
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
            
            body: _isBlocked 
                ? _buildBlockedBody()
                : (!canViewProfile)
                    ? _buildPrivateAccountBody() 
                    : TabBarView(
                        controller: _tabController,
                        children: [
                          Builder(builder: (context) => _buildMyPosts(context, _userId)),
                          Builder(builder: (context) => _buildMyReposts(context, _userId)),
                          Builder(builder: (context) => _buildMyReplies(context, _userId)),
                        ],
                      ),
          ),
        );

        return widget.includeScaffold 
            ? Scaffold(extendBodyBehindAppBar: true, body: content) 
            : content;
      }
    );
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
        if (value == 'block') _toggleBlock();
        if (value == 'report') _reportUser();
      },
      itemBuilder: (context) => isMyProfile 
        ? [PopupMenuItem(value: 'share', child: Text('Share Profile')), PopupMenuItem(value: 'settings', child: Text('Settings')), PopupMenuItem(value: 'logout', child: Text('Logout', style: TextStyle(color: Colors.red)))]
        : [
            PopupMenuItem(value: 'share', child: Text('Share Account')), 
            PopupMenuItem(value: 'report', child: Text('Report User')),
            PopupMenuItem(value: 'block', child: Text(_isBlocked ? 'Unblock' : 'Block', style: TextStyle(color: Colors.red))),
          ],
    );
  }

  Widget _buildHeaderFlexibleSpace(
    BuildContext context, 
    Map<String, dynamic> data, 
    bool isMyProfile, 
    bool isPrivate, 
    bool amIFollowing
  ) {
    final theme = Theme.of(context);
    final String? bannerImageUrl = data['bannerImageUrl'];
    final String? profileImageUrl = data['profileImageUrl'];
    final String? dept = data['department'];
    final String? prodi = data['studyProgram'];
    final String? deptCode = data['departmentCode'];
    
    return Stack(
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 150,
          child: GestureDetector(
            onTap: () { 
              if(isMyProfile) _showBannerOptions(context, bannerImageUrl, 'banner'); 
              else if(bannerImageUrl!=null && !_isBlocked) _openFullImage(context, bannerImageUrl, 'banner'); 
            },
            child: Hero(
              tag: 'banner', 
              child: Container(
                color: TwitterTheme.darkGrey, 
                child: bannerImageUrl != null 
                  ? CachedNetworkImage(imageUrl: bannerImageUrl, fit: BoxFit.cover, errorWidget: (context, url, error) => Container(color: TwitterTheme.darkGrey)) 
                  : (isMyProfile ? Center(child: Icon(Icons.camera_alt, color: Colors.white)) : null)
              )
            ),
          ),
        ),
        
        Positioned(
          top: 120, 
          left: 16,
          child: GestureDetector(
            onTap: () { 
              if(isMyProfile) _showProfileOptions(context, profileImageUrl, 'avatar'); 
              else if(profileImageUrl!=null && !_isBlocked) _openFullImage(context, profileImageUrl, 'avatar'); 
            },
            child: Hero(tag: 'avatar', child: Stack(children: [
              CircleAvatar(radius: 49, backgroundColor: theme.scaffoldBackgroundColor, child: _buildAvatarImage(data)),
            ])),
          ),
        ),

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
              : _isBlocked 
                ? ElevatedButton(onPressed: _toggleBlock, child: Text("Unblock"), style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white))
                : _buildFollowButton(isPrivate, amIFollowing)
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFollowButton(bool isPrivate, bool amIFollowing) {
    if (amIFollowing) {
      return OutlinedButton(
        onPressed: _isProcessingFollow ? null : () => _unfollowUser(false), 
        child: Text("Unfollow")
      );
    }

    if (!isPrivate) {
      return ElevatedButton(
        onPressed: _isProcessingFollow ? null : () => _followUser(false), 
        style: ElevatedButton.styleFrom(backgroundColor: TwitterTheme.blue, foregroundColor: Colors.white),
        child: Text("Follow"),
      );
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: _firestore
          .collection('users')
          .doc(_userId)
          .collection('follow_requests')
          .doc(_user!.uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data!.exists) {
          return OutlinedButton(
            onPressed: _isProcessingFollow ? null : () => _unfollowUser(true), 
            style: OutlinedButton.styleFrom(
              backgroundColor: Theme.of(context).cardColor,
              side: BorderSide(color: Theme.of(context).dividerColor),
            ),
            child: Text("Requested", style: TextStyle(color: Theme.of(context).hintColor)),
          );
        }
        
        return ElevatedButton(
          onPressed: _isProcessingFollow ? null : () => _followUser(true), 
          style: ElevatedButton.styleFrom(backgroundColor: TwitterTheme.blue, foregroundColor: Colors.white),
          child: Text("Follow"),
        );
      },
    );
  }

  Widget _buildProfileInfoBody(BuildContext context, Map<String, dynamic> data, bool isMyProfile) {
    final theme = Theme.of(context);
    final String name = data['name'] ?? 'Name';
    final String handle = "@${(data['email'] ?? '').split('@')[0]}";
    final String displayBio = _isBioExpanded ? (data['bio'] ?? '') : ((data['bio'] ?? '').length > 100 ? (data['bio'] ?? '').substring(0, 100) + '...' : (data['bio'] ?? ''));
    
    final String verificationStatus = data['verificationStatus'] ?? 'none';
    final bool isVerified = verificationStatus == 'verified';
    final bool isPending = verificationStatus == 'pending';

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(
          children: [
            Flexible(
              child: Text(name, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, fontSize: 22), overflow: TextOverflow.ellipsis),
            ),
            if (isVerified) ...[
              SizedBox(width: 4),
              Icon(Icons.verified, size: 22, color: TwitterTheme.blue),
            ] else if (data['isPrivate'] ?? false) ...[
              SizedBox(width: 6),
              Icon(Icons.lock, size: 22, color: theme.textTheme.titleLarge?.color),
            ],
          ],
        ),
        Text(handle, style: theme.textTheme.titleSmall),
        
        if (isMyProfile && !isVerified)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: InkWell(
              onTap: isPending 
                ? () => OverlayService().showTopNotification(context, "Verification is under review.", Icons.access_time, (){}, color: Colors.orange)
                : () => Navigator.push(context, MaterialPageRoute(builder: (_) => KtmVerificationScreen())),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isPending ? Colors.orange.withOpacity(0.1) : TwitterTheme.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: isPending ? Colors.orange : TwitterTheme.blue),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(isPending ? Icons.hourglass_top : Icons.verified_outlined, size: 16, color: isPending ? Colors.orange : TwitterTheme.blue),
                    SizedBox(width: 6),
                    Text(
                      isPending ? "Verification Pending" : "Get Verified", 
                      style: TextStyle(color: isPending ? Colors.orange : TwitterTheme.blue, fontWeight: FontWeight.bold, fontSize: 12)
                    ),
                  ],
                ),
              ),
            ),
          ),

        SizedBox(height: 8),
        if (!_isBlocked) ...[
          Text(displayBio.isEmpty ? "No bio set." : displayBio, style: theme.textTheme.bodyLarge),
          if ((data['bio'] ?? '').length > 100) GestureDetector(onTap: () => setState(() => _isBioExpanded = !_isBioExpanded), child: Text(_isBioExpanded ? "Show less" : "Read more", style: TextStyle(color: TwitterTheme.blue, fontWeight: FontWeight.bold))),
          SizedBox(height: 8),
          Row(children: [Icon(Icons.calendar_today, size: 14, color: theme.hintColor), SizedBox(width: 4), Text(_formatJoinedDate(data['createdAt']), style: theme.textTheme.titleSmall)]),
          SizedBox(height: 8),
          Row(
            children: [
              _buildStatText(context, (data['following'] ?? []).length, "Following", 1), 
              SizedBox(width: 16), 
              _buildStatText(context, (data['followers'] ?? []).length, "Followers", 2)
            ]
          ),
          SizedBox(height: 16),
        ]
      ])
    );
  }

  Widget _buildBlockedBody() {
    return Container(
      alignment: Alignment.center,
      padding: EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.block, size: 64, color: Colors.grey),
          SizedBox(height: 16),
          Text("You have blocked this user.", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          SizedBox(height: 8),
          Text("You cannot see their posts or interact with them.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
          SizedBox(height: 16),
          OutlinedButton(onPressed: _toggleBlock, child: Text("Unblock"))
        ],
      ),
    );
  }

  Widget _buildPrivateAccountBody() {
    final theme = Theme.of(context);
    return Container(
      alignment: Alignment.center,
      padding: EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: theme.dividerColor, width: 2)
            ),
            child: Icon(Icons.lock_outline, size: 48, color: theme.primaryColor),
          ),
          SizedBox(height: 24),
          Text(
            "This account is private",
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 8),
          Text(
            "Follow this account to see their posts and replies.",
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
          ),
        ],
      ),
    );
  }

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

  Widget _buildStatText(BuildContext context, int count, String label, int tabIndex) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => FollowListScreen(
              userId: _userId,
              initialIndex: tabIndex, 
            )
          )
        );
      },
      child: Row(
        children: [
          Text("$count", style: TextStyle(fontWeight: FontWeight.bold)), 
          SizedBox(width: 4), 
          Text(label, style: TextStyle(color: Theme.of(context).hintColor))
        ]
      ),
    );
  }

  Widget _buildMyPosts(BuildContext context, String userId) {
    return FutureBuilder<DocumentSnapshot>(
      future: _firestore.collection('users').doc(userId).get(),
      builder: (context, userSnapshot) {
        if (userSnapshot.hasError) return CommonErrorWidget(message: "Failed to load posts.", isConnectionError: true);
        
        final firestorePinned = (userSnapshot.data?.data() as Map<String, dynamic>?)?['pinnedPostId'];
        final activePinnedId = _optimisticPinnedPostId == '' ? null : (_optimisticPinnedPostId ?? firestorePinned);

        return StreamBuilder<QuerySnapshot>(
          stream: _firestore.collection('posts').where('userId', isEqualTo: userId).orderBy('timestamp', descending: true).snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) return CommonErrorWidget(message: "Failed to load posts stream.", isConnectionError: true);
            
            List<Widget> slivers = [];
            if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
              slivers.add(SliverFillRemaining(child: Center(child: CircularProgressIndicator())));
            } else {
              final allDocs = snapshot.data?.docs ?? [];
              
              final visibleDocs = allDocs.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                
                // NEW: Hide community identity posts on personal profile
                final bool isCommunityIdentityPost = data['isCommunityPost'] ?? false;
                if (isCommunityIdentityPost) return false;

                final visibility = data['visibility'] ?? 'public';
                final ownerId = data['userId'];
                
                if (visibility == 'public') return true;
                if (visibility == 'followers') return true;
                if (visibility == 'private' && ownerId == _auth.currentUser?.uid) return true;
                
                return false;
              }).toList();

              if (visibleDocs.isEmpty) {
                slivers.add(SliverFillRemaining(child: Center(child: Text("No posts yet."))));
              } else {
                if (activePinnedId != null) {
                  final index = visibleDocs.indexWhere((d) => d.id == activePinnedId);
                  if (index != -1) {
                    final pinned = visibleDocs.removeAt(index);
                    visibleDocs.insert(0, pinned);
                  }
                }
                slivers.add(SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final doc = visibleDocs[index];
                      return BlogPostCard(
                        key: ValueKey(doc.id),
                        postId: doc.id,
                        postData: doc.data() as Map<String, dynamic>,
                        isOwner: doc['userId'] == _auth.currentUser?.uid,
                        heroContextId: 'profile_posts',
                        isPinned: doc.id == activePinnedId,
                        onPinToggle: (id, isPinned) => _handlePinToggle(id, isPinned),
                        currentProfileUserId: _userId,
                      );
                    },
                    childCount: visibleDocs.length,
                  ),
                ));
                slivers.add(SliverToBoxAdapter(child: SizedBox(height: 80)));
              }
            }

            return CustomScrollView(
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
        if (snapshot.hasError) return CommonErrorWidget(message: "Failed to load replies.", isConnectionError: true);
        
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
              final parentPostId = doc.reference.parent.parent!.id;

              return StreamBuilder<DocumentSnapshot>(
                stream: _firestore.collection('posts').doc(parentPostId).snapshots(),
                builder: (context, parentSnapshot) {
                  if (!parentSnapshot.hasData || !parentSnapshot.data!.exists) return SizedBox.shrink();
                  
                  final parentData = parentSnapshot.data!.data() as Map<String, dynamic>;
                  final visibility = parentData['visibility'] ?? 'public';
                  final ownerId = parentData['userId'];
                  
                  final isVisible = (visibility == 'public') || 
                                    (visibility == 'followers') || 
                                    (visibility == 'private' && ownerId == _auth.currentUser?.uid);
                  
                  if (isVisible) {
                    return Theme(
                      data: Theme.of(context).copyWith(listTileTheme: ListTileThemeData(minVerticalPadding: 0, visualDensity: VisualDensity.compact, contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 0))),
                      child: CommentTile(
                        key: ValueKey(doc.id), 
                        commentId: doc.id, 
                        commentData: doc.data() as Map<String, dynamic>, 
                        postId: parentPostId, 
                        isOwner: true, 
                        showPostContext: true, 
                        heroContextId: 'profile_replies',
                        currentProfileUserId: _userId,
                      ),
                    );
                  }
                  return SizedBox.shrink(); 
                },
              );
            }, childCount: docs.length)));
            slivers.add(SliverToBoxAdapter(child: SizedBox(height: 80)));
          }
        }
        return CustomScrollView(physics: const AlwaysScrollableScrollPhysics(), slivers: slivers);
      },
    );
  }

  Widget _buildMyReposts(BuildContext context, String userId) {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('posts').where('repostedBy', arrayContains: userId).orderBy('timestamp', descending: true).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return CommonErrorWidget(message: "Failed to load reposts.", isConnectionError: true);
        List<Widget> slivers = [];
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          slivers.add(SliverFillRemaining(child: Center(child: CircularProgressIndicator())));
        } else {
          final allDocs = snapshot.data?.docs ?? [];
          
          final visibleDocs = allDocs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final visibility = data['visibility'] ?? 'public';
            final ownerId = data['userId'];
            
            if (visibility == 'public') return true;
            if (visibility == 'followers') return true; 
            if (visibility == 'private' && ownerId == _auth.currentUser?.uid) return true;
            
            return false;
          }).toList();

          if (visibleDocs.isEmpty) {
            slivers.add(SliverFillRemaining(child: Center(child: Text("No reposts yet."))));
          } else {
            slivers.add(SliverList(delegate: SliverChildBuilderDelegate((context, index) {
              final doc = visibleDocs[index];
              return BlogPostCard(
                key: ValueKey('repost_${doc.id}'),
                postId: doc.id, 
                postData: doc.data() as Map<String, dynamic>, 
                isOwner: doc['userId'] == _auth.currentUser?.uid, 
                heroContextId: 'profile_reposts',
                currentProfileUserId: _userId,
              );
            }, childCount: visibleDocs.length)));
            slivers.add(SliverToBoxAdapter(child: SizedBox(height: 80)));
          }
        }

        return CustomScrollView(
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