// ignore_for_file: prefer_const_constructors
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../screens/post_detail_screen.dart'; 
import '../screens/user_profile_screen.dart'; 
import 'package:timeago/timeago.dart' as timeago; 

final FirebaseAuth _auth = FirebaseAuth.instance;
final FirebaseFirestore _firestore = FirebaseFirestore.instance;

class CommentTile extends StatefulWidget {
  // ... (konstruktor tetap sama)
  final String commentId;
  final Map<String, dynamic> commentData;
  final String postId; 
  final bool isOwner;
  final bool showPostContext; 

  const CommentTile({
    super.key,
    required this.commentId,
    required this.commentData,
    required this.postId,
    required this.isOwner,
    this.showPostContext = false, 
  });

  @override
  State<CommentTile> createState() => _CommentTileState();
}

class _CommentTileState extends State<CommentTile> {
  // ... (semua fungsi logika: _deleteComment, _showEditDialog, _submitEdit, dll. tetap sama)
  // ...
  final TextEditingController _editController = TextEditingController();

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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete reply: $e')),
        );
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
      if(mounted) Navigator.of(context).pop(); 
    } catch (e) {
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update reply: $e'))
        );
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
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => UserProfileScreen(userId: commentUserId),
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
    final data = widget.commentData;
    final theme = Theme.of(context);

    final String userName = data['userName'] ?? 'Anonymous';
    final String text = data['text'] ?? '';
    final Timestamp? timestamp = data['timestamp'] as Timestamp?;

    return InkWell(
      onTap: _navigateToOriginalPost, 
      child: Container(
        color: theme.cardColor,
        padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.showPostContext)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0, left: 36.0), 
                child: Text(
                  "Replying to post", 
                  style: theme.textTheme.titleSmall
                ),
              ),
            
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: _navigateToUserProfile,
                  child: CircleAvatar(
                    radius: 24, 
                    child: Text(userName.isNotEmpty ? userName[0] : 'A'),
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
                      Text(text, style: theme.textTheme.bodyLarge),
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
      child: Icon(Icons.more_horiz, color: Theme.of(context).textTheme.titleSmall?.color, size: 20),
    );
  }
}