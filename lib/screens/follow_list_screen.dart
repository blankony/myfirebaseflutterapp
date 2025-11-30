// ignore_for_file: prefer_const_constructors
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../main.dart'; 
import 'dashboard/profile_page.dart'; 
import '../widgets/common_error_widget.dart'; // REQUIRED

final FirebaseFirestore _firestore = FirebaseFirestore.instance;
final FirebaseAuth _auth = FirebaseAuth.instance;

class FollowListScreen extends StatefulWidget {
  final String userId;
  final int initialIndex;

  const FollowListScreen({
    super.key,
    required this.userId,
    this.initialIndex = 0,
  });

  @override
  State<FollowListScreen> createState() => _FollowListScreenState();
}

class _FollowListScreenState extends State<FollowListScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<String> _followingIds = [];
  List<String> _followersIds = [];
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialIndex,
    );
    _fetchLists();
  }

  Future<void> _fetchLists() async {
    setState(() { _isLoading = true; _hasError = false; });
    try {
      final doc = await _firestore.collection('users').doc(widget.userId).get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        if (mounted) {
          setState(() {
            _followingIds = List<String>.from(data['following'] ?? []);
            _followersIds = List<String>.from(data['followers'] ?? []);
            _isLoading = false;
          });
        }
      } else {
        if (mounted) setState(() { _isLoading = false; });
      }
    } catch (e) {
      debugPrint("Error fetching lists: $e");
      if (mounted) setState(() { _isLoading = false; _hasError = true; });
    }
  }

  // --- CLEANUP LOGIC ---
  // If we detect a user doesn't exist anymore, we remove them from the array
  // so the counts match the actual list next time.
  void _cleanupDeadUser(String deadUserId, String listType) {
    // Only the owner of the profile can clean their own lists
    if (_auth.currentUser?.uid != widget.userId) return;

    final docRef = _firestore.collection('users').doc(widget.userId);
    
    if (listType == 'following') {
      docRef.update({
        'following': FieldValue.arrayRemove([deadUserId])
      });
    } else if (listType == 'followers') {
      docRef.update({
        'followers': FieldValue.arrayRemove([deadUserId])
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  List<String> get _mutualsIds {
    final followingSet = _followingIds.toSet();
    final followersSet = _followersIds.toSet();
    return followingSet.intersection(followersSet).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          "Connections",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: theme.primaryColor,
          unselectedLabelColor: theme.hintColor,
          indicatorColor: theme.primaryColor,
          tabs: const [
            Tab(text: "Mutuals"),
            Tab(text: "Following"),
            Tab(text: "Followers"),
          ],
        ),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : _hasError 
            ? CommonErrorWidget(
                message: "Couldn't load connections.", 
                isConnectionError: true, 
                onRetry: _fetchLists
              )
            : TabBarView(
              controller: _tabController,
              children: [
                _UserList(
                  userIds: _mutualsIds, 
                  emptyMessage: "No mutual followers yet.",
                  // Mutuals are derived, we don't strictly clean up from here to avoid double-writes,
                  // but cleaning following/followers individually handles it.
                  listType: 'mutuals',
                  onDeadUserFound: (id) {}, 
                ),
                _UserList(
                  userIds: _followingIds, 
                  emptyMessage: "Not following anyone yet.",
                  listType: 'following',
                  onDeadUserFound: (id) => _cleanupDeadUser(id, 'following'),
                ),
                _UserList(
                  userIds: _followersIds, 
                  emptyMessage: "No followers yet.",
                  listType: 'followers',
                  onDeadUserFound: (id) => _cleanupDeadUser(id, 'followers'),
                ),
              ],
            ),
    );
  }
}

class _UserList extends StatelessWidget {
  final List<String> userIds;
  final String emptyMessage;
  final String listType;
  final Function(String) onDeadUserFound;

  const _UserList({
    required this.userIds, 
    required this.emptyMessage,
    required this.listType,
    required this.onDeadUserFound,
  });

  @override
  Widget build(BuildContext context) {
    if (userIds.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 64, color: Colors.grey.withOpacity(0.5)),
            SizedBox(height: 16),
            Text(emptyMessage, style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: userIds.length,
      itemBuilder: (context, index) {
        return _UserTile(
          userId: userIds[index], 
          onDeadUser: () => onDeadUserFound(userIds[index])
        );
      },
    );
  }
}

class _UserTile extends StatelessWidget {
  final String userId;
  final VoidCallback onDeadUser;

  const _UserTile({required this.userId, required this.onDeadUser});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentUserId = _auth.currentUser?.uid;

    return FutureBuilder<DocumentSnapshot>(
      future: _firestore.collection('users').doc(userId).get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return SizedBox(height: 60, child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))));
        }
        
        // 1. Check if document exists
        if (!snapshot.hasData || !snapshot.data!.exists) {
          // If not, trigger cleanup
          WidgetsBinding.instance.addPostFrameCallback((_) {
            onDeadUser();
          });
          return SizedBox.shrink(); // Hide the deleted user from the list
        }

        final data = snapshot.data!.data() as Map<String, dynamic>?;
        if (data == null) return SizedBox.shrink();

        final name = data['name'] ?? 'User';
        final email = data['email'] ?? '';
        final handle = email.isNotEmpty ? "@${email.split('@')[0]}" : "";
        final profileImageUrl = data['profileImageUrl'];
        final int iconId = data['avatarIconId'] ?? 0;
        final String? colorHex = data['avatarHex'];

        return InkWell(
          onTap: () {
            Navigator.push(
              context, 
              MaterialPageRoute(
                builder: (_) => ProfilePage(userId: userId, includeScaffold: true)
              )
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            child: Row(
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
                      Text(name, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      Text(handle, style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
} 