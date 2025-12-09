// ignore_for_file: prefer_const_constructors
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import '../../widgets/blog_post_card.dart';
import '../../main.dart';
import 'community_settings_screen.dart'; 
import 'community_members_screen.dart'; 
import '../create_post_screen.dart'; 
import '../../services/overlay_service.dart';
import '../../services/cloudinary_service.dart';
import '../image_viewer_screen.dart'; 

class CommunityDetailScreen extends StatefulWidget {
  final String communityId;
  final Map<String, dynamic> communityData;

  const CommunityDetailScreen({
    super.key,
    required this.communityId,
    required this.communityData,
  });

  @override
  State<CommunityDetailScreen> createState() => _CommunityDetailScreenState();
}

class _CommunityDetailScreenState extends State<CommunityDetailScreen> {
  final CloudinaryService _cloudinaryService = CloudinaryService();
  bool _isUploadingImage = false;

  Route _createSlideUpRoute(Widget page) {
    return PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return SlideTransition(position: animation.drive(Tween(begin: Offset(0.0, 1.0), end: Offset.zero).chain(CurveTween(curve: Curves.easeOutQuart))), child: child);
      },
    );
  }

  Future<void> _handleFollowAction(bool isFollowing) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      if (isFollowing) {
        await FirebaseFirestore.instance.collection('communities').doc(widget.communityId).update({
          'followers': FieldValue.arrayRemove([user.uid]),
        });
        if(mounted) OverlayService().showTopNotification(context, "Unfollowed", Icons.remove_circle_outline, (){});
      } else {
        await FirebaseFirestore.instance.collection('communities').doc(widget.communityId).update({
          'followers': FieldValue.arrayUnion([user.uid])
        });
        if(mounted) OverlayService().showTopNotification(context, "Following", Icons.check_circle, (){}, color: Colors.green);
      }
    } catch (e) {
      if(mounted) OverlayService().showTopNotification(context, "Action failed", Icons.error, (){}, color: Colors.red);
    }
  }

  void _openFullImage(BuildContext context, String url, String heroTag) {
    Navigator.of(context).push(PageRouteBuilder(opaque: false, pageBuilder: (_, __, ___) => ImageViewerScreen(imageUrl: url, heroTag: heroTag, mediaType: 'image')));
  }

  void _showImageOptions(BuildContext context, String? url, bool isBanner, bool hasControl) {
    if (url == null && !hasControl) return;
    showModalBottomSheet(context: context, shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))), builder: (ctx) {
      return SafeArea(child: Wrap(children: [
        if (url != null) ListTile(leading: Icon(Icons.visibility_outlined, color: TwitterTheme.blue), title: Text(isBanner ? "View Banner" : "View Icon"), onTap: () { Navigator.pop(ctx); _openFullImage(context, url, isBanner ? 'community_banner' : 'community_icon'); }),
        if (hasControl) ListTile(leading: Icon(Icons.photo_library_outlined, color: TwitterTheme.blue), title: Text(isBanner ? "Change Banner" : "Change Icon"), onTap: () { Navigator.pop(ctx); _pickAndUploadImage(isBanner: isBanner); }),
      ]));
    });
  }

  Future<void> _pickAndUploadImage({required bool isBanner}) async {
    final picker = ImagePicker();
    final XFile? pickedFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (pickedFile == null) return;
    final croppedFile = await ImageCropper().cropImage(sourcePath: pickedFile.path, compressQuality: 70, aspectRatio: isBanner ? CropAspectRatio(ratioX: 3, ratioY: 1) : CropAspectRatio(ratioX: 1, ratioY: 1));
    if (croppedFile == null) return;
    setState(() => _isUploadingImage = true);
    try {
      final String? url = await _cloudinaryService.uploadImage(File(croppedFile.path));
      if (url != null) {
        Map<String, dynamic> update = isBanner ? {'bannerImageUrl': url} : {'imageUrl': url};
        await FirebaseFirestore.instance.collection('communities').doc(widget.communityId).update(update);
        if(mounted) OverlayService().showTopNotification(context, "Updated!", Icons.check_circle, (){}, color: Colors.green);
      }
    } catch (e) {
      if(mounted) OverlayService().showTopNotification(context, "Upload failed", Icons.error, (){}, color: Colors.red);
    } finally {
      if(mounted) setState(() => _isUploadingImage = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('communities').doc(widget.communityId).snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.hasData && snapshot.data!.exists ? snapshot.data!.data() as Map<String, dynamic> : widget.communityData;
        final String ownerId = data['ownerId'];
        final List admins = data['admins'] ?? [];
        final List editors = data['editors'] ?? [];
        final List followers = data['followers'] ?? [];
        final bool isOwner = user?.uid == ownerId;
        final bool isAdmin = admins.contains(user?.uid);
        final bool isEditor = editors.contains(user?.uid);
        final bool isFollower = followers.contains(user?.uid);
        final bool hasFullControl = isOwner || isAdmin;
        final bool canPost = isOwner || isAdmin || isEditor;
        final String name = data['name'] ?? 'Channel';
        final String? bannerUrl = data['bannerImageUrl'];
        final String? avatarUrl = data['imageUrl'];
        final bool isVerified = data['isVerified'] ?? false;

        return Scaffold(
          body: NestedScrollView(
            physics: BouncingScrollPhysics(),
            headerSliverBuilder: (context, innerBoxIsScrolled) {
              return [
                SliverAppBar(
                  expandedHeight: 180.0,
                  pinned: true,
                  title: innerBoxIsScrolled ? Text(name) : null,
                  elevation: 0,
                  actions: [
                    if (hasFullControl)
                      IconButton(
                        icon: Icon(Icons.settings_outlined),
                        onPressed: () => Navigator.push(context, _createSlideUpRoute(CommunitySettingsScreen(communityId: widget.communityId, communityData: data, isOwner: isOwner, isAdmin: isAdmin))),
                      )
                  ],
                  flexibleSpace: FlexibleSpaceBar(
                    background: Stack(
                      fit: StackFit.expand,
                      children: [
                        GestureDetector(
                          onTap: () => _showImageOptions(context, bannerUrl, true, hasFullControl),
                          child: Hero(tag: 'community_banner', child: bannerUrl != null ? CachedNetworkImage(imageUrl: bannerUrl, fit: BoxFit.cover) : Container(color: isDarkMode ? Colors.grey[800] : Colors.grey[300], child: hasFullControl ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.add_a_photo, color: Colors.white), Text("Add Banner", style: TextStyle(color: Colors.white, fontSize: 12))])) : null)),
                        ),
                        Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black.withOpacity(0.8)]))),
                        Positioned(
                          left: 16, bottom: 16, right: 16,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              GestureDetector(
                                onTap: () => _showImageOptions(context, avatarUrl, false, hasFullControl),
                                child: Hero(tag: 'community_icon', child: Container(decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: theme.scaffoldBackgroundColor, width: 3)), child: CircleAvatar(radius: 36, backgroundColor: TwitterTheme.blue, backgroundImage: avatarUrl != null ? CachedNetworkImageProvider(avatarUrl) : null, child: avatarUrl == null ? Text(name[0].toUpperCase(), style: TextStyle(fontSize: 32, color: Colors.white)) : null))),
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                                  Row(children: [Flexible(child: Text(name, style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)), if (isVerified) ...[SizedBox(width: 4), Icon(Icons.verified, size: 18, color: TwitterTheme.blue)]]),
                                  Text(data['category'] == 'pnj_official' ? "Official Channel" : "Community", style: TextStyle(color: Colors.white70, fontSize: 12)),
                                ]),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(data['description'] ?? "No description provided.", style: theme.textTheme.bodyMedium),
                        SizedBox(height: 12),
                        Row(
                          children: [
                            InkWell(
                              onTap: () => Navigator.push(context, _createSlideUpRoute(CommunityMembersScreen(communityId: widget.communityId, communityData: data, isStaff: hasFullControl))),
                              child: Row(children: [Icon(Icons.group, size: 16, color: theme.hintColor), SizedBox(width: 4), Text("${followers.length} Followers", style: TextStyle(fontWeight: FontWeight.bold)), Icon(Icons.arrow_forward_ios, size: 12, color: theme.hintColor)]),
                            ),
                            Spacer(),
                            if (!canPost)
                              ElevatedButton(onPressed: () => _handleFollowAction(isFollower), style: ElevatedButton.styleFrom(backgroundColor: isFollower ? theme.cardColor : TwitterTheme.blue, foregroundColor: isFollower ? theme.textTheme.bodyLarge?.color : Colors.white, elevation: 0, side: isFollower ? BorderSide(color: theme.dividerColor) : null, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))), child: Text(isFollower ? "Following" : "Follow"))
                            else
                              ElevatedButton.icon(onPressed: () => Navigator.push(context, _createSlideUpRoute(CreatePostScreen(initialData: {'communityId': widget.communityId, 'communityName': name, 'communityIcon': avatarUrl}))), icon: Icon(Icons.campaign, size: 18), label: Text("Broadcast"), style: ElevatedButton.styleFrom(backgroundColor: TwitterTheme.blue, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)))),
                          ],
                        ),
                        Divider(height: 24),
                        Text("Broadcasts", style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ];
            },
            body: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('posts').where('communityId', isEqualTo: widget.communityId).orderBy('timestamp', descending: true).snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return Center(child: CircularProgressIndicator());
                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) return Center(child: Padding(padding: EdgeInsets.only(top: 40), child: Text("No broadcasts yet.", style: TextStyle(color: Colors.grey))));
                return ListView.builder(padding: EdgeInsets.only(bottom: 80), itemCount: docs.length, itemBuilder: (context, index) {
                  final post = docs[index];
                  final pData = post.data() as Map<String, dynamic>;
                  return BlogPostCard(postId: post.id, postData: pData, isOwner: hasFullControl || pData['userId'] == user?.uid, heroContextId: 'community_${widget.communityId}');
                });
              },
            ),
          ),
        );
      }
    );
  }
}