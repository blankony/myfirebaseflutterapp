// ignore_for_file: prefer_const_constructors
import 'dart:io'; 
import 'dart:typed_data'; 
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:share_plus/share_plus.dart'; 
import 'package:shared_preferences/shared_preferences.dart'; 
import '../screens/post_detail_screen.dart'; 
import '../screens/user_profile_screen.dart'; 
import 'package:timeago/timeago.dart' as timeago; 
import '../main.dart';

final FirebaseAuth _auth = FirebaseAuth.instance;
final FirebaseFirestore _firestore = FirebaseFirestore.instance;

class BlogPostCard extends StatefulWidget {
  final String postId;
  final Map<String, dynamic> postData;
  final bool isOwner;
  final bool isClickable;
  final bool isDetailView; 

  const BlogPostCard({
    super.key, 
    required this.postId,
    required this.postData,
    required this.isOwner,
    this.isClickable = true, 
    this.isDetailView = false, 
  });

  @override
  State<BlogPostCard> createState() => _BlogPostCardState();
}

class _BlogPostCardState extends State<BlogPostCard> {
  final TextEditingController _editController = TextEditingController();
  late bool _isLiked;
  late int _likeCount;

  late bool _isReposted;
  late int _repostCount;
  
  Uint8List? _localImageBytes;
  String? _selectedAvatarIconName;
  String? _currentUserId; 

  @override
  void initState() {
    super.initState();
    _syncLikeState();
    _syncRepostState(); 
    _loadLocalAvatar(); 
  }

  Future<void> _loadLocalAvatar() async {
    _currentUserId = _auth.currentUser?.uid;
    if (widget.isOwner && _currentUserId != null) {
      final prefs = await SharedPreferences.getInstance();
      final String? imagePath = prefs.getString('profile_picture_path_$_currentUserId');
      final String? iconName = prefs.getString('profile_avatar_icon_$_currentUserId');
      
      if (mounted) {
        if (imagePath != null) {
          final file = File(imagePath);
          if (await file.exists()) {
            final bytes = await file.readAsBytes();
            setState(() {
              _localImageBytes = bytes;
              _selectedAvatarIconName = null;
            });
          } else {
            await prefs.remove('profile_picture_path_$_currentUserId');
            setState(() {
              _localImageBytes = null;
              _selectedAvatarIconName = iconName; 
            });
          }
        } else if (iconName != null) {
          setState(() {
            _localImageBytes = null;
            _selectedAvatarIconName = iconName;
          });
        } else {
          setState(() {
            _localImageBytes = null;
            _selectedAvatarIconName = null;
          });
        }
      }
    }
  }

  @override
  void didUpdateWidget(covariant BlogPostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.postData != oldWidget.postData) {
      _syncLikeState();
      _syncRepostState(); 
    }
  }

  void _syncLikeState() {
    final currentUserUid = _auth.currentUser?.uid;
    final Map<String, dynamic> likes = Map<String, dynamic>.from(widget.postData['likes'] ?? {});
    _likeCount = likes.length;
    _isLiked = currentUserUid != null ? likes.containsKey(currentUserUid) : false;
  }
  
  void _syncRepostState() {
    final currentUserUid = _auth.currentUser?.uid;
    final List<dynamic> repostedBy = widget.postData['repostedBy'] ?? []; 
    _repostCount = repostedBy.length;
    _isReposted = currentUserUid != null ? repostedBy.contains(currentUserUid) : false;
  }

  Future<void> _toggleLike() async {
    final user = _auth.currentUser;
    if (user == null) return;
    
    final bool originalIsLiked = _isLiked;
    final int originalLikeCount = _likeCount;
    setState(() {
      _isLiked = !_isLiked;
      if (_isLiked) {
        _likeCount++;
      } else {
        _likeCount--;
      }
    });

    try {
      final postDocRef = _firestore.collection('posts').doc(widget.postId);
      final postDoc = await postDocRef.get();
      Map<String, dynamic> likes = Map<String, dynamic>.from(postDoc.data()?['likes'] ?? {});
      
      final postOwnerId = widget.postData['userId'];
      final bool isLiking = !likes.containsKey(user.uid);

      if (isLiking) {
        likes[user.uid] = true; 
        
        if (user.uid != postOwnerId) {
          _sendNotification(
            ownerId: postOwnerId,
            senderId: user.uid,
            type: 'like',
            postId: widget.postId,
          );
        }

      } else {
        likes.remove(user.uid); 
      }
      
      await postDocRef.update({'likes': likes});

    } catch (e) {
      setState(() {
        _isLiked = originalIsLiked;
        _likeCount = originalLikeCount;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update like: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _toggleRepost() async {
    final user = _auth.currentUser;
    if (user == null) return;
    
    final bool originalIsReposted = _isReposted;
    final int originalRepostCount = _repostCount;
    setState(() {
      _isReposted = !_isReposted;
      if (_isReposted) {
        _repostCount++;
      } else {
        _repostCount--;
      }
    });

    try {
      final postDocRef = _firestore.collection('posts').doc(widget.postId);
      final postDoc = await postDocRef.get();
      List<dynamic> repostedBy = List<dynamic>.from(postDoc.data()?['repostedBy'] ?? []);
      
      final postOwnerId = widget.postData['userId'];
      final bool isReposting = !repostedBy.contains(user.uid);

      if (isReposting) {
        repostedBy.add(user.uid);
        
        if (user.uid != postOwnerId) {
          _sendNotification(
            ownerId: postOwnerId,
            senderId: user.uid,
            type: 'repost',
            postId: widget.postId,
          );
        }
      
      } else {
        repostedBy.remove(user.uid);
      }
      
      await postDocRef.update({'repostedBy': repostedBy});

    } catch (e) {
      setState(() {
        _isReposted = originalIsReposted;
        _repostCount = originalRepostCount;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to repost: ${e.toString()}')),
        );
      }
    }
  }

  void _sendNotification({
    required String ownerId,
    required String senderId,
    required String type,
    required String postId,
  }) {
    String postTextSnippet = (widget.postData['text'] as String);
    if (postTextSnippet.length > 50) {
      postTextSnippet = postTextSnippet.substring(0, 50) + '...';
    }

    _firestore
        .collection('users')
        .doc(ownerId)
        .collection('notifications')
        .add({
      'type': type,
      'senderId': senderId,
      'postId': postId,
      'postTextSnippet': postTextSnippet,
      'timestamp': FieldValue.serverTimestamp(),
      'isRead': false,
    });
  }

  Future<void> _deletePost() async {
    final didConfirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Delete Post"),
        content: Text("Are you sure you want to delete this post?"),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text("Cancel")),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: Text("Delete", style: TextStyle(color: Colors.red))),
        ],
      ),
    ) ?? false;
    if (didConfirm) {
      try {
        await _firestore.collection('posts').doc(widget.postId).delete();
      } catch (e) {
        if(mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete post: $e'))
          );
        }
      }
    }
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
    try {
      await _firestore.collection('posts').doc(widget.postId).update({
        'text': _editController.text,
      });
      if(mounted) Navigator.of(context).pop(); 
    } catch (e) {
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update post: $e'))
        );
        Navigator.of(context).pop(); 
      }
    }
  }

  void _navigateToDetail() {
    if (!widget.isClickable) return; 
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => PostDetailScreen(
          postId: widget.postId,
          initialPostData: widget.postData, 
        ),
      ),
    );
  }

  void _navigateToUserProfile() {
    final postUserId = widget.postData['userId'];
    if (postUserId == null) return;
    if (postUserId == _auth.currentUser?.uid && !widget.isClickable) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => UserProfileScreen(userId: postUserId),
      ),
    );
  }

  String _formatTimestamp(Timestamp? timestamp) {
    if (timestamp == null) return "just now";
    return timeago.format(timestamp.toDate(), locale: 'en_short');
  }

  Future<void> _sharePost() async {
    final String text = widget.postData['text'] ?? 'Check out this post!';
    final String userName = widget.postData['userName'] ?? 'A user';
    
    final String shareContent = '"$text"\n- $userName';

    try {
      await Share.share(
        shareContent,
        subject: 'Post by $userName', 
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to share: $e')),
      );
    }
  }

  IconData _getIconDataFromString(String? iconName) {
    switch (iconName) {
      case 'face':
        return Icons.face;
      case 'rocket':
        return Icons.rocket_launch;
      case 'pet':
        return Icons.pets;
      default:
        return Icons.person; 
    }
  }

  @override
  void dispose() {
    _editController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String userName = widget.postData['userName'] ?? 'Anonymous User';
    final String text = widget.postData['text'] ?? '';
    final Timestamp? timestamp = widget.postData['timestamp'] as Timestamp?;
    
    final int commentCount = widget.postData['commentCount'] ?? 0;
    final theme = Theme.of(context);

    final bool showCustomAvatar = widget.isOwner && (_localImageBytes != null || _selectedAvatarIconName != null);

    return InkWell( 
      onTap: _navigateToDetail, 
      child: Container(
        color: theme.cardColor, 
        padding: const EdgeInsets.all(12.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: _navigateToUserProfile,
              child: CircleAvatar(
                radius: 24,
                backgroundImage: (widget.isOwner && _localImageBytes != null) 
                  ? MemoryImage(_localImageBytes!) 
                  : null,
                child: (showCustomAvatar && _localImageBytes == null)
                  ? Icon(
                      _getIconDataFromString(_selectedAvatarIconName),
                      size: 26,
                      color: TwitterTheme.blue,
                    )
                  : (showCustomAvatar == false) 
                    ? Text(userName.isNotEmpty ? userName[0].toUpperCase() : 'A')
                    : null, 
              ),
            ),
            SizedBox(width: 12),
            Expanded(
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
                  
                  SizedBox(height: 4),
                  Text(
                    text,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontSize: widget.isDetailView ? 18 : 15, 
                    ),
                    maxLines: widget.isDetailView ? null : 10,
                    overflow: widget.isDetailView ? null : TextOverflow.ellipsis,
                  ),
                  
                  if (widget.isDetailView)
                    _buildStatsRow(commentCount, _likeCount),
                  
                  if (!widget.isDetailView)
                    _buildActionRow(commentCount, _repostCount, _isReposted, _likeCount, _isLiked),
                ],
              ),
            ),
          ],
        ),
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
                    title: Text('Edit Post'),
                    onTap: () {
                      Navigator.of(context).pop();
                      _showEditDialog();
                    },
                  ),
                  ListTile(
                    leading: Icon(Icons.delete_outline, color: Colors.red),
                    title: Text('Delete Post', style: TextStyle(color: Colors.red)),
                    onTap: () {
                      Navigator.of(context).pop();
                      _deletePost();
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
      child: Icon(Icons.more_horiz, color: Theme.of(context).textTheme.titleSmall?.color, size: 20),
    );
  }

  Widget _buildActionRow(int commentCount, int repostCount, bool isReposted, int likeCount, bool isLiked) {
    return Padding(
      padding: const EdgeInsets.only(top: 12.0),
      child: Row(
        children: [
          Expanded(
            child: _buildActionButton(
              context,
              icon: Icons.chat_bubble_outline,
              text: commentCount.toString(),
              onTap: _navigateToDetail,
            ),
          ),
          Expanded(
            child: _buildActionButton(
              context,
              icon: Icons.repeat,
              text: repostCount.toString(),
              color: isReposted ? Colors.green : null, 
              onTap: _toggleRepost, 
            ),
          ),
          Expanded(
            child: _buildActionButton(
              context,
              icon: isLiked ? Icons.favorite : Icons.favorite_border,
              text: likeCount.toString(),
              color: isLiked ? Colors.pink : null,
              onTap: _toggleLike,
            ),
          ),
          Expanded(
            child: _buildActionButton(
              context,
              icon: Icons.share_outlined,
              text: null,
              onTap: _sharePost,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow(int commentCount, int likeCount) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12.0, bottom: 12.0),
      child: Row(
        children: [
          Text(likeCount.toString(), style: theme.textTheme.titleMedium),
          SizedBox(width: 4),
          Text("Likes", style: theme.textTheme.titleSmall),
          SizedBox(width: 16),
          Text(commentCount.toString(), style: theme.textTheme.titleMedium),
          SizedBox(width: 4),
          Text("Replies", style: theme.textTheme.titleSmall),
        ],
      ),
    );
  }

  Widget _buildActionButton(BuildContext context, {required IconData icon, String? text, required VoidCallback onTap, Color? color}) {
    final theme = Theme.of(context);
    final iconColor = color ?? theme.textTheme.titleSmall?.color;
    return InkWell(
      onTap: onTap,
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: iconColor, size: 20),
            if (text != null && text != "0")
              Padding(
                padding: const EdgeInsets.only(left: 4.0),
                child: Text(
                  text,
                  style: theme.textTheme.titleSmall?.copyWith(color: iconColor),
                ),
              ),
          ],
        ),
      ),
    );
  }
}