// ignore_for_file: prefer_const_constructors
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../widgets/blog_post_card.dart';
import '../../main.dart';
import 'profile_page.dart';
import '../../services/prediction_service.dart';

final FirebaseAuth _auth = FirebaseAuth.instance;
final FirebaseFirestore _firestore = FirebaseFirestore.instance;

class SearchPage extends StatefulWidget {
  final bool isSearching;
  final VoidCallback onSearchPressed;
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
  
  // State for Trending
  bool _showAllTrending = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void didUpdateWidget(SearchPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Fix: Reset tab to "Posts" (index 0) whenever search is opened
    if (widget.isSearching && !oldWidget.isSearching) {
      _tabController.index = 0;
    }
    
    // FIX: Auto-open search bar when navigating to search page
    if (!oldWidget.isSearching && !widget.isSearching) {
      // This means we just navigated to search page, open search bar
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!widget.isSearching) {
          widget.onSearchPressed();
        }
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _tabController.dispose();
    _debounce?.cancel();
    super.dispose();
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
    
    // FIX: Close search bar when clearing search
    if (widget.isSearching) {
      widget.onSearchPressed();
    }
  }

  void _onTrendingTagClicked(String tag) {
    final query = tag.startsWith('#') ? tag : tag;
    
    setState(() {
      _searchController.text = query;
      _searchText = query.toLowerCase();
      
      if (!widget.isSearching) {
        widget.onSearchPressed();
      }
    });
    
    FocusScope.of(context).unfocus();
  }

  // Get suggested users based on mutual connections or random
  Future<List<DocumentSnapshot>> _getSuggestedUsers(String? currentUserId) async {
    if (currentUserId == null) return [];

    try {
      // Get current user's data
      final currentUserDoc = await _firestore.collection('users').doc(currentUserId).get();
      if (!currentUserDoc.exists) return [];

      final currentUserData = currentUserDoc.data() as Map<String, dynamic>;
      final List<dynamic> following = currentUserData['following'] ?? [];

      Set<String> suggestedUserIds = {};
      
      // If user follows people, get friends of friends
      if (following.isNotEmpty) {
        for (String followedUserId in following) {
          final followedUserDoc = await _firestore.collection('users').doc(followedUserId).get();
          if (followedUserDoc.exists) {
            final followedUserData = followedUserDoc.data() as Map<String, dynamic>;
            final List<dynamic> theirFollowing = followedUserData['following'] ?? [];
            
            // Add their friends (excluding current user and already following)
            for (String potentialFriend in theirFollowing) {
              if (potentialFriend != currentUserId && !following.contains(potentialFriend)) {
                suggestedUserIds.add(potentialFriend);
              }
            }
          }
        }
      }

      // If we have suggestions from mutual connections, fetch them
      if (suggestedUserIds.isNotEmpty) {
        List<DocumentSnapshot> suggestions = [];
        for (String userId in suggestedUserIds.take(5)) {
          final userDoc = await _firestore.collection('users').doc(userId).get();
          if (userDoc.exists) {
            suggestions.add(userDoc);
          }
        }
        return suggestions;
      }

      // Otherwise, return random users
      final allUsersSnapshot = await _firestore.collection('users').limit(20).get();
      final randomUsers = allUsersSnapshot.docs
          .where((doc) => doc.id != currentUserId && !following.contains(doc.id))
          .toList();
      
      randomUsers.shuffle();
      return randomUsers.take(5).toList();

    } catch (e) {
      print('Error getting suggested users: $e');
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final theme = Theme.of(context);
    
    // Layout Constants
    final double searchBarBaseHeight = 70.0;
    final double suggestionHeight = _searchSuggestion != null ? 30.0 : 0.0;
    final double currentSearchBarHeight = widget.isSearching ? (searchBarBaseHeight + suggestionHeight) : 0.0;
    
    // FIX: Use a fixed value that matches your app bar
    final double topAnchor = 90.0;

    // FIX: Content padding is consistent with small gap below
    final double contentTopPadding = widget.isSearching 
        ? (topAnchor + currentSearchBarHeight) 
        : topAnchor;

    // FIX: Handle back button to close search bar
    return WillPopScope(
      onWillPop: () async {
        if (widget.isSearching) {
          // Clear search and close search bar
          setState(() {
            _searchController.clear();
            _searchText = '';
            _searchSuggestion = null;
          });
          widget.onSearchPressed(); // Close search bar
          return false; // Don't pop the route
        }
        return true; // Allow back navigation
      },
      child: Stack(
        children: [
          // --- 1. MAIN CONTENT LAYER ---
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.only(top: contentTopPadding),
              child: _searchText.isEmpty && !widget.isSearching
                  ? _buildExplorePage(theme)
                  : _buildSearchResults(theme),
            ),
          ),

          // --- 2. SEARCH BAR LAYER (Overlay) ---
          Positioned(
            top: topAnchor,
            left: 0,
            right: 0,
            child: Align(
              alignment: Alignment.topRight,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeInOutQuart,
                width: widget.isSearching ? screenWidth : 0,
                height: currentSearchBarHeight,
                child: ClipRRect(
                  borderRadius: BorderRadius.only(bottomLeft: Radius.circular(20)),
                  child: Container(
                    color: theme.scaffoldBackgroundColor,
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
                                  hintText: 'Search for posts, or users...',
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
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExplorePage(ThemeData theme) {
    final user = _auth.currentUser;

    return RefreshIndicator(
      onRefresh: () async {
        setState(() {}); 
        await Future.delayed(Duration(seconds: 1));
      },
      child: SingleChildScrollView(
        physics: AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(bottom: 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- TRENDING SECTION ---
            // FIX: Reduced bottom padding for tighter spacing
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  Icon(Icons.trending_up, color: TwitterTheme.blue),
                  SizedBox(width: 8),
                  Text(
                    "Trending at PNJ",
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                  ),
                ],
              ),
            ),
            
            StreamBuilder<QuerySnapshot>(
              stream: _firestore.collection('posts').orderBy('timestamp', descending: true).limit(100).snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return SizedBox(height: 100, child: Center(child: CircularProgressIndicator()));

                final allPosts = snapshot.data!.docs;
                final trends = _predictionService.analyzeTrendingTopics(allPosts);

                if (trends.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Text("No trending topics yet.", style: TextStyle(color: Colors.grey)),
                  );
                }

                final maxItems = _showAllTrending ? 10 : 3;
                final displayCount = trends.length.clamp(0, maxItems);
                final displayedTrends = trends.take(displayCount).toList();
                final canExpand = trends.length > 3;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // FIX: Added padding: EdgeInsets.zero to remove ListView default padding
                    ListView.separated(
                      shrinkWrap: true,
                      physics: NeverScrollableScrollPhysics(),
                      padding: EdgeInsets.zero,
                      itemCount: displayedTrends.length,
                      separatorBuilder: (context, index) => Divider(
                        height: 1,
                        thickness: 0.5,
                        color: theme.dividerColor.withOpacity(0.3), // FIX: Subtle divider
                      ),
                      itemBuilder: (context, index) {
                        final tag = displayedTrends[index]['tag'];
                        final count = displayedTrends[index]['count'];
                        final isHashtag = tag.toString().startsWith('#');
                        final isTopTrending = index == 0; // FIX: Check if #1 trending
                        
                        // FIX: Added contentPadding to control ListTile spacing
                        return ListTile(
                          dense: false,
                          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          leading: Text(
                            "${index + 1}",
                            style: TextStyle(color: theme.hintColor, fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          title: Text(
                            tag,
                            style: TextStyle(
                              fontWeight: FontWeight.bold, 
                              fontSize: 16,
                              color: isHashtag ? TwitterTheme.blue : theme.textTheme.bodyLarge?.color
                            ),
                          ),
                          subtitle: Text("$count buzzing interactions"),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // FIX: Add fire icon for top trending
                              if (isTopTrending)
                                Padding(
                                  padding: const EdgeInsets.only(right: 8.0),
                                  child: Icon(Icons.local_fire_department, color: Colors.orange, size: 20),
                                ),
                              Icon(Icons.arrow_forward_ios, size: 14, color: theme.hintColor),
                            ],
                          ),
                          onTap: () => _onTrendingTagClicked(tag),
                        );
                      },
                    ),
                    
                    if (canExpand)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                        child: InkWell(
                          onTap: () => setState(() => _showAllTrending = !_showAllTrending),
                          child: Row(
                            children: [
                              Text(
                                _showAllTrending ? "Show less" : "Show more",
                                style: TextStyle(color: TwitterTheme.blue, fontWeight: FontWeight.bold),
                              ),
                              Icon(
                                _showAllTrending ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                                color: TwitterTheme.blue,
                                size: 16,
                              )
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),

            Divider(thickness: 8, color: theme.dividerColor.withOpacity(0.1)), // FIX: More subtle thick divider

            // --- DISCOVER SECTION (PERSONALIZED) ---
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Icon(Icons.explore_outlined, color: Colors.purple),
                  SizedBox(width: 8),
                  Text(
                    "Discover For You",
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                  ),
                ],
              ),
            ),

            StreamBuilder<DocumentSnapshot>(
              stream: user != null ? _firestore.collection('users').doc(user.uid).snapshots() : null,
              builder: (context, userSnapshot) {
                Map<String, dynamic> userProfile = {};
                if (userSnapshot.hasData && userSnapshot.data!.exists) {
                  userProfile = userSnapshot.data!.data() as Map<String, dynamic>;
                }

                return StreamBuilder<QuerySnapshot>(
                  stream: _firestore.collection('posts').orderBy('timestamp', descending: true).limit(50).snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return Center(child: CircularProgressIndicator());
                    
                    final discoverDocs = _predictionService.getPersonalizedRecommendations(
                      snapshot.data!.docs, 
                      userProfile, 
                      user?.uid ?? ''
                    );

                    if (discoverDocs.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 32.0),
                        child: Center(child: Text("No new recommendations. Interact more to personalize!")),
                      );
                    }

                    // FIX: Show only first 10 posts
                    final displayedPosts = discoverDocs.take(10).toList();
                    final hasMore = discoverDocs.length > 10;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Display first 10 posts
                        ...displayedPosts.map((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          
                          return BlogPostCard(
                            postId: doc.id,
                            postData: data,
                            isOwner: false,
                            heroContextId: 'discover',
                          );
                        }).toList(),
                        
                        // Show "See More" button if there are more posts
                        if (hasMore)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
                            child: Center(
                              child: OutlinedButton(
                                onPressed: () {
                                  // TODO: Navigate to full discover page or expand list
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('More posts coming soon!')),
                                  );
                                },
                                style: OutlinedButton.styleFrom(
                                  padding: EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                                  side: BorderSide(color: TwitterTheme.blue),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                ),
                                child: Text(
                                  "See More Recommendations",
                                  style: TextStyle(color: TwitterTheme.blue, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                );
              }
            ),

            Divider(thickness: 8, color: theme.dividerColor.withOpacity(0.1)),

            // --- PEOPLE YOU MIGHT KNOW SECTION ---
            // FIXED: Replaced duplicate "Discover" section with actual User Recommendations
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Icon(Icons.person_add_alt_1_outlined, color: Colors.blueAccent),
                  SizedBox(width: 8),
                  Text(
                    "People You Might Know",
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                  ),
                ],
              ),
            ),

            FutureBuilder<List<DocumentSnapshot>>(
              future: _getSuggestedUsers(user?.uid),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()));
                }
                
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text("No suggestions available right now."),
                  );
                }
                
                return Column(
                  children: snapshot.data!.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    return _UserSearchTile(
                      userId: doc.id,
                      userData: data,
                      currentUserId: user?.uid,
                    );
                  }).toList(),
                );
              }
            ),
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
              heroContextId: 'search_results',
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