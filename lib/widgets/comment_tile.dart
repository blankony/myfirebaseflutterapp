// ignore_for_file: prefer_const_constructors
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:share_plus/share_plus.dart'; 
import 'package:flutter_cache_manager/flutter_cache_manager.dart'; 
import '../screens/post_detail_screen.dart'; 
import '../screens/dashboard/profile_page.dart'; 
import '../screens/image_viewer_screen.dart'; 
import 'package:timeago/timeago.dart' as timeago; 
import '../main.dart';
import 'package:cached_network_image/cached_network_image.dart'; 
import '../services/overlay_service.dart';

final FirebaseAuth _auth = FirebaseAuth.instance;
final FirebaseFirestore _firestore = FirebaseFirestore.instance;

class CommentTile extends StatefulWidget {
  final String commentId;
  final Map<String, dynamic> commentData;
  final String postId; 
  final bool isOwner;
  final bool showPostContext; 
  final String heroContextId; 
  
  // NEW: To prevent loop when on profile page
  final String? currentProfileUserId;
  
  // NEW: Determines if the thread line should terminate at this tile
  final bool isLast;

  const CommentTile({
    super.key,
    required this.commentId,
    required this.commentData,
    required this.postId,
    required this.isOwner,
    this.showPostContext = false, 
    this.heroContextId = 'comment', 
    this.currentProfileUserId,
    this.isLast = true, // Default to true so isolated comments (e.g. Profile) don't have dangling lines
  });

  @override
  State<CommentTile> createState() => _CommentTileState();
}

class _CommentTileState extends State<CommentTile> with SingleTickerProviderStateMixin {
  final TextEditingController _editController = TextEditingController();
  
  late bool _isLiked;
  late int _likeCount;
  late bool _isReposted; 
  late int _repostCount; 
  
  late AnimationController _likeController;
  late Animation<double> _likeAnimation;

  @override
  void initState() {
    super.initState();
    _syncStatsState();
    _likeController = AnimationController(duration: const Duration(milliseconds: 200), vsync: this);
    _likeAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(CurvedAnimation(parent: _likeController, curve: Curves.easeInOut));
  }

  @override
  void didUpdateWidget(covariant CommentTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.commentData != oldWidget.commentData) {
      _syncStatsState();
    }
  }

  void _syncStatsState() {
    final currentUser = _auth.currentUser;
    final likes = widget.commentData['likes'] as Map<String, dynamic>? ?? {};
    final reposts = widget.commentData['repostedBy'] as List? ?? []; 
    
    if (mounted) {
      setState(() {
        _isLiked = currentUser != null && likes.containsKey(currentUser.uid);
        _likeCount = likes.length;
        _isReposted = currentUser != null && reposts.contains(currentUser.uid); 
        _repostCount = reposts.length; 
      });
    }
  }

  Future<void> _toggleLike() async {
    final user = _auth.currentUser;
    if (user == null) return;

    _likeController.forward().then((_) => _likeController.reverse());

    setState(() {
      _isLiked = !_isLiked;
      if (_isLiked) _likeCount++; else _likeCount--;
    });

    try {
      final commentRef = _firestore
          .collection('posts')
          .doc(widget.postId)
          .collection('comments')
          .doc(widget.commentId);

      if (_isLiked) {
        await commentRef.update({'likes.${user.uid}': true});
      } else {
        await commentRef.update({'likes.${user.uid}': FieldValue.delete()});
      }
    } catch (e) {
      _syncStatsState(); 
    }
  }

  Future<void> _toggleRepost() async {
    final user = _auth.currentUser;
    if (user == null) return;

    setState(() {
      _isReposted = !_isReposted;
      if (_isReposted) _repostCount++; else _repostCount--;
    });

    try {
      final commentRef = _firestore
          .collection('posts')
          .doc(widget.postId)
          .collection('comments')
          .doc(widget.commentId);

      if (_isReposted) {
        await commentRef.update({'repostedBy': FieldValue.arrayUnion([user.uid])});
      } else {
        await commentRef.update({'repostedBy': FieldValue.arrayRemove([user.uid])});
      }
    } catch (e) {
      print("Repost Error: $e"); 
      _syncStatsState();
    }
  }

  Future<void> _shareComment() async {
    final String text = widget.commentData['text'] ?? '';
    final String? mediaUrl = widget.commentData['mediaUrl'];
    final String userName = widget.commentData['userName'] ?? 'User';
    final String shareText = 'Replying to post: "$text" - by $userName';

    try {
      if (mediaUrl != null && mediaUrl.isNotEmpty) {
        final file = await DefaultCacheManager().getSingleFile(mediaUrl);
        await Share.shareXFiles([XFile(file.path)], text: shareText);
      } else {
        await Share.share(shareText);
      }
    } catch (e) {
      debugPrint('Error sharing: $e');
    }
  }

  Future<void> _deleteComment() async {
    final didConfirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Delete Reply"),
        content: Text("Are you sure you want to delete this reply?"),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text("Cancel")),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: Text("Delete")),
        ],
      ),
    ) ?? false;
    if (!didConfirm) return;
    try {
      final writeBatch = _firestore.batch();
      final commentDocRef = _firestore
          .collection('posts')
          .doc(widget.postId)
          .collection('comments')
          .doc(widget.commentId);
      writeBatch.delete(commentDocRef);
      final postDocRef = _firestore.collection('posts').doc(widget.postId);
      writeBatch.update(postDocRef, {
        'commentCount': FieldValue.increment(-1),
      });
      await writeBatch.commit();
      
      if(mounted) OverlayService().showTopNotification(context, "Reply deleted", Icons.delete_outline, (){});
    } catch (e) {
      if (mounted) {
        OverlayService().showTopNotification(context, "Failed to delete", Icons.error, (){}, color: Colors.red);
      }
    }
  }

  Future<void> _showEditDialog() async {
    _editController.text = widget.commentData['text'] ?? '';
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Edit Reply'),
          content: TextField(
            controller: _editController,
            maxLines: 5,
            decoration: InputDecoration(hintText: "Edit your reply..."),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: _submitEdit,
              child: Text('Save'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _submitEdit() async {
    if (_editController.text.isEmpty) return;
    try {
      await _firestore
          .collection('posts')
          .doc(widget.postId)
          .collection('comments')
          .doc(widget.commentId)
          .update({
        'text': _editController.text,
      });
      if(mounted) {
        Navigator.of(context).pop(); 
        OverlayService().showTopNotification(context, "Reply updated", Icons.check_circle, (){});
      }
    } catch (e) {
      if(mounted) {
        OverlayService().showTopNotification(context, "Failed to update", Icons.error, (){}, color: Colors.red);
        Navigator.of(context).pop(); 
      }
    }
  }

  void _navigateToOriginalPost() {
    if (!widget.showPostContext) return; 
    _firestore.collection('posts').doc(widget.postId).get().then((doc) {
      if (doc.exists && mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => PostDetailScreen(
              postId: doc.id,
              initialPostData: doc.data() as Map<String, dynamic>,
            ),
          ),
        );
      }
    });
  }

  void _navigateToUserProfile() {
    final commentUserId = widget.commentData['userId'];
    if (commentUserId == null) return;
    if (commentUserId == _auth.currentUser?.uid) return;
    
    // NEW: Check loop prevention
    if (widget.currentProfileUserId != null && commentUserId == widget.currentProfileUserId) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ProfilePage(userId: commentUserId, includeScaffold: true), 
      ),
    );
  }

  void _openMediaViewer(String url, String? type) {
    final String heroTag = '${widget.heroContextId}_${widget.commentId}_$url';

    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false, 
        barrierColor: Colors.black,
        pageBuilder: (_, __, ___) => ImageViewerScreen(
          imageUrl: url,
          mediaType: type,
          heroTag: heroTag, 
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        }
      ),
    );
  }

  String _formatTimestamp(Timestamp? timestamp) {
    if (timestamp == null) return "just now";
    return timeago.format(timestamp.toDate(), locale: 'en_short');
  }

  @override
  void dispose() {
    _editController.dispose();
    _likeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String? profileImageUrl = widget.commentData['profileImageUrl'];
    
    if (widget.showPostContext) {
      return FutureBuilder<DocumentSnapshot>(
        future: _firestore.collection('posts').doc(widget.postId).get(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return SizedBox.shrink(); 
          if (!snapshot.data!.exists) {
             // Use default isLast behavior if parent doesn't exist (likely standalone)
             return _buildReplyTile(context, isThreaded: false, profileImageUrl: profileImageUrl); 
          }
          final parentData = snapshot.data!.data() as Map<String, dynamic>;
          
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildParentPostSnippet(context, parentData),
              // Force isThreaded true to show connection from parent
              _buildReplyTile(context, isThreaded: true, profileImageUrl: profileImageUrl),
            ],
          );
        },
      );
    }
    return _buildReplyTile(context, isThreaded: true, profileImageUrl: profileImageUrl);
  }

  Widget _buildParentPostSnippet(BuildContext context, Map<String, dynamic> parentData) {
    final theme = Theme.of(context);
    final String parentName = parentData['userName'] ?? 'Unknown';
    final String parentText = parentData['text'] ?? '';

    final int parentIconId = parentData['avatarIconId'] ?? 0;
    final String? parentColorHex = parentData['avatarHex'];
    final Color parentAvatarBg = AvatarHelper.getColor(parentColorHex);
    final String? parentProfileImageUrl = parentData['profileImageUrl'];

    Widget parentAvatarWidget;
    if (parentProfileImageUrl != null && parentProfileImageUrl.isNotEmpty) {
      parentAvatarWidget = CircleAvatar(
        radius: 16, 
        backgroundColor: Colors.transparent,
        backgroundImage: CachedNetworkImageProvider(parentProfileImageUrl),
      );
    } else {
      parentAvatarWidget = CircleAvatar(
        radius: 16, 
        backgroundColor: parentAvatarBg,
        child: Icon(AvatarHelper.getIcon(parentIconId), size: 16, color: Colors.white),
      );
    }

    return InkWell(
      onTap: _navigateToOriginalPost,
      child: Container(
        color: theme.cardColor,
        // Removed bottom padding to make line connect better
        padding: EdgeInsets.fromLTRB(12, 12, 16, 0), 
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 40,
                child: Column(
                  children: [
                    parentAvatarWidget,
                    Expanded(
                      child: Container(
                        width: 2,
                        color: theme.dividerColor,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("$parentName • Original Post", style: theme.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
                    SizedBox(height: 2),
                    Text(
                      parentText, 
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
                      maxLines: 2, 
                      overflow: TextOverflow.ellipsis
                    ),
                    SizedBox(height: 8),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReplyTile(BuildContext context, {required bool isThreaded, String? profileImageUrl}) {
    final data = widget.commentData;
    final theme = Theme.of(context);
    final String userName = data['userName'] ?? 'Anonymous';
    final String text = data['text'] ?? '';
    final Timestamp? timestamp = data['timestamp'] as Timestamp?;
    
    final String? mediaUrl = data['mediaUrl'];
    final String? mediaType = data['mediaType'];

    final int iconId = data['avatarIconId'] ?? 0;
    final String? colorHex = data['avatarHex'];
    final Color avatarBg = AvatarHelper.getColor(colorHex);

    Widget avatarWidget;
    if (profileImageUrl != null && profileImageUrl.isNotEmpty) {
      avatarWidget = CircleAvatar(
        radius: 18, 
        backgroundColor: Colors.transparent,
        backgroundImage: CachedNetworkImageProvider(profileImageUrl), 
      );
    } else {
      avatarWidget = CircleAvatar(
        radius: 18, 
        backgroundColor: avatarBg,
        child: Icon(AvatarHelper.getIcon(iconId), size: 20, color: Colors.white),
      );
    }

    return InkWell(
      onTap: _navigateToOriginalPost,
      child: Container(
        color: theme.cardColor,
        child: IntrinsicHeight(
          child: Row(
            // CHANGED: stretch to make the thread line fill the height
            crossAxisAlignment: CrossAxisAlignment.stretch, 
            children: [
              Container(
                width: 48,
                color: Colors.transparent,
                // Using CustomPaint for precise, connected lines
                child: isThreaded 
                  ? CustomPaint(
                      painter: ThreadLinePainter(
                        context: context,
                        isLast: widget.isLast,
                      ),
                    )
                  : null,
              ),

              // ADDED: Align to top center so the avatar doesn't stretch
              Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0), 
                  child: GestureDetector(
                    onTap: _navigateToUserProfile,
                    child: avatarWidget, 
                  ),
                ),
              ),

              SizedBox(width: 10),

              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0), 
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: _navigateToUserProfile,
                              child: Text(
                                userName,
                                style: theme.textTheme.titleMedium,
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                          ),
                          SizedBox(width: 8),
                          Text(
                            _formatTimestamp(timestamp),
                            style: theme.textTheme.titleSmall,
                          ),
                          if (widget.isOwner)
                            _buildOptionsButton(),
                        ],
                      ),
                      SizedBox(height: 2),
                      if (text.isNotEmpty)
                        Text(text, style: theme.textTheme.bodyLarge),
                        
                      if (mediaUrl != null && mediaUrl.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0, bottom: 8.0),
                          child: GestureDetector(
                            onTap: () => _openMediaViewer(mediaUrl, mediaType),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                height: 150, 
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  color: Colors.black,
                                  border: Border.all(color: theme.dividerColor.withOpacity(0.3)),
                                ),
                                child: mediaType == 'video'
                                    ? Center(child: Icon(Icons.play_circle_fill, color: Colors.white, size: 40))
                                    : Hero(
                                        tag: '${widget.heroContextId}_${widget.commentId}_$mediaUrl',
                                        child: CachedNetworkImage(
                                          imageUrl: mediaUrl,
                                          fit: BoxFit.cover,
                                          placeholder: (context, url) => Center(child: CircularProgressIndicator(strokeWidth: 2)),
                                          errorWidget: (context, url, error) => Icon(Icons.error, color: Colors.grey),
                                        ),
                                      ),
                              ),
                            ),
                          ),
                        ),
                      
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0, bottom: 4.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            _buildActionButton(
                              icon: Icons.repeat,
                              text: _repostCount.toString(),
                              color: _isReposted ? Colors.green : null,
                              onTap: _toggleRepost
                            ),
                            SizedBox(width: 24), 
                            
                            _buildActionButton(
                              icon: _isLiked ? Icons.favorite : Icons.favorite_border,
                              text: _likeCount.toString(),
                              color: _isLiked ? Colors.pink : null,
                              onTap: _toggleLike,
                              animation: _likeAnimation
                            ),
                            SizedBox(width: 24),
                            
                            _buildActionButton(
                              icon: Icons.share_outlined,
                              text: null,
                              color: null,
                              onTap: _shareComment
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String? text,
    required Color? color,
    required VoidCallback onTap,
    Animation<double>? animation
  }) {
    final theme = Theme.of(context);
    final iconColor = color ?? theme.hintColor;
    Widget iconWidget = Icon(icon, size: 18, color: iconColor);
    if (animation != null) {
      iconWidget = ScaleTransition(scale: animation, child: iconWidget);
    }
    return InkWell(
      onTap: onTap,
      child: Row(
        children: [
          iconWidget,
          if (text != null && text != "0")
            Padding(
              padding: const EdgeInsets.only(left: 4.0),
              child: Text(
                text,
                style: TextStyle(color: iconColor, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildOptionsButton() {
    return InkWell(
      onTap: () {
        showModalBottomSheet(
          context: context,
          builder: (context) {
            return Container(
              child: Wrap(
                children: [
                  ListTile(
                    leading: Icon(Icons.edit_outlined),
                    title: Text('Edit Reply'),
                    onTap: () {
                      Navigator.of(context).pop();
                      _showEditDialog();
                    },
                  ),
                  ListTile(
                    leading: Icon(Icons.delete_outline, color: Colors.red),
                    title: Text('Delete Reply', style: TextStyle(color: Colors.red)),
                    onTap: () {
                      Navigator.of(context).pop();
                      _deleteComment();
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
      child: Icon(Icons.more_horiz, color: Theme.of(context).textTheme.titleSmall?.color, size: 18),
    );
  }
}

class ThreadLinePainter extends CustomPainter {
  final BuildContext context;
  final bool isLast;

  ThreadLinePainter({required this.context, required this.isLast});

  @override
  void paint(Canvas canvas, Size size) {
    final theme = Theme.of(context);
    final paint = Paint()
      ..color = theme.dividerColor
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    // ALIGNMENT LOGIC:
    // The parent post avatar (in _buildParentPostSnippet) is located as follows:
    // - Padding left: 12.0
    // - SizedBox width: 40.0 (Centered in this box -> +20.0)
    // - Total center X = 12.0 + 20.0 = 32.0
    //
    // The reply tile starts at 0.0 inside its 48.0 wide container.
    // So the vertical line must be drawn at x = 32.0 to align with the parent.
    final double x = 32.0;
    
    // Avatar Vertical Alignment:
    // Avatar is inside Padding(vertical: 8.0). Radius is 18.0.
    // Center Y = 8.0 + 18.0 = 26.0.
    final double avatarCenterY = 26.0; 
    final double curveRadius = 12.0;

    Path path = Path();
    path.moveTo(x, 0);

    if (isLast) {
      // Draw "L" shape: Vertical down to start of curve, then curve to right
      path.lineTo(x, avatarCenterY - curveRadius);
      path.quadraticBezierTo(x, avatarCenterY, x + curveRadius, avatarCenterY);
      path.lineTo(size.width, avatarCenterY); // Line extends to the avatar (which starts at 48.0)
    } else {
      // Draw "|-" shape: Full vertical line for next sibling, with a branch
      path.lineTo(x, size.height);
      
      // Branch off for the current avatar
      Path branchPath = Path();
      branchPath.moveTo(x, avatarCenterY - curveRadius);
      branchPath.quadraticBezierTo(x, avatarCenterY, x + curveRadius, avatarCenterY);
      branchPath.lineTo(size.width, avatarCenterY);
      
      canvas.drawPath(branchPath, paint);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant ThreadLinePainter oldDelegate) {
    return oldDelegate.isLast != isLast;
  }
}