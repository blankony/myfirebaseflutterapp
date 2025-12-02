// ignore_for_file: prefer_const_constructors
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:share_plus/share_plus.dart'; 
import 'package:url_launcher/url_launcher.dart'; 
import '../screens/post_detail_screen.dart'; 
import '../screens/dashboard/profile_page.dart'; 
import '../screens/image_viewer_screen.dart'; 
import 'package:timeago/timeago.dart' as timeago; 
import '../main.dart';
import 'package:flutter/services.dart'; 
import 'package:cached_network_image/cached_network_image.dart'; 
import 'package:video_player/video_player.dart'; 
import '../services/overlay_service.dart';
import '../services/moderation_service.dart'; 

final FirebaseAuth _auth = FirebaseAuth.instance;
final FirebaseFirestore _firestore = FirebaseFirestore.instance;

// --- DUMB WIDGET: Just renders the controller it is given ---
class _VideoPlayerWidget extends StatelessWidget {
  final VideoPlayerController controller;
  
  const _VideoPlayerWidget({required this.controller});

  @override
  Widget build(BuildContext context) {
    if (!controller.value.isInitialized) {
      return Container(
        color: Colors.black,
        height: 200,
        width: double.infinity,
        child: Center(child: CircularProgressIndicator(color: TwitterTheme.blue)),
      );
    }

    return Container(
      color: Colors.black,
      height: 200,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        alignment: Alignment.center,
        children: [
          FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: controller.value.size.width,
              height: controller.value.size.height,
              child: VideoPlayer(controller),
            ),
          ),
          Container(color: Colors.black.withOpacity(0.4)),
          Center(
            child: Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 32),
            ),
          ),
        ],
      ),
    );
  }
}

class _PostMediaPreview extends StatelessWidget {
  final String mediaUrl;
  final String? mediaType;
  final String text;
  final Map<String, dynamic> postData; 
  final String postId; 
  final String heroContextId; 
  final VideoPlayerController? videoController; 

  const _PostMediaPreview({
    required this.mediaUrl,
    this.mediaType,
    required this.text,
    required this.postData, 
    required this.postId, 
    required this.heroContextId,
    this.videoController,
  });

  String? _getVideoId(String url) {
    if (url.contains('youtube.com') || url.contains('youtu.be')) {
      final regExp = RegExp(r"youtu(?:.*\/v\/|.*v\=|\.be\/)([A-Za-z0-9_\-]+)");
      return regExp.firstMatch(url)?.group(1);
    }
    return null;
  }
  
  String? _extractLinkInText() {
    final linkRegExp = RegExp(r'(https?:\/\/[^\s]+)');
    final match = linkRegExp.firstMatch(text);
    return match?.group(0);
  }

  void _navigateToViewer(BuildContext context, {String? url, String? type}) {
     final String heroTag = '${heroContextId}_${postId}_${url ?? mediaUrl}';

     Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black, 
        pageBuilder: (_, __, ___) => ImageViewerScreen(
          imageUrl: url ?? mediaUrl, 
          mediaType: type ?? mediaType,
          postData: postData, 
          postId: postId,
          heroTag: heroTag, 
          videoController: videoController,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        }
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    if (mediaUrl.isNotEmpty) {
      final String heroTag = '${heroContextId}_${postId}_$mediaUrl';

      return AspectRatio( 
        aspectRatio: 4 / 3,
        child: GestureDetector(
          onTap: () => _navigateToViewer(context, type: mediaType),
          child: Hero(
            tag: heroTag,
            transitionOnUserGestures: true,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: (mediaType == 'video' && videoController != null)
                  ? _VideoPlayerWidget(controller: videoController!)
                  : CachedNetworkImage( 
                      imageUrl: mediaUrl,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                          color: theme.dividerColor.withOpacity(0.5),
                          child: Center(child: CircularProgressIndicator(color: TwitterTheme.blue)),
                        ),
                      errorWidget: (context, url, error) => Container(
                          color: Colors.red.withOpacity(0.1),
                          child: Center(child: Text('Failed to load media.', style: TextStyle(color: Colors.red))),
                        ),
                    ),
            ),
          ),
        ),
      );
    } 
    
    final externalLink = _extractLinkInText();
    final youtubeId = externalLink != null ? _getVideoId(externalLink) : null;
    
    if (youtubeId != null) {
      return AspectRatio( 
        aspectRatio: 4 / 3,
        child: GestureDetector(
          onTap: () async {
            final url = Uri.parse(externalLink!);
            if (await canLaunchUrl(url)) {
              await launchUrl(url, mode: LaunchMode.externalApplication);
            }
          },
          child: Container(
            margin: const EdgeInsets.only(top: 12),
            decoration: BoxDecoration(
              color: Colors.red.shade900, 
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.ondemand_video, color: Colors.white, size: 50),
                  SizedBox(height: 8),
                  Text('Tap to watch on YouTube', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        ),
      );
    }
    
    return const SizedBox.shrink();
  }
}

class BlogPostCard extends StatefulWidget {
  final String postId;
  final Map<String, dynamic> postData;
  final bool isOwner;
  final bool isClickable; 
  final bool isDetailView;
  final String heroContextId; 
  final VideoPlayerController? preloadedController; 
  final bool isPinned; 
  final Function(String, bool)? onPinToggle;

  const BlogPostCard({
    super.key,
    required this.postId,
    required this.postData,
    required this.isOwner,
    this.isClickable = true,
    this.isDetailView = false,
    this.heroContextId = 'feed', 
    this.preloadedController,
    this.isPinned = false, 
    this.onPinToggle,
  });

  @override
  State<BlogPostCard> createState() => _BlogPostCardState();
}

class _BlogPostCardState extends State<BlogPostCard> with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  final TextEditingController _editController = TextEditingController();
  late AnimationController _likeController;
  late Animation<double> _likeAnimation;
  late AnimationController _shareController;
  late Animation<double> _shareAnimation;
  late AnimationController _repostController;
  late Animation<double> _repostAnimation;

  bool _isLiked = false;
  bool _isReposted = false;
  bool _isSharing = false;
  int _likeCount = 0;
  int _repostCount = 0;
  
  late bool _localIsPinned;

  VideoPlayerController? _videoController;
  bool _isVideoOwner = false; 
  
  @override
  void initState() {
    super.initState();
    _localIsPinned = widget.isPinned; 
    _syncState();
    _initVideoController();
    
    _likeController = AnimationController(duration: const Duration(milliseconds: 200), vsync: this);
    _likeAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(CurvedAnimation(parent: _likeController, curve: Curves.easeInOut));

    _shareController = AnimationController(duration: const Duration(milliseconds: 200), vsync: this);
    _shareAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(CurvedAnimation(parent: _shareController, curve: Curves.easeInOut));

    _repostController = AnimationController(duration: const Duration(milliseconds: 200), vsync: this);
    _repostAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(CurvedAnimation(parent: _repostController, curve: Curves.easeInOut));
  }

  void _initVideoController() {
    final mediaUrl = widget.postData['mediaUrl'];
    final mediaType = widget.postData['mediaType'];

    if (mediaType == 'video' && mediaUrl != null) {
      if (widget.preloadedController != null) {
        _videoController = widget.preloadedController;
        _isVideoOwner = false;
      } else {
        _videoController = VideoPlayerController.networkUrl(Uri.parse(mediaUrl))
          ..initialize().then((_) {
            final duration = _videoController!.value.duration;
            final targetPosition = duration.inSeconds > 10 ? Duration(seconds: 10) : duration;
            _videoController!.seekTo(targetPosition).then((_) {
               if(mounted) setState((){}); 
            });
            _videoController!.setVolume(0);
            _videoController!.pause();
          });
        _isVideoOwner = true;
      }
    }
  }

  @override
  void didUpdateWidget(covariant BlogPostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.postData != widget.postData) {
      _syncState();
      
      if (oldWidget.postData['mediaUrl'] != widget.postData['mediaUrl']) {
        if (_isVideoOwner) {
          _videoController?.dispose();
        }
        _initVideoController();
      }
    }
    if (oldWidget.isPinned != widget.isPinned) {
      setState(() {
        _localIsPinned = widget.isPinned;
      });
    }
  }

  void _syncState() {
    final currentUser = _auth.currentUser;
    final likes = widget.postData['likes'] as Map<String, dynamic>? ?? {};
    final reposts = widget.postData['repostedBy'] as List? ?? [];
    
    if (mounted) {
      setState(() {
        _isLiked = currentUser != null && likes.containsKey(currentUser.uid);
        _likeCount = likes.length;
        _isReposted = currentUser != null && reposts.contains(currentUser.uid);
        _repostCount = reposts.length;
      });
    }
  }
  
  @override
  void dispose() {
    _likeController.dispose();
    _shareController.dispose();
    _repostController.dispose();
    _editController.dispose();
    
    if (_isVideoOwner) {
      _videoController?.dispose();
    }
    super.dispose();
  }

  void _toggleLike() async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;
    _likeController.forward().then((_) => _likeController.reverse());
    if (hapticNotifier.value) HapticFeedback.lightImpact();
    final docRef = _firestore.collection('posts').doc(widget.postId);
    setState(() { _isLiked = !_isLiked; if (_isLiked) _likeCount++; else _likeCount--; }); 
    try {
      final notificationId = 'like_${widget.postId}_${currentUser.uid}';
      final notificationRef = _firestore.collection('users').doc(widget.postData['userId']).collection('notifications').doc(notificationId);
      if (_isLiked) {
        await docRef.update({'likes.${currentUser.uid}': true});
        if (widget.postData['userId'] != currentUser.uid) {
          notificationRef.set({'type': 'like','senderId': currentUser.uid,'postId': widget.postId,'postTextSnippet': widget.postData['text'],'timestamp': FieldValue.serverTimestamp(),'isRead': false,});
        }
      } else {
        await docRef.update({'likes.${currentUser.uid}': FieldValue.delete()});
        if (widget.postData['userId'] != currentUser.uid) notificationRef.delete();
      }
    } catch (e) { _syncState(); }
  }

  void _toggleRepost() async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;
    _repostController.forward().then((_) => _repostController.reverse());
    if (hapticNotifier.value) HapticFeedback.lightImpact();
    final docRef = _firestore.collection('posts').doc(widget.postId);
    setState(() { _isReposted = !_isReposted; if (_isReposted) _repostCount++; else _repostCount--; });
    try {
      final notificationId = 'repost_${widget.postId}_${currentUser.uid}';
      final notificationRef = _firestore.collection('users').doc(widget.postData['userId']).collection('notifications').doc(notificationId);
      if (_isReposted) {
        await docRef.update({'repostedBy': FieldValue.arrayUnion([currentUser.uid])});
        if (widget.postData['userId'] != currentUser.uid) {
          notificationRef.set({'type': 'repost','senderId': currentUser.uid,'postId': widget.postId,'postTextSnippet': widget.postData['text'],'timestamp': FieldValue.serverTimestamp(),'isRead': false,});
        }
      } else {
        await docRef.update({'repostedBy': FieldValue.arrayRemove([currentUser.uid])});
        if (widget.postData['userId'] != currentUser.uid) notificationRef.delete();
      }
    } catch (e) { _syncState(); }
  }
  
  // FIX: New _handleBookmarkToggle
  // Kita menerima status saat ini sebagai parameter
  void _handleBookmarkToggle(bool isCurrentlyBookmarked) async {
    final user = _auth.currentUser;
    if (user == null) return;
    
    if (hapticNotifier.value) HapticFeedback.lightImpact();
    
    final docRef = _firestore.collection('users').doc(user.uid).collection('bookmarks').doc(widget.postId);
    
    // 1. Tampilkan notifikasi DULUAN sebelum proses async (agar muncul meskipun widget didispose)
    if (!isCurrentlyBookmarked) {
       OverlayService().showTopNotification(context, "Saved to bookmarks", Icons.bookmark, (){});
    } else {
       OverlayService().showTopNotification(context, "Removed from bookmarks", Icons.bookmark_remove, (){});
    }

    // 2. Lakukan operasi database
    try {
      if (!isCurrentlyBookmarked) {
        await docRef.set({
          'timestamp': FieldValue.serverTimestamp(),
        });
      } else {
        await docRef.delete();
      }
    } catch (e) {
      // Jika error, notifikasi error
      OverlayService().showTopNotification(context, "Failed to bookmark", Icons.error, (){}, color: Colors.red);
    }
  }

  // --- NEW: TOGGLE VISIBILITY ---
  void _toggleVisibility() async {
    final currentVis = widget.postData['visibility'] ?? 'public';
    final newVis = currentVis == 'public' ? 'private' : 'public';
    
    try {
      await _firestore.collection('posts').doc(widget.postId).update({
        'visibility': newVis,
      });
      OverlayService().showTopNotification(
        context, 
        "Post is now ${newVis.toUpperCase()}", 
        newVis == 'public' ? Icons.public : Icons.lock, 
        (){},
      );
    } catch (e) {
      OverlayService().showTopNotification(context, "Failed to update visibility", Icons.error, (){}, color: Colors.red);
    }
  }

  void _sharePost() {
    _shareController.forward().then((_) => _shareController.reverse());
    setState(() { _isSharing = true; });
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) setState(() { _isSharing = false; });
      Share.share('Check out this post by ${widget.postData['userName']}: "${widget.postData['text']}"');
    });
  }

  Future<void> _deletePost() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete Post'),
        content: Text('Are you sure you want to delete this post?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    ) ?? false;
    if (confirm) {
      try {
        await _firestore.collection('posts').doc(widget.postId).delete();
        if(mounted) OverlayService().showTopNotification(context, "Post deleted", Icons.delete_outline, (){});
      } catch (e) {
        if(mounted) OverlayService().showTopNotification(context, "Failed to delete", Icons.error, (){}, color: Colors.red);
      }
    }
  }

  Future<void> _togglePin() async {
    final user = _auth.currentUser;
    if (user == null) return;
    final bool newPinState = !_localIsPinned;
    setState(() {
      _localIsPinned = newPinState; 
    });
    if (widget.onPinToggle != null) {
      widget.onPinToggle!(widget.postId, newPinState);
    }
    try {
      if (!newPinState) { 
        await _firestore.collection('users').doc(user.uid).update({
          'pinnedPostId': FieldValue.delete(),
        });
        if(mounted) OverlayService().showTopNotification(context, "Post unpinned", Icons.push_pin_outlined, (){});
      } else { 
        await _firestore.collection('users').doc(user.uid).update({
          'pinnedPostId': widget.postId,
        });
        if(mounted) OverlayService().showTopNotification(context, "Post pinned to profile", Icons.push_pin, (){});
      }
    } catch (e) {
      setState(() {
        _localIsPinned = !newPinState;
      });
      if (widget.onPinToggle != null) widget.onPinToggle!(widget.postId, !newPinState);
      if(mounted) OverlayService().showTopNotification(context, "Failed to pin", Icons.error, (){}, color: Colors.red);
    }
  }

  Route _createSlideLeftRoute(Widget page) {
    return PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        const begin = Offset(1.0, 0.0); 
        const end = Offset.zero;
        const curve = Curves.easeInOutQuart;
        var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
        return SlideTransition(position: animation.drive(tween), child: child);
      },
    );
  }

  void _navigateToDetail() {
    if (!widget.isClickable) return; 
    Navigator.of(context).push(
      _createSlideLeftRoute(
        PostDetailScreen(
          postId: widget.postId,
          initialPostData: widget.postData, 
          heroContextId: widget.heroContextId,
          preloadedController: _videoController, 
        ),
      ),
    );
  }

  void _navigateToUserProfile() {
    final postUserId = widget.postData['userId'];
    if (postUserId == null) return;
    if (widget.isOwner) {
      final scaffold = Scaffold.maybeOf(context);
      if (scaffold != null && scaffold.hasDrawer) {
        if (hapticNotifier.value) HapticFeedback.lightImpact();
        scaffold.openDrawer();
        return;
      }
    }
    Navigator.of(context).push(
      _createSlideLeftRoute(
        ProfilePage(userId: postUserId, includeScaffold: true), 
      ),
    );
  }

  Future<void> _showEditDialog() async {
    _editController.text = widget.postData['text'] ?? '';
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Edit Post'),
          content: TextField(
            controller: _editController,
            maxLines: 5,
            decoration: InputDecoration(hintText: "Edit your post..."),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: Text('Cancel')),
            ElevatedButton(onPressed: _submitEdit, child: Text('Save')),
          ],
        );
      },
    );
  }

  Future<void> _submitEdit() async {
    try {
      await _firestore.collection('posts').doc(widget.postId).update({'text': _editController.text});
      if(mounted) Navigator.of(context).pop(); 
    } catch (e) {
      if(mounted) {
        OverlayService().showTopNotification(context, "Edit failed", Icons.error, (){}, color: Colors.red);
        Navigator.of(context).pop(); 
      }
    }
  }

  // --- REPORT & BLOCK LOGIC ---
  void _reportPost() {
    showDialog(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: Text("Report Post"),
          children: [
            SimpleDialogOption(onPressed: () => _submitReport('Spam'), child: Text('Spam')),
            SimpleDialogOption(onPressed: () => _submitReport('Harassment'), child: Text('Harassment')),
            SimpleDialogOption(onPressed: () => _submitReport('Inappropriate Content'), child: Text('Inappropriate Content')),
            SimpleDialogOption(onPressed: () => _submitReport('Misinformation'), child: Text('Misinformation')),
            Padding(padding: EdgeInsets.all(8), child: TextButton(onPressed: ()=>Navigator.pop(context), child: Text("Cancel"))),
          ],
        );
      }
    );
  }

  void _submitReport(String reason) {
    Navigator.pop(context);
    moderationService.reportContent(
      targetId: widget.postId, 
      targetType: 'post', 
      reason: reason
    );
    OverlayService().showTopNotification(context, "Report submitted.", Icons.flag, (){});
  }

  void _blockUser() async {
    final didConfirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Block User?"),
        content: Text("They will not be able to follow you or view your posts, and you will not see their posts."),
        actions: [
          TextButton(onPressed: ()=>Navigator.pop(context, false), child: Text("Cancel")),
          TextButton(onPressed: ()=>Navigator.pop(context, true), child: Text("Block", style: TextStyle(color: Colors.red))),
        ],
      )
    ) ?? false;

    if (didConfirm) {
      await moderationService.blockUser(widget.postData['userId']);
      if (mounted) OverlayService().showTopNotification(context, "User blocked", Icons.block, (){});
    }
  }

  String _formatTimestamp(Timestamp? timestamp) {
    if (timestamp == null) return "just now";
    if (widget.postData['isUploading'] == true) return "Uploading...";
    if (widget.postData['uploadFailed'] == true) return "Failed";
    return timeago.format(timestamp.toDate(), locale: 'en_short');
  }

  Widget _buildUploadStatus(double progress) {
    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Uploading media...", style: TextStyle(color: TwitterTheme.blue, fontWeight: FontWeight.bold)),
          SizedBox(height: 4),
          LinearProgressIndicator(value: null, backgroundColor: Theme.of(context).dividerColor, valueColor: AlwaysStoppedAnimation<Color>(TwitterTheme.blue)),
          SizedBox(height: 4),
          Text('Processing...', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }

  @override
  bool get wantKeepAlive => true; 

  @override
  Widget build(BuildContext context) {
    super.build(context);
    
    // --- BLOCK CHECK ---
    return StreamBuilder<List<String>>(
      stream: moderationService.streamBlockedUsers(),
      builder: (context, snapshot) {
        final blockedUsers = snapshot.data ?? [];
        if (blockedUsers.contains(widget.postData['userId'])) {
          return SizedBox.shrink(); // Hide Content
        }

        final theme = Theme.of(context);
        final text = widget.postData['text'] ?? '';
        final mediaUrl = widget.postData['mediaUrl'];
        final mediaType = widget.postData['mediaType'];
        final isUploading = widget.postData['isUploading'] == true;
        final uploadProgress = widget.postData['uploadProgress'] as double? ?? 0.0;
        final uploadFailed = widget.postData['uploadFailed'] == true;
        final int commentCount = widget.postData['commentCount'] ?? 0;
        
        // --- NEW: VISIBILITY CHECK ---
        final visibility = widget.postData['visibility'] ?? 'public';
        
        if (uploadFailed) {
          return Container(
            padding: const EdgeInsets.all(12.0),
            color: Colors.red.withOpacity(0.1),
            child: Text("Post upload failed: ${text}", style: TextStyle(color: Colors.red)),
          );
        }

        return GestureDetector(
          onTap: (widget.isClickable && !widget.isDetailView) ? _navigateToDetail : null,
          child: Container(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: theme.dividerColor, width: 0.5)),
              color: theme.cardColor,
            ),
            padding: const EdgeInsets.all(16.0), 
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_localIsPinned)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8.0, left: 36.0),
                    child: Row(
                      children: [
                        Icon(Icons.push_pin, size: 14, color: theme.hintColor),
                        SizedBox(width: 4),
                        Text(
                          "Pinned Post", 
                          style: TextStyle(
                            fontSize: 12, 
                            fontWeight: FontWeight.bold,
                            color: theme.hintColor
                          )
                        ),
                      ],
                    ),
                  ),

                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildAvatar(context),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildPostHeader(context),
                          if (text.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4.0),
                              child: Text(
                                text,
                                style: theme.textTheme.bodyLarge?.copyWith(fontSize: widget.isDetailView ? 18 : 15),
                                maxLines: widget.isDetailView ? null : 10,
                                overflow: widget.isDetailView ? null : TextOverflow.ellipsis,
                              ),
                            ),
                          if (isUploading)
                            _buildUploadStatus(uploadProgress)
                          else if (mediaUrl != null || (text.contains('http') && !widget.isDetailView))
                            Padding(
                              padding: const EdgeInsets.only(top: 12.0),
                              child: _PostMediaPreview(
                                mediaUrl: mediaUrl ?? '',
                                mediaType: mediaType,
                                text: text,
                                postData: widget.postData, 
                                postId: widget.postId, 
                                heroContextId: widget.heroContextId, 
                                videoController: _videoController, 
                              ),
                            ),
                          if (widget.isDetailView && !isUploading)
                            _buildDetailActionRow()
                          else if (!isUploading)
                            _buildFeedActionRow(commentCount),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      }
    );
  }

  Widget _buildAvatar(BuildContext context) {
    final String authorId = widget.postData['userId'];
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(authorId).snapshots(),
      builder: (context, snapshot) {
        int iconId = 0;
        String? colorHex;
        String? profileImageUrl;
        if (snapshot.hasData && snapshot.data != null && snapshot.data!.exists) {
          final userData = snapshot.data!.data() as Map<String, dynamic>;
          iconId = userData['avatarIconId'] ?? 0;
          colorHex = userData['avatarHex'];
          profileImageUrl = userData['profileImageUrl'];
        } else {
           iconId = widget.postData['avatarIconId'] ?? 0;
           colorHex = widget.postData['avatarHex'];
           profileImageUrl = widget.postData['profileImageUrl'];
        }
        final Color avatarBgColor = AvatarHelper.getColor(colorHex);
        return GestureDetector(
           onTap: _navigateToUserProfile,
          child: CircleAvatar(
            radius: 24,
            backgroundColor: profileImageUrl != null ? Colors.transparent : avatarBgColor,
            backgroundImage: profileImageUrl != null ? CachedNetworkImageProvider(profileImageUrl) : null,
            child: profileImageUrl == null ? Icon(AvatarHelper.getIcon(iconId), size: 26, color: Colors.white) : null,
          ),
        );
      },
    );
  }

  Widget _buildPostHeader(BuildContext context) {
    final timeAgo = _formatTimestamp(widget.postData['timestamp'] as Timestamp?);
    final String userName = widget.postData['userName'] ?? 'User';
    final String handle = "@${widget.postData['userEmail']?.split('@')[0] ?? 'user'}";
    final theme = Theme.of(context);
    
    // VISIBILITY CHECK
    final String visibility = widget.postData['visibility'] ?? 'public';
    final bool isPrivate = visibility == 'private';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      userName, 
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold), 
                      overflow: TextOverflow.ellipsis
                    ),
                  ),
                  if (isPrivate) ...[
                    SizedBox(width: 4),
                    Icon(Icons.lock, size: 14, color: theme.hintColor),
                  ],
                ],
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start, 
              children: [
                SizedBox(width: 4),
                Padding(
                  padding: const EdgeInsets.only(top: 2.0),
                  child: Text("· $timeAgo", style: TextStyle(color: theme.hintColor, fontSize: 12)),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 4.0),
                  child: SizedBox(
                    width: 24,
                    height: 24, 
                    child: _buildOptionsButton(),
                  ),
                ),
              ],
            ),
          ],
        ),
        Text(handle, style: TextStyle(color: theme.hintColor, fontSize: 13), overflow: TextOverflow.ellipsis),
      ],
    );
  }

  Widget _buildOptionsButton() {
    return PopupMenuButton<String>(
      padding: EdgeInsets.zero,
      icon: Icon(Icons.more_horiz, color: Theme.of(context).hintColor, size: 18),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 4,
      color: Theme.of(context).cardColor,
      onSelected: (value) {
        if (value == 'edit') _showEditDialog();
        else if (value == 'delete') _deletePost();
        else if (value == 'pin') _togglePin(); 
        else if (value == 'report') _reportPost();
        else if (value == 'block') _blockUser();
        else if (value == 'toggle_visibility') _toggleVisibility(); // NEW
      },
      itemBuilder: (context) {
        if (widget.isOwner) {
          final isPrivate = (widget.postData['visibility'] ?? 'public') == 'private';
          return [
            PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit_outlined, size: 20, color: Theme.of(context).textTheme.bodyLarge?.color), SizedBox(width: 12), Text("Edit Post")])),
            PopupMenuItem(
              value: 'toggle_visibility', 
              child: Row(
                children: [
                  Icon(isPrivate ? Icons.public : Icons.lock, size: 20, color: Theme.of(context).textTheme.bodyLarge?.color), 
                  SizedBox(width: 12), 
                  Text(isPrivate ? "Set to Public" : "Set to Private")
                ]
              )
            ),
            PopupMenuItem(
              value: 'pin', 
              child: Row(
                children: [
                  Icon(_localIsPinned ? Icons.push_pin : Icons.push_pin_outlined, size: 20, color: Theme.of(context).textTheme.bodyLarge?.color), 
                  SizedBox(width: 12), 
                  Text(_localIsPinned ? "Unpin from Profile" : "Pin to Profile")
                ]
              )
            ),
            PopupMenuDivider(),
            PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline, size: 20, color: Colors.red), SizedBox(width: 12), Text("Delete Post", style: TextStyle(color: Colors.red))])),
          ];
        } else {
          return [
            PopupMenuItem(value: 'report', child: Row(children: [Icon(Icons.flag_outlined, size: 20, color: Theme.of(context).textTheme.bodyLarge?.color), SizedBox(width: 12), Text("Report Post")])),
            PopupMenuItem(value: 'block', child: Row(children: [Icon(Icons.block, size: 20, color: Colors.red), SizedBox(width: 12), Text("Block User", style: TextStyle(color: Colors.red))])),
          ];
        }
      },
    );
  }

  // --- HELPER UNTUK BOOKMARK BUTTON (STREAM) ---
  Widget _buildBookmarkButton() {
    final user = _auth.currentUser;
    if (user == null) {
      return _buildActionButton(Icons.bookmark_border, null, null, () {});
    }

    return StreamBuilder<DocumentSnapshot>(
      // DENGARKAN STATUS BOOKMARK SECARA REAL-TIME DARI FIRESTORE
      stream: _firestore
          .collection('users')
          .doc(user.uid)
          .collection('bookmarks')
          .doc(widget.postId)
          .snapshots(),
      builder: (context, snapshot) {
        final bool isBookmarked = snapshot.hasData && snapshot.data!.exists;
        
        return _buildActionButton(
          isBookmarked ? Icons.bookmark : Icons.bookmark_border, 
          null, 
          isBookmarked ? TwitterTheme.blue : null, 
          () => _handleBookmarkToggle(isBookmarked) // Pass status saat ini
        );
      },
    );
  }

  Widget _buildFeedActionRow(int commentCount) {
    return Padding(
      padding: const EdgeInsets.only(top: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildActionButton(Icons.chat_bubble_outline, commentCount.toString(), null, _navigateToDetail),
          _buildActionButton(Icons.repeat, _repostCount.toString(), _isReposted ? Colors.green : null, _toggleRepost, _repostAnimation),
          _buildActionButton(_isLiked ? Icons.favorite : Icons.favorite_border, _likeCount.toString(), _isLiked ? Colors.pink : null, _toggleLike, _likeAnimation),
          _buildBookmarkButton(), // FIX: Gunakan widget bookmark yang real-time
          _buildActionButton(Icons.share_outlined, null, _isSharing ? TwitterTheme.blue : null, _sharePost, _shareAnimation),
        ],
      ),
    );
  }

  Widget _buildDetailActionRow() {
    return Padding(
      padding: const EdgeInsets.only(top: 16.0, bottom: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildActionButton(Icons.repeat, _repostCount.toString(), _isReposted ? Colors.green : null, _toggleRepost, _repostAnimation),
          _buildActionButton(_isLiked ? Icons.favorite : Icons.favorite_border, _likeCount.toString(), _isLiked ? Colors.pink : null, _toggleLike, _likeAnimation),
          _buildBookmarkButton(), // FIX: Gunakan widget bookmark yang real-time
          _buildActionButton(Icons.share_outlined, 'Share', _isSharing ? TwitterTheme.blue : null, _sharePost, _shareAnimation),
        ],
      ),
    );
  }

  Widget _buildActionButton(IconData icon, String? text, Color? color, VoidCallback onTap, [Animation<double>? animation]) {
    final theme = Theme.of(context);
    final iconColor = color ?? theme.textTheme.bodySmall?.color ?? Colors.grey;
    Widget iconWidget = Icon(icon, size: 20, color: iconColor);
    if (animation != null) iconWidget = ScaleTransition(scale: animation, child: iconWidget);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
        child: Row(
          children: [
            iconWidget, 
            if (text != null && text != "0" && text.isNotEmpty) Padding(padding: const EdgeInsets.only(left: 6.0), child: Text(text, style: TextStyle(color: iconColor, fontSize: 13))),
          ],
        ),
      ),
    );
  }
}