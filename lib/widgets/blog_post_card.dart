// ignore_for_file: prefer_const_constructors
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter/services.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../screens/post_detail_screen.dart';
import '../screens/dashboard/profile_page.dart';
import '../screens/community/community_detail_screen.dart';
import '../services/overlay_service.dart';
import '../services/moderation_service.dart';
import '../services/app_localizations.dart';
import '../main.dart';

// IMPORT COMPONENTS
import 'blog_post_card/video_player_widget.dart';
import 'blog_post_card/post_media_preview.dart';
import 'blog_post_card/post_header.dart';
import 'blog_post_card/post_action_bar.dart';

final FirebaseAuth _auth = FirebaseAuth.instance;
final FirebaseFirestore _firestore = FirebaseFirestore.instance;

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

  final bool isCommunityAdmin;
  final List<String> blockedUserIds;

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
    this.isCommunityAdmin = false, 
    this.blockedUserIds = const [], 
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
  bool _isVideoInitialized = false; 
  bool _isVideoLoading = false;

  // [REPOST FEATURE] State Variables
  bool _isRepostWrapper = false;
  Map<String, dynamic>? _resolvedPostData;
  bool _isLoadingOriginal = false;
  String _originalError = '';

  @override
  void initState() {
    super.initState();
    _localIsPinned = widget.isPinned;
    
    // [REPOST FEATURE] Check if this is a repost wrapper
    if (widget.postData['type'] == 'repost' && widget.postData['originalPostId'] != null) {
      _isRepostWrapper = true;
      _fetchOriginalPost(widget.postData['originalPostId']);
    } else {
      _resolvedPostData = widget.postData;
      _syncState();
    }
    
    // [OPTIMASI 3] Init video hanya jika preloaded dan bukan repost wrapper
    if (widget.preloadedController != null && !_isRepostWrapper) {
      _videoController = widget.preloadedController;
      _isVideoInitialized = true;
      _isVideoOwner = false;
    } 

    _likeController = AnimationController(duration: const Duration(milliseconds: 200), vsync: this);
    _likeAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(CurvedAnimation(parent: _likeController, curve: Curves.easeInOut));

    _shareController = AnimationController(duration: const Duration(milliseconds: 200), vsync: this);
    _shareAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(CurvedAnimation(parent: _shareController, curve: Curves.easeInOut));

    _repostController = AnimationController(duration: const Duration(milliseconds: 200), vsync: this);
    _repostAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(CurvedAnimation(parent: _repostController, curve: Curves.easeInOut));
  }

  // [REPOST FEATURE] Helper Getter
  String get effectivePostId => _isRepostWrapper ? (widget.postData['originalPostId'] ?? widget.postId) : widget.postId;
  Map<String, dynamic> get effectivePostData => _resolvedPostData ?? {};

  bool get effectiveIsOwner {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return false;
    return effectivePostData['userId'] == currentUser.uid;
  }

  Future<void> _fetchOriginalPost(String originalId) async {
    if (mounted) setState(() => _isLoadingOriginal = true);
    try {
      final doc = await _firestore.collection('posts').doc(originalId).get();
      if (doc.exists) {
        if (mounted) {
          setState(() {
            _resolvedPostData = doc.data();
            _isLoadingOriginal = false;
            _syncState();
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _originalError = 'Post no longer exists';
            _isLoadingOriginal = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _originalError = 'Failed to load post';
          _isLoadingOriginal = false;
        });
      }
    }
  }

  Future<void> _initializeVideo() async {
    if (_isVideoInitialized || _videoController != null || _isVideoLoading) return;
    
    final data = effectivePostData;
    final String? singleUrl = data['mediaUrl'];
    final List<dynamic> urls = data['mediaUrls'] ?? [];
    final String? videoUrl = (urls.isNotEmpty) ? urls.first : singleUrl;

    if (videoUrl != null) {
      setState(() => _isVideoLoading = true);
      
      try {
        final controller = VideoPlayerController.networkUrl(Uri.parse(videoUrl));
        await controller.initialize();
        controller.setLooping(true);
        
        if (mounted) {
          setState(() {
            _videoController = controller;
            _isVideoInitialized = true;
            _isVideoOwner = true;
            _isVideoLoading = false;
          });
          _videoController!.play();
        } else {
          controller.dispose();
        }
      } catch (e) {
        if (mounted) setState(() => _isVideoLoading = false);
        debugPrint("Error initializing video: $e");
      }
    }
  }

  @override
  void didUpdateWidget(covariant BlogPostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isPinned != widget.isPinned) {
      setState(() {
        _localIsPinned = widget.isPinned;
      });
    }
  }

  void _syncState() {
    final currentUser = _auth.currentUser;
    if (_resolvedPostData == null) return;

    final likes = _resolvedPostData!['likes'] as Map<String, dynamic>? ?? {};
    final reposts = _resolvedPostData!['repostedBy'] as List? ?? [];

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
    
    final docRef = _firestore.collection('posts').doc(effectivePostId);
    
    setState(() {
      _isLiked = !_isLiked;
      if (_isLiked) {
        _likeCount++;
      } else {
        _likeCount--;
      }
    });
    
    try {
      final notificationId = 'like_${effectivePostId}_${currentUser.uid}';
      final notificationRef = _firestore.collection('users').doc(effectivePostData['userId']).collection('notifications').doc(notificationId);
      
      if (_isLiked) {
        await docRef.update({'likes.${currentUser.uid}': true});
        if (effectivePostData['userId'] != currentUser.uid) {
          notificationRef.set({
            'type': 'like',
            'senderId': currentUser.uid,
            'postId': effectivePostId,
            'postTextSnippet': effectivePostData['text'],
            'timestamp': FieldValue.serverTimestamp(),
            'isRead': false,
          });
        }
      } else {
        await docRef.update({'likes.${currentUser.uid}': FieldValue.delete()});
        if (effectivePostData['userId'] != currentUser.uid) notificationRef.delete();
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

    final targetId = effectivePostId;
    final targetAuthorId = effectivePostData['userId'];
    final docRef = _firestore.collection('posts').doc(targetId);

    // Optimistic UI update
    setState(() {
      _isReposted = !_isReposted;
      if (_isReposted) {
        _repostCount++;
      } else {
        _repostCount--;
      }
    });

    try {
      final notificationId = 'repost_${targetId}_${currentUser.uid}';
      final notificationRef = _firestore.collection('users').doc(targetAuthorId).collection('notifications').doc(notificationId);

      if (_isReposted) {
        // [MODIFIKASI] Fetch user name agar tidak "User"
        String reposterName = currentUser.displayName ?? 'User';
        try {
           final userDoc = await _firestore.collection('users').doc(currentUser.uid).get();
           if (userDoc.exists) {
             final data = userDoc.data();
             reposterName = data?['userName'] ?? data?['name'] ?? reposterName;
           }
        } catch (_) {}

        // Create Repost Wrapper
        await _firestore.collection('posts').add({
          'type': 'repost',
          'originalPostId': targetId,
          'userId': currentUser.uid,
          'userName': reposterName,
          'userEmail': currentUser.email,
          'timestamp': FieldValue.serverTimestamp(),
          'visibility': effectivePostData['visibility'] ?? 'public',
        });

        await docRef.update({
          'repostedBy': FieldValue.arrayUnion([currentUser.uid])
        });

        if (targetAuthorId != currentUser.uid) {
          notificationRef.set({
            'type': 'repost',
            'senderId': currentUser.uid,
            'postId': targetId,
            'postTextSnippet': effectivePostData['text'],
            'timestamp': FieldValue.serverTimestamp(),
            'isRead': false,
          });
        }
      } else {
        // Delete Repost Wrapper
        final query = await _firestore.collection('posts')
            .where('originalPostId', isEqualTo: targetId)
            .where('userId', isEqualTo: currentUser.uid)
            .where('type', isEqualTo: 'repost')
            .get();

        for (var doc in query.docs) {
          await doc.reference.delete();
        }

        await docRef.update({
          'repostedBy': FieldValue.arrayRemove([currentUser.uid])
        });

        if (targetAuthorId != currentUser.uid) notificationRef.delete();
      }
    } catch (e) {
      debugPrint("Repost Error: $e");
      _syncState();
      if (mounted) {
         OverlayService().showTopNotification(context, "Failed to update repost", Icons.error, () {}, color: Colors.red);
      }
    }
  }

  void _handleBookmarkToggle(bool isCurrentlyBookmarked) async {
    final user = _auth.currentUser;
    if (user == null) return;
    if (hapticNotifier.value) HapticFeedback.lightImpact();
    var t = AppLocalizations.of(context)!;

    final docRef = _firestore.collection('users').doc(user.uid).collection('bookmarks').doc(effectivePostId);

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
    
    final currentVis = effectivePostData['visibility'] ?? 'public';
    String newVis;

    if (currentVis == 'private') {
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      final bool isPrivateAccount = userDoc.data()?['isPrivate'] ?? false;
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
      await _firestore.collection('posts').doc(effectivePostId).update({
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
    final text = effectivePostData['text'] ?? '';
    final name = effectivePostData['userName'] ?? 'User';
    
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) setState(() {
        _isSharing = false;
      });
      Share.share('Check out this post by $name: "$text"');
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
        
        if (_isRepostWrapper && widget.postData['originalPostId'] != null) {
             await _firestore.collection('posts').doc(widget.postData['originalPostId']).update({
                'repostedBy': FieldValue.arrayRemove([_auth.currentUser?.uid])
             });
        }

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
      widget.onPinToggle!(effectivePostId, newPinState);
    }
    try {
      if (!newPinState) {
        await _firestore.collection('users').doc(user.uid).update({'pinnedPostId': FieldValue.delete()});
        if (mounted) OverlayService().showTopNotification(context, t.translate('profile_unpin_success'), Icons.push_pin_outlined, () {});
      } else {
        await _firestore.collection('users').doc(user.uid).update({'pinnedPostId': effectivePostId});
        if (mounted) OverlayService().showTopNotification(context, t.translate('profile_pin_success'), Icons.push_pin, () {});
      }
    } catch (e) {
      setState(() {
        _localIsPinned = !newPinState;
      });
      if (widget.onPinToggle != null) widget.onPinToggle!(effectivePostId, !newPinState);
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
          postId: effectivePostId,
          initialPostData: effectivePostData,
          heroContextId: widget.heroContextId,
          preloadedController: _videoController,
        ),
      ),
    );
  }

  void _navigateToSource() {
    final String? communityId = effectivePostData['communityId'];

    if (communityId != null) {
      Navigator.of(context).push(
        _createSlideLeftRoute(
          CommunityDetailScreen(
            communityId: communityId,
            communityData: const {}, 
          ),
        ),
      );
      return;
    }

    final postUserId = effectivePostData['userId'];
    if (postUserId == null) return;
    
    if (effectiveIsOwner) {
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
    _editController.text = effectivePostData['text'] ?? '';
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
      await _firestore.collection('posts').doc(effectivePostId).update({'text': _editController.text});
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
        targetId: effectivePostId,
        targetType: 'post',
        reason: reason);
    OverlayService().showTopNotification(context, t.translate('report_submitted'), Icons.flag, () {});
  }

  void _reportCommunity() {
    var t = AppLocalizations.of(context)!;
    final String? communityId = effectivePostData['communityId'];
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
                    TextButton(onPressed: () => Navigator.pop(context, true), child: Text(t.translate('general_delete'), style: TextStyle(color: Colors.red))), 
                  ],
                )) ??
        false;

    if (didConfirm) {
      await moderationService.blockUser(effectivePostData['userId']);
      if (mounted) OverlayService().showTopNotification(context, t.translate('user_blocked'), Icons.block, () {});
    }
  }

  Widget _buildUploadStatus(double progress) {
    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Uploading media...", style: TextStyle(color: TwitterTheme.blue, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          LinearProgressIndicator(value: null, backgroundColor: Theme.of(context).dividerColor, valueColor: AlwaysStoppedAnimation<Color>(TwitterTheme.blue)),
          const SizedBox(height: 4),
          Text('Processing...', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }

  void _onMenuAction(String value) {
    if (value == 'edit') {
      _showEditDialog();
    } else if (value == 'delete') {
      _deletePost();
    } else if (value == 'pin') {
      _togglePin();
    } else if (value == 'report') {
      _reportPost();
    } else if (value == 'block') {
      _blockUser();
    } else if (value == 'toggle_visibility') {
      _toggleVisibility();
    } else if (value == 'report_community') {
      _reportCommunity();
    }
  }

  // [MODIFIKASI UTAMA DI SINI]
  Widget _buildRepostHeader(BuildContext context) {
    if (!_isRepostWrapper) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final reposterId = widget.postData['userId'];
    final timestamp = widget.postData['timestamp'] as Timestamp?;
    final timeStr = timestamp != null ? timeago.format(timestamp.toDate(), locale: 'en_short') : 'just now';

    // Nama awal dari dokumen repost (fallback jika loading)
    final initialName = widget.postData['userName'] ?? 'User';

    // Menggunakan StreamBuilder untuk memastikan nama selalu terupdate real-time dari koleksi users
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(reposterId).snapshots(),
      builder: (context, snapshot) {
        String displayName = initialName;
        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>;
          // Prioritaskan 'userName', lalu 'name', lalu kembali ke initialName
          displayName = data['userName'] ?? data['name'] ?? displayName;
        }

        return Container(
          padding: const EdgeInsets.only(left: 36.0, bottom: 6.0),
          child: Row(
            children: [
              Icon(Icons.repeat, size: 14, color: theme.hintColor),
              const SizedBox(width: 6),
              Flexible(
                child: GestureDetector(
                  onTap: () {
                    if (reposterId != null) {
                       Navigator.of(context).push(_createSlideLeftRoute(ProfilePage(userId: reposterId, includeScaffold: true)));
                    }
                  },
                  child: RichText(
                    text: TextSpan(
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor, fontSize: 13, fontWeight: FontWeight.w600),
                      children: [
                        TextSpan(text: "$displayName "), // Menampilkan nama dinamis
                        TextSpan(text: "reposted · $timeStr", style: const TextStyle(fontWeight: FontWeight.normal)),
                      ],
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        );
      }
    );
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);

    // [REPOST FEATURE] Loading/Error states for wrapper
    if (_isRepostWrapper) {
      if (_isLoadingOriginal) {
        return Container(
          padding: const EdgeInsets.all(16.0),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: theme.dividerColor, width: 0.5))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
               _buildRepostHeader(context),
               const SizedBox(height: 12),
               const Center(child: CircularProgressIndicator.adaptive(strokeWidth: 2)),
            ],
          ),
        );
      }
      if (_resolvedPostData == null || _originalError.isNotEmpty) {
        return Container(
           padding: const EdgeInsets.all(16.0),
           decoration: BoxDecoration(border: Border(bottom: BorderSide(color: theme.dividerColor, width: 0.5))),
           child: Column(
             crossAxisAlignment: CrossAxisAlignment.start,
             children: [
               _buildRepostHeader(context),
               const SizedBox(height: 12),
               Container(
                 padding: const EdgeInsets.all(12),
                 decoration: BoxDecoration(
                   color: theme.dividerColor.withOpacity(0.1),
                   borderRadius: BorderRadius.circular(8),
                 ),
                 child: Row(
                   children: [
                     Icon(Icons.error_outline, color: theme.hintColor),
                     const SizedBox(width: 8),
                     Text(_originalError.isNotEmpty ? _originalError : "Original post not found", style: TextStyle(color: theme.hintColor)),
                   ],
                 ),
               )
             ],
           ),
        );
      }
    }

    if (widget.blockedUserIds.contains(effectivePostData['userId'])) {
      return const SizedBox.shrink();
    }
    if (_isRepostWrapper && widget.blockedUserIds.contains(widget.postData['userId'])) {
      return const SizedBox.shrink();
    }

    final text = effectivePostData['text'] ?? '';
    final mediaType = effectivePostData['mediaType'];
    final isUploading = effectivePostData['isUploading'] == true;
    final uploadProgress = effectivePostData['uploadProgress'] as double? ?? 0.0;
    final uploadFailed = effectivePostData['uploadFailed'] == true;
    final int commentCount = effectivePostData['commentCount'] ?? 0;

    List<String> mediaUrls = [];
    if (effectivePostData['mediaUrls'] != null) {
      mediaUrls = List<String>.from(effectivePostData['mediaUrls']);
    } else if (effectivePostData['mediaUrl'] != null) {
      mediaUrls = [effectivePostData['mediaUrl']];
    }

    if (uploadFailed) {
      return Container(
        padding: const EdgeInsets.all(12.0),
        color: Colors.red.withOpacity(0.1),
        child: Text("Post upload failed: $text", style: const TextStyle(color: Colors.red)),
      );
    }

    return GestureDetector(
      onTap: (widget.isClickable && !widget.isDetailView) ? _navigateToDetail : null,
      child: Container(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: theme.dividerColor, width: 0.5)),
          color: theme.cardColor,
        ),
        child: Stack(
          children: [
            if (widget.isDetailView && commentCount > 0)
              Positioned(
                left: 32, 
                top: 36, 
                bottom: 0,
                child: Container(
                  width: 2,
                  color: theme.dividerColor,
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildRepostHeader(context),

                  PostHeader(
                    postData: effectivePostData, 
                    isOwner: effectiveIsOwner,
                    isCommunityAdmin: widget.isCommunityAdmin,
                    isPinned: _localIsPinned,
                    onNavigateToSource: _navigateToSource,
                    onMenuAction: _onMenuAction,
                  ),
                  
                  Padding(
                    padding: const EdgeInsets.only(left: 60.0), 
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
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
                            child: Builder(
                              builder: (context) {
                                if (mediaType == 'video' && !_isVideoInitialized) {
                                    return GestureDetector(
                                      onTap: _initializeVideo,
                                      child: Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          PostMediaPreview(
                                            mediaUrls: mediaUrls,
                                            mediaType: mediaType,
                                            text: text,
                                            postData: effectivePostData,
                                            postId: effectivePostId,
                                            heroContextId: widget.heroContextId,
                                            videoController: null, 
                                          ),
                                          Container(
                                            color: Colors.black26,
                                            child: Center(
                                              child: _isVideoLoading 
                                                ? const CircularProgressIndicator(color: Colors.white)
                                                : const Icon(Icons.play_circle_fill, size: 64, color: Colors.white70),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                }
                                
                                return PostMediaPreview(
                                  mediaUrls: mediaUrls,
                                  mediaType: mediaType,
                                  text: text,
                                  postData: effectivePostData,
                                  postId: effectivePostId,
                                  heroContextId: widget.heroContextId,
                                  videoController: _videoController,
                                );
                              }
                            ),
                          ),

                        if (!isUploading)
                          PostActionBar(
                            postId: effectivePostId,
                            commentCount: commentCount,
                            repostCount: _repostCount,
                            likeCount: _likeCount,
                            isReposted: _isReposted,
                            isLiked: _isLiked,
                            isSharing: _isSharing,
                            isDetailView: widget.isDetailView,
                            onCommentTap: _navigateToDetail,
                            onRepostTap: _toggleRepost,
                            onLikeTap: _toggleLike,
                            onShareTap: _sharePost,
                            onBookmarkTap: _handleBookmarkToggle,
                            likeAnimation: _likeAnimation,
                            repostAnimation: _repostAnimation,
                            shareAnimation: _shareAnimation,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}