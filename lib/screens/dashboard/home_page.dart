// ignore_for_file: prefer_const_constructors
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../widgets/blog_post_card.dart';
import '../../widgets/common_error_widget.dart';
import '../../main.dart';
import '../../services/prediction_service.dart';

final FirebaseAuth _auth = FirebaseAuth.instance;
final FirebaseFirestore _firestore = FirebaseFirestore.instance;

class HomePage extends StatefulWidget {
  final ScrollController scrollController;
  final bool isRecommended; // Parameter dikembalikan

  const HomePage({
    super.key,
    required this.scrollController,
    this.isRecommended = false,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with AutomaticKeepAliveClientMixin {
  late Stream<QuerySnapshot> _postsStream;
  String _refreshKey = ''; 
  final PredictionService _aiService = PredictionService(); 

  @override
  void initState() {
    super.initState();
    _initStream();
  }

  void _initStream() {
    _postsStream = _firestore
        .collection('posts')
        .orderBy('timestamp', descending: true)
        .limit(100) 
        .snapshots();
  }

  Future<void> _handleRefresh() async {
    await Future.delayed(Duration(seconds: 1));
    if (mounted) {
      setState(() {
        _refreshKey = DateTime.now().toString();
      });
    }
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final double contentTopPadding = 10.0; // Adjusted padding since TabBar is in Dashboard
    final String? currentUserId = _auth.currentUser?.uid;

    return StreamBuilder<DocumentSnapshot>(
      stream: currentUserId != null 
          ? _firestore.collection('users').doc(currentUserId).snapshots() 
          : null,
      builder: (context, userSnapshot) {
        
        Map<String, dynamic> userData = {};
        List<dynamic> followingList = [];
        
        if (userSnapshot.hasData && userSnapshot.data!.exists) {
          userData = userSnapshot.data!.data() as Map<String, dynamic>;
          followingList = userData['following'] ?? [];
        }

        return StreamBuilder<QuerySnapshot>(
          stream: _postsStream,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Center(child: CircularProgressIndicator());
            }
            
            if (snapshot.hasError) {
              return Padding(
                padding: EdgeInsets.only(top: 50),
                child: CommonErrorWidget(
                  message: "Couldn't load posts.",
                  isConnectionError: true,
                  onRetry: () => setState(() => _initStream()),
                ),
              );
            }

            List<QueryDocumentSnapshot> allDocs = snapshot.data?.docs ?? [];
            
            // --- FEED FILTERING LOGIC ---
            final visibleDocs = allDocs.where((doc) {
              final data = doc.data() as Map<String, dynamic>;
              
              // SKIP COMMUNITY POSTS IN MAIN FEED
              if (data['communityId'] != null) return false;

              final visibility = data['visibility'] ?? 'public';
              final ownerId = data['userId'];
              
              if (visibility == 'public') return true;
              
              if (visibility == 'followers') {
                if (ownerId == currentUserId) return true;
                if (followingList.contains(ownerId)) return true;
                return false; 
              }
              
              if (visibility == 'private' && ownerId == currentUserId) return true;
              
              return false;
            }).toList();
            // ---------------------------

            List<QueryDocumentSnapshot> finalDocs = visibleDocs;
            if (widget.isRecommended && visibleDocs.isNotEmpty) {
              finalDocs = _aiService.getPersonalizedRecommendations(
                visibleDocs,
                userData, 
                currentUserId ?? ''
              );
            }

            if (finalDocs.isEmpty) {
               return Center(
                 child: Column(
                   mainAxisAlignment: MainAxisAlignment.center,
                   children: [
                     Icon(Icons.feed_outlined, size: 64, color: Colors.grey),
                     SizedBox(height: 16),
                     Text("No posts yet.", style: TextStyle(color: Colors.grey)),
                   ],
                 ),
               );
            }

            return RefreshIndicator(
              onRefresh: _handleRefresh,
              color: TwitterTheme.blue,
              child: ListView.builder(
                key: PageStorageKey('home_list_${widget.isRecommended ? 'rec' : 'recents'}$_refreshKey'),
                controller: widget.scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.only(top: contentTopPadding, bottom: 100),
                itemCount: finalDocs.length,
                itemBuilder: (context, index) {
                  final doc = finalDocs[index];
                  final data = doc.data() as Map<String, dynamic>;
                  
                  return BlogPostCard(
                    postId: doc.id,
                    postData: data,
                    isOwner: data['userId'] == currentUserId,
                    heroContextId: widget.isRecommended ? 'home_recommended' : 'home_recent',
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}