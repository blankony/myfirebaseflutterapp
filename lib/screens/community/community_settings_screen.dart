// ignore_for_file: prefer_const_constructors, use_build_context_synchronously
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
  bool _isDeleting = false;

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

  // --- DELETE COMMUNITY LOGIC ---
  Future<void> _deleteCommunity() async {
    // 1. Show Confirmation Dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Delete Community?"),
        content: Text(
          "Are you sure you want to delete '${widget.communityData['name']}'?\n\nThis action cannot be undone and will remove the community for all members.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text("Delete"),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isDeleting = true);

    try {
      // 2. Delete the Community Document
      await FirebaseFirestore.instance
          .collection('communities')
          .doc(widget.communityId)
          .delete();

      // (Optional: You could also delete all posts related to this community using a Cloud Function or Batch here)

      if (mounted) {
        OverlayService().showTopNotification(
          context, 
          "Community deleted successfully", 
          Icons.delete_forever, 
          (){},
          color: Colors.grey
        );
        // 3. Navigate back to Home
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isDeleting = false);
        OverlayService().showTopNotification(context, "Failed to delete: $e", Icons.error, (){}, color: Colors.red);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ownerId = widget.communityData['ownerId'];
    
    return Scaffold(
      appBar: AppBar(title: Text("Community Settings")),
      body: Column(
        children: [
          // MEMBER LIST
          Expanded(
            child: StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance.collection('communities').doc(widget.communityId).snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return Center(child: CircularProgressIndicator());
                
                // Handle case where document is deleted while viewing settings
                if (!snapshot.data!.exists) return Center(child: Text("Community no longer exists"));

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
                        final userData = userSnap.data!.data() as Map<String, dynamic>? ?? {};
                        
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
          ),

          // DELETE BUTTON (Only for Owner)
          if (widget.isOwner)
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isDeleting ? null : _deleteCommunity,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade50,
                    foregroundColor: Colors.red,
                    padding: EdgeInsets.symmetric(vertical: 16),
                    elevation: 0,
                    side: BorderSide(color: Colors.red.withOpacity(0.5)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: _isDeleting 
                      ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.red))
                      : Icon(Icons.delete_forever),
                  label: Text(_isDeleting ? "Deleting..." : "Delete Community"),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget? _buildActionMenu(String targetId, bool isTargetOwner, bool isTargetAdmin) {
    
    if (isTargetOwner) return null;

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