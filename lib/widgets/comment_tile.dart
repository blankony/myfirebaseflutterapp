// ignore_for_file: prefer_const_constructors
import 'dart:io';
import 'dart:typed_data'; 
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  Uint8List? _localImageBytes;
  String? _selectedAvatarIconName;
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
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

  IconData _getIconDataFromString(String? iconName) {
    switch (iconName) {
      case 'face': return Icons.face;
      case 'rocket': return Icons.rocket_launch;
      case 'pet': return Icons.pets;
      default: return Icons.person; 
    }
  }

  @override
  void dispose() {
    _editController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // If showing context (Profile Page), render Parent Post + Reply
    if (widget.showPostContext) {
      return FutureBuilder<DocumentSnapshot>(
        future: _firestore.collection('posts').doc(widget.postId).get(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return SizedBox.shrink(); // Loading or error
          
          // If parent post is deleted, just show the reply normally
          if (!snapshot.data!.exists) {
             return _buildReplyTile(context, isThreaded: false); 
          }

          final parentData = snapshot.data!.data() as Map<String, dynamic>;
          
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Parent Post Snippet
              _buildParentPostSnippet(context, parentData),
              // 2. The Reply (Threaded)
              _buildReplyTile(context, isThreaded: true),
            ],
          );
        },
      );
    }

    // Standard View (Post Detail Page)
    return _buildReplyTile(context, isThreaded: true); // Threaded look for consistency
  }

  // --- WIDGET: Parent Post Snippet (The "Original Post") ---
  Widget _buildParentPostSnippet(BuildContext context, Map<String, dynamic> parentData) {
    final theme = Theme.of(context);
    final String parentName = parentData['userName'] ?? 'Unknown';
    final String parentText = parentData['text'] ?? '';
    final String parentUserId = parentData['userId'];

    return InkWell(
      onTap: _navigateToOriginalPost,
      child: Container(
        color: theme.cardColor,
        padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Parent Avatar Column
              Column(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: theme.dividerColor,
                    child: Text(parentName.isNotEmpty ? parentName[0].toUpperCase() : '?', style: TextStyle(fontSize: 12, color: theme.cardColor)),
                  ),
                  // Vertical Line (Thread connector)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: theme.dividerColor,
                    ),
                  ),
                ],
              ),
              SizedBox(width: 12),
              // Parent Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(parentName, style: theme.textTheme.titleMedium?.copyWith(fontSize: 14, color: theme.hintColor)),
                        SizedBox(width: 4),
                        Text("• Original Post", style: theme.textTheme.bodySmall?.copyWith(fontSize: 10, fontStyle: FontStyle.italic)),
                      ],
                    ),
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

  // --- WIDGET: The Actual Reply ---
  Widget _buildReplyTile(BuildContext context, {required bool isThreaded}) {
    final data = widget.commentData;
    final theme = Theme.of(context);
    final String userName = data['userName'] ?? 'Anonymous';
    final String text = data['text'] ?? '';
    final Timestamp? timestamp = data['timestamp'] as Timestamp?;
    final bool showCustomAvatar = widget.isOwner && (_localImageBytes != null || _selectedAvatarIconName != null);

    return InkWell(
      onTap: _navigateToOriginalPost,
      child: Container(
        color: theme.cardColor,
        padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Tree Visuals
              if (isThreaded)
                Container(
                  width: 36, // Adjust based on parent avatar size
                  alignment: Alignment.topCenter,
                  child: showCustomAvatar && _localImageBytes == null
                    ? CircleAvatar(
                        radius: 18,
                        backgroundColor: theme.cardColor,
                        child: Icon(_getIconDataFromString(_selectedAvatarIconName), size: 20, color: TwitterTheme.blue),
                      )
                    : CircleAvatar(
                        radius: 18,
                        backgroundImage: (widget.isOwner && _localImageBytes != null) 
                          ? MemoryImage(_localImageBytes!) 
                          : null,
                        child: (!showCustomAvatar) 
                          ? Text(userName.isNotEmpty ? userName[0] : 'A') 
                          : null,
                      ),
                )
              else 
                // Fallback simple avatar if not threaded
                GestureDetector(
                  onTap: _navigateToUserProfile,
                  child: CircleAvatar(radius: 18, child: Text(userName[0])),
                ),

              SizedBox(width: 12),
              
              // Reply Content
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
                    SizedBox(height: 2),
                    Text(text, style: theme.textTheme.bodyLarge),
                  ],
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
      child: Icon(Icons.more_horiz, color: Theme.of(context).textTheme.titleSmall?.color, size: 20),
    );
  }
}