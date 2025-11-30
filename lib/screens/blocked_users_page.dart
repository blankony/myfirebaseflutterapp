// ignore_for_file: prefer_const_constructors
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../services/moderation_service.dart';
import '../../main.dart'; // For AvatarHelper and TwitterTheme

class BlockedUsersPage extends StatelessWidget {
  const BlockedUsersPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Blocked Accounts"),
      ),
      body: StreamBuilder<List<String>>(
        stream: moderationService.streamBlockedUsers(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }

          final blockedIds = snapshot.data ?? [];

          if (blockedIds.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.block, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text("You haven't blocked anyone.", style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }

          return ListView.builder(
            itemCount: blockedIds.length,
            itemBuilder: (context, index) {
              final userId = blockedIds[index];
              return FutureBuilder<DocumentSnapshot>(
                future: FirebaseFirestore.instance.collection('users').doc(userId).get(),
                builder: (context, userSnapshot) {
                  if (!userSnapshot.hasData) return SizedBox.shrink();
                  
                  final data = userSnapshot.data!.data() as Map<String, dynamic>? ?? {};
                  final name = data['name'] ?? 'Unknown User';
                  final email = data['email'] ?? '';
                  final handle = email.isNotEmpty ? "@${email.split('@')[0]}" : "";
                  final profileImageUrl = data['profileImageUrl'];
                  final iconId = data['avatarIconId'] ?? 0;
                  final colorHex = data['avatarHex'];

                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: profileImageUrl != null ? Colors.transparent : AvatarHelper.getColor(colorHex),
                      backgroundImage: profileImageUrl != null ? CachedNetworkImageProvider(profileImageUrl) : null,
                      child: profileImageUrl == null ? Icon(AvatarHelper.getIcon(iconId), color: Colors.white, size: 20) : null,
                    ),
                    title: Text(name),
                    subtitle: Text(handle),
                    trailing: OutlinedButton(
                      onPressed: () async {
                        await moderationService.unblockUser(userId);
                      },
                      child: Text("Unblock"),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}