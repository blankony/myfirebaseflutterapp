// ignore_for_file: prefer_const_constructors
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../widgets/blog_post_card.dart';
import '../widgets/common_error_widget.dart';
import '../main.dart';

class SavedPostsScreen extends StatelessWidget {
  const SavedPostsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Scaffold(body: Center(child: Text("Please log in")));

    return Scaffold(
      appBar: AppBar(
        title: const Text("Saved Posts"),
        centerTitle: true,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('bookmarks')
            .orderBy('timestamp', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
             return CommonErrorWidget(message: "Error loading bookmarks", isConnectionError: true);
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data?.docs ?? [];

          if (docs.isEmpty) {
             return Center(
               child: Column(
                 mainAxisAlignment: MainAxisAlignment.center,
                 children: [
                   Icon(Icons.bookmark_border, size: 64, color: Theme.of(context).hintColor.withOpacity(0.5)),
                   const SizedBox(height: 16),
                   Text("No saved posts yet", style: TextStyle(color: Theme.of(context).hintColor)),
                 ],
               ),
             );
          }

          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final bookmark = docs[index];
              final postId = bookmark.id; // We use postId as document ID for bookmarks

              return FutureBuilder<DocumentSnapshot>(
                future: FirebaseFirestore.instance.collection('posts').doc(postId).get(),
                builder: (context, postSnapshot) {
                   if (postSnapshot.connectionState == ConnectionState.waiting) {
                     return const SizedBox(height: 100, child: Center(child: CircularProgressIndicator()));
                   }
                   
                   if (!postSnapshot.hasData || !postSnapshot.data!.exists) {
                     // Post might be deleted. 
                     // Optional: Auto-remove bookmark here if desired, but for now just hide it.
                     return const SizedBox.shrink();
                   }

                   final postData = postSnapshot.data!.data() as Map<String, dynamic>;
                   
                   return BlogPostCard(
                     postId: postId,
                     postData: postData,
                     isOwner: postData['userId'] == user.uid,
                     heroContextId: 'saved_posts', // Unique hero tag context
                   );
                },
              );
            },
          );
        },
      ),
    );
  }
}