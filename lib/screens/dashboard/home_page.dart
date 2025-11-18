// ignore_for_file: prefer_const_constructors
import 'dart:io';
import 'dart:typed_data'; 
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
            child: _AppBarAvatar(), 
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

class _AppBarAvatar extends StatefulWidget {
  const _AppBarAvatar();

  @override
  State<_AppBarAvatar> createState() => _AppBarAvatarState();
}

class _AppBarAvatarState extends State<_AppBarAvatar> {
  Uint8List? _localImageBytes;
  String? _selectedAvatarIconName;
  final String? _currentUserId = _auth.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _loadLocalAvatar();
  }

  Future<void> _loadLocalAvatar() async {
    if (_currentUserId == null) return;
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
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: _currentUserId != null ? _firestore.collection('users').doc(_currentUserId).snapshots() : null,
      builder: (context, snapshot) {
        String initial = 'U';
        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>;
          final String name = data['name'] ?? 'U';
          if (name.isNotEmpty) {
            initial = name[0].toUpperCase();
          }
        }

        return CircleAvatar(
          radius: 18,
          backgroundImage: _localImageBytes != null ? MemoryImage(_localImageBytes!) : null,
          child: (_localImageBytes == null && _selectedAvatarIconName != null)
            ? Icon(
                _getIconDataFromString(_selectedAvatarIconName),
                size: 20,
                color: TwitterTheme.blue,
              )
            : (_localImageBytes == null && _selectedAvatarIconName == null)
              ? Text(initial)
              : null,
        );
      },
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