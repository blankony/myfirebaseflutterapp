// ignore_for_file: prefer_const_constructors
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../widgets/blog_post_card.dart'; 
import '../widgets/comment_tile.dart'; 

final FirebaseAuth _auth = FirebaseAuth.instance;
final FirebaseFirestore _firestore = FirebaseFirestore.instance;

class PostDetailScreen extends StatefulWidget {
  final String postId;
  final Map<String, dynamic> initialPostData;

  const PostDetailScreen({
    super.key,
    required this.postId,
    required this.initialPostData,
  });

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final TextEditingController _commentController = TextEditingController();
  final User? _currentUser = _auth.currentUser;

  Future<void> _postComment() async {
    if (_commentController.text.isEmpty || _currentUser == null) {
      return;
    }

    String userName = "Anonymous";
    String userEmail = "anonymous@mail.com";
    try {
      final userDoc = await _firestore.collection('users').doc(_currentUser!.uid).get();
      if (userDoc.exists) {
        userName = userDoc.data()?['name'] ?? userName;
        userEmail = userDoc.data()?['email'] ?? userEmail;
      }
    } catch (e) {
      // Biarkan nama default
    }

    final commentData = {
      'text': _commentController.text,
      'timestamp': FieldValue.serverTimestamp(),
      'userId': _currentUser!.uid,
      'userName': userName,
      'userEmail': userEmail,
      'originalPostId': widget.postId,
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
      _commentController.clear();
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
                      Map<String, dynamic> data = widget.initialPostData;
                      if (snapshot.hasData) {
                        data = snapshot.data!.data() as Map<String, dynamic>;
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
                  Divider(height: 1, thickness: 1), 
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

        return ListView.separated(
          itemCount: snapshot.data!.docs.length,
          shrinkWrap: true,
          physics: NeverScrollableScrollPhysics(),
          separatorBuilder: (context, index) => Divider(height: 1, thickness: 1),
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
        // ### PERBAIKAN DI SINI ###
        // Hapus 'viewInsets.bottom' dan ganti dengan 'padding.bottom' (Safe Area)
        bottom: MediaQuery.of(context).padding.bottom + 8.0, 
        top: 8.0,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _commentController,
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
    );
  }
}