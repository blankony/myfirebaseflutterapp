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
import '../../main.dart';
import '../edit_profile_screen.dart';
import '../image_viewer_screen.dart'; 
import 'settings_page.dart'; 
import '../../services/overlay_service.dart';
import '../../services/cloudinary_service.dart'; // Ensure this is imported

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

class _ProfilePageState extends State<ProfilePage> with TickerProviderStateMixin {
  late TabController _tabController;
  final ScrollController _scrollController = ScrollController();
  
  late final User? _user;
  late final String _userId;
  
  bool _isScrolled = false;
  bool _isBioExpanded = false;
  int _targetTabIndex = 0;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _user = _auth.currentUser;
    _userId = widget.userId ?? _user!.uid;
    
    _tabController = TabController(
      length: 3, 
      vsync: this, 
      initialIndex: 0,
    );
    
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

  // --- NEW: Image Picker & Upload Logic ---
  Future<void> _pickAndUploadImage({required bool isBanner}) async {
    final picker = ImagePicker();
    final XFile? pickedFile = await picker.pickImage(
      source: ImageSource.gallery, 
      imageQuality: 70
    );

    if (pickedFile == null) return;

    // Crop Image
    final croppedFile = await ImageCropper().cropImage(
      sourcePath: pickedFile.path,
      compressQuality: 70,
      aspectRatio: isBanner 
          ? CropAspectRatio(ratioX: 3, ratioY: 1) // Banner Ratio
          : CropAspectRatio(ratioX: 1, ratioY: 1), // Avatar Ratio
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: isBanner ? 'Crop Banner' : 'Crop Avatar',
          toolbarColor: TwitterTheme.blue,
          toolbarWidgetColor: Colors.white,
          initAspectRatio: isBanner ? CropAspectRatioPreset.ratio3x2 : CropAspectRatioPreset.square,
          lockAspectRatio: true,
        ),
        IOSUiSettings(
          title: isBanner ? 'Crop Banner' : 'Crop Avatar',
          aspectRatioLockEnabled: true,
        ),
      ],
    );

    if (croppedFile == null) return;

    setState(() => _isUploading = true);
    
    if (mounted) {
       OverlayService().showTopNotification(context, "Uploading...", Icons.cloud_upload, (){}, color: TwitterTheme.blue);
    }

    try {
      // Upload to Cloudinary
      final String? downloadUrl = await _cloudinaryService.uploadImage(File(croppedFile.path));

      if (downloadUrl != null) {
        // Update Firestore
        final Map<String, dynamic> updateData = {};
        if (isBanner) {
          updateData['bannerImageUrl'] = downloadUrl;
        } else {
          updateData['profileImageUrl'] = downloadUrl;
          updateData['avatarIconId'] = -1; // Reset icon ID if setting custom image
        }

        await _firestore.collection('users').doc(_userId).update(updateData);
        
        // Note: For Avatar updates, you should ideally also run the Batch Update 
        // logic (from EditProfileScreen) to update past posts. 
        // For simplicity in this direct view, we just update the profile.

        if (mounted) {
          OverlayService().showTopNotification(context, "Updated successfully!", Icons.check_circle, (){}, color: Colors.green);
        }
      }
    } catch (e) {
      if (mounted) {
        OverlayService().showTopNotification(context, "Upload failed", Icons.error, (){}, color: Colors.red);
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  // --- NEW: Profile Options Bottom Sheet ---
  void _showProfileOptions(BuildContext context, String? currentImageUrl, String heroTag) {
    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(height: 10),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
              SizedBox(height: 20),
              
              if (currentImageUrl != null && currentImageUrl.isNotEmpty)
                ListTile(
                  leading: Icon(Icons.visibility_outlined, color: TwitterTheme.blue),
                  title: Text("View Photo"),
                  onTap: () {
                    Navigator.pop(context);
                    _openFullImage(context, currentImageUrl, heroTag);
                  },
                ),
              
              ListTile(
                leading: Icon(Icons.photo_library_outlined, color: TwitterTheme.blue),
                title: Text("Change Photo"),
                onTap: () {
                  Navigator.pop(context);
                  _pickAndUploadImage(isBanner: false);
                },
              ),
              SizedBox(height: 10),
            ],
          ),
        );
      },
    );
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
      
      final notificationId = 'follow_${_user!.uid}';
      _firestore.collection('users').doc(_userId).collection('notifications')
        .doc(notificationId)
        .set({
          'type': 'follow', 
          'senderId': _user!.uid, 
          'timestamp': FieldValue.serverTimestamp(), 
          'isRead': false,
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

      final notificationId = 'follow_${_user!.uid}';
      _firestore.collection('users').doc(_userId).collection('notifications')
        .doc(notificationId)
        .delete();

    } catch (e) { if(mounted) OverlayService().showTopNotification(context, "Failed to unfollow", Icons.error, (){}, color: Colors.red); }
  }

  void _shareProfile(String name) {
    Share.share("Check out $name's profile on Sapa PNJ!");
  }

  void _blockUser(String name) {
    OverlayService().showTopNotification(context, 'Blocked $name', Icons.block, (){});
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

  Future<void> _handleRefresh() async {
    await Future.delayed(Duration(seconds: 1));
    if (mounted) setState(() {});
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
      color: TwitterTheme.blue,
      edgeOffset: widget.includeScaffold ? 100 : 0, 
      child: NestedScrollView(
        controller: _scrollController,
        key: PageStorageKey('profile_nested_scroll_$_userId'), 
        physics: AlwaysScrollableScrollPhysics(),
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
                  backgroundColor: appBarBgColor, 
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
                  onTap: (index) {
                    _targetTabIndex = index;
                  },
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
          physics: null, 
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
        restorationId: null,
        body: content,
      );
    }
    return content;
  }

  // MODIFIED: Updated Header with Interactive Tap Logic
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
    final String bannerTag = 'profile_banner_${_userId}';
    final String avatarTag = 'profile_avatar_${_userId}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: headerStackHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // --- BANNER IMAGE ---
              GestureDetector(
                onTap: () {
                  if (isMyProfile) {
                    // Tap to Edit Banner (Direct)
                    _pickAndUploadImage(isBanner: true);
                  } else if (bannerImageUrl != null && bannerImageUrl.isNotEmpty) {
                    // Tap to View Banner (Others)
                    _openFullImage(context, bannerImageUrl, bannerTag);
                  }
                },
                child: Hero(
                  tag: bannerTag,
                  child: Container(
                    height: bannerHeight,
                    width: double.infinity,
                    decoration: BoxDecoration(color: TwitterTheme.darkGrey),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (bannerImageUrl != null && bannerImageUrl.isNotEmpty)
                          CachedNetworkImage(
                            imageUrl: bannerImageUrl, 
                            fit: BoxFit.cover, 
                            placeholder: (context, url) => Container(color: TwitterTheme.darkGrey), 
                            errorWidget: (context, url, error) => Container(color: TwitterTheme.darkGrey)
                          ),
                        // Add an edit icon overlay if it's my profile
                        if (isMyProfile)
                          Center(
                            child: Container(
                              padding: EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.black38,
                                shape: BoxShape.circle
                              ),
                              child: Icon(Icons.camera_alt, color: Colors.white, size: 24),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              
              // --- PROFILE AVATAR ---
              Positioned(
                top: bannerHeight - avatarRadius,
                left: 16,
                child: GestureDetector(
                  onTap: () {
                    final String? profileUrl = data['profileImageUrl'];
                    if (isMyProfile) {
                      // Show Options Bottom Sheet
                      _showProfileOptions(context, profileUrl, avatarTag);
                    } else if (profileUrl != null && profileUrl.isNotEmpty) {
                      // Just View
                      _openFullImage(context, profileUrl, avatarTag);
                    }
                  },
                  child: Stack(
                    children: [
                      Hero(
                        tag: avatarTag,
                        child: CircleAvatar(
                          radius: avatarRadius + 4,
                          backgroundColor: theme.scaffoldBackgroundColor,
                          child: _buildAvatarImage(data),
                        ),
                      ),
                      if (isMyProfile)
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            padding: EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: TwitterTheme.blue,
                              shape: BoxShape.circle,
                              border: Border.all(color: theme.scaffoldBackgroundColor, width: 2)
                            ),
                            child: Icon(Icons.camera_alt, size: 14, color: Colors.white),
                          ),
                        ),
                    ],
                  ),
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
                              final result = await Navigator.of(context).push(MaterialPageRoute(builder: (context) => EditProfileScreen()));
                              if (mounted && result == true) {
                                _targetTabIndex = 0;
                                _tabController.animateTo(0); 
                                setState(() {});
                              }
                            },
                            style: OutlinedButton.styleFrom(foregroundColor: theme.textTheme.bodyLarge?.color, side: BorderSide(color: theme.dividerColor), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), visualDensity: VisualDensity.compact),
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
              Text(displayBio.isEmpty ? "No bio set." : displayBio, style: theme.textTheme.bodyLarge?.copyWith(fontStyle: bio.isEmpty ? FontStyle.italic : FontStyle.normal)),
              if (isLongBio)
                GestureDetector(
                  onTap: () => setState(() => _isBioExpanded = !_isBioExpanded),
                  child: Padding(padding: const EdgeInsets.only(top: 4.0), child: Text(_isBioExpanded ? "Show less" : "Read more", style: TextStyle(color: TwitterTheme.blue, fontWeight: FontWeight.bold))),
                ),
              SizedBox(height: 8),
              Row(children: [Icon(Icons.calendar_today_outlined, size: 14, color: theme.hintColor), SizedBox(width: 8), Text(_formatJoinedDate(data['createdAt']), style: theme.textTheme.titleSmall)]),
              SizedBox(height: 8),
              Row(children: [_buildStatText(context, following.length, "Following"), SizedBox(width: 16), _buildStatText(context, followers.length, "Followers")]),
              SizedBox(height: 16),
            ],
          ),
        ),
      ],
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
    final int iconId = data['avatarIconId'] ?? 0;
    final String? colorHex = data['avatarHex'];
    final String? profileImageUrl = data['profileImageUrl']; 
    final Color bgColor = AvatarHelper.getColor(colorHex);
    if (profileImageUrl != null && profileImageUrl.isNotEmpty) {
      return CircleAvatar(radius: 45, backgroundColor: Colors.grey, backgroundImage: CachedNetworkImageProvider(profileImageUrl));
    }
    return CircleAvatar(radius: 45, backgroundColor: bgColor, child: Icon(AvatarHelper.getIcon(iconId), size: 50, color: Colors.white));
  }

  Widget _buildFollowButton(List<dynamic> followers) {
    final bool amIFollowing = followers.contains(_user?.uid);
    return amIFollowing
      ? OutlinedButton(onPressed: _unfollowUser, child: Text("Unfollow"))
      : ElevatedButton(onPressed: _followUser, style: ElevatedButton.styleFrom(backgroundColor: TwitterTheme.blue, foregroundColor: Colors.white), child: Text("Follow"));
  }

  Widget _buildStatText(BuildContext context, int count, String label) {
    final theme = Theme.of(context);
    return Row(children: [Text(count.toString(), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)), SizedBox(width: 4), Text(label, style: theme.textTheme.titleSmall)]);
  }

  Widget _buildMyPosts(String userId) {
    return FutureBuilder<DocumentSnapshot>(
      future: _firestore.collection('users').doc(userId).get(),
      builder: (context, userSnapshot) {
        String? pinnedPostId;
        if (userSnapshot.hasData && userSnapshot.data!.exists) {
          final data = userSnapshot.data!.data() as Map<String, dynamic>;
          pinnedPostId = data['pinnedPostId'];
        }

        return StreamBuilder<QuerySnapshot>(
          stream: _firestore.collection('posts').where('userId', isEqualTo: userId).orderBy('timestamp', descending: true).snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
              return Center(child: CircularProgressIndicator());
            }
            
            final docs = snapshot.data?.docs ?? [];
            if (docs.isEmpty) return Center(child: Text('No posts yet.'));

            // Sort Pinned to Top
            if (pinnedPostId != null) {
              final pinnedIndex = docs.indexWhere((doc) => doc.id == pinnedPostId);
              if (pinnedIndex != -1) {
                final pinnedDoc = docs.removeAt(pinnedIndex);
                docs.insert(0, pinnedDoc); 
              }
            }

            return ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: docs.length,
              separatorBuilder: (context, index) => Divider(height: 1, thickness: 1),
              itemBuilder: (context, index) {
                final doc = docs[index];
                final data = doc.data() as Map<String, dynamic>;
                return BlogPostCard(
                  postId: doc.id,
                  postData: data,
                  isOwner: data['userId'] == _auth.currentUser?.uid,
                  heroContextId: 'profile_posts',
                  isPinned: doc.id == pinnedPostId,
                );
              },
            );
          },
        );
      }
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

        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: docs.length,
          separatorBuilder: (context, index) => Divider(height: 1, thickness: 1),
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
      physics: const NeverScrollableScrollPhysics(),
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
  @override bool shouldRebuild(_SliverAppBarDelegate oldDelegate) => true;
}