// ignore_for_file: prefer_const_constructors
import 'dart:async'; 
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart'; // Added Import
import '../../widgets/blog_post_card.dart';
import '../../main.dart'; 
import 'profile_page.dart'; 
import '../../services/prediction_service.dart'; 

final FirebaseAuth _auth = FirebaseAuth.instance;
final FirebaseFirestore _firestore = FirebaseFirestore.instance;

class SearchPage extends StatefulWidget {
  final bool isSearching;
  final VoidCallback onSearchPressed;
  // Callback baru untuk navigasi ke tab Recommended
  final VoidCallback? onNavigateToRecommended; 

  const SearchPage({
    Key? key,
    required this.isSearching,
    required this.onSearchPressed,
    this.onNavigateToRecommended,
  }) : super(key: key);

  @override
  State<SearchPage> createState() => SearchPageState();
}

class SearchPageState extends State<SearchPage> with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final PredictionService _predictionService = PredictionService(); 
  
  late TabController _tabController;
  
  String _searchText = '';
  String? _searchSuggestion; 
  Timer? _debounce;
  
  // State untuk fitur Trending
  bool _showAllTrending = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _tabController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void startSearch() {
    _searchFocusNode.requestFocus();
  }

  void _onSearchChanged(String value) {
    setState(() {
      _searchText = value.toLowerCase().trim();
      _searchSuggestion = null; 
    });

    if (_debounce?.isActive ?? false) _debounce!.cancel();

    _debounce = Timer(const Duration(milliseconds: 600), () async {
      if (value.trim().isEmpty) return;
      
      final suggestion = await _predictionService.getCompletion(value, 'search');
      
      if (mounted && suggestion != null && suggestion.toLowerCase() != _searchText) {
        setState(() {
          _searchSuggestion = suggestion;
        });
      }
    });
  }

  void _applySuggestion() {
    if (_searchSuggestion != null) {
      _searchController.text = _searchSuggestion!;
      _onSearchChanged(_searchSuggestion!); 
      FocusScope.of(context).unfocus();
    }
  }

  void _clearSearch() {
    setState(() {
      _searchController.clear();
      _searchText = '';
      _searchSuggestion = null;
    });
  }

  // --- ALGORITMA TRENDING ---
  List<QueryDocumentSnapshot> _getTrendingPosts(List<QueryDocumentSnapshot> allPosts) {
    if (allPosts.isEmpty) return [];

    // 1. Analisis Frekuensi Kata (Sederhana) untuk mendeteksi topik hangat
    final Map<String, int> wordFrequency = {};
    final List<String> stopWords = [
      'the', 'and', 'is', 'to', 'in', 'of', // English
      'di', 'dan', 'yang', 'ini', 'itu', 'aku', 'kamu', 'ke', 'dari', 'ada', 'dengan', 'untuk' // Indo
    ];

    for (var doc in allPosts) {
      final data = doc.data() as Map<String, dynamic>;
      final text = (data['text'] ?? '').toString().toLowerCase();
      // Hapus tanda baca dan split spasi
      final words = text.replaceAll(RegExp(r'[^\w\s]'), '').split(RegExp(r'\s+'));
      
      for (var word in words) {
        if (word.length > 3 && !stopWords.contains(word)) {
          wordFrequency[word] = (wordFrequency[word] ?? 0) + 1;
        }
      }
    }

    // Ambil Top 5 Keyword
    final sortedKeywords = wordFrequency.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topKeywords = sortedKeywords.take(5).map((e) => e.key).toList();

    // 2. Scoring & Sorting
    List<Map<String, dynamic>> scoredPosts = allPosts.map((doc) {
      final data = doc.data() as Map<String, dynamic>;
      double score = 0;
      
      final int likes = (data['likes'] as Map?)?.length ?? 0;
      final int reposts = (data['repostedBy'] as List?)?.length ?? 0;
      final int comments = data['commentCount'] ?? 0;
      final String text = (data['text'] ?? '').toString().toLowerCase();

      // Poin Interaksi (Bobot: Repost > Reply > Like)
      score += (likes * 1.0) + (reposts * 3.0) + (comments * 2.0);

      // Poin Keyword Trending
      for (var keyword in topKeywords) {
        if (text.contains(keyword)) {
          score += 5.0; // Bonus poin jika mengandung topik hangat
        }
      }

      return {'doc': doc, 'score': score};
    }).toList();

    // Sort dari score tertinggi
    scoredPosts.sort((a, b) => (b['score'] as double).compareTo(a['score'] as double));

    // Ambil 10 teratas
    return scoredPosts.take(10).map((e) => e['doc'] as QueryDocumentSnapshot).toList();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final double searchBarHeight = 70.0;
    final theme = Theme.of(context);

    return Column(
      children: [
        // 1. SPACER
        SizedBox(height: MediaQuery.of(context).padding.top + kToolbarHeight),

        // 2. ANIMATED SEARCH BAR
        Align(
          alignment: Alignment.topRight,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeInOutQuart,
            width: widget.isSearching ? screenWidth : 0,
            height: widget.isSearching ? (searchBarHeight + (_searchSuggestion != null ? 30 : 0)) : 0,
            child: ClipRRect(
              borderRadius: BorderRadius.only(bottomLeft: Radius.circular(20)),
              child: SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                child: Column(
                  children: [
                    Container(
                      width: screenWidth,
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      child: Center(
                        child: TextField(
                          controller: _searchController,
                          focusNode: _searchFocusNode,
                          autofocus: false, 
                          decoration: InputDecoration(
                            hintText: 'Search posts or users...',
                            prefixIcon: Icon(Icons.search),
                            suffixIcon: _searchController.text.isNotEmpty 
                              ? IconButton(icon: Icon(Icons.clear), onPressed: _clearSearch) 
                              : null,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(30),
                              borderSide: BorderSide.none,
                            ),
                            filled: true,
                            contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 0),
                          ),
                          onChanged: _onSearchChanged,
                        ),
                      ),
                    ),
                    
                    if (_searchSuggestion != null && widget.isSearching)
                      InkWell(
                        onTap: _applySuggestion,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 8.0, left: 24.0, right: 24.0),
                          child: Row(
                            children: [
                              Icon(Icons.lightbulb_outline, size: 14, color: TwitterTheme.blue),
                              SizedBox(width: 8),
                              Expanded(
                                child: RichText(
                                  text: TextSpan(
                                    style: TextStyle(color: theme.textTheme.bodyMedium?.color, fontSize: 13),
                                    children: [
                                      TextSpan(text: "Suggestion: "),
                                      TextSpan(
                                        text: _searchSuggestion, 
                                        style: TextStyle(fontWeight: FontWeight.bold, color: TwitterTheme.blue)
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),

        // 3. SPACER
        AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOutQuart,
          height: widget.isSearching ? 0 : 20.0, 
        ),

        // 4. CONTENT
        Expanded(
          child: _searchText.isEmpty && !widget.isSearching
              ? _buildRecommendations(theme)
              : _buildSearchResults(theme),
        ),
      ],
    );
  }

  // --- MODIFIKASI BAGIAN INI ---
  Widget _buildRecommendations(ThemeData theme) {
    return RefreshIndicator(
      onRefresh: () async {
        setState(() {}); // Rebuild untuk fetch ulang trending
        await Future.delayed(Duration(seconds: 1));
      },
      child: SingleChildScrollView(
        physics: AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(bottom: 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Row(
                children: [
                  Icon(Icons.trending_up, color: TwitterTheme.blue),
                  SizedBox(width: 8),
                  Text(
                    "Trending Right Now",
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                  ),
                ],
              ),
            ),
            
            // Trending Content
            StreamBuilder<QuerySnapshot>(
              // Ambil 50 post terbaru untuk analisis trending
              stream: _firestore.collection('posts').orderBy('timestamp', descending: true).limit(50).snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return SizedBox(
                    height: 100,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                final allPosts = snapshot.data!.docs;
                final trendingPosts = _getTrendingPosts(allPosts);

                if (trendingPosts.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text("No trending topics yet.", style: TextStyle(color: Colors.grey)),
                  );
                }

                // Tentukan berapa banyak yang ditampilkan (3 atau 10)
                final displayCount = _showAllTrending ? trendingPosts.length : (trendingPosts.length > 3 ? 3 : trendingPosts.length);
                final displayedPosts = trendingPosts.take(displayCount).toList();

                return Column(
                  children: [
                    // List Trending Posts
                    ListView.separated(
                      shrinkWrap: true,
                      physics: NeverScrollableScrollPhysics(),
                      itemCount: displayedPosts.length,
                      separatorBuilder: (context, index) => Divider(height: 1),
                      itemBuilder: (context, index) {
                        final doc = displayedPosts[index];
                        final data = doc.data() as Map<String, dynamic>;
                        
                        // Tampilan sedikit berbeda untuk trending list (misal: ada nomor urut)
                        return Stack(
                          children: [
                            BlogPostCard(
                              postId: doc.id,
                              postData: data,
                              isOwner: data['userId'] == _auth.currentUser?.uid,
                            ),
                            // Badge Nomor Trending
                            Positioned(
                              top: 8,
                              right: 8,
                              child: Container(
                                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: TwitterTheme.blue.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  "#${index + 1}",
                                  style: TextStyle(
                                    color: TwitterTheme.blue,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),

                    // Tombol Show More / Less
                    if (trendingPosts.length > 3)
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _showAllTrending = !_showAllTrending;
                          });
                        },
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(_showAllTrending ? "Show Less" : "Show More Trending"),
                            Icon(_showAllTrending ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),

            SizedBox(height: 24),
            Divider(thickness: 8, color: theme.dividerColor.withOpacity(0.3)),
            SizedBox(height: 24),

            // Tombol Recommended For You
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [TwitterTheme.blue.withOpacity(0.1), theme.cardColor],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: TwitterTheme.blue.withOpacity(0.3)),
                ),
                child: Column(
                  children: [
                    Icon(Icons.auto_awesome, size: 40, color: TwitterTheme.blue),
                    SizedBox(height: 12),
                    Text(
                      "Curated Just For You",
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 8),
                    Text(
                      "Discover content based on your interests and activity.",
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
                    ),
                    SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          if (widget.onNavigateToRecommended != null) {
                            widget.onNavigateToRecommended!();
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text("Please go to Home > Recommended tab"))
                            );
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: TwitterTheme.blue,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                        ),
                        child: Text("See Recommended Feed"),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResults(ThemeData theme) {
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: theme.dividerColor)),
          ),
          child: TabBar(
            controller: _tabController,
            labelColor: theme.primaryColor,
            unselectedLabelColor: theme.hintColor,
            indicatorColor: theme.primaryColor,
            tabs: const [
              Tab(text: 'Posts'),
              Tab(text: 'Users'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildPostResults(),
              _buildUserResults(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPostResults() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('posts')
          .orderBy('timestamp', descending: true)
          .limit(100) 
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
        if (snapshot.connectionState == ConnectionState.waiting) return Center(child: CircularProgressIndicator());
        
        final docs = snapshot.data?.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final text = (data['text'] ?? '').toString().toLowerCase();
          return text.contains(_searchText);
        }).toList() ?? [];
        
        if (docs.isEmpty) {
          return Center(child: Text('No posts found for "$_searchText"'));
        }

        return ListView.builder(
          padding: EdgeInsets.only(bottom: 100),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            return BlogPostCard(
              postId: docs[index].id,
              postData: data,
              isOwner: data['userId'] == _auth.currentUser?.uid,
            );
          },
        );
      },
    );
  }

  Widget _buildUserResults() {
    final myUid = _auth.currentUser?.uid;

    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('users').limit(100).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
        if (snapshot.connectionState == ConnectionState.waiting) return Center(child: CircularProgressIndicator());
        
        final docs = snapshot.data?.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final name = (data['name'] ?? '').toString().toLowerCase();
          final email = (data['email'] ?? '').toString().toLowerCase();
          return name.contains(_searchText) || email.contains(_searchText);
        }).toList() ?? [];

        if (docs.isEmpty) {
          return Center(child: Text('No users found for "$_searchText"'));
        }

        return ListView.builder(
          padding: EdgeInsets.only(bottom: 100),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            final userId = docs[index].id;
            
            if (userId == myUid) return SizedBox.shrink();

            return _UserSearchTile(
              userId: userId,
              userData: data,
              currentUserId: myUid,
            );
          },
        );
      },
    );
  }
}

class _UserSearchTile extends StatefulWidget {
  final String userId;
  final Map<String, dynamic> userData;
  final String? currentUserId;

  const _UserSearchTile({
    required this.userId,
    required this.userData,
    this.currentUserId,
  });

  @override
  State<_UserSearchTile> createState() => _UserSearchTileState();
}

class _UserSearchTileState extends State<_UserSearchTile> {
  bool _isFollowing = false;

  @override
  void initState() {
    super.initState();
    _checkFollowStatus();
  }

  @override
  void didUpdateWidget(covariant _UserSearchTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.userData != oldWidget.userData) {
      _checkFollowStatus();
    }
  }

  void _checkFollowStatus() {
    if (widget.currentUserId == null) return;
    final followers = List<dynamic>.from(widget.userData['followers'] ?? []);
    setState(() {
      _isFollowing = followers.contains(widget.currentUserId);
    });
  }

  Future<void> _toggleFollow() async {
    if (widget.currentUserId == null) return;

    final myDocRef = _firestore.collection('users').doc(widget.currentUserId);
    final targetDocRef = _firestore.collection('users').doc(widget.userId);
    
    final batch = _firestore.batch();

    if (_isFollowing) {
      batch.update(myDocRef, {'following': FieldValue.arrayRemove([widget.userId])});
      batch.update(targetDocRef, {'followers': FieldValue.arrayRemove([widget.currentUserId])});
      setState(() => _isFollowing = false);
    } else {
      batch.update(myDocRef, {'following': FieldValue.arrayUnion([widget.userId])});
      batch.update(targetDocRef, {'followers': FieldValue.arrayUnion([widget.currentUserId])});
      
      _firestore.collection('users').doc(widget.userId).collection('notifications').add({
        'type': 'follow',
        'senderId': widget.currentUserId,
        'timestamp': FieldValue.serverTimestamp(),
        'isRead': false,
      });

      setState(() => _isFollowing = true);
    }

    try {
      await batch.commit();
    } catch (e) {
      _checkFollowStatus();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Action failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = widget.userData['name'] ?? 'User';
    final email = widget.userData['email'] ?? '';
    final handle = email.isNotEmpty ? "@${email.split('@')[0]}" : "";
    final bio = widget.userData['bio'] ?? '';
    final followersCount = (widget.userData['followers'] as List?)?.length ?? 0;
    
    final List<dynamic> followingList = widget.userData['following'] ?? [];
    final bool followsMe = widget.currentUserId != null && followingList.contains(widget.currentUserId);

    // Avatar Data
    final int iconId = widget.userData['avatarIconId'] ?? 0;
    final String? colorHex = widget.userData['avatarHex'];
    final String? profileImageUrl = widget.userData['profileImageUrl'];

    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ProfilePage(userId: widget.userId, includeScaffold: true)),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: profileImageUrl != null ? Colors.transparent : AvatarHelper.getColor(colorHex),
              backgroundImage: profileImageUrl != null ? CachedNetworkImageProvider(profileImageUrl) : null,
              child: profileImageUrl == null ? Icon(AvatarHelper.getIcon(iconId), size: 24, color: Colors.white) : null,
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          name, 
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (followsMe) ...[
                        SizedBox(width: 6),
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          decoration: BoxDecoration(
                            color: theme.dividerColor.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            "Follows you",
                            style: theme.textTheme.bodySmall?.copyWith(fontSize: 10, color: theme.hintColor),
                          ),
                        )
                      ]
                    ],
                  ),
                  Text(handle, style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor)),
                  if (bio.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Text(
                        bio, 
                        style: theme.textTheme.bodyMedium,
                        maxLines: 1, 
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  SizedBox(height: 4),
                  Text(
                    "$followersCount followers",
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
                  ),
                ],
              ),
            ),
            SizedBox(width: 8),
            _isFollowing
                ? OutlinedButton(
                    onPressed: _toggleFollow,
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      side: BorderSide(color: theme.dividerColor),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                    child: Text("Following", style: TextStyle(color: theme.textTheme.bodyMedium?.color)),
                  )
                : ElevatedButton(
                    onPressed: _toggleFollow,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: TwitterTheme.blue,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                    child: Text("Follow"),
                  ),
          ],
        ),
      ),
    );
  }
}