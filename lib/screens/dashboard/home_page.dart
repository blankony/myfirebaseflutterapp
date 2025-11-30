// ignore_for_file: prefer_const_constructors
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../widgets/blog_post_card.dart';
import '../../widgets/common_error_widget.dart'; // REQUIRED
import '../../main.dart';
import '../../services/prediction_service.dart';

final FirebaseAuth _auth = FirebaseAuth.instance;
final FirebaseFirestore _firestore = FirebaseFirestore.instance;

class HomePage extends StatefulWidget {
  final ScrollController scrollController;
  final bool isRecommended;

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

    final double contentTopPadding = 160.0; 
    final double refreshIndicatorOffset = 120.0;
    final String? currentUserId = _auth.currentUser?.uid;

    return StreamBuilder<DocumentSnapshot>(
      stream: currentUserId != null 
          ? _firestore.collection('users').doc(currentUserId).snapshots() 
          : null,
      builder: (context, userSnapshot) {
        
        Map<String, dynamic> userData = {};
        if (userSnapshot.hasData && userSnapshot.data!.exists) {
          userData = userSnapshot.data!.data() as Map<String, dynamic>;
        }

        return Stack(
          children: [
            StreamBuilder<QuerySnapshot>(
              stream: _postsStream,
              builder: (context, snapshot) {
                // 1. Handle Loading
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator());
                }
                
                // 2. Handle Errors (Offline/Permission)
                if (snapshot.hasError) {
                  return Padding(
                    padding: EdgeInsets.only(top: contentTopPadding),
                    child: CommonErrorWidget(
                      message: "Couldn't load posts. Please check your connection.",
                      isConnectionError: true,
                      onRetry: () => setState(() => _initStream()),
                    ),
                  );
                }

                List<QueryDocumentSnapshot> docs = snapshot.data?.docs ?? [];
                
                // --- APPLY AI RECOMMENDATION ALGORITHM ---
                if (widget.isRecommended && docs.isNotEmpty) {
                  docs = _aiService.getPersonalizedRecommendations(
                    docs, 
                    userData, 
                    currentUserId ?? ''
                  );
                }
                // ------------------------------------------

                return RefreshIndicator(
                  onRefresh: _handleRefresh,
                  color: TwitterTheme.blue,
                  edgeOffset: refreshIndicatorOffset,
                  child: docs.isNotEmpty
                      ? ListView.builder(
                          key: PageStorageKey('home_list_${widget.isRecommended ? 'rec' : 'recents'}$_refreshKey'),
                          controller: widget.scrollController,
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: EdgeInsets.only(top: contentTopPadding, bottom: 100),
                          itemCount: docs.length,
                          itemBuilder: (context, index) {
                            final doc = docs[index];
                            final data = doc.data() as Map<String, dynamic>;
                            
                            return Column(
                              children: [
                                BlogPostCard(
                                  postId: doc.id,
                                  postData: data,
                                  isOwner: data['userId'] == currentUserId,
                                  heroContextId: widget.isRecommended ? 'home_recommended' : 'home_recent',
                                ),
                              ],
                            );
                          },
                        )
                      : ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            SizedBox(height: contentTopPadding),
                            Container(
                              height: 300,
                              alignment: Alignment.center,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.auto_awesome_outlined, size: 64, color: Colors.grey),
                                  SizedBox(height: 16),
                                  Text(
                                    widget.isRecommended 
                                      ? 'No recommendations yet.' 
                                      : 'No posts yet.', 
                                    style: TextStyle(color: Colors.grey, fontSize: 18, fontWeight: FontWeight.bold)
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    widget.isRecommended
                                      ? 'Interact with posts to teach our AI!'
                                      : 'Start exploring or create a post!', 
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
          ],
        );
      },
    );
  }
}