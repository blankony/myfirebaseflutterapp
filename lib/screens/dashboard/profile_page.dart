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
import '../../services/app_localizations.dart'; // IMPORT LOCALIZATION

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
    
    // Force reload user data to get fresh emailVerified status on init
    _user?.reload();

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
    
    // LOCALIZATION
    var t = AppLocalizations.of(context)!;
    
    if (isPinned) {
      OverlayService().showTopNotification(context, t.translate('profile_pin_success'), Icons.push_pin, (){});
    } else {
      OverlayService().showTopNotification(context, t.translate('profile_unpin_success'), Icons.push_pin_outlined, (){});
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
    // LOCALIZATION
    var t = AppLocalizations.of(context)!;

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
                    Text(t.translate('profile_uploading'), style: TextStyle(fontWeight: FontWeight.bold)),
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
    // LOCALIZATION
    var t = AppLocalizations.of(context)!;

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
                title: Text(t.translate('profile_camera')),
                onTap: () {
                  Navigator.pop(context);
                  _pickAndUploadImage(isBanner: isBanner, source: ImageSource.camera);
                },
              ),
              ListTile(
                leading: Icon(Icons.photo_library, color: TwitterTheme.blue),
                title: Text(t.translate('profile_gallery')),
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
    // LOCALIZATION
    var t = AppLocalizations.of(context)!;

    final picker = ImagePicker();
    final XFile? pickedFile = await picker.pickImage(source: source, imageQuality: 70);
    if (pickedFile == null) return;

    final croppedFile = await ImageCropper().cropImage(
      sourcePath: pickedFile.path,
      compressQuality: 70,
      aspectRatio: isBanner ? CropAspectRatio(ratioX: 3, ratioY: 1) : CropAspectRatio(ratioX: 1, ratioY: 1),
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: isBanner ? t.translate('profile_crop_banner') : t.translate('profile_crop_avatar'), 
          toolbarColor: TwitterTheme.blue, 
          toolbarWidgetColor: Colors.white, 
          initAspectRatio: isBanner ? CropAspectRatioPreset.ratio3x2 : CropAspectRatioPreset.square, 
          lockAspectRatio: true
        ),
        IOSUiSettings(title: isBanner ? t.translate('profile_crop_banner') : t.translate('profile_crop_avatar'), aspectRatioLockEnabled: true),
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
        if (mounted) OverlayService().showTopNotification(context, t.translate('profile_update_success'), Icons.check_circle, (){}, color: Colors.green);
      }
    } catch (e) {
      try { loadingOverlay.remove(); } catch(_) {}
      if (mounted) OverlayService().showTopNotification(context, t.translate('profile_upload_fail'), Icons.error, (){}, color: Colors.red);
    }
  }

  void _showBannerOptions(BuildContext context, String? currentBannerUrl, String heroTag) {
    var t = AppLocalizations.of(context)!;
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
                  title: Text(t.translate('profile_view_banner')),
                  onTap: () { Navigator.pop(context); _openFullImage(context, currentBannerUrl, heroTag); },
                ),
              ListTile(
                leading: Icon(Icons.photo_library_outlined, color: TwitterTheme.blue),
                title: Text(t.translate('profile_change_banner')),
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
    var t = AppLocalizations.of(context)!;
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
                  title: Text(t.translate('profile_view_photo')),
                  onTap: () { Navigator.pop(context); _openFullImage(context, currentImageUrl, heroTag); },
                ),
              ListTile(
                leading: Icon(Icons.photo_library_outlined, color: TwitterTheme.blue),
                title: Text(t.translate('profile_change_photo')),
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
    var t = AppLocalizations.of(context)!;
    
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
        
        if(mounted) OverlayService().showTopNotification(context, t.translate('profile_req_sent'), Icons.send, (){}, color: Colors.blue);
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
       if(mounted) OverlayService().showTopNotification(context, "${t.translate('profile_action_fail')}: $e", Icons.error, (){}, color: Colors.red);
    } finally {
      if(mounted) setState(() => _isProcessingFollow = false);
    }
  }

  Future<void> _unfollowUser(bool isRequestOnly) async {
    if (_user == null || _isProcessingFollow) return;
    setState(() => _isProcessingFollow = true);
    var t = AppLocalizations.of(context)!;

    try {
      if (isRequestOnly) {
        await _firestore.collection('users').doc(_userId).collection('follow_requests').doc(_user!.uid).delete();
        await _firestore.collection('users').doc(_userId).collection('notifications').doc('request_${_user!.uid}').delete();
        if(mounted) OverlayService().showTopNotification(context, t.translate('profile_req_cancel'), Icons.close, (){});
      } else {
        final batch = _firestore.batch();
        final myDocRef = _firestore.collection('users').doc(_user!.uid);
        final targetDocRef = _firestore.collection('users').doc(_userId);
        batch.update(myDocRef, {'following': FieldValue.arrayRemove([_userId])});
        batch.update(targetDocRef, {'followers': FieldValue.arrayRemove([_user!.uid])});
        await batch.commit();
      }
    } catch (e) { 
      if(mounted) OverlayService().showTopNotification(context, t.translate('profile_action_fail'), Icons.error, (){}, color: Colors.red); 
    } finally {
      if(mounted) setState(() => _isProcessingFollow = false);
    }
  }

  void _shareProfile(String name) { 
    var t = AppLocalizations.of(context)!;
    // Simple localization, assuming name doesn't need translation
    Share.share(t.translate('profile_share_text')); 
  }
  
  Future<void> _toggleBlock() async {
    var t = AppLocalizations.of(context)!;
    if (_isBlocked) {
      await moderationService.unblockUser(_userId);
      if(mounted) OverlayService().showTopNotification(context, t.translate('profile_unblocked'), Icons.check_circle, (){});
    } else {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(t.translate('profile_block_confirm_title')),
          content: Text(t.translate('profile_block_confirm_desc')),
          actions: [
            TextButton(onPressed: ()=>Navigator.pop(ctx, false), child: Text(t.translate('general_cancel'))),
            TextButton(onPressed: ()=>Navigator.pop(ctx, true), child: Text(t.translate('general_delete'), style: TextStyle(color: Colors.red))), // Using general_delete as "Block" action often red
          ],
        )
      ) ?? false;
      if (confirm) {
        await moderationService.blockUser(_userId);
        if(mounted) OverlayService().showTopNotification(context, t.translate('profile_blocked'), Icons.block, (){});
      }
    }
  }

  void _reportUser() {
    var t = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: Text(t.translate('profile_report_title')),
          children: [
            SimpleDialogOption(onPressed: () => _submitReport('Spam'), child: Text(t.translate('profile_report_spam'))),
            SimpleDialogOption(onPressed: () => _submitReport('Impersonation'), child: Text(t.translate('profile_report_imperson'))),
            SimpleDialogOption(onPressed: () => _submitReport('Inappropriate Profile'), child: Text(t.translate('profile_report_inappr'))),
            Padding(padding: EdgeInsets.all(8), child: TextButton(onPressed: ()=>Navigator.pop(context), child: Text(t.translate('general_cancel')))),
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
    // LOCALIZATION
    var t = AppLocalizations.of(context)!;
    OverlayService().showTopNotification(context, t.translate('profile_report_submitted'), Icons.flag, (){});
  }

  Future<void> _signOut(BuildContext context) async {
    var t = AppLocalizations.of(context)!;
    final didConfirm = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: Text(t.translate('settings_logout')), 
      content: Text(t.translate('settings_logout_confirm')), 
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t.translate('general_cancel'))), 
        TextButton(onPressed: () => Navigator.pop(context, true), child: Text(t.translate('settings_logout'), style: TextStyle(color: Colors.red)))
      ]
    )) ?? false;
    if (didConfirm) { await _auth.signOut(); if (context.mounted) Navigator.of(context).popUntil((route) => route.isFirst); }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String _formatJoinedDate(Timestamp? timestamp) {
    var t = AppLocalizations.of(context)!;
    if (timestamp == null) return t.translate('profile_joined_unknown');
    return '${t.translate('profile_joined')} ${DateFormat('MMMM yyyy').format(timestamp.toDate())}';
  }

  Future<void> _handleRefresh() async {
    // FIX: Force reload to update emailVerified status from server
    try {
      await _user?.reload();
    } catch (_) {}
    await Future.delayed(Duration(seconds: 1));
    if (mounted) setState(() {}); 
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    var t = AppLocalizations.of(context)!;

    if (_userId == null) return Center(child: Text(t.translate('profile_not_logged_in')));
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    
    final double topPadding = MediaQuery.of(context).padding.top;
    final double pinnedHeaderHeight = topPadding + kToolbarHeight;

    return StreamBuilder<DocumentSnapshot>(
      stream: _firestore.collection('users').doc(_userId).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(appBar: AppBar(title: Text(t.translate('profile_error_title'))), body: Center(child: Text(t.translate('profile_error_generic'))));
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
                        tabs: [
                          Tab(text: t.translate('profile_posts')),
                          Tab(text: t.translate('profile_reposts')),
                          Tab(text: t.translate('profile_replies'))
                        ],
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
    var t = AppLocalizations.of(context)!;
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
        ? [
            PopupMenuItem(value: 'share', child: Text(t.translate('profile_menu_share'))), 
            PopupMenuItem(value: 'settings', child: Text(t.translate('profile_menu_settings'))), 
            PopupMenuItem(value: 'logout', child: Text(t.translate('settings_logout'), style: TextStyle(color: Colors.red)))
          ]
        : [
            PopupMenuItem(value: 'share', child: Text(t.translate('profile_menu_share_account'))), 
            PopupMenuItem(value: 'report', child: Text(t.translate('profile_report_title'))),
            PopupMenuItem(value: 'block', child: Text(_isBlocked ? t.translate('profile_unblocked') : t.translate('general_delete'), style: TextStyle(color: Colors.red))), // Using Delete/Block key
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
    var t = AppLocalizations.of(context)!;
    
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
              ? OutlinedButton(onPressed: () async { if(await Navigator.push(context, MaterialPageRoute(builder: (_) => EditProfileScreen())) == true) setState((){}); }, child: Text(t.translate('profile_edit')), style: OutlinedButton.styleFrom(shape: StadiumBorder()))
              : _isBlocked 
                ? ElevatedButton(onPressed: _toggleBlock, child: Text(t.translate('profile_unblocked')), style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white))
                : _buildFollowButton(isPrivate, amIFollowing)
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFollowButton(bool isPrivate, bool amIFollowing) {
    var t = AppLocalizations.of(context)!;
    if (amIFollowing) {
      return OutlinedButton(
        onPressed: _isProcessingFollow ? null : () => _unfollowUser(false), 
        child: Text(t.translate('profile_unfollow'))
      );
    }

    if (!isPrivate) {
      return ElevatedButton(
        onPressed: _isProcessingFollow ? null : () => _followUser(false), 
        style: ElevatedButton.styleFrom(backgroundColor: TwitterTheme.blue, foregroundColor: Colors.white),
        child: Text(t.translate('community_follow')),
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
            child: Text(t.translate('profile_requested'), style: TextStyle(color: Theme.of(context).hintColor)),
          );
        }
        
        return ElevatedButton(
          onPressed: _isProcessingFollow ? null : () => _followUser(true), 
          style: ElevatedButton.styleFrom(backgroundColor: TwitterTheme.blue, foregroundColor: Colors.white),
          child: Text(t.translate('community_follow')),
        );
      },
    );
  }

  Widget _buildProfileInfoBody(BuildContext context, Map<String, dynamic> data, bool isMyProfile) {
    final theme = Theme.of(context);
    var t = AppLocalizations.of(context)!;
    
    final String name = data['name'] ?? 'Name';
    final String handle = "@${(data['email'] ?? '').split('@')[0]}";
    final String displayBio = _isBioExpanded ? (data['bio'] ?? '') : ((data['bio'] ?? '').length > 100 ? (data['bio'] ?? '').substring(0, 100) + '...' : (data['bio'] ?? ''));
    
    final String verificationStatus = data['verificationStatus'] ?? 'none';
    final bool isVerified = verificationStatus == 'verified';
    final bool isPending = verificationStatus == 'pending';
    
    bool showEmailVerifyBtn = false;
    bool showKtmVerifyBtn = false;

    if (isMyProfile) {
      if (_user != null && !_user!.emailVerified) {
        showEmailVerifyBtn = true;
      } else if (!isVerified && !isPending) {
        showKtmVerifyBtn = true;
      }
    }

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
        
        // --- VERIFICATION BUTTONS ---
        if (showEmailVerifyBtn)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: InkWell(
              onTap: () async {
                try {
                  await _user!.sendEmailVerification();
                  if(mounted) OverlayService().showTopNotification(context, t.translate('profile_verify_sent'), Icons.mark_email_read, (){});
                } catch (e) {
                  if(mounted) OverlayService().showTopNotification(context, t.translate('profile_verify_wait'), Icons.timer, (){}, color: Colors.orange);
                }
              },
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.red),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min, 
                  children: [
                    Icon(Icons.warning, size: 16, color: Colors.red), 
                    SizedBox(width: 6), 
                    Text(t.translate('profile_verify_email'), style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12))
                  ]
                ),
              ),
            ),
          )
        else if (isPending)
           Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.orange)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.hourglass_top, size: 16, color: Colors.orange), SizedBox(width: 6), Text(t.translate('profile_verify_pending'), style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 12))]),
            ),
          )
        else if (showKtmVerifyBtn)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: InkWell(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => KtmVerificationScreen())),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: TwitterTheme.blue.withOpacity(0.1), borderRadius: BorderRadius.circular(20), border: Border.all(color: TwitterTheme.blue)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.verified_outlined, size: 16, color: TwitterTheme.blue), SizedBox(width: 6), Text(t.translate('profile_verify_get'), style: TextStyle(color: TwitterTheme.blue, fontWeight: FontWeight.bold, fontSize: 12))]),
              ),
            ),
          ),
        
        SizedBox(height: 8),
        if (!_isBlocked) ...[
          Text(displayBio.isEmpty ? t.translate('profile_no_bio') : displayBio, style: theme.textTheme.bodyLarge),
          if ((data['bio'] ?? '').length > 100) GestureDetector(onTap: () => setState(() => _isBioExpanded = !_isBioExpanded), child: Text(_isBioExpanded ? t.translate('general_show_less') : t.translate('general_show_more'), style: TextStyle(color: TwitterTheme.blue, fontWeight: FontWeight.bold))),
          SizedBox(height: 8),
          Row(children: [Icon(Icons.calendar_today, size: 14, color: theme.hintColor), SizedBox(width: 4), Text(_formatJoinedDate(data['createdAt']), style: theme.textTheme.titleSmall)]),
          SizedBox(height: 8),
          Row(
            children: [
              _buildStatText(context, (data['following'] ?? []).length, t.translate('profile_following'), 1), 
              SizedBox(width: 16), 
              _buildStatText(context, (data['followers'] ?? []).length, t.translate('profile_followers'), 2)
            ]
          ),
          SizedBox(height: 16),
        ]
      ])
    );
  }

  Widget _buildBlockedBody() {
    var t = AppLocalizations.of(context)!;
    return Container(
      alignment: Alignment.center,
      padding: EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.block, size: 64, color: Colors.grey),
          SizedBox(height: 16),
          Text(t.translate('profile_blocked_title'), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          SizedBox(height: 8),
          Text(t.translate('profile_blocked_desc'), textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
          SizedBox(height: 16),
          OutlinedButton(onPressed: _toggleBlock, child: Text(t.translate('profile_unblocked')))
        ],
      ),
    );
  }

  Widget _buildPrivateAccountBody() {
    final theme = Theme.of(context);
    var t = AppLocalizations.of(context)!;
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
            t.translate('profile_private_title'),
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 8),
          Text(
            t.translate('profile_private_desc'),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
          ),
        ],
      ),
    );
  }

  void _showBadgeInfo(BuildContext context, String dept, String prodi) {
    var t = AppLocalizations.of(context)!;
    showDialog(context: context, builder: (context) => AlertDialog(
      title: Text(t.translate('profile_academic_title')), 
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [Text(t.translate('profile_dept'), style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)), Text(dept, style: TextStyle(fontSize: 16)), SizedBox(height: 16), Text(t.translate('profile_prodi'), style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)), Text(prodi, style: TextStyle(fontSize: 16))]), 
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(t.translate('general_cancel'), style: TextStyle(color: TwitterTheme.blue)))]
    ));
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
    var t = AppLocalizations.of(context)!;
    return FutureBuilder<DocumentSnapshot>(
      future: _firestore.collection('users').doc(userId).get(),
      builder: (context, userSnapshot) {
        if (userSnapshot.hasError) return CommonErrorWidget(message: t.translate('profile_load_posts_fail'), isConnectionError: true);
        
        final firestorePinned = (userSnapshot.data?.data() as Map<String, dynamic>?)?['pinnedPostId'];
        final activePinnedId = _optimisticPinnedPostId == '' ? null : (_optimisticPinnedPostId ?? firestorePinned);

        return StreamBuilder<QuerySnapshot>(
          stream: _firestore.collection('posts').where('userId', isEqualTo: userId).orderBy('timestamp', descending: true).snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) return CommonErrorWidget(message: t.translate('profile_load_stream_fail'), isConnectionError: true);
            
            List<Widget> slivers = [];
            if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
              slivers.add(SliverFillRemaining(child: Center(child: CircularProgressIndicator())));
            } else {
              final allDocs = snapshot.data?.docs ?? [];
              
              final visibleDocs = allDocs.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
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
                slivers.add(SliverFillRemaining(child: Center(child: Text(t.translate('profile_no_posts')))));
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
    var t = AppLocalizations.of(context)!;
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collectionGroup('comments').where('userId', isEqualTo: userId).orderBy('timestamp', descending: true).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return CommonErrorWidget(message: t.translate('profile_load_replies_fail'), isConnectionError: true);
        
        List<Widget> slivers = [];
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          slivers.add(SliverFillRemaining(child: Center(child: CircularProgressIndicator())));
        } else {
          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            slivers.add(SliverFillRemaining(child: Center(child: Text(t.translate('profile_no_replies')))));
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
    var t = AppLocalizations.of(context)!;
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('posts').where('repostedBy', arrayContains: userId).orderBy('timestamp', descending: true).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return CommonErrorWidget(message: t.translate('profile_load_reposts_fail'), isConnectionError: true);
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
            slivers.add(SliverFillRemaining(child: Center(child: Text(t.translate('profile_no_reposts')))));
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