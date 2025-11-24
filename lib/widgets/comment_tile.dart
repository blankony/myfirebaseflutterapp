// ignore_for_file: prefer_const_constructors
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../screens/post_detail_screen.dart'; 
import '../screens/user_profile_screen.dart'; 
import 'package:timeago/timeago.dart' as timeago; 
import '../main.dart';

final FirebaseAuth _auth = FirebaseAuth.instance;
final FirebaseFirestore _firestore = FirebaseFirestore.instance;

class CommentTile extends StatefulWidget {
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
    if (widget.showPostContext) {
      return FutureBuilder<DocumentSnapshot>(
        future: _firestore.collection('posts').doc(widget.postId).get(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return SizedBox.shrink(); 
          if (!snapshot.data!.exists) {
             return _buildReplyTile(context, isThreaded: false); 
          }
          final parentData = snapshot.data!.data() as Map<String, dynamic>;
          
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildParentPostSnippet(context, parentData),
              _buildReplyTile(context, isThreaded: true),
            ],
          );
        },
      );
    }
    return _buildReplyTile(context, isThreaded: true);
  }

  Widget _buildParentPostSnippet(BuildContext context, Map<String, dynamic> parentData) {
    final theme = Theme.of(context);
    final String parentName = parentData['userName'] ?? 'Unknown';
    final String parentText = parentData['text'] ?? '';

    final int parentIconId = parentData['avatarIconId'] ?? 0;
    final String? parentColorHex = parentData['avatarHex'];
    final Color parentAvatarBg = AvatarHelper.getColor(parentColorHex);

    return InkWell(
      onTap: _navigateToOriginalPost,
      child: Container(
        color: theme.cardColor,
        padding: EdgeInsets.fromLTRB(12, 12, 16, 0), 
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 40,
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 16, 
                      backgroundColor: parentAvatarBg,
                      child: Icon(AvatarHelper.getIcon(parentIconId), size: 16, color: Colors.white),
                    ),
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

  Widget _buildReplyTile(BuildContext context, {required bool isThreaded}) {
    final data = widget.commentData;
    final theme = Theme.of(context);
    final String userName = data['userName'] ?? 'Anonymous';
    final String text = data['text'] ?? '';
    final Timestamp? timestamp = data['timestamp'] as Timestamp?;

    final int iconId = data['avatarIconId'] ?? 0;
    final String? colorHex = data['avatarHex'];
    final Color avatarBg = AvatarHelper.getColor(colorHex);

    return InkWell(
      onTap: _navigateToOriginalPost,
      child: Container(
        color: theme.cardColor,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Tree Structure
              Container(
                width: 48,
                color: Colors.transparent,
                child: Stack(
                  children: [
                    Positioned(
                      top: 0,
                      bottom: 0,
                      left: 20, 
                      child: Container(
                        width: 2,
                        color: theme.dividerColor, 
                      ),
                    ),
                    Positioned(
                      top: 24, 
                      left: 20, 
                      width: 16, 
                      child: Container(
                        height: 2,
                        color: theme.dividerColor,
                      ),
                    ),
                  ],
                ),
              ),

              // Avatar
              Padding(
                padding: const EdgeInsets.only(top: 8.0, bottom: 8.0),
                child: GestureDetector(
                  onTap: _navigateToUserProfile,
                  child: CircleAvatar(
                    radius: 18, 
                    backgroundColor: avatarBg,
                    child: Icon(AvatarHelper.getIcon(iconId), size: 20, color: Colors.white),
                  ),
                ),
              ),

              SizedBox(width: 10),

              // Content
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
                      Text(text, style: theme.textTheme.bodyLarge),
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