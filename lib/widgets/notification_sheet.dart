// ignore_for_file: prefer_const_constructors
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../screens/post_detail_screen.dart';
import '../screens/user_profile_screen.dart';
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

    final notifQuery = _firestore
        .collection('users')
        .doc(_currentUser!.uid)
        .collection('notifications')
        .where('isRead', isEqualTo: false);
    
    final notifSnapshot = await notifQuery.get();
    
    final batch = _firestore.batch();
    for (final doc in notifSnapshot.docs) {
      batch.update(doc.reference, {'isRead': true});
    }
    await batch.commit();
  }

  @override
  Widget build(BuildContext context) {
    if (_currentUser == null) {
      return Center(child: Text("Please log in."));
    }

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
         borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      padding: EdgeInsets.only(top: 16),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.grey[600],
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          SizedBox(height: 16),
          Text(
            "Notifications",
            style: Theme.of(context).textTheme.titleLarge,
          ),
          SizedBox(height: 8),
          Divider(height: 1),
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
                if (snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text("You have no notifications yet."),
                    ),
                  );
                }

                return ListView.builder(
                  controller: widget.scrollController, 
                  itemCount: snapshot.data!.docs.length,
                  itemBuilder: (context, index) {
                    final data = snapshot.data!.docs[index].data() as Map<String, dynamic>;
                    return _NotificationTile(notificationData: data);
                  },
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
  
  const _NotificationTile({required this.notificationData});

  Future<DocumentSnapshot> _getSenderData(String senderId) {
    return _firestore.collection('users').doc(senderId).get();
  }

  void _navigateToNotification(BuildContext context) {
    final String type = notificationData['type'];
    
    Navigator.of(context).pop(); 

    if (type == 'follow') {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => UserProfileScreen(userId: notificationData['senderId']),
      ));
    } else if (type == 'like' || type == 'repost' || type == 'comment') {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PostDetailScreen(postId: notificationData['postId']),
      ));
    }
  }

  String _formatTimestamp(Timestamp? timestamp) {
    if (timestamp == null) return "just now";
    return timeago.format(timestamp.toDate(), locale: 'en_short');
  }

  @override
  Widget build(BuildContext context) {
    final String type = notificationData['type'];
    final String senderId = notificationData['senderId'];
    final Timestamp? timestamp = notificationData['timestamp'];
    
    IconData iconData;
    Color iconColor;

    switch (type) {
      case 'follow':
        iconData = Icons.person_add;
        iconColor = TwitterTheme.blue;
        break;
      case 'like':
        iconData = Icons.favorite;
        iconColor = Colors.pink;
        break;
      case 'repost':
        iconData = Icons.repeat;
        iconColor = Colors.green;
        break;
      case 'comment':
        iconData = Icons.chat_bubble;
        iconColor = Colors.grey; 
        break;
      default:
        iconData = Icons.notifications;
        iconColor = Colors.grey;
    }

    return FutureBuilder<DocumentSnapshot>(
      future: _getSenderData(senderId),
      builder: (context, userSnapshot) {
        String senderName = 'Someone';
        String senderInitial = 'S';
        if (userSnapshot.hasData && userSnapshot.data!.exists) {
          final data = userSnapshot.data!.data() as Map<String, dynamic>;
          senderName = data['name'] ?? 'Anonymous';
          if (senderName.isNotEmpty) {
            senderInitial = senderName[0].toUpperCase();
          }
        }
        
        String title = '';
        String subtitle = '';

        if(type == 'follow') {
          title = '$senderName started following you';
        } else if (type == 'like') {
          title = '$senderName liked your post';
          subtitle = notificationData['postTextSnippet'] ?? '';
        } else if (type == 'repost') {
          title = '$senderName reposted your post';
          subtitle = notificationData['postTextSnippet'] ?? '';
        } else if (type == 'comment') {
          title = '$senderName replied to your post';
          subtitle = notificationData['postTextSnippet'] ?? '';
        }

        return ListTile(
          leading: Stack(
            children: [
              CircleAvatar(
                child: Text(senderInitial),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  padding: EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: iconColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 2)
                  ),
                  child: Icon(iconData, size: 12, color: Colors.white),
                ),
              )
            ],
          ),
          title: Text(title, style: TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text(
            subtitle.isNotEmpty ? '$subtitle\n${_formatTimestamp(timestamp)}' : _formatTimestamp(timestamp),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          isThreeLine: subtitle.isNotEmpty,
          onTap: () => _navigateToNotification(context),
        );
      },
    );
  }
}