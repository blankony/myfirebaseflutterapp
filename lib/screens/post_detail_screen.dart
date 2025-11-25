// ignore_for_file: prefer_const_constructors
import 'dart:async'; // Timer
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../widgets/blog_post_card.dart'; 
import '../widgets/comment_tile.dart'; 
import '../services/prediction_service.dart'; // Import Service
import '../main.dart'; // TwitterTheme

final FirebaseAuth _auth = FirebaseAuth.instance;
final FirebaseFirestore _firestore = FirebaseFirestore.instance;

class PostDetailScreen extends StatefulWidget {
  final String postId;
  final Map<String, dynamic>? initialPostData;

  const PostDetailScreen({
    super.key,
    required this.postId,
    this.initialPostData,
  });

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final TextEditingController _commentController = TextEditingController();
  final PredictionService _predictionService = PredictionService();
  final User? _currentUser = _auth.currentUser;

  // Predictive Text State
  String? _predictedText;
  Timer? _debounce;

  // Listener untuk Predictive Text
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

  // Helper for Slide Left Animation
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

  Future<void> _postComment() async {
    if (_commentController.text.isEmpty || _currentUser == null) {
      return;
    }

    String userName = "Anonymous";
    String userEmail = "anonymous@mail.com";
    int iconId = 0;
    String hex = '';

    try {
      final userDoc = await _firestore.collection('users').doc(_currentUser!.uid).get();
      if (userDoc.exists) {
        final data = userDoc.data();
        userName = data?['name'] ?? userName;
        userEmail = data?['email'] ?? userEmail;
        iconId = data?['avatarIconId'] ?? 0;
        hex = data?['avatarHex'] ?? '';
      }
    } catch (e) {}

    final commentData = {
      'text': _commentController.text,
      'timestamp': FieldValue.serverTimestamp(),
      'userId': _currentUser!.uid,
      'originalPostId': widget.postId,
      'userName': userName,
      'userEmail': userEmail,
      'avatarIconId': iconId,
      'avatarHex': hex,
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

      _commentController.clear();
      setState(() { _predictedText = null; }); // Reset prediksi
      FocusScope.of(context).unfocus();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to post comment: $e')),
        );
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
            padding: const EdgeInsets.all(16.0),
            child: Center(child: Text("No replies yet.")),
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
            );
          },
        );
      },
    );
  }

  Widget _buildCommentInput() {
    return Container(
      padding: EdgeInsets.only(
        left: 16.0, 
        right: 8.0, 
        bottom: MediaQuery.of(context).padding.bottom + 8.0, 
        top: 8.0,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // === AI PREDICTION WIDGET FOR COMMENT ===
          if (_predictedText != null)
            GestureDetector(
              onTap: _acceptPrediction,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Row(
                  children: [
                    Icon(Icons.auto_awesome, size: 12, color: TwitterTheme.blue),
                    SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        "Suggestion: ...$_predictedText",
                        style: TextStyle(
                          color: TwitterTheme.blue,
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
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

          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _commentController,
                  onChanged: _onCommentChanged, // Listener
                  decoration: InputDecoration(
                    hintText: "Write your reply...",
                    hintStyle: TextStyle(color: Theme.of(context).hintColor),
                    border: InputBorder.none,
                  ),
                  maxLines: null, 
                ),
              ),
              ElevatedButton(
                onPressed: _postComment,
                child: Text('Reply'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}