// ignore_for_file: prefer_const_constructors
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../widgets/blog_post_card.dart'; 
import '../create_post_screen.dart'; 
import '../../widgets/notification_sheet.dart';
import '../../main.dart';

final FirebaseAuth _auth = FirebaseAuth.instance;
final FirebaseFirestore _firestore = FirebaseFirestore.instance;

class HomePage extends StatefulWidget {
  final VoidCallback onProfileTap;

  const HomePage({
    super.key,
    required this.onProfileTap, 
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {

  void _navigateToCreatePost() {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true, 
        builder: (context) => CreatePostScreen(),
      ),
    );
  }

  void _showNotificationSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true, 
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6, 
          minChildSize: 0.3,     
          maxChildSize: 0.9,     
          builder: (context, scrollController) {
            return NotificationSheet(scrollController: scrollController);
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: GestureDetector(
          onTap: widget.onProfileTap,
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: CircleAvatar(
              child: Icon(Icons.person, size: 20),
              radius: 18,
            ),
          ),
        ),
        title: Image.asset(
          'images/app_icon.png',
          height: 30, 
        ),
        centerTitle: true,
        actions: [
          _NotificationButton(onPressed: _showNotificationSheet),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _firestore
            .collection('posts')
            .orderBy('timestamp', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(child: Text('No posts yet.'));
          }

          return ListView.separated(
            itemCount: snapshot.data!.docs.length,
            separatorBuilder: (context, index) => Divider(
              height: 1, 
              thickness: 1,
            ),
            itemBuilder: (context, index) {
              final doc = snapshot.data!.docs[index];
              final data = doc.data() as Map<String, dynamic>;
              final currentUserUid = _auth.currentUser?.uid;
              
              return BlogPostCard(
                postId: doc.id, 
                postData: data,
                isOwner: data['userId'] == currentUserUid,
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _navigateToCreatePost, 
        tooltip: 'New Post', 
        child: const Icon(Icons.edit_outlined), 
      ),
    );
  }
}

class _NotificationButton extends StatelessWidget {
  final VoidCallback onPressed;
  
  const _NotificationButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;
    if (user == null) {
      return IconButton(icon: Icon(Icons.notifications_none), onPressed: onPressed);
    }

    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('users')
          .doc(user.uid)
          .collection('notifications')
          .where('isRead', isEqualTo: false)
          .limit(1) 
          .snapshots(),
      builder: (context, snapshot) {
        final bool hasUnread = snapshot.hasData && snapshot.data!.docs.isNotEmpty;

        return Stack(
          children: [
            IconButton(
              icon: Icon(
                hasUnread ? Icons.notifications : Icons.notifications_none,
              ),
              onPressed: onPressed,
            ),
            if (hasUnread)
              Positioned(
                top: 10,
                right: 10,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: TwitterTheme.blue,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}