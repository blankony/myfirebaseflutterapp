// ignore_for_file: prefer_const_constructors
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../widgets/blog_post_card.dart';
import '../../widgets/common_error_widget.dart';
import '../../main.dart';
import '../dashboard/profile_page.dart';
import '../community/community_detail_screen.dart'; // NEW
import '../../services/prediction_service.dart';
import '../../services/overlay_service.dart';
import '../../services/voice_service.dart';

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

class SearchPageState extends State<SearchPage> with TickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final PredictionService _predictionService = PredictionService();
  
  bool _isListening = false;
  
  late TabController _tabController;
  late AnimationController _micAnimController; 
  
  String _searchText = '';
  String? _searchSuggestion;
  Timer? _debounce;
  
  bool _showAllTrending = false;

  @override
  void initState() {
    super.initState();
    // CHANGED length to 3 to include Communities
    _tabController = TabController(length: 3, vsync: this);
    _micAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
      lowerBound: 1.0,
      upperBound: 1.3, 
    );
    
    voiceService.initialize();
  }

  @override
  void didUpdateWidget(SearchPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSearching && !oldWidget.isSearching) {
      _tabController.index = 0;
      Future.delayed(Duration(milliseconds: 100), () {
        if(mounted && widget.isSearching) FocusScope.of(context).requestFocus(_searchFocusNode);
      });
    }
    
    if (oldWidget.isSearching && !widget.isSearching) {
      _searchController.clear();
      _searchText = '';
      _searchSuggestion = null;
      _stopListening();
      FocusScope.of(context).unfocus(); 
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _tabController.dispose();
    _micAnimController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _startListening() async {
    if (voiceService.isListening) {
      await voiceService.stopListening();
    }

    if (_searchFocusNode.hasFocus) {
      _searchFocusNode.unfocus();
      await Future.delayed(const Duration(milliseconds: 200));
    }

    if (!widget.isSearching) {
      widget.onSearchPressed();
    }

    if(mounted) {
      setState(() => _isListening = true);
      _micAnimController.forward();
    }

    voiceService.startListening(
      onListeningStateChanged: (isListening) {},
      onResult: (text) {
        if (!mounted) return;
        
        String finalQuery = text;
        String lowerQuery = finalQuery.toLowerCase();
        
        if (lowerQuery.startsWith("cari ")) finalQuery = finalQuery.substring(5);
        else if (lowerQuery.startsWith("search for ")) finalQuery = finalQuery.substring(11);
        else if (lowerQuery.startsWith("buka ")) finalQuery = finalQuery.substring(5);

        if (lowerQuery.contains("profil") || lowerQuery.contains("user")) {
          _tabController.animateTo(1); 
        } else if (lowerQuery.contains("komunitas") || lowerQuery.contains("community")) {
          _tabController.animateTo(2); 
        } else {
          _tabController.animateTo(0); 
        }

        _searchController.text = finalQuery;
        _searchController.selection = TextSelection.fromPosition(TextPosition(offset: finalQuery.length));
        _onSearchChanged(finalQuery);
      },
    );
  }

  void _stopListening() {
    if(mounted) {
      _micAnimController.reverse();
      setState(() => _isListening = false);
    }
    voiceService.stopListening();
  }

  void _onSearchChanged(String value) {
    setState(() {
      _searchText = value.toLowerCase().trim();
      _searchSuggestion = null;
    });

    if (_debounce?.isActive ?? false) _debounce!.cancel();

    _debounce = Timer(const Duration(milliseconds: 300), () async { 
      if (value.trim().isEmpty) return;
      final suggestion = await _predictionService.getLocalPrediction(value);
      if (mounted && suggestion != null && suggestion.toLowerCase() != _searchText) {
        setState(() { _searchSuggestion = suggestion; });
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
    if (_isListening) _stopListening();
    if (widget.isSearching) widget.onSearchPressed();
  }

  void _onTrendingTagClicked(String tag) {
    final query = tag.startsWith('#') ? tag : tag;
    setState(() {
      _searchController.text = query;
      _searchText = query.toLowerCase();
      if (!widget.isSearching) widget.onSearchPressed();
    });
    FocusScope.of(context).unfocus();
  }

  Future<List<DocumentSnapshot>> _getSuggestedUsers(String? currentUserId) async {
    if (currentUserId == null) return [];
    try {
      final currentUserDoc = await _firestore.collection('users').doc(currentUserId).get();
      if (!currentUserDoc.exists) return [];
      final currentUserData = currentUserDoc.data() as Map<String, dynamic>;
      final List<dynamic> following = currentUserData['following'] ?? [];

      Set<String> suggestedUserIds = {};
      if (following.isNotEmpty) {
        for (String followedUserId in following) {
          final followedUserDoc = await _firestore.collection('users').doc(followedUserId).get();
          if (followedUserDoc.exists) {
            final followedUserData = followedUserDoc.data() as Map<String, dynamic>;
            final List<dynamic> theirFollowing = followedUserData['following'] ?? [];
            for (String potentialFriend in theirFollowing) {
              if (potentialFriend != currentUserId && !following.contains(potentialFriend)) {
                suggestedUserIds.add(potentialFriend);
              }
            }
          }
        }
      }
      if (suggestedUserIds.isNotEmpty) {
        List<DocumentSnapshot> suggestions = [];
        for (String userId in suggestedUserIds.take(5)) {
          final userDoc = await _firestore.collection('users').doc(userId).get();
          if (userDoc.exists) suggestions.add(userDoc);
        }
        return suggestions;
      }
      final allUsersSnapshot = await _firestore.collection('users').limit(20).get();
      final randomUsers = allUsersSnapshot.docs.where((doc) => doc.id != currentUserId && !following.contains(doc.id)).toList();
      randomUsers.shuffle();
      return randomUsers.take(5).toList();
    } catch (e) { return []; }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final theme = Theme.of(context);
    
    final double searchBarBaseHeight = 70.0;
    final double suggestionHeight = _searchSuggestion != null ? 30.0 : 0.0;
    final double currentSearchBarHeight = widget.isSearching ? (searchBarBaseHeight + suggestionHeight) : 0.0;
    final double topAnchor = 90.0;
    final double contentTopPadding = widget.isSearching ? (topAnchor + currentSearchBarHeight) : topAnchor;

    return WillPopScope(
      onWillPop: () async {
        if (widget.isSearching) {
          _clearSearch();
          return false; 
        }
        return true; 
      },
      child: Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.only(top: contentTopPadding),
              child: _searchText.isEmpty && !widget.isSearching
                  ? _buildExplorePage(theme)
                  : _buildSearchResults(theme),
            ),
          ),
          Positioned(
            top: topAnchor,
            left: 0, right: 0,
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
                    child: widget.isSearching 
                        ? SingleChildScrollView(
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
                                      readOnly: _isListening, 
                                      decoration: InputDecoration(
                                        hintText: _isListening ? 'Listening...' : 'Search PNJ...',
                                        hintStyle: TextStyle(
                                          color: _isListening ? TwitterTheme.blue : theme.hintColor,
                                          fontStyle: _isListening ? FontStyle.italic : FontStyle.normal,
                                          fontWeight: _isListening ? FontWeight.bold : FontWeight.normal,
                                        ),
                                        prefixIcon: Icon(Icons.search),
                                        suffixIcon: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (_searchController.text.isNotEmpty)
                                              IconButton(icon: Icon(Icons.clear), onPressed: _clearSearch),
                                            
                                            Listener(
                                              onPointerDown: (details) => _startListening(),
                                              onPointerUp: (details) => _stopListening(),
                                              onPointerCancel: (details) => _stopListening(),
                                              child: Padding(
                                                padding: const EdgeInsets.only(right: 12.0, left: 4.0),
                                                child: ScaleTransition(
                                                  scale: _micAnimController,
                                                  child: Container(
                                                    padding: EdgeInsets.all(8),
                                                    decoration: BoxDecoration(
                                                      shape: BoxShape.circle,
                                                      color: _isListening ? Colors.red : Colors.transparent,
                                                      boxShadow: _isListening ? [
                                                        BoxShadow(color: Colors.red.withOpacity(0.4), blurRadius: 10, spreadRadius: 2)
                                                      ] : null,
                                                    ),
                                                    child: Icon(
                                                      _isListening ? Icons.mic : Icons.mic_none,
                                                      color: _isListening ? Colors.white : theme.primaryColor,
                                                      size: 24,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
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
                                                  TextSpan(text: _searchSuggestion, style: TextStyle(fontWeight: FontWeight.bold, color: TwitterTheme.blue)),
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
                          )
                        : SizedBox.shrink(),
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
    return RefreshIndicator(
      notificationPredicate: (notification) => !_isListening,
      onRefresh: () async {
        setState(() {}); 
        await Future.delayed(Duration(seconds: 1));
      },
      child: SingleChildScrollView(
        physics: _isListening 
            ? NeverScrollableScrollPhysics() 
            : AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(bottom: 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  Icon(Icons.trending_up, color: TwitterTheme.blue),
                  SizedBox(width: 8),
                  Text("Trending at PNJ", style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                ],
              ),
            ),
            
            StreamBuilder<QuerySnapshot>(
              stream: _firestore.collection('posts').orderBy('timestamp', descending: true).limit(100).snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) return Padding(padding: EdgeInsets.all(16), child: Text("Unable to load trends"));
                if (!snapshot.hasData) return SizedBox(height: 100, child: Center(child: CircularProgressIndicator()));

                final allPosts = snapshot.data!.docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  return (data['visibility'] ?? 'public') == 'public';
                }).toList();

                final trends = _predictionService.analyzeTrendingTopics(allPosts);

                if (trends.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Text("No trending topics yet.", style: TextStyle(color: Colors.grey)),
                  );
                }

                final maxItems = _showAllTrending ? 10 : 3;
                final displayedTrends = trends.take(maxItems).toList();
                final canExpand = trends.length > 3;

                return Column(
                  children: [
                    ListView.separated(
                      shrinkWrap: true,
                      physics: NeverScrollableScrollPhysics(),
                      padding: EdgeInsets.zero,
                      itemCount: displayedTrends.length,
                      separatorBuilder: (context, index) => Divider(height: 1, thickness: 0.5, color: theme.dividerColor.withOpacity(0.3)),
                      itemBuilder: (context, index) {
                        final tag = displayedTrends[index]['tag'];
                        final count = displayedTrends[index]['count'];
                        final isHashtag = tag.toString().startsWith('#');
                        final isTopTrending = index == 0;
                        
                        return ListTile(
                          dense: false,
                          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          leading: Text("${index + 1}", style: TextStyle(color: theme.hintColor, fontWeight: FontWeight.bold, fontSize: 16)),
                          title: Text(tag, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isHashtag ? TwitterTheme.blue : theme.textTheme.bodyLarge?.color)),
                          subtitle: Text("$count distinct posts"),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isTopTrending) Padding(padding: const EdgeInsets.only(right: 8.0), child: Icon(Icons.local_fire_department, color: Colors.orange, size: 20)),
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
                              Text(_showAllTrending ? "Show less" : "Show more", style: TextStyle(color: TwitterTheme.blue, fontWeight: FontWeight.bold)),
                              Icon(_showAllTrending ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: TwitterTheme.blue, size: 16)
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),

            Divider(thickness: 8, color: theme.dividerColor.withOpacity(0.1)),

            // --- NEW: RECOMMENDED COMMUNITIES SECTION ---
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Icon(Icons.groups_outlined, color: Colors.orange),
                  SizedBox(width: 8),
                  Text("Communities for You", style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                ],
              ),
            ),

            StreamBuilder<DocumentSnapshot>(
              stream: _auth.currentUser != null ? _firestore.collection('users').doc(_auth.currentUser!.uid).snapshots() : null,
              builder: (context, userSnapshot) {
                List<dynamic> followingList = [];
                if (userSnapshot.hasData && userSnapshot.data!.exists) {
                  final uData = userSnapshot.data!.data() as Map<String, dynamic>;
                  followingList = uData['following'] ?? [];
                }

                return StreamBuilder<QuerySnapshot>(
                  stream: _firestore.collection('communities').limit(50).snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) return Padding(padding: EdgeInsets.all(16), child: Text("Error loading communities"));
                    if (!snapshot.hasData) return Center(child: CircularProgressIndicator());

                    final allCommunities = snapshot.data!.docs;
                    
                    final recommended = _predictionService.getRecommendedCommunities(
                      allCommunities, 
                      _auth.currentUser?.uid ?? '', 
                      followingList
                    );

                    if (recommended.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Text("No new communities to recommend right now.", style: TextStyle(color: Colors.grey)),
                      );
                    }

                    return SizedBox(
                      height: 160,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        itemCount: recommended.length > 10 ? 10 : recommended.length,
                        itemBuilder: (context, index) {
                          final doc = recommended[index];
                          final data = doc.data() as Map<String, dynamic>;
                          final name = data['name'] ?? 'Community';
                          final imageUrl = data['imageUrl'];
                          final membersCount = (data['followers'] as List?)?.length ?? 0;

                          return Container(
                            width: 140,
                            margin: EdgeInsets.all(4),
                            child: Card(
                              elevation: 2,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () {
                                  Navigator.push(context, MaterialPageRoute(
                                    builder: (_) => CommunityDetailScreen(communityId: doc.id, communityData: data)
                                  ));
                                },
                                child: Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      CircleAvatar(
                                        radius: 28,
                                        backgroundColor: TwitterTheme.blue.withOpacity(0.1),
                                        backgroundImage: imageUrl != null ? CachedNetworkImageProvider(imageUrl) : null,
                                        child: imageUrl == null ? Text(name[0].toUpperCase(), style: TextStyle(fontWeight: FontWeight.bold, color: TwitterTheme.blue)) : null,
                                      ),
                                      SizedBox(height: 8),
                                      Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.bold)),
                                      Text("$membersCount members", style: TextStyle(fontSize: 11, color: Colors.grey)),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  }
                );
              }
            ),

            Divider(thickness: 8, color: theme.dividerColor.withOpacity(0.1)),

            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Icon(Icons.explore_outlined, color: Colors.purple),
                  SizedBox(width: 8),
                  Text("Discover For You", style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                ],
              ),
            ),

            StreamBuilder<DocumentSnapshot>(
              stream: _auth.currentUser != null ? _firestore.collection('users').doc(_auth.currentUser!.uid).snapshots() : null,
              builder: (context, userSnapshot) {
                List<dynamic> followingList = [];
                if (userSnapshot.hasData && userSnapshot.data!.exists) {
                  final uData = userSnapshot.data!.data() as Map<String, dynamic>;
                  followingList = uData['following'] ?? [];
                }

                return StreamBuilder<QuerySnapshot>(
                  stream: _firestore.collection('posts').orderBy('timestamp', descending: true).limit(50).snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) return Padding(padding: EdgeInsets.all(16), child: CommonErrorWidget(message: "Couldn't load discovery.", isConnectionError: true));
                    if (!snapshot.hasData) return Center(child: CircularProgressIndicator());
                    
                    final publicPosts = snapshot.data!.docs.where((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      return (data['visibility'] ?? 'public') == 'public';
                    }).toList();

                    final discoverDocs = _predictionService.getDiscoverRecommendations(
                      publicPosts, 
                      _auth.currentUser?.uid ?? '',
                      followingList,
                    );

                    if (discoverDocs.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 32.0),
                        child: Center(child: Text("No new discoveries. Follow more people to help us learn!")),
                      );
                    }

                    final displayedPosts = discoverDocs.take(10).toList();

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ...displayedPosts.map((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          return BlogPostCard(
                            postId: doc.id,
                            postData: data,
                            isOwner: false,
                            heroContextId: 'discover',
                          );
                        }).toList(),
                      ],
                    );
                  },
                );
              }
            ),

            Divider(thickness: 8, color: theme.dividerColor.withOpacity(0.1)),

            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Icon(Icons.person_add_alt_1_outlined, color: Colors.blueAccent),
                  SizedBox(width: 8),
                  Text("People You Might Know", style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                ],
              ),
            ),

            FutureBuilder<List<DocumentSnapshot>>(
              future: _getSuggestedUsers(_auth.currentUser?.uid),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()));
                if (snapshot.hasError) return Padding(padding: EdgeInsets.all(16), child: Text("Couldn't load suggestions (Offline)."));
                if (!snapshot.hasData || snapshot.data!.isEmpty) return Padding(padding: const EdgeInsets.all(16.0), child: Text("No suggestions available right now."));
                return Column(
                  children: snapshot.data!.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    return _UserSearchTile(userId: doc.id, userData: data, currentUserId: _auth.currentUser?.uid);
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
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: theme.dividerColor))),
          child: TabBar(
            controller: _tabController,
            labelColor: theme.primaryColor,
            unselectedLabelColor: theme.hintColor,
            indicatorColor: theme.primaryColor,
            tabs: const [Tab(text: 'Posts'), Tab(text: 'Users'), Tab(text: 'Communities')], // Added Tab
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [_buildPostResults(), _buildUserResults(), _buildCommunityResults()], // Added View
          ),
        ),
      ],
    );
  }

  // --- EXISTING POST & USER RESULTS METHODS (UNCHANGED) ---
  Widget _buildPostResults() {
    final currentUserId = _auth.currentUser?.uid;
    return StreamBuilder<DocumentSnapshot>(
      stream: currentUserId != null ? _firestore.collection('users').doc(currentUserId).snapshots() : null,
      builder: (context, userSnapshot) {
        List<dynamic> followingList = [];
        if (userSnapshot.hasData && userSnapshot.data!.exists) {
          final uData = userSnapshot.data!.data() as Map<String, dynamic>;
          followingList = uData['following'] ?? [];
        }
        return StreamBuilder<QuerySnapshot>(
          stream: _firestore.collection('posts').orderBy('timestamp', descending: true).limit(100).snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) return CommonErrorWidget(message: "Search failed.", isConnectionError: true);
            if (snapshot.connectionState == ConnectionState.waiting) return Center(child: CircularProgressIndicator());
            final docs = snapshot.data?.docs.where((doc) {
              final data = doc.data() as Map<String, dynamic>;
              final text = (data['text'] ?? '').toString().toLowerCase();
              final visibility = data['visibility'] ?? 'public';
              final ownerId = data['userId'];
              bool isVisible = false;
              if (visibility == 'public') isVisible = true;
              else if (visibility == 'followers') {
                if (ownerId == currentUserId || followingList.contains(ownerId)) isVisible = true;
              } else if (visibility == 'private') {
                if (ownerId == currentUserId) isVisible = true;
              }
              return isVisible && text.contains(_searchText);
            }).toList() ?? [];
            if (docs.isEmpty) return Center(child: Text('No posts found for "$_searchText"'));
            return ListView.builder(
              padding: EdgeInsets.only(bottom: 100),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              itemCount: docs.length,
              itemBuilder: (context, index) {
                final data = docs[index].data() as Map<String, dynamic>;
                return BlogPostCard(postId: docs[index].id, postData: data, isOwner: data['userId'] == currentUserId, heroContextId: 'search_results');
              },
            );
          },
        );
      }
    );
  }

  Widget _buildUserResults() {
    final myUid = _auth.currentUser?.uid;
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('users').limit(100).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return CommonErrorWidget(message: "User search failed.", isConnectionError: true);
        if (snapshot.connectionState == ConnectionState.waiting) return Center(child: CircularProgressIndicator());
        final docs = snapshot.data?.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final name = (data['name'] ?? '').toString().toLowerCase();
          final email = (data['email'] ?? '').toString().toLowerCase();
          return name.contains(_searchText) || email.contains(_searchText);
        }).toList() ?? [];
        if (docs.isEmpty) return Center(child: Text('No users found for "$_searchText"'));
        return ListView.builder(
          padding: EdgeInsets.only(bottom: 100),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            final userId = docs[index].id;
            if (userId == myUid) return SizedBox.shrink();
            return _UserSearchTile(userId: userId, userData: data, currentUserId: myUid);
          },
        );
      },
    );
  }

  // --- NEW: COMMUNITY RESULTS ---
  Widget _buildCommunityResults() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('communities').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return CommonErrorWidget(message: "Search failed.", isConnectionError: true);
        if (snapshot.connectionState == ConnectionState.waiting) return Center(child: CircularProgressIndicator());

        final docs = snapshot.data?.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final name = (data['name'] ?? '').toString().toLowerCase();
          final desc = (data['description'] ?? '').toString().toLowerCase();
          return name.contains(_searchText) || desc.contains(_searchText);
        }).toList() ?? [];

        if (docs.isEmpty) return Center(child: Text('No communities found for "$_searchText"'));

        return ListView.builder(
          padding: EdgeInsets.only(bottom: 100),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data() as Map<String, dynamic>;
            final String name = data['name'] ?? 'Community';
            final String? imageUrl = data['imageUrl'];
            final int memberCount = (data['followers'] as List?)?.length ?? 0;

            return ListTile(
              leading: CircleAvatar(
                backgroundImage: imageUrl != null ? CachedNetworkImageProvider(imageUrl) : null,
                backgroundColor: TwitterTheme.blue.withOpacity(0.1),
                child: imageUrl == null ? Icon(Icons.groups, color: TwitterTheme.blue) : null,
              ),
              title: Text(name, style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text("$memberCount members"),
              trailing: Icon(Icons.arrow_forward_ios, size: 14),
              onTap: () {
                Navigator.push(context, MaterialPageRoute(
                  builder: (_) => CommunityDetailScreen(communityId: doc.id, communityData: data)
                ));
              },
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
  const _UserSearchTile({required this.userId, required this.userData, this.currentUserId});
  @override State<_UserSearchTile> createState() => _UserSearchTileState();
}

class _UserSearchTileState extends State<_UserSearchTile> {
  bool _isFollowing = false;
  @override void initState() { super.initState(); _checkFollowStatus(); }
  @override void didUpdateWidget(covariant _UserSearchTile oldWidget) { super.didUpdateWidget(oldWidget); if (widget.userData != oldWidget.userData) _checkFollowStatus(); }
  void _checkFollowStatus() {
    if (widget.currentUserId == null) return;
    final followers = List<dynamic>.from(widget.userData['followers'] ?? []);
    setState(() { _isFollowing = followers.contains(widget.currentUserId); });
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
        'type': 'follow', 'senderId': widget.currentUserId, 'timestamp': FieldValue.serverTimestamp(), 'isRead': false,
      });
      setState(() => _isFollowing = true);
    }
    try { await batch.commit(); } catch (e) { _checkFollowStatus(); if (mounted) OverlayService().showTopNotification(context, "Action failed: $e", Icons.error, (){}, color: Colors.red); }
  }
  @override Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = widget.userData['name'] ?? 'User';
    final email = widget.userData['email'] ?? '';
    final handle = email.isNotEmpty ? "@${email.split('@')[0]}" : "";
    final followersCount = (widget.userData['followers'] as List?)?.length ?? 0;
    final int iconId = widget.userData['avatarIconId'] ?? 0;
    final String? colorHex = widget.userData['avatarHex'];
    final String? profileImageUrl = widget.userData['profileImageUrl'];

    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProfilePage(userId: widget.userId, includeScaffold: true))),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(radius: 24, backgroundColor: profileImageUrl != null ? Colors.transparent : AvatarHelper.getColor(colorHex), backgroundImage: profileImageUrl != null ? CachedNetworkImageProvider(profileImageUrl) : null, child: profileImageUrl == null ? Icon(AvatarHelper.getIcon(iconId), size: 24, color: Colors.white) : null),
            SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
              Text(handle, style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor)),
              SizedBox(height: 4), Text("$followersCount followers", style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor))
            ])),
            SizedBox(width: 8),
            _isFollowing
              ? OutlinedButton(onPressed: _toggleFollow, style: OutlinedButton.styleFrom(padding: EdgeInsets.symmetric(horizontal: 16), side: BorderSide(color: theme.dividerColor), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))), child: Text("Following", style: TextStyle(color: theme.textTheme.bodyMedium?.color)))
              : ElevatedButton(onPressed: _toggleFollow, style: ElevatedButton.styleFrom(backgroundColor: TwitterTheme.blue, foregroundColor: Colors.white, elevation: 0, padding: EdgeInsets.symmetric(horizontal: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))), child: Text("Follow"))
          ],
        ),
      ),
    );
  }
}