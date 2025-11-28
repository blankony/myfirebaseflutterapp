// ignore_for_file: prefer_const_constructors
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import '../screens/post_detail_screen.dart';
import '../screens/dashboard/profile_page.dart';
import '../main.dart';

final FirebaseAuth _auth = FirebaseAuth.instance;
final FirebaseFirestore _firestore = FirebaseFirestore.instance;

class NotificationSheet extends StatefulWidget {
  final ScrollController scrollController;
  const NotificationSheet({super.key, required this.scrollController});

  @override
  State<NotificationSheet> createState() => _NotificationSheetState();
}

class _NotificationSheetState extends State<NotificationSheet> {
  final User? _currentUser = _auth.currentUser;

  @override
  void initState() {
    super.initState();
    _markNotificationsAsRead();
  }

  Future<void> _markNotificationsAsRead() async {
    if (_currentUser == null) return;
    // Batch update unread notifications
    final notifQuery = _firestore
        .collection('users')
        .doc(_currentUser!.uid)
        .collection('notifications')
        .where('isRead', isEqualTo: false);

    final notifSnapshot = await notifQuery.get();
    if (notifSnapshot.docs.isEmpty) return;

    final batch = _firestore.batch();
    for (final doc in notifSnapshot.docs) {
      batch.update(doc.reference, {'isRead': true});
    }
    await batch.commit();
  }

  // --- Date Grouping Helper ---
  String _getGroupLabel(Timestamp timestamp) {
    final now = DateTime.now();
    final date = timestamp.toDate();
    final today = DateTime(now.year, now.month, now.day);
    final notificationDate = DateTime(date.year, date.month, date.day);
    final difference = today.difference(notificationDate).inDays;

    if (difference == 0) {
      // Check if it's very recent (last 1 hour)
      if (now.difference(date).inMinutes < 60) return "New";
      return "Today";
    }
    if (difference == 1) return "Yesterday";
    if (difference < 7) return "This Week";
    return "Earlier";
  }

  @override
  Widget build(BuildContext context) {
    if (_currentUser == null) {
      return Center(child: Text("Please log in."));
    }
    
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // REMOVED DRAG HANDLE (Black Stripe)
          
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 10), 
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Activity",
                  style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: Icon(Icons.check_circle_outline),
                  tooltip: "Mark all read",
                  onPressed: _markNotificationsAsRead,
                )
              ],
            ),
          ),
          
          Divider(height: 1),

          // Notification List with Grouping
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _firestore
                  .collection('users')
                  .doc(_currentUser!.uid)
                  .collection('notifications')
                  .orderBy('timestamp', descending: true)
                  .limit(50)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return Center(child: CircularProgressIndicator());
                }
                final docs = snapshot.data!.docs;
                
                if (docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.notifications_none, size: 64, color: theme.hintColor.withOpacity(0.3)),
                        SizedBox(height: 16),
                        Text("No notifications yet", style: TextStyle(color: theme.hintColor)),
                      ],
                    ),
                  );
                }

                // --- Build Grouped List ---
                List<Widget> listItems = [];
                String? currentGroup;

                for (var doc in docs) {
                  final data = doc.data() as Map<String, dynamic>;
                  final Timestamp? timestamp = data['timestamp'];
                  
                  if (timestamp != null) {
                    String group = _getGroupLabel(timestamp);
                    if (group != currentGroup) {
                      currentGroup = group;
                      listItems.add(
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                          child: Text(
                            group,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold, 
                              color: theme.primaryColor
                            ),
                          ),
                        )
                      );
                    }
                  }

                  final bool isRead = data['isRead'] ?? true;
                  listItems.add(_NotificationTile(notificationData: data, isRead: isRead));
                }

                return ListView(
                  controller: widget.scrollController,
                  children: listItems,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final Map<String, dynamic> notificationData;
  final bool isRead;

  const _NotificationTile({
    required this.notificationData,
    required this.isRead,
  });

  Future<DocumentSnapshot> _getSenderData(String senderId) {
    return _firestore.collection('users').doc(senderId).get();
  }

  void _navigateToTarget(BuildContext context) {
    final String type = notificationData['type'];
    final String? postId = notificationData['postId'];
    final String senderId = notificationData['senderId'];

    Navigator.of(context).pop(); 

    if (type == 'follow') {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ProfilePage(userId: senderId, includeScaffold: true),
      ));
    } else if (postId != null && (type == 'like' || type == 'repost' || type == 'comment')) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PostDetailScreen(postId: postId),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final String senderId = notificationData['senderId'];
    
    // --- SYSTEM NOTIFICATION (Direct Render) ---
    if (senderId == 'system') {
      return _buildSystemTile(context, theme);
    }

    // --- USER NOTIFICATION (Fetch Data) ---
    return FutureBuilder<DocumentSnapshot>(
      future: _getSenderData(senderId),
      builder: (context, snapshot) {
        String name = "Someone";
        String? profileUrl;
        
        if (snapshot.hasData && snapshot.data!.exists) {
          final userData = snapshot.data!.data() as Map<String, dynamic>;
          name = userData['name'] ?? "Unknown";
          profileUrl = userData['profileImageUrl'];
        }

        return _buildUserTile(context, theme, name, profileUrl);
      },
    );
  }

  Widget _buildSystemTile(BuildContext context, ThemeData theme) {
    final String type = notificationData['type'];
    final String text = notificationData['postTextSnippet'] ?? '';
    final Timestamp? timestamp = notificationData['timestamp'];
    
    IconData icon = Icons.info;
    Color color = theme.primaryColor;
    String title = "System Notification";

    if (type == 'upload_complete') {
      icon = Icons.cloud_done;
      color = Colors.green;
      title = "Upload Successful";
    }

    return Container(
      color: isRead ? Colors.transparent : theme.primaryColor.withOpacity(0.05),
      child: ListTile(
        contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.1),
          child: Icon(icon, color: color),
        ),
        title: Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: 4),
            Text(text, maxLines: 2, overflow: TextOverflow.ellipsis),
            if (timestamp != null)
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text(
                  timeago.format(timestamp.toDate()),
                  style: TextStyle(fontSize: 12, color: theme.hintColor),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserTile(BuildContext context, ThemeData theme, String name, String? profileUrl) {
    final String type = notificationData['type'];
    final String snippet = notificationData['postTextSnippet'] ?? '';
    final Timestamp? timestamp = notificationData['timestamp'];

    IconData badgeIcon;
    Color badgeColor;
    String actionText;

    switch (type) {
      case 'like':
        badgeIcon = Icons.favorite;
        badgeColor = Colors.pink;
        actionText = "liked your post";
        break;
      case 'repost':
        badgeIcon = Icons.repeat;
        badgeColor = Colors.green;
        actionText = "reposted your post";
        break;
      case 'comment':
        badgeIcon = Icons.chat_bubble;
        badgeColor = TwitterTheme.blue;
        actionText = "replied to you";
        break;
      case 'follow':
        badgeIcon = Icons.person_add;
        badgeColor = Colors.purple;
        actionText = "followed you";
        break;
      default:
        badgeIcon = Icons.notifications;
        badgeColor = Colors.grey;
        actionText = "interacted with you";
    }

    return InkWell(
      onTap: () => _navigateToTarget(context),
      child: Container(
        color: isRead ? Colors.transparent : theme.primaryColor.withOpacity(0.05),
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: theme.dividerColor,
                  backgroundImage: profileUrl != null ? CachedNetworkImageProvider(profileUrl) : null,
                  child: profileUrl == null ? Icon(Icons.person, color: Colors.white) : null,
                ),
                Positioned(
                  bottom: -2,
                  right: -2,
                  child: Container(
                    padding: EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: badgeColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: theme.scaffoldBackgroundColor, width: 2),
                    ),
                    child: Icon(badgeIcon, size: 12, color: Colors.white),
                  ),
                )
              ],
            ),
            
            SizedBox(width: 16),
            
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    text: TextSpan(
                      style: theme.textTheme.bodyMedium,
                      children: [
                        TextSpan(
                          text: name,
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        TextSpan(text: " $actionText"),
                      ],
                    ),
                  ),
                  if (snippet.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Text(
                        snippet,
                        style: TextStyle(color: theme.hintColor),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  if (timestamp != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Text(
                        timeago.format(timestamp.toDate()),
                        style: TextStyle(color: theme.hintColor, fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}