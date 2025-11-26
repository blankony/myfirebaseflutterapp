// ignore_for_file: prefer_const_constructors
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../widgets/blog_post_card.dart';
import '../../main.dart';

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
  
  final List<String> _trendingKeywords = ['tech', 'flutter', 'coding', 'project', 'seminar'];
  final List<String> _personalKeywords = ['selamat pagi', 'morning', 'halo', 'hello', 'semangat'];

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
        _initStream();
      });
    }
  }

  @override
  bool get wantKeepAlive => true;

  List<QueryDocumentSnapshot> _getRecommendedPosts(
    List<QueryDocumentSnapshot> allPosts, 
    Map<String, dynamic> userData
  ) {
    final List<dynamic> following = userData['following'] ?? [];
    final String myUid = _auth.currentUser?.uid ?? '';

    List<Map<String, dynamic>> scoredPosts = allPosts.map((doc) {
      final data = doc.data() as Map<String, dynamic>;
      double score = 0;

      final String text = (data['text'] ?? '').toString().toLowerCase();
      final String userId = data['userId'] ?? '';
      final Timestamp? timestamp = data['timestamp'] as Timestamp?;
      final int likeCount = (data['likes'] as Map?)?.length ?? 0;

      if (following.contains(userId)) score += 50;
      score += (likeCount * 0.5); 

      for (var keyword in _trendingKeywords) {
        if (text.contains(keyword)) {
          score += 10;
          break;
        }
      }

      for (var keyword in _personalKeywords) {
        if (text.contains(keyword)) {
          score += 15;
          break;
        }
      }

      if (timestamp != null) {
        final hoursAgo = DateTime.now().difference(timestamp.toDate()).inHours;
        score += (20.0 / (hoursAgo + 1)); 
      }

      if (userId == myUid) score -= 5; 

      return {'doc': doc, 'score': score};
    }).toList();

    scoredPosts.sort((a, b) => (b['score'] as double).compareTo(a['score'] as double));
    return scoredPosts.map((e) => e['doc'] as QueryDocumentSnapshot).toList();
  }

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
                // FIX: Hanya loading jika data benar-benar kosong (mencegah flicker)
                if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                  return Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }

                List<QueryDocumentSnapshot> docs = snapshot.data?.docs ?? [];
                
                if (widget.isRecommended && docs.isNotEmpty) {
                  docs = _getRecommendedPosts(docs, userData);
                }

                return RefreshIndicator(
                  onRefresh: _handleRefresh,
                  color: TwitterTheme.blue,
                  edgeOffset: refreshIndicatorOffset,
                  child: docs.isNotEmpty
                      ? ListView.builder(
                          // PENTING: Key ini menjaga posisi scroll saat kembali dari full screen
                          key: PageStorageKey('home_list_${widget.isRecommended ? 'rec' : 'recents'}'),
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
                                    'No posts yet.', 
                                    style: TextStyle(color: Colors.grey, fontSize: 18, fontWeight: FontWeight.bold)
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    'Start exploring or create a post!', 
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