// ignore_for_file: prefer_const_constructors
import 'dart:async'; 
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart'; 
import 'package:cached_network_image/cached_network_image.dart'; 
import '../widgets/blog_post_card.dart'; 
import '../widgets/comment_tile.dart'; 
import '../services/prediction_service.dart'; 
import '../services/cloudinary_service.dart'; 
import '../main.dart'; 

final FirebaseAuth _auth = FirebaseAuth.instance;
final FirebaseFirestore _firestore = FirebaseFirestore.instance;
final CloudinaryService _cloudinaryService = CloudinaryService(); 

class PostDetailScreen extends StatefulWidget {
  final String postId;
  final Map<String, dynamic>? initialPostData;
  // 1. TAMBAHKAN PARAMETER INI
  final String heroContextId; 

  const PostDetailScreen({
    super.key,
    required this.postId,
    this.initialPostData,
    this.heroContextId = 'feed', // Default ke 'feed' jika tidak diisi
  });

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final TextEditingController _commentController = TextEditingController();
  final PredictionService _predictionService = PredictionService();
  final User? _currentUser = _auth.currentUser;

  String? _predictedText;
  Timer? _debounce;
  bool _isSending = false;
  File? _selectedMediaFile;
  String? _mediaType;

  void _onCommentChanged(String text) {
    setState(() {
      _predictedText = null;
    });

    if (_debounce?.isActive ?? false) _debounce!.cancel();

    _debounce = Timer(const Duration(milliseconds: 800), () async {
      if (text.trim().isEmpty) return;
      
      final suggestion = await _predictionService.getCompletion(text, 'comment');
      if (mounted && suggestion != null && suggestion.isNotEmpty) {
        setState(() {
          _predictedText = suggestion;
        });
      }
    });
  }

  void _acceptPrediction() {
    if (_predictedText != null) {
      final currentText = _commentController.text;
      final separator = currentText.endsWith(' ') ? '' : ' ';
      final newText = "$currentText$separator$_predictedText ";
      
      _commentController.text = newText;
      _commentController.selection = TextSelection.fromPosition(
        TextPosition(offset: newText.length),
      );
      
      setState(() {
        _predictedText = null;
      });
    }
  }

  Future<void> _pickMedia(ImageSource source, {bool isVideo = false}) async {
    final picker = ImagePicker();
    XFile? pickedFile;
    
    try {
      if (isVideo) {
        pickedFile = await picker.pickVideo(source: source);
        if (pickedFile != null) {
          setState(() {
            _selectedMediaFile = File(pickedFile!.path);
            _mediaType = 'video';
          });
        }
      } else {
        pickedFile = await picker.pickImage(source: source, imageQuality: 70);
        if (pickedFile != null) {
          setState(() {
            _selectedMediaFile = File(pickedFile!.path);
            _mediaType = 'image';
          });
        }
      }
    } catch (e) {
      debugPrint("Error picking media: $e");
    }
  }

  void _clearMedia() {
    setState(() {
      _selectedMediaFile = null;
      _mediaType = null;
    });
  }

  Future<void> _postComment() async {
    if ((_commentController.text.trim().isEmpty && _selectedMediaFile == null) || _currentUser == null || _isSending) {
      return;
    }

    setState(() { _isSending = true; });

    String? mediaUrl;
    if (_selectedMediaFile != null) {
      mediaUrl = await _cloudinaryService.uploadMedia(_selectedMediaFile!);
      if (mediaUrl == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to upload media. Please try again.')));
          setState(() { _isSending = false; });
        }
        return;
      }
    }

    String userName = "Anonymous";
    String userEmail = "anonymous@mail.com";
    int iconId = 0;
    String hex = '';
    String? profileImageUrl;

    try {
      final userDoc = await _firestore.collection('users').doc(_currentUser!.uid).get();
      if (userDoc.exists) {
        final data = userDoc.data();
        userName = data?['name'] ?? userName;
        userEmail = data?['email'] ?? userEmail;
        iconId = data?['avatarIconId'] ?? 0;
        hex = data?['avatarHex'] ?? '';
        profileImageUrl = data?['profileImageUrl'];
      }
    } catch (e) {}

    final commentData = {
      'text': _commentController.text.trim(),
      'mediaUrl': mediaUrl,
      'mediaType': _mediaType,
      'timestamp': FieldValue.serverTimestamp(),
      'userId': _currentUser!.uid,
      'originalPostId': widget.postId,
      'userName': userName,
      'userEmail': userEmail,
      'avatarIconId': iconId,
      'avatarHex': hex,
      'profileImageUrl': profileImageUrl,
    };

    try {
      final writeBatch = _firestore.batch();
      final commentDocRef = _firestore
          .collection('posts')
          .doc(widget.postId)
          .collection('comments')
          .doc(); 
      writeBatch.set(commentDocRef, commentData);
      final postDocRef = _firestore.collection('posts').doc(widget.postId);
      writeBatch.update(postDocRef, {
        'commentCount': FieldValue.increment(1),
      });

      await writeBatch.commit();

      final String? postOwnerId = widget.initialPostData?['userId'];
      if (postOwnerId != null && postOwnerId != _currentUser!.uid) {
        String commentSnippet = commentData['text'] as String;
        if (commentSnippet.isEmpty) commentSnippet = "Sent a ${_mediaType ?? 'media'} attachment";
        if (commentSnippet.length > 50) {
          commentSnippet = commentSnippet.substring(0, 50) + '...';
        }
        
        _firestore
            .collection('users')
            .doc(postOwnerId) 
            .collection('notifications')
            .add({
          'type': 'comment', 
          'senderId': _currentUser!.uid,
          'postId': widget.postId,
          'postTextSnippet': commentSnippet, 
          'timestamp': FieldValue.serverTimestamp(),
          'isRead': false,
        });
      }

      if (mounted) {
        _commentController.clear();
        _clearMedia();
        setState(() { 
          _predictedText = null; 
          _isSending = false; 
        }); 
        FocusScope.of(context).unfocus();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to post comment: $e')),
        );
        setState(() { _isSending = false; }); 
      }
    }
  }

  @override
  void dispose() {
    _commentController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Post"), 
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  StreamBuilder<DocumentSnapshot>(
                    stream: _firestore.collection('posts').doc(widget.postId).snapshots(),
                    builder: (context, snapshot) {
                      
                      if (!snapshot.hasData && widget.initialPostData == null) {
                        return Center(child: Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: CircularProgressIndicator(),
                        ));
                      }
                      
                      Map<String, dynamic>? data = snapshot.hasData
                          ? snapshot.data!.data() as Map<String, dynamic>?
                          : widget.initialPostData;

                      if (data == null) {
                         return Center(child: Padding(
                           padding: const EdgeInsets.all(24.0),
                           child: Text("Post not found or has been deleted."),
                         ));
                      }
                      
                      return BlogPostCard(
                        postId: widget.postId,
                        postData: data,
                        isOwner: data['userId'] == _currentUser?.uid,
                        isClickable: false, 
                        isDetailView: true, 
                        // 2. TERUSKAN ID AGAR ANIMASI HERO COCOK
                        heroContextId: widget.heroContextId, 
                      );
                    },
                  ),
                  
                  _buildCommentList(),
                ],
              ),
            ),
          ),
          _buildCommentInput(),
        ],
      ),
    );
  }

  Widget _buildCommentList() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('posts')
          .doc(widget.postId)
          .collection('comments')
          .orderBy('timestamp', descending: false) 
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(32.0),
            child: Center(child: Text("No replies yet. Be the first!", style: TextStyle(color: Colors.grey))),
          );
        }

        return ListView.builder(
          itemCount: snapshot.data!.docs.length,
          shrinkWrap: true,
          physics: NeverScrollableScrollPhysics(),
          itemBuilder: (context, index) {
            final doc = snapshot.data!.docs[index];
            final data = doc.data() as Map<String, dynamic>;
            
            return CommentTile(
              commentId: doc.id,
              commentData: data,
              postId: widget.postId, 
              isOwner: data['userId'] == _currentUser?.uid,
              // Untuk komentar, kita pakai ID unik berdasarkan parent context
              heroContextId: '${widget.heroContextId}_comments', 
            );
          },
        );
      },
    );
  }

  Widget _buildCommentInput() {
    final theme = Theme.of(context);
    
    return Container(
      padding: EdgeInsets.only(
        left: 12.0, 
        right: 12.0, 
        bottom: MediaQuery.of(context).padding.bottom + 12.0, 
        top: 12.0,
      ),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(top: BorderSide(color: theme.dividerColor)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: Offset(0, -2),
          )
        ]
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_predictedText != null)
            GestureDetector(
              onTap: _acceptPrediction,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                margin: EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: TwitterTheme.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_awesome, size: 14, color: TwitterTheme.blue),
                    SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        "Suggested: ...$_predictedText",
                        style: TextStyle(
                          color: TwitterTheme.blue,
                          fontSize: 13,
                          fontWeight: FontWeight.bold
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          if (_selectedMediaFile != null)
            Container(
              margin: EdgeInsets.only(bottom: 10),
              height: 100,
              width: 100,
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: _mediaType == 'video' 
                        ? Container(color: Colors.black, child: Center(child: Icon(Icons.videocam, color: Colors.white)))
                        : Image.file(_selectedMediaFile!, fit: BoxFit.cover, width: 100, height: 100),
                  ),
                  Positioned(
                    top: 2,
                    right: 2,
                    child: GestureDetector(
                      onTap: _clearMedia,
                      child: CircleAvatar(
                        radius: 10,
                        backgroundColor: Colors.black54,
                        child: Icon(Icons.close, size: 14, color: Colors.white),
                      ),
                    ),
                  )
                ],
              ),
            ),

          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton(
                onPressed: () => _pickMedia(ImageSource.gallery),
                icon: Icon(Icons.add_photo_alternate_outlined, color: TwitterTheme.blue),
                padding: EdgeInsets.zero,
                constraints: BoxConstraints(minWidth: 40, minHeight: 40),
              ),
              
              Expanded(
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: theme.brightness == Brightness.dark 
                        ? TwitterTheme.darkGrey.withOpacity(0.2) 
                        : TwitterTheme.extraLightGrey,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: TextField(
                    controller: _commentController,
                    onChanged: _onCommentChanged, 
                    decoration: InputDecoration(
                      hintText: "Post your reply",
                      hintStyle: TextStyle(color: theme.hintColor),
                      filled: false, 
                      border: InputBorder.none,
                      focusedBorder: InputBorder.none, 
                      enabledBorder: InputBorder.none,
                      errorBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 4),
                    ),
                    maxLines: 4,
                    minLines: 1, 
                  ),
                ),
              ),
              
              SizedBox(width: 8),
              
              _isSending 
                ? Padding(
                    padding: const EdgeInsets.all(10.0),
                    child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : Container(
                    decoration: BoxDecoration(
                      color: TwitterTheme.blue,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      onPressed: _postComment,
                      icon: Icon(Icons.send_rounded, size: 20, color: Colors.white),
                      padding: EdgeInsets.all(10),
                      constraints: BoxConstraints(),
                    ),
                  ),
            ],
          ),
        ],
      ),
    );
  }
}