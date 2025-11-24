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
    if (widget.showPostContext) {
      return FutureBuilder<DocumentSnapshot>(
        future: _firestore.collection('posts').doc(widget.postId).get(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return SizedBox.shrink(); 
          if (!snapshot.data!.exists) {
             return _buildReplyTile(context); 
          }
          final parentData = snapshot.data!.data() as Map<String, dynamic>;
          
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildParentPostSnippet(context, parentData),
              _buildReplyTile(context),
            ],
          );
        },
      );
    }
    return _buildReplyTile(context);
  }

  Widget _buildParentPostSnippet(BuildContext context, Map<String, dynamic> parentData) {
    final theme = Theme.of(context);
    final String parentName = parentData['userName'] ?? 'Unknown';
    final String parentText = parentData['text'] ?? '';

    return InkWell(
      onTap: _navigateToOriginalPost,
      child: Container(
        color: theme.cardColor,
        padding: EdgeInsets.fromLTRB(12, 12, 16, 0), // Adjusted padding for alignment
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Parent Trunk Column
              SizedBox(
                width: 40,
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 16, // Smaller avatar for parent context
                      backgroundColor: theme.dividerColor,
                      child: Text(parentName.isNotEmpty ? parentName[0].toUpperCase() : '?', style: TextStyle(fontSize: 12, color: theme.cardColor)),
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

  // ### FIXED: L-Shape Visual Implementation ###
  Widget _buildReplyTile(BuildContext context) {
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
        // We remove standard padding here because we structure the tree manually
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. THE TREE STRUCTURE (L-Shape)
              Container(
                width: 48, // Fixed width for the tree visual area
                color: Colors.transparent,
                child: Stack(
                  children: [
                    // Trunk (Vertical Line)
                    Positioned(
                      top: 0,
                      bottom: 0,
                      left: 20, // Center of the 40px area
                      child: Container(
                        width: 2,
                        color: theme.dividerColor, // The tree line color
                      ),
                    ),
                    // Branch (Horizontal Line)
                    Positioned(
                      top: 24, // Align with center of Avatar
                      left: 20, // Start from Trunk
                      width: 16, // Reach to Avatar
                      child: Container(
                        height: 2,
                        color: theme.dividerColor,
                      ),
                    ),
                  ],
                ),
              ),

              // 2. AVATAR
              Padding(
                padding: const EdgeInsets.only(top: 8.0, bottom: 8.0),
                child: GestureDetector(
                  onTap: _navigateToUserProfile,
                  child: CircleAvatar(
                    radius: 18, 
                    backgroundImage: (widget.isOwner && _localImageBytes != null) 
                      ? MemoryImage(_localImageBytes!) 
                      : null,
                    child: (showCustomAvatar && _localImageBytes == null)
                      ? Icon(
                          _getIconDataFromString(_selectedAvatarIconName),
                          size: 20,
                          color: TwitterTheme.blue,
                        )
                      : (showCustomAvatar == false) 
                        ? Text(userName.isNotEmpty ? userName[0] : 'A', style: TextStyle(fontSize: 14))
                        : null, 
                  ),
                ),
              ),

              SizedBox(width: 10),

              // 3. CONTENT
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