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
import 'package:path_provider/path_provider.dart';
import 'dart:io';

final FirebaseAuth _auth = FirebaseAuth.instance;
final FirebaseFirestore _firestore = FirebaseFirestore.instance;

class _VideoPlayerWidget extends StatefulWidget {
  final String videoUrl;
  const _VideoPlayerWidget({required this.videoUrl});

  @override
  State<_VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<_VideoPlayerWidget> {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      height: 200,
      width: double.infinity,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.play_circle_fill, color: Colors.white, size: 50),
            SizedBox(height: 8),
            Text("Tap to play video", style: TextStyle(color: Colors.white)),
          ],
        ),
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
  final String heroContextId; // PARAMETER BARU

  const _PostMediaPreview({
    required this.mediaUrl,
    this.mediaType,
    required this.text,
    required this.postData, 
    required this.postId, 
    required this.heroContextId, // WAJIB DIISI
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
     // BUAT TAG UNIK DENGAN CONTEXT ID
     // Format: contextId_postId_url
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
          heroTag: heroTag, // KIRIM TAG UNIK INI
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
      // GUNAKAN TAG YANG SAMA DI SINI
      final String heroTag = '${heroContextId}_${postId}_$mediaUrl';

      return AspectRatio( 
        aspectRatio: 4 / 3,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: GestureDetector(
            onTap: () => _navigateToViewer(context, type: mediaType),
            child: mediaType == 'video' 
                ? _VideoPlayerWidget(videoUrl: mediaUrl)
                : Hero( 
                    tag: heroTag,
                    transitionOnUserGestures: true,
                    child: CachedNetworkImage( 
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
  final String heroContextId; // PARAMETER BARU DI SINI

  const BlogPostCard({
    super.key,
    required this.postId,
    required this.postData,
    required this.isOwner,
    this.isClickable = true,
    this.isDetailView = false,
    this.heroContextId = 'feed', // Default value agar tidak error di tempat lain
  });

  @override
  State<BlogPostCard> createState() => _BlogPostCardState();
}

class _BlogPostCardState extends State<BlogPostCard> with TickerProviderStateMixin {
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

  @override
  void initState() {
    super.initState();
    _syncState();
    
    _likeController = AnimationController(duration: const Duration(milliseconds: 200), vsync: this);
    _likeAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(CurvedAnimation(parent: _likeController, curve: Curves.easeInOut));

    _shareController = AnimationController(duration: const Duration(milliseconds: 200), vsync: this);
    _shareAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(CurvedAnimation(parent: _shareController, curve: Curves.easeInOut));

    _repostController = AnimationController(duration: const Duration(milliseconds: 200), vsync: this);
    _repostAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(CurvedAnimation(parent: _repostController, curve: Curves.easeInOut));
  }

  @override
  void didUpdateWidget(covariant BlogPostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.postData != widget.postData) {
      _syncState();
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
      if (_isLiked) _likeCount++; else _likeCount--;
    }); 

    try {
      if (_isLiked) {
        await docRef.update({'likes.${currentUser.uid}': true});
        if (widget.postData['userId'] != currentUser.uid) {
          _firestore.collection('users').doc(widget.postData['userId']).collection('notifications').add({
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
      }
    } catch (e) {
      _syncState(); // Revert on error
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
      if (_isReposted) _repostCount++; else _repostCount--;
    });

    try {
      if (_isReposted) {
        await docRef.update({'repostedBy': FieldValue.arrayUnion([currentUser.uid])});
        if (widget.postData['userId'] != currentUser.uid) {
          _firestore.collection('users').doc(widget.postData['userId']).collection('notifications').add({
            'type': 'repost',
            'senderId': currentUser.uid,
            'postId': widget.postId,
            'postTextSnippet': widget.postData['text'],
            'timestamp': FieldValue.serverTimestamp(),
            'isRead': false,
          });
        }
      } else {
        await docRef.update({'repostedBy': FieldValue.arrayRemove([currentUser.uid])});
      }
    } catch (e) {
      _syncState();
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
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Post deleted")));
      } catch (e) {
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to delete: $e")));
      }
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
        Navigator.of(context).pop(); 
      }
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
          Text(
            "Uploading media...",
            style: TextStyle(color: TwitterTheme.blue, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 4),
          LinearProgressIndicator(
            value: null, 
            backgroundColor: Theme.of(context).dividerColor,
            valueColor: AlwaysStoppedAnimation<Color>(TwitterTheme.blue),
          ),
          SizedBox(height: 4),
          Text(
            'Processing...',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = widget.postData['text'] ?? '';
    final mediaUrl = widget.postData['mediaUrl'];
    final mediaType = widget.postData['mediaType'];
    final isUploading = widget.postData['isUploading'] == true;
    final uploadProgress = widget.postData['uploadProgress'] as double? ?? 0.0;
    final uploadFailed = widget.postData['uploadFailed'] == true;
    final int commentCount = widget.postData['commentCount'] ?? 0;

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
        padding: const EdgeInsets.all(12.0),
        child: Row(
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
                        heroContextId: widget.heroContextId, // PASSING PARAMETER
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
      ),
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
            backgroundImage: profileImageUrl != null
                ? CachedNetworkImageProvider(profileImageUrl)
                : null,
            child: profileImageUrl == null
                ? Icon(AvatarHelper.getIcon(iconId), size: 26, color: Colors.white)
                : null,
          ),
        );
      },
    );
  }

  Widget _buildPostHeader(BuildContext context) {
    final timeAgo = _formatTimestamp(widget.postData['timestamp'] as Timestamp?);
    final String userName = widget.postData['userName'] ?? 'User';
    final String handle = "@${widget.postData['userEmail']?.split('@')[0] ?? 'user'}";

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                userName,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Row(
              children: [
                SizedBox(width: 4),
                Text("· $timeAgo", style: TextStyle(color: Theme.of(context).hintColor, fontSize: 12)),
                if (widget.isOwner)
                  _buildOptionsButton(),
              ],
            ),
          ],
        ),
        Text(
          handle,
          style: TextStyle(color: Theme.of(context).hintColor, fontSize: 13),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildOptionsButton() {
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_horiz, color: Theme.of(context).hintColor, size: 18),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 4,
      color: Theme.of(context).cardColor,
      onSelected: (value) {
        if (value == 'edit') {
          _showEditDialog();
        } else if (value == 'delete') {
          _deletePost();
        } else if (value == 'pin') {
           if (mounted) {
             ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Post pinned to profile (Demo)")));
           }
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'edit',
          child: Row(
            children: [
              Icon(Icons.edit_outlined, size: 20, color: Theme.of(context).textTheme.bodyLarge?.color),
              SizedBox(width: 12),
              Text("Edit Post"),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'pin',
          child: Row(
            children: [
              Icon(Icons.push_pin_outlined, size: 20, color: Theme.of(context).textTheme.bodyLarge?.color),
              SizedBox(width: 12),
              Text("Pin to Profile"),
            ],
          ),
        ),
        PopupMenuDivider(),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline, size: 20, color: Colors.red),
              SizedBox(width: 12),
              Text("Delete Post", style: TextStyle(color: Colors.red)),
            ],
          ),
        ),
      ],
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
          _buildActionButton(Icons.share_outlined, 'Share', _isSharing ? TwitterTheme.blue : null, _sharePost, _shareAnimation),
        ],
      ),
    );
  }

  Widget _buildActionButton(IconData icon, String? text, Color? color, VoidCallback onTap, [Animation<double>? animation]) {
    final theme = Theme.of(context);
    final iconColor = color ?? theme.textTheme.bodySmall?.color ?? Colors.grey;
    
    Widget iconWidget = Icon(icon, size: 20, color: iconColor);
    if (animation != null) {
      iconWidget = ScaleTransition(scale: animation, child: iconWidget);
    }

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
        child: Row(
          children: [
            iconWidget, 
            if (text != null && text != "0" && text.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 6.0),
                child: Text(text, style: TextStyle(color: iconColor, fontSize: 13)),
              ),
          ],
        ),
      ),
    );
  }
}