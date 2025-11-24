// ignore_for_file: prefer_const_constructors
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../widgets/blog_post_card.dart';
import '../create_post_screen.dart';
import '../../main.dart';

final FirebaseAuth _auth = FirebaseAuth.instance;
final FirebaseFirestore _firestore = FirebaseFirestore.instance;

class HomePage extends StatefulWidget {
  final ScrollController scrollController;
  final bool isRecommended; // New parameter

  const HomePage({
    super.key,
    required this.scrollController,
    this.isRecommended = false, // Default to Recent
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with AutomaticKeepAliveClientMixin {
  late Stream<QuerySnapshot> _postsStream;

  @override
  void initState() {
    super.initState();
    _initStream();
  }

  void _initStream() {
    _postsStream = _firestore
        .collection('posts')
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  Future<void> _handleRefresh() async {
    await Future.delayed(Duration(seconds: 1));
    if (mounted) {
      setState(() {
        _initStream();
      });
    }
  }

  @override
  bool get wantKeepAlive => true; // CRUCIAL

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
    super.build(context); // CRUCIAL

    final double contentTopPadding = 160.0; 
    final double refreshIndicatorOffset = 120.0;

    return Stack(
      children: [
        // --- TODO FOR BACKEND ENGINEER ---
        // TODO: Implement Narrow AI Recommendation Algorithm
        // 1. PRIORITY - Following Feed: Fetch and display new posts from accounts the user follows FIRST.
        //    - Query the 'users' collection -> 'following' list.
        //    - Fetch recent posts where 'userId' matches the following list.
        // 2. Analyze User Behavior: Track 'likes', 'reposts', and 'time spent' on specific posts.
        // 3. Keyword Extraction: Extract tags/keywords from those high-engagement posts (e.g., "tech", "morning", "flutter").
        // 4. Intelligent Querying: Fill the remaining feed with posts containing these weighted keywords.
        // 5. Personalization: 
        //    - IF user likes "selamat pagi" posts -> Prioritize posts with "pagi", "morning", "hello".
        //    - IF user likes image-heavy posts -> Prioritize posts with media.
        // 6. Fallback: If no history/following, use the current "Random Shuffle" or "Trending" logic.
        // ---------------------------------

        StreamBuilder<QuerySnapshot>(
          stream: _postsStream,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            }

            // Logic: Determine which list to show
            List<QueryDocumentSnapshot> docs = snapshot.hasData ? snapshot.data!.docs : [];
            
            if (widget.isRecommended && docs.isNotEmpty) {
              // Create a copy and shuffle to simulate "Random/Recommended" order
              // This ensures the "Recommended" tab looks different from "Recent"
              docs = List.from(docs)..shuffle();
            }

            return RefreshIndicator(
              onRefresh: _handleRefresh,
              color: TwitterTheme.blue,
              edgeOffset: refreshIndicatorOffset,
              child: docs.isNotEmpty
                  ? ListView.builder(
                      controller: widget.scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.only(top: contentTopPadding, bottom: 100),
                      itemCount: docs.length,
                      itemBuilder: (context, index) {
                        final doc = docs[index];
                        final data = doc.data() as Map<String, dynamic>;
                        final currentUserUid = _auth.currentUser?.uid;

                        return Column(
                          children: [
                            BlogPostCard(
                              postId: doc.id,
                              postData: data,
                              isOwner: data['userId'] == currentUserUid,
                            ),
                          ],
                        );
                      },
                    )
                  : ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(height: contentTopPadding),
                        // Better Empty State
                        Container(
                          height: 300,
                          alignment: Alignment.center,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.auto_awesome_outlined, size: 64, color: Colors.grey),
                              SizedBox(height: 16),
                              Text(
                                'No posts yet.', 
                                style: TextStyle(color: Colors.grey, fontSize: 18, fontWeight: FontWeight.bold)
                              ),
                              SizedBox(height: 8),
                              Text(
                                'Be the first to start the conversation!', 
                                style: TextStyle(color: Colors.grey)
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
            );
          },
        ),

        // Only show FAB on Recent Posts tab (optional, but standard pattern)
        if (!widget.isRecommended)
          Positioned(
            bottom: 16,
            right: 16,
            child: FloatingActionButton(
              onPressed: _navigateToCreatePost,
              tooltip: 'New Post',
              child: const Icon(Icons.edit_outlined),
            ),
          ),
      ],
    );
  }
}