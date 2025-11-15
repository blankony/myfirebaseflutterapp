// ignore_for_file: prefer_const_constructors
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../screens/post_detail_screen.dart'; 
import '../screens/user_profile_screen.dart'; 
import 'package:timeago/timeago.dart' as timeago; 

final FirebaseAuth _auth = FirebaseAuth.instance;
final FirebaseFirestore _firestore = FirebaseFirestore.instance;

class BlogPostCard extends StatefulWidget {
  // ... (konstruktor tetap sama)
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
  // ... (semua fungsi logika: _toggleLike, _deletePost, _showEditDialog, dll. tetap sama)
  // ...
  final TextEditingController _editController = TextEditingController();
  late bool _isLiked;
  late int _likeCount;

  @override
  void initState() {
    super.initState();
    _syncLikeState();
  }

  @override
  void didUpdateWidget(covariant BlogPostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.postData != oldWidget.postData) {
      _syncLikeState();
    }
  }

  void _syncLikeState() {
    final currentUserUid = _auth.currentUser?.uid;
    final Map<String, dynamic> likes = Map<String, dynamic>.from(widget.postData['likes'] ?? {});
    _likeCount = likes.length;
    _isLiked = currentUserUid != null ? likes.containsKey(currentUserUid) : false;
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
      Map<String, dynamic> likes = Map<String, dynamic>.from(widget.postData['likes'] ?? {});
      if (likes.containsKey(user.uid)) {
        likes.remove(user.uid); 
      } else {
        likes[user.uid] = true; 
      }
      await _firestore.collection('posts').doc(widget.postId).update({'likes': likes});
    } catch (e) {
      setState(() {
        _isLiked = originalIsLiked;
        _likeCount = originalLikeCount;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update like: $e')),
        );
      }
    }
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
    final int retweetCount = widget.postData['retweetCount'] ?? 0;
    final theme = Theme.of(context);

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
                child: Text(userName.isNotEmpty ? userName[0].toUpperCase() : 'A'),
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ### PERUBAHAN DI SINI ###
                  Row(
                    children: [
                      // Nama diberi prioritas
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
                      // Spasi
                      SizedBox(width: 8),
                      // Waktu (handle disembunyikan)
                      Text(
                        _formatTimestamp(timestamp),
                        style: theme.textTheme.titleSmall,
                      ),
                      // Tombol Opsi
                      if (widget.isOwner)
                        _buildOptionsButton(),
                    ],
                  ),
                  // ### AKHIR PERUBAHAN ###
                  
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
                    _buildActionRow(commentCount, retweetCount, _likeCount, _isLiked),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionsButton() {
    // ... (Fungsi ini tidak berubah)
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

  Widget _buildActionRow(int commentCount, int retweetCount, int likeCount, bool isLiked) {
    // ... (Fungsi ini tidak berubah)
    return Padding(
      padding: const EdgeInsets.only(top: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildActionButton(
            context,
            icon: Icons.chat_bubble_outline,
            text: commentCount.toString(),
            onTap: _navigateToDetail,
          ),
          _buildActionButton(
            context,
            icon: Icons.repeat,
            text: retweetCount.toString(),
            onTap: () { /* TODO: Retweet Logic */ },
          ),
          _buildActionButton(
            context,
            icon: isLiked ? Icons.favorite : Icons.favorite_border,
            text: likeCount.toString(),
            color: isLiked ? Colors.pink : null,
            onTap: _toggleLike,
          ),
          _buildActionButton(
            context,
            icon: Icons.share_outlined,
            text: null,
            onTap: () { /* TODO: Share Logic */ },
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow(int commentCount, int likeCount) {
    // ... (Fungsi ini tidak berubah)
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
    // ... (Fungsi ini tidak berubah)
    final theme = Theme.of(context);
    final iconColor = color ?? theme.textTheme.titleSmall?.color;
    return InkWell(
      onTap: onTap,
      child: Row(
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
    );
  }
}