// ignore_for_file: prefer_const_constructors
import 'dart:async'; 
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../widgets/blog_post_card.dart';
import '../../main.dart'; 
import 'profile_page.dart'; // FIXED: Import path dikoreksi (karena satu folder)
import '../../services/prediction_service.dart'; 

final FirebaseAuth _auth = FirebaseAuth.instance;
final FirebaseFirestore _firestore = FirebaseFirestore.instance;

class SearchPage extends StatefulWidget {
  final bool isSearching;
  final VoidCallback onSearchPressed;

  const SearchPage({
    Key? key,
    required this.isSearching,
    required this.onSearchPressed,
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

    // Debounce 600ms
    _debounce = Timer(const Duration(milliseconds: 600), () async {
      if (value.trim().isEmpty) return;
      
      // Service sekarang otomatis handle fallback jika Gemini error/lambat
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
                    
                    // === AI/LOCAL SEARCH SUGGESTION ===
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

  Widget _buildRecommendations(ThemeData theme) {
    return RefreshIndicator(
      onRefresh: () async {
        await Future.delayed(Duration(seconds: 1));
      },
      child: SingleChildScrollView(
        physics: AlwaysScrollableScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Container(
          height: MediaQuery.of(context).size.height * 0.6, 
          alignment: Alignment.center,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.search, size: 64, color: Colors.grey.withOpacity(0.5)),
              SizedBox(height: 16),
              Text(
                'Search for posts or users', 
                style: theme.textTheme.titleMedium?.copyWith(color: Colors.grey)
              ),
            ],
          ),
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
              backgroundColor: theme.cardColor,
              child: Icon(Icons.person, color: theme.primaryColor),
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