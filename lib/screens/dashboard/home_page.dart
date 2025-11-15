// ignore_for_file: prefer_const_constructors
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../widgets/blog_post_card.dart'; 
import '../create_post_screen.dart'; 

final FirebaseAuth _auth = FirebaseAuth.instance;
final FirebaseFirestore _firestore = FirebaseFirestore.instance;

class HomePage extends StatefulWidget {
  // ### BARU: Tambahkan callback ###
  final VoidCallback onProfileTap;

  const HomePage({
    super.key,
    required this.onProfileTap, // ### BARU: Wajibkan di konstruktor ###
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // ### PERUBAHAN DI SINI ###
        // Bungkus Padding dengan GestureDetector
        leading: GestureDetector(
          onTap: widget.onProfileTap, // Panggil callback saat diklik
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: CircleAvatar(
              child: Icon(Icons.person, size: 20),
              radius: 18,
            ),
          ),
        ),
        // ### AKHIR PERUBAHAN ###
        title: Image.asset(
          'images/app_icon.png',
          height: 30, 
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(Icons.auto_awesome_outlined),
            onPressed: () { /* Untuk "Top Posts" */ },
          ),
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