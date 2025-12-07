// ignore_for_file: prefer_const_constructors
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../services/overlay_service.dart';
import '../../main.dart';

class CommunitySettingsScreen extends StatefulWidget {
  final String communityId;
  final Map<String, dynamic> communityData;
  final bool isOwner;
  final bool isAdmin;

  const CommunitySettingsScreen({
    super.key,
    required this.communityId,
    required this.communityData,
    required this.isOwner,
    required this.isAdmin,
  });

  @override
  State<CommunitySettingsScreen> createState() => _CommunitySettingsScreenState();
}

class _CommunitySettingsScreenState extends State<CommunitySettingsScreen> {
  // Roles Logic Helper
  Future<void> _updateRole(String targetUid, String action) async {
    final docRef = FirebaseFirestore.instance.collection('communities').doc(widget.communityId);
    
    try {
      if (action == 'promote') {
        await docRef.update({'admins': FieldValue.arrayUnion([targetUid])});
        OverlayService().showTopNotification(context, "User promoted to Admin", Icons.check_circle, (){});
      } else if (action == 'demote') {
        await docRef.update({'admins': FieldValue.arrayRemove([targetUid])});
        OverlayService().showTopNotification(context, "User demoted to Member", Icons.arrow_downward, (){});
      } else if (action == 'kick') {
        // Hapus dari members dan admins
        final batch = FirebaseFirestore.instance.batch();
        batch.update(docRef, {'members': FieldValue.arrayRemove([targetUid])});
        batch.update(docRef, {'admins': FieldValue.arrayRemove([targetUid])});
        await batch.commit();
        OverlayService().showTopNotification(context, "User kicked from community", Icons.remove_circle, (){}, color: Colors.red);
      }
      setState(() {}); // Refresh UI
    } catch (e) {
      OverlayService().showTopNotification(context, "Action failed", Icons.error, (){}, color: Colors.red);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ownerId = widget.communityData['ownerId'];
    
    return Scaffold(
      appBar: AppBar(title: Text("Community Settings")),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('communities').doc(widget.communityId).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return Center(child: CircularProgressIndicator());
          
          final data = snapshot.data!.data() as Map<String, dynamic>;
          final List members = data['members'] ?? [];
          final List admins = data['admins'] ?? [];

          return ListView.builder(
            itemCount: members.length,
            itemBuilder: (context, index) {
              final memberId = members[index];
              
              return FutureBuilder<DocumentSnapshot>(
                future: FirebaseFirestore.instance.collection('users').doc(memberId).get(),
                builder: (context, userSnap) {
                  if (!userSnap.hasData) return SizedBox.shrink();
                  final userData = userSnap.data!.data() as Map<String, dynamic>;
                  
                  final bool isTargetOwner = memberId == ownerId;
                  final bool isTargetAdmin = admins.contains(memberId);
                  
                  String roleLabel = "Member";
                  Color roleColor = Colors.grey;
                  
                  if (isTargetOwner) { roleLabel = "Owner"; roleColor = Colors.red; }
                  else if (isTargetAdmin) { roleLabel = "Admin"; roleColor = Colors.blue; }

                  return ListTile(
                    leading: CircleAvatar(
                      backgroundImage: userData['profileImageUrl'] != null ? CachedNetworkImageProvider(userData['profileImageUrl']) : null,
                      child: userData['profileImageUrl'] == null ? Icon(Icons.person) : null,
                    ),
                    title: Text(userData['name'] ?? "Unknown"),
                    subtitle: Text(roleLabel, style: TextStyle(color: roleColor, fontWeight: FontWeight.bold)),
                    trailing: _buildActionMenu(memberId, isTargetOwner, isTargetAdmin),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget? _buildActionMenu(String targetId, bool isTargetOwner, bool isTargetAdmin) {
    // Logic: 
    // Owner can do anything except kick self.
    // Admin can kick Member. Admin CANNOT kick Owner or other Admin.
    
    if (isTargetOwner) return null; // No actions against owner

    List<PopupMenuEntry<String>> actions = [];

    if (widget.isOwner) {
      if (isTargetAdmin) {
        actions.add(PopupMenuItem(value: 'demote', child: Text("Demote to Member")));
      } else {
        actions.add(PopupMenuItem(value: 'promote', child: Text("Promote to Admin")));
      }
      actions.add(PopupMenuItem(value: 'kick', child: Text("Kick User", style: TextStyle(color: Colors.red))));
    } else if (widget.isAdmin) {
      // Admin can only kick normal members
      if (!isTargetAdmin) {
        actions.add(PopupMenuItem(value: 'kick', child: Text("Kick User", style: TextStyle(color: Colors.red))));
      }
    }

    if (actions.isEmpty) return null;

    return PopupMenuButton<String>(
      onSelected: (value) => _updateRole(targetId, value),
      itemBuilder: (context) => actions,
    );
  }
}