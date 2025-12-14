// ignore_for_file: prefer_const_constructors
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../screens/post_detail_screen.dart';
import '../screens/dashboard/profile_page.dart';
import '../screens/community/community_detail_screen.dart';
import '../screens/image_viewer_screen.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../main.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import '../services/overlay_service.dart';
import '../services/moderation_service.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import '../services/app_localizations.dart'; // IMPORT LOCALIZATION

final FirebaseAuth _auth = FirebaseAuth.instance;
final FirebaseFirestore _firestore = FirebaseFirestore.instance;

// --- DUMB WIDGET: Video Player (Tidak Perlu Ubah) ---
class _VideoPlayerWidget extends StatelessWidget {
  final VideoPlayerController controller;
  final bool isThumbnail;

  const _VideoPlayerWidget({
    required this.controller,
    this.isThumbnail = false,
  });

  @override
  Widget build(BuildContext context) {
    if (!controller.value.isInitialized) {
      return Container(
        color: Colors.black,
        height: isThumbnail ? null : 300,
        width: double.infinity,
        child: Center(child: CircularProgressIndicator(color: TwitterTheme.blue)),
      );
    }

    Widget videoDisplay;

    if (isThumbnail) {
      videoDisplay = SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: controller.value.size.width,
            height: controller.value.size.height,
            child: VideoPlayer(controller),
          ),
        ),
      );
    } else {
      videoDisplay = AspectRatio(
        aspectRatio: controller.value.aspectRatio,
        child: VideoPlayer(controller),
      );
    }

    return Container(
      color: Colors.black,
      constraints: isThumbnail ? null : BoxConstraints(maxHeight: 400),
      width: double.infinity,
      child: Stack(
        alignment: Alignment.center,
        children: [
          videoDisplay,
          Container(color: Colors.black.withOpacity(0.2)),
          Center(
            child: Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.25),
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

// --- SMART WIDGET: Media Preview (Tidak Perlu Ubah) ---
class _PostMediaPreview extends StatefulWidget {
  final List<String> mediaUrls;
  final String? mediaType;
  final String text;
  final Map<String, dynamic> postData;
  final String postId;
  final String heroContextId;
  final VideoPlayerController? videoController;

  const _PostMediaPreview({
    required this.mediaUrls,
    this.mediaType,
    required this.text,
    required this.postData,
    required this.postId,
    required this.heroContextId,
    this.videoController,
  });

  @override
  State<_PostMediaPreview> createState() => _PostMediaPreviewState();
}

class _PostMediaPreviewState extends State<_PostMediaPreview> {
  int _currentIndex = 0;

  String? _getVideoId(String url) {
    if (url.contains('youtube.com') || url.contains('youtu.be')) {
      final regExp = RegExp(r"youtu(?:.*\/v\/|.*v\=|\.be\/)([A-Za-z0-9_\-]+)");
      return regExp.firstMatch(url)?.group(1);
    }
    return null;
  }

  String? _extractLinkInText() {
    final linkRegExp = RegExp(r'(https?:\/\/[^\s]+)');
    final match = linkRegExp.firstMatch(widget.text);
    return match?.group(0);
  }

  void _navigateToViewer(BuildContext context, String url) {
    final String heroTag = '${widget.heroContextId}_${widget.postId}_$url';

    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black, 
        pageBuilder: (_, __, ___) => ImageViewerScreen(
          imageUrl: url,
          mediaType: widget.mediaType,
          postData: widget.postData,
          postId: widget.postId,
          heroTag: heroTag,
          videoController: widget.videoController,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (widget.mediaType == 'video' && widget.mediaUrls.isNotEmpty && widget.videoController != null) {
      final String videoUrl = widget.mediaUrls.first;
      final String heroTag = '${widget.heroContextId}_${widget.postId}_$videoUrl';

      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: GestureDetector(
          onTap: () => _navigateToViewer(context, videoUrl),
          child: Hero(
            tag: heroTag,
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: _VideoPlayerWidget(
                controller: widget.videoController!,
                isThumbnail: true, 
              ),
            ),
          ),
        ),
      );
    }

    if (widget.mediaUrls.isNotEmpty) {
      final bool isMulti = widget.mediaUrls.length > 1;

      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            isMulti
                ? AspectRatio(
                    aspectRatio: 1.0,
                    child: PageView.builder(
                      itemCount: widget.mediaUrls.length,
                      onPageChanged: (index) {
                        setState(() => _currentIndex = index);
                      },
                      itemBuilder: (context, index) {
                        final url = widget.mediaUrls[index];
                        return GestureDetector(
                          onTap: () => _navigateToViewer(context, url),
                          child: Hero(
                            tag: '${widget.heroContextId}_${widget.postId}_$url',
                            child: CachedNetworkImage(
                              imageUrl: url,
                              fit: BoxFit.cover,
                              placeholder: (context, url) => Container(color: theme.dividerColor.withOpacity(0.1)),
                              errorWidget: (context, url, error) => Icon(Icons.error),
                            ),
                          ),
                        );
                      },
                    ),
                  )
                : AspectRatio(
                    aspectRatio: 4 / 3,
                    child: GestureDetector(
                      onTap: () => _navigateToViewer(context, widget.mediaUrls.first),
                      child: Hero(
                        tag: '${widget.heroContextId}_${widget.postId}_${widget.mediaUrls.first}',
                        child: CachedNetworkImage(
                          imageUrl: widget.mediaUrls.first,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Container(color: theme.dividerColor.withOpacity(0.1)),
                          errorWidget: (context, url, error) => Icon(Icons.error),
                        ),
                      ),
                    ),
                  ),
            if (isMulti)
              Positioned(
                top: 12,
                right: 12,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    "${_currentIndex + 1}/${widget.mediaUrls.length}",
                    style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    final externalLink = _extractLinkInText();
    final youtubeId = externalLink != null ? _getVideoId(externalLink) : null;

    if (youtubeId != null) {
      return AspectRatio(
        aspectRatio: 16 / 9,
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
                  Text('Watch on YouTube', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
  final String? currentProfileUserId;

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
    this.currentProfileUserId,
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

  // --- COMMUNITY PERMISSIONS STATE ---
  StreamSubscription? _communityRoleSubscription;
  bool _isCommunityAdmin = false;

  @override
  void initState() {
    super.initState();
    _localIsPinned = widget.isPinned;
    _syncState();
    _initVideoController();
    _checkCommunityPermissions();

    _likeController = AnimationController(duration: const Duration(milliseconds: 200), vsync: this);
    _likeAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(CurvedAnimation(parent: _likeController, curve: Curves.easeInOut));

    _shareController = AnimationController(duration: const Duration(milliseconds: 200), vsync: this);
    _shareAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(CurvedAnimation(parent: _shareController, curve: Curves.easeInOut));

    _repostController = AnimationController(duration: const Duration(milliseconds: 200), vsync: this);
    _repostAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(CurvedAnimation(parent: _repostController, curve: Curves.easeInOut));
  }

  void _checkCommunityPermissions() {
    final user = _auth.currentUser;
    final String? communityId = widget.postData['communityId'];

    if (user != null && communityId != null) {
      _communityRoleSubscription = _firestore.collection('communities').doc(communityId).snapshots().listen((snapshot) {
        if (mounted && snapshot.exists) {
          final data = snapshot.data();
          if (data != null) {
            final String ownerId = data['ownerId'];
            final List admins = data['admins'] ?? [];
            final bool isAdmin = (user.uid == ownerId) || admins.contains(user.uid);

            if (_isCommunityAdmin != isAdmin) {
              setState(() => _isCommunityAdmin = isAdmin);
            }
          }
        }
      });
    }
  }

  void _initVideoController() {
    final String? singleUrl = widget.postData['mediaUrl'];
    final List<dynamic> urls = widget.postData['mediaUrls'] ?? [];
    final String? mediaType = widget.postData['mediaType'];

    final String? videoUrl = (urls.isNotEmpty) ? urls.first : singleUrl;

    if (mediaType == 'video' && videoUrl != null) {
      if (widget.preloadedController != null) {
        _videoController = widget.preloadedController;
        _isVideoOwner = false;
      } else {
        _videoController = VideoPlayerController.networkUrl(Uri.parse(videoUrl))
          ..initialize().then((_) {
            final duration = _videoController!.value.duration;
            final targetPosition = duration.inSeconds > 10 ? Duration(seconds: 10) : duration;
            _videoController!.seekTo(targetPosition).then((_) {
              if (mounted) setState(() {});
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
      
      if (oldWidget.postData['communityId'] != widget.postData['communityId']) {
        _communityRoleSubscription?.cancel();
        _checkCommunityPermissions();
      }

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
    _communityRoleSubscription?.cancel();
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
    setState(() {
      _isLiked = !_isLiked;
      if (_isLiked)
        _likeCount++;
      else
        _likeCount--;
    });
    try {
      final notificationId = 'like_${widget.postId}_${currentUser.uid}';
      final notificationRef = _firestore.collection('users').doc(widget.postData['userId']).collection('notifications').doc(notificationId);
      if (_isLiked) {
        await docRef.update({'likes.${currentUser.uid}': true});
        if (widget.postData['userId'] != currentUser.uid) {
          notificationRef.set({
            'type': 'like',
            'senderId': currentUser.uid,
            'postId': widget.postId,
            'postTextSnippet': widget.postData['text'],
            'timestamp': FieldValue.serverTimestamp(),
            'isRead': false,
          });
        }
      } else {
        await docRef.update({'likes.${currentUser.uid}': FieldValue.delete()});
        if (widget.postData['userId'] != currentUser.uid) notificationRef.delete();
      }
    } catch (e) {
      _syncState();
    }
  }

  void _toggleRepost() async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;
    _repostController.forward().then((_) => _repostController.reverse());
    if (hapticNotifier.value) HapticFeedback.lightImpact();
    final docRef = _firestore.collection('posts').doc(widget.postId);
    setState(() {
      _isReposted = !_isReposted;
      if (_isReposted)
        _repostCount++;
      else
        _repostCount--;
    });
    try {
      final notificationId = 'repost_${widget.postId}_${currentUser.uid}';
      final notificationRef = _firestore.collection('users').doc(widget.postData['userId']).collection('notifications').doc(notificationId);
      if (_isReposted) {
        await docRef.update({
          'repostedBy': FieldValue.arrayUnion([currentUser.uid])
        });
        if (widget.postData['userId'] != currentUser.uid) {
          notificationRef.set({
            'type': 'repost',
            'senderId': currentUser.uid,
            'postId': widget.postId,
            'postTextSnippet': widget.postData['text'],
            'timestamp': FieldValue.serverTimestamp(),
            'isRead': false,
          });
        }
      } else {
        await docRef.update({
          'repostedBy': FieldValue.arrayRemove([currentUser.uid])
        });
        if (widget.postData['userId'] != currentUser.uid) notificationRef.delete();
      }
    } catch (e) {
      _syncState();
    }
  }

  void _handleBookmarkToggle(bool isCurrentlyBookmarked) async {
    final user = _auth.currentUser;
    if (user == null) return;
    if (hapticNotifier.value) HapticFeedback.lightImpact();
    
    // LOCALIZATION
    var t = AppLocalizations.of(context)!;

    final docRef = _firestore.collection('users').doc(user.uid).collection('bookmarks').doc(widget.postId);

    if (!isCurrentlyBookmarked) {
      OverlayService().showTopNotification(context, t.translate('post_bookmark_saved'), Icons.bookmark, () {});
    } else {
      OverlayService().showTopNotification(context, t.translate('post_bookmark_removed'), Icons.bookmark_remove, () {});
    }

    try {
      if (!isCurrentlyBookmarked) {
        await docRef.set({'timestamp': FieldValue.serverTimestamp()});
      } else {
        await docRef.delete();
      }
    } catch (e) {
      OverlayService().showTopNotification(context, t.translate('post_bookmark_error'), Icons.error, () {}, color: Colors.red);
    }
  }

  void _toggleVisibility() async {
    final user = _auth.currentUser;
    if (user == null) return;
    var t = AppLocalizations.of(context)!;

    final currentVis = widget.postData['visibility'] ?? 'public';
    String newVis;

    if (currentVis == 'private') {
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      final bool isPrivateAccount = userDoc.exists && (userDoc.data()?['isPrivate'] ?? false);
      newVis = isPrivateAccount ? 'followers' : 'public';
    } else {
      newVis = 'private';
    }

    String msg;
    IconData icon;
    Color? color;

    if (newVis == 'private') {
      msg = t.translate('vis_toast_private');
      icon = Icons.visibility_off;
    } else if (newVis == 'followers') {
      msg = t.translate('vis_toast_followers');
      icon = Icons.people;
      color = Colors.orange;
    } else {
      msg = t.translate('vis_toast_public');
      icon = Icons.public;
    }

    if (mounted) OverlayService().showTopNotification(context, msg, icon, () {}, color: color);

    try {
      await _firestore.collection('posts').doc(widget.postId).update({
        'visibility': newVis,
      });
    } catch (e) {
      if (mounted) {
        OverlayService().showTopNotification(context, t.translate('vis_toast_fail'), Icons.error, () {}, color: Colors.red);
      }
    }
  }

  void _sharePost() {
    _shareController.forward().then((_) => _shareController.reverse());
    setState(() {
      _isSharing = true;
    });
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) setState(() {
        _isSharing = false;
      });
      Share.share('Check out this post by ${widget.postData['userName']}: "${widget.postData['text']}"');
    });
  }

  Future<void> _deletePost() async {
    var t = AppLocalizations.of(context)!;
    final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(t.translate('delete_post_title')),
            content: Text(t.translate('delete_post_confirm')),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.translate('general_cancel'))),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.translate('general_delete'), style: TextStyle(color: Colors.red))),
            ],
          ),
        ) ??
        false;
    if (confirm) {
      try {
        await _firestore.collection('posts').doc(widget.postId).delete();
        if (mounted) OverlayService().showTopNotification(context, t.translate('post_deleted'), Icons.delete_outline, () {});
      } catch (e) {
        if (mounted) OverlayService().showTopNotification(context, t.translate('post_delete_fail'), Icons.error, () {}, color: Colors.red);
      }
    }
  }

  Future<void> _togglePin() async {
    final user = _auth.currentUser;
    if (user == null) return;
    var t = AppLocalizations.of(context)!;
    final bool newPinState = !_localIsPinned;
    setState(() {
      _localIsPinned = newPinState;
    });
    if (widget.onPinToggle != null) {
      widget.onPinToggle!(widget.postId, newPinState);
    }
    try {
      if (!newPinState) {
        await _firestore.collection('users').doc(user.uid).update({'pinnedPostId': FieldValue.delete()});
        if (mounted) OverlayService().showTopNotification(context, t.translate('profile_unpin_success'), Icons.push_pin_outlined, () {});
      } else {
        await _firestore.collection('users').doc(user.uid).update({'pinnedPostId': widget.postId});
        if (mounted) OverlayService().showTopNotification(context, t.translate('profile_pin_success'), Icons.push_pin, () {});
      }
    } catch (e) {
      setState(() {
        _localIsPinned = !newPinState;
      });
      if (widget.onPinToggle != null) widget.onPinToggle!(widget.postId, !newPinState);
      if (mounted) OverlayService().showTopNotification(context, t.translate('pin_fail'), Icons.error, () {}, color: Colors.red);
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

  void _navigateToSource() {
    final String? communityId = widget.postData['communityId'];

    // 1. If Community Post, Go to Community Detail
    if (communityId != null) {
      Navigator.of(context).push(
        _createSlideLeftRoute(
          CommunityDetailScreen(
            communityId: communityId,
            communityData: {}, // Fetch inside screen
          ),
        ),
      );
      return;
    }

    // 2. Else Go to User Profile
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
    if (widget.currentProfileUserId != null && postUserId == widget.currentProfileUserId) return;

    Navigator.of(context).push(
      _createSlideLeftRoute(
        ProfilePage(userId: postUserId, includeScaffold: true),
      ),
    );
  }

  Future<void> _showEditDialog() async {
    var t = AppLocalizations.of(context)!;
    _editController.text = widget.postData['text'] ?? '';
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(t.translate('edit_post_title')),
          content: TextField(
            controller: _editController,
            maxLines: 5,
            decoration: InputDecoration(hintText: t.translate('edit_post_hint')),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(t.translate('general_cancel'))),
            ElevatedButton(onPressed: _submitEdit, child: Text(t.translate('general_save'))),
          ],
        );
      },
    );
  }

  Future<void> _submitEdit() async {
    var t = AppLocalizations.of(context)!;
    try {
      await _firestore.collection('posts').doc(widget.postId).update({'text': _editController.text});
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        OverlayService().showTopNotification(context, t.translate('edit_post_fail'), Icons.error, () {}, color: Colors.red);
        Navigator.of(context).pop();
      }
    }
  }

  void _reportPost() {
    var t = AppLocalizations.of(context)!;
    showDialog(
        context: context,
        builder: (context) {
          return SimpleDialog(
            title: Text(t.translate('report_post_title')),
            children: [
              SimpleDialogOption(onPressed: () => _submitReport('Spam'), child: Text(t.translate('report_reason_spam'))),
              SimpleDialogOption(onPressed: () => _submitReport('Harassment'), child: Text(t.translate('report_reason_harass'))),
              SimpleDialogOption(onPressed: () => _submitReport('Inappropriate Content'), child: Text(t.translate('report_reason_inappropriate'))),
              SimpleDialogOption(onPressed: () => _submitReport('Misinformation'), child: Text(t.translate('report_reason_misinfo'))),
              Padding(padding: EdgeInsets.all(8), child: TextButton(onPressed: () => Navigator.pop(context), child: Text(t.translate('general_cancel')))),
            ],
          );
        });
  }

  void _submitReport(String reason) {
    var t = AppLocalizations.of(context)!;
    Navigator.pop(context);
    moderationService.reportContent(
        targetId: widget.postId,
        targetType: 'post',
        reason: reason);
    OverlayService().showTopNotification(context, t.translate('report_submitted'), Icons.flag, () {});
  }

  void _reportCommunity() {
    var t = AppLocalizations.of(context)!;
    final String? communityId = widget.postData['communityId'];
    if (communityId == null) return;

    showDialog(
        context: context,
        builder: (context) {
          return SimpleDialog(
            title: Text(t.translate('report_comm_title')),
            children: [
              SimpleDialogOption(onPressed: () => _submitCommunityReport(communityId, 'Spam'), child: Text(t.translate('report_reason_spam'))),
              SimpleDialogOption(onPressed: () => _submitCommunityReport(communityId, 'Harassment'), child: Text(t.translate('report_reason_harass'))),
              SimpleDialogOption(onPressed: () => _submitCommunityReport(communityId, 'Inappropriate Content'), child: Text(t.translate('report_reason_inappropriate'))),
              SimpleDialogOption(onPressed: () => _submitCommunityReport(communityId, 'Misinformation'), child: Text(t.translate('report_reason_misinfo'))),
              Padding(padding: EdgeInsets.all(8), child: TextButton(onPressed: () => Navigator.pop(context), child: Text(t.translate('general_cancel')))),
            ],
          );
        });
  }

  void _submitCommunityReport(String communityId, String reason) {
    var t = AppLocalizations.of(context)!;
    Navigator.pop(context);
    moderationService.reportContent(
        targetId: communityId,
        targetType: 'community',
        reason: reason);
    OverlayService().showTopNotification(context, t.translate('report_comm_submitted'), Icons.flag, () {});
  }

  void _blockUser() async {
    var t = AppLocalizations.of(context)!;
    final didConfirm = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
                  title: Text(t.translate('block_user_title')),
                  content: Text(t.translate('block_user_confirm')),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t.translate('general_cancel'))),
                    TextButton(onPressed: () => Navigator.pop(context, true), child: Text(t.translate('general_delete'), style: TextStyle(color: Colors.red))), // Using "Delete" key for block action
                  ],
                )) ??
        false;

    if (didConfirm) {
      await moderationService.blockUser(widget.postData['userId']);
      if (mounted) OverlayService().showTopNotification(context, t.translate('user_blocked'), Icons.block, () {});
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
    var t = AppLocalizations.of(context)!; // GET LOCALIZATION

    return StreamBuilder<List<String>>(
        stream: moderationService.streamBlockedUsers(),
        builder: (context, snapshot) {
          final blockedUsers = snapshot.data ?? [];
          if (blockedUsers.contains(widget.postData['userId'])) {
            return SizedBox.shrink();
          }

          final theme = Theme.of(context);
          final text = widget.postData['text'] ?? '';
          final mediaType = widget.postData['mediaType'];
          final isUploading = widget.postData['isUploading'] == true;
          final uploadProgress = widget.postData['uploadProgress'] as double? ?? 0.0;
          final uploadFailed = widget.postData['uploadFailed'] == true;
          final int commentCount = widget.postData['commentCount'] ?? 0;

          List<String> mediaUrls = [];
          if (widget.postData['mediaUrls'] != null) {
            mediaUrls = List<String>.from(widget.postData['mediaUrls']);
          } else if (widget.postData['mediaUrl'] != null) {
            mediaUrls = [widget.postData['mediaUrl']];
          }

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
                          Text(t.translate('post_pinned'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: theme.hintColor)), // "Pinned Post"
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
                            else if (mediaUrls.isNotEmpty || (text.contains('http') && !widget.isDetailView))
                              Padding(
                                padding: const EdgeInsets.only(top: 12.0),
                                child: _PostMediaPreview(
                                  mediaUrls: mediaUrls, 
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
        });
  }

  // --- UPDATED AVATAR LOGIC (REAL-TIME SYNC) ---
  Widget _buildAvatar(BuildContext context) {
    // Determine which image to show based on post type
    final bool isCommunityPost = widget.postData['isCommunityPost'] ?? false;
    final String? communityId = widget.postData['communityId'];

    if (communityId != null && isCommunityPost) {
      // Official Community Post: Fetch fresh image from 'communities' collection
      return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('communities').doc(communityId).snapshots(),
          builder: (context, snapshot) {
            String? displayImg = widget.postData['communityIcon']; // Fallback

            if (snapshot.hasData && snapshot.data!.exists) {
              final data = snapshot.data!.data() as Map<String, dynamic>;
              displayImg = data['imageUrl'] ?? displayImg;
            }

            return GestureDetector(
              onTap: _navigateToSource,
              child: CircleAvatar(
                radius: 24,
                backgroundColor: TwitterTheme.blue.withOpacity(0.1),
                backgroundImage: displayImg != null ? CachedNetworkImageProvider(displayImg) : null,
                child: displayImg == null ? Icon(Icons.groups, size: 26, color: TwitterTheme.blue) : null,
              ),
            );
          });
    }

    // Otherwise (Personal Post or User Post in Community): Show User Avatar
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
          onTap: _navigateToSource,
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

  // --- UPDATED HEADER LOGIC (REAL-TIME SYNC) ---
  Widget _buildPostHeader(BuildContext context) {
    final theme = Theme.of(context);
    final timeAgo = _formatTimestamp(widget.postData['timestamp'] as Timestamp?);

    // Check context
    final String? communityId = widget.postData['communityId'];
    final bool isCommunityPost = widget.postData['isCommunityPost'] ?? false;
    final bool isVerifiedFromPost = widget.postData['communityVerified'] ?? false;

    // 1. OFFICIAL COMMUNITY POST
    if (communityId != null && isCommunityPost) {
      // Stream fresh community name & verification status
      return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('communities').doc(communityId).snapshots(),
          builder: (context, snapshot) {
            String comName = widget.postData['communityName'] ?? 'Community';
            bool isVerified = isVerifiedFromPost;

            if (snapshot.hasData && snapshot.data!.exists) {
              final data = snapshot.data!.data() as Map<String, dynamic>;
              comName = data['name'] ?? comName;
              isVerified = data['isVerified'] ?? isVerified;
            }

            final String userName = widget.postData['userName'] ?? 'Member';

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: GestureDetector(
                              onTap: _navigateToSource,
                              child: Text(comName,
                                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                                  overflow: TextOverflow.ellipsis),
                            ),
                          ),
                          if (isVerified) ...[
                            SizedBox(width: 4),
                            Icon(Icons.verified, size: 14, color: TwitterTheme.blue),
                          ],
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        Text("· $timeAgo", style: TextStyle(color: theme.hintColor, fontSize: 12)),
                        SizedBox(width: 8),
                        SizedBox(width: 24, height: 24, child: _buildOptionsButton()),
                      ],
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 2.0),
                  child: Row(
                    children: [
                      Icon(Icons.person, size: 12, color: theme.hintColor),
                      SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          "Posted by $userName",
                          style: TextStyle(color: theme.hintColor, fontSize: 11),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          });
    }

    // 2. PERSONAL POST IN COMMUNITY
    if (communityId != null && !isCommunityPost) {
      final String userName = widget.postData['userName'] ?? 'User';

      // Also stream community name here for correctness
      return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('communities').doc(communityId).snapshots(),
          builder: (context, snapshot) {
            String comName = widget.postData['communityName'] ?? 'Community';
            if (snapshot.hasData && snapshot.data!.exists) {
              final data = snapshot.data!.data() as Map<String, dynamic>;
              comName = data['name'] ?? comName;
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: GestureDetector(
                              onTap: _navigateToSource,
                              child: Text(userName,
                                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                                  overflow: TextOverflow.ellipsis),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        Text("· $timeAgo", style: TextStyle(color: theme.hintColor, fontSize: 12)),
                        SizedBox(width: 8),
                        SizedBox(width: 24, height: 24, child: _buildOptionsButton()),
                      ],
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 2.0),
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          "in $comName",
                          style: TextStyle(color: theme.hintColor, fontSize: 11, fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                )
              ],
            );
          });
    }

    // 3. STANDARD USER POST
    final String userName = widget.postData['userName'] ?? 'User';
    final String handle = "@${widget.postData['userEmail']?.split('@')[0] ?? 'user'}";
    final String visibility = widget.postData['visibility'] ?? 'public';
    final bool isPrivate = visibility == 'private';
    final bool isFollowersOnly = visibility == 'followers';

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
                    child: GestureDetector(
                      onTap: _navigateToSource,
                      child: Text(
                        userName,
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  if (isPrivate) ...[
                    SizedBox(width: 4),
                    Icon(Icons.lock, size: 14, color: theme.hintColor),
                  ] else if (isFollowersOnly) ...[
                    SizedBox(width: 4),
                    Icon(Icons.people, size: 14, color: theme.hintColor),
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
    var t = AppLocalizations.of(context)!;
    return PopupMenuButton<String>(
      padding: EdgeInsets.zero,
      icon: Icon(Icons.more_horiz, color: Theme.of(context).hintColor, size: 18),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 4,
      color: Theme.of(context).cardColor,
      onSelected: (value) {
        if (value == 'edit')
          _showEditDialog();
        else if (value == 'delete')
          _deletePost();
        else if (value == 'pin')
          _togglePin();
        else if (value == 'report')
          _reportPost();
        else if (value == 'block')
          _blockUser();
        else if (value == 'toggle_visibility')
          _toggleVisibility();
        else if (value == 'report_community') _reportCommunity();
      },
      itemBuilder: (context) {
        final List<PopupMenuEntry<String>> options = [];

        // CASE 1: I am the Author (Standard User editing own post)
        if (widget.isOwner) {
          final isPrivate = (widget.postData['visibility'] ?? 'public') == 'private';
          options.addAll([
            PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit_outlined, size: 20, color: Theme.of(context).textTheme.bodyLarge?.color), SizedBox(width: 12), Text(t.translate('menu_edit'))])), // "Edit Post"
            PopupMenuItem(value: 'toggle_visibility', child: Row(children: [Icon(isPrivate ? Icons.public : Icons.lock_outline, size: 20, color: Theme.of(context).textTheme.bodyLarge?.color), SizedBox(width: 12), Text(isPrivate ? t.translate('menu_unhide') : t.translate('menu_hide'))])), // "Unhide" / "Hide"
            PopupMenuItem(value: 'pin', child: Row(children: [Icon(_localIsPinned ? Icons.push_pin : Icons.push_pin_outlined, size: 20, color: Theme.of(context).textTheme.bodyLarge?.color), SizedBox(width: 12), Text(_localIsPinned ? t.translate('menu_unpin') : t.translate('menu_pin'))])), // "Unpin" / "Pin"
            PopupMenuDivider(),
            PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline, size: 20, color: Colors.red), SizedBox(width: 12), Text(t.translate('menu_delete'), style: TextStyle(color: Colors.red))])), // "Delete Post"
          ]);
        }
        // CASE 2: I am a Community Admin/Owner (Editing someone else's post)
        else if (_isCommunityAdmin) {
          options.addAll([
            PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit_outlined, size: 20, color: Theme.of(context).textTheme.bodyLarge?.color), SizedBox(width: 12), Text(t.translate('menu_edit_admin'))])), // "Edit Post (Admin)"
            PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline, size: 20, color: Colors.red), SizedBox(width: 12), Text(t.translate('menu_delete_admin'), style: TextStyle(color: Colors.red))])), // "Delete Post (Admin)"
            PopupMenuDivider(),
            PopupMenuItem(value: 'report', child: Row(children: [Icon(Icons.flag_outlined, size: 20, color: Theme.of(context).textTheme.bodyLarge?.color), SizedBox(width: 12), Text(t.translate('menu_report'))])), // "Report Post"
            PopupMenuItem(value: 'block', child: Row(children: [Icon(Icons.block, size: 20, color: Colors.red), SizedBox(width: 12), Text(t.translate('menu_block'), style: TextStyle(color: Colors.red))])), // "Block User"
          ]);
        }
        // CASE 3: Standard User (Viewing someone else's post)
        else {
          options.addAll([
            PopupMenuItem(value: 'report', child: Row(children: [Icon(Icons.flag_outlined, size: 20, color: Theme.of(context).textTheme.bodyLarge?.color), SizedBox(width: 12), Text(t.translate('menu_report'))])), // "Report Post"
            PopupMenuItem(value: 'block', child: Row(children: [Icon(Icons.block, size: 20, color: Colors.red), SizedBox(width: 12), Text(t.translate('menu_block'), style: TextStyle(color: Colors.red))])), // "Block User"
          ]);
        }

        // Add "Report Community" for everyone if this is a community post
        if (widget.postData['communityId'] != null) {
          options.add(PopupMenuItem(value: 'report_community', child: Row(children: [Icon(Icons.flag, size: 20, color: Colors.orange), SizedBox(width: 12), Text(t.translate('menu_report_comm'))]))); // "Report Community"
        }

        return options;
      },
    );
  }

  Widget _buildBookmarkButton() {
    final user = _auth.currentUser;
    if (user == null) {
      return _buildActionButton(Icons.bookmark_border, null, null, () {});
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: _firestore.collection('users').doc(user.uid).collection('bookmarks').doc(widget.postId).snapshots(),
      builder: (context, snapshot) {
        final bool isBookmarked = snapshot.hasData && snapshot.data!.exists;
        return _buildActionButton(isBookmarked ? Icons.bookmark : Icons.bookmark_border, null, isBookmarked ? TwitterTheme.blue : null, () => _handleBookmarkToggle(isBookmarked));
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
          _buildBookmarkButton(),
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
          _buildBookmarkButton(),
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