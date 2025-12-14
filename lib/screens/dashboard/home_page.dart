// ignore_for_file: prefer_const_constructors
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../widgets/blog_post_card.dart';
import '../../widgets/common_error_widget.dart';
import '../../main.dart';
import '../../services/prediction_service.dart';
import '../../services/app_localizations.dart';

final FirebaseAuth _auth = FirebaseAuth.instance;
final FirebaseFirestore _firestore = FirebaseFirestore.instance;

class HomePage extends StatefulWidget {
  final ScrollController scrollController;
  final ScrollController recommendedScrollController;

  const HomePage({
    super.key,
    required this.scrollController,
    required this.recommendedScrollController,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with AutomaticKeepAliveClientMixin, SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ScrollController _localScrollController = ScrollController(); 
  bool _isScrolled = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    
    _localScrollController.addListener(() {
      if (_localScrollController.hasClients) {
        bool scrolled = _localScrollController.offset > 0;
        if (scrolled != _isScrolled) {
          setState(() => _isScrolled = scrolled);
        }
      }
    });
  }

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _tabController.dispose();
    _localScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    var t = AppLocalizations.of(context)!;

    return NestedScrollView(
      controller: _localScrollController,
      headerSliverBuilder: (context, innerBoxIsScrolled) {
        return [
          SliverAppBar(
            pinned: true,
            floating: true,
            snap: true,
            elevation: 0,
            backgroundColor: Colors.transparent, 
            automaticallyImplyLeading: false, 
            toolbarHeight: 0,
            collapsedHeight: 0,
            expandedHeight: 0,
            
            bottom: PreferredSize(
              preferredSize: Size.fromHeight(48),
              child: ClipRRect( 
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
                  child: Container(
                    color: theme.scaffoldBackgroundColor.withOpacity(0.85),
                    child: TabBar(
                      controller: _tabController,
                      labelColor: TwitterTheme.blue,
                      unselectedLabelColor: theme.hintColor,
                      indicatorColor: TwitterTheme.blue,
                      indicatorSize: TabBarIndicatorSize.label,
                      tabs: [
                        Tab(text: t.translate('home_recent')),
                        Tab(text: t.translate('home_recommended')),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ];
      },
      body: TabBarView(
        controller: _tabController,
        children: [
          _PostFeedList(
            scrollController: widget.scrollController,
            feedType: 'recent',
            refreshOffset: 60, 
          ),
          _PostFeedList(
            scrollController: widget.recommendedScrollController,
            feedType: 'recommended',
            refreshOffset: 60,
          ),
        ],
      ),
    );
  }
}

class _PostFeedList extends StatefulWidget {
  final ScrollController scrollController;
  final String feedType;
  final double refreshOffset;

  const _PostFeedList({required this.scrollController, required this.feedType, required this.refreshOffset});

  @override
  State<_PostFeedList> createState() => _PostFeedListState();
}

class _PostFeedListState extends State<_PostFeedList> with AutomaticKeepAliveClientMixin {
  final PredictionService _aiService = PredictionService(); 
  late Stream<QuerySnapshot> _stream;
  String _refreshKey = '';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _stream = _firestore.collection('posts')
        .orderBy('timestamp', descending: true)
        .limit(50)
        .snapshots();
  }

  Future<void> _refresh() async {
    await Future.delayed(Duration(seconds: 1));
    if(mounted) setState(() => _refreshKey = DateTime.now().toString());
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final user = _auth.currentUser;
    final bool isRec = widget.feedType == 'recommended';
    
    // LOCALIZATION
    var t = AppLocalizations.of(context)!;

    return StreamBuilder<DocumentSnapshot>(
      stream: user != null ? _firestore.collection('users').doc(user.uid).snapshots() : null,
      builder: (context, userSnap) {
        Map<String, dynamic> userData = {};
        if (userSnap.hasData && userSnap.data!.exists) {
          userData = userSnap.data!.data() as Map<String, dynamic>;
        }

        return StreamBuilder<QuerySnapshot>(
          stream: _stream,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Center(child: CircularProgressIndicator()); 
            }
            
            if (snapshot.hasError) return CommonErrorWidget(message: t.translate('home_error_loading'));

            final allDocs = snapshot.data?.docs ?? [];
            
            List<QueryDocumentSnapshot> docs = allDocs.where((doc) {
              final data = doc.data() as Map<String, dynamic>;
              if (data['communityId'] != null) return false; 
              
              final vis = data['visibility'] ?? 'public';
              if (vis == 'public') return true;
              if (vis == 'followers' && user != null) {
                final following = List.from(userData['following'] ?? []);
                return data['userId'] == user.uid || following.contains(data['userId']);
              }
              return vis == 'private' && data['userId'] == user?.uid;
            }).toList();

            if (isRec && docs.isNotEmpty) {
              docs = _aiService.getPersonalizedRecommendations(docs, userData, user?.uid ?? '');
            }

            if (docs.isEmpty) {
               return Center(
                 child: Column(
                   mainAxisAlignment: MainAxisAlignment.center,
                   children: [
                     Icon(Icons.feed_outlined, size: 64, color: Colors.grey.withOpacity(0.5)),
                     SizedBox(height: 16),
                     Text(t.translate('home_no_posts'), style: TextStyle(color: Colors.grey)),
                   ],
                 ),
               );
            }

            return RefreshIndicator(
              onRefresh: _refresh,
              edgeOffset: widget.refreshOffset,
              child: ListView.builder(
                key: PageStorageKey('${widget.feedType}_$_refreshKey'),
                controller: widget.scrollController,
                padding: EdgeInsets.only(top: 10, bottom: 100),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  return BlogPostCard(
                    postId: docs[index].id,
                    postData: docs[index].data() as Map<String, dynamic>,
                    isOwner: docs[index]['userId'] == user?.uid,
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