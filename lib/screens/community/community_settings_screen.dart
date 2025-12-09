// ignore_for_file: prefer_const_constructors, use_build_context_synchronously
import 'dart:io'; 
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart'; // REQUIRED IMPORT
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart'; 
import 'package:image_cropper/image_cropper.dart'; 
import '../../services/overlay_service.dart';
import '../../services/cloudinary_service.dart'; 
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

class _CommunitySettingsScreenState extends State<CommunitySettingsScreen> with SingleTickerProviderStateMixin {
  final CloudinaryService _cloudinaryService = CloudinaryService();
  late TabController _tabController;
  
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";

  bool _isDeleting = false;
  bool _isUploadingImage = false;
  bool _allowMemberPosts = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this); 
    _allowMemberPosts = widget.communityData['allowMemberPosts'] ?? false;
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _updatePermission(bool value) async {
    setState(() => _allowMemberPosts = value);
    try {
      await FirebaseFirestore.instance.collection('communities').doc(widget.communityId).update({
        'allowMemberPosts': value
      });
    } catch(e) {
      setState(() => _allowMemberPosts = !value); // Revert on fail
    }
  }

  Future<void> _pickAndUploadImage(ImageSource source) async {
    final picker = ImagePicker();
    try {
      final XFile? pickedFile = await picker.pickImage(source: source, imageQuality: 70);
      if (pickedFile == null) return;

      final croppedFile = await ImageCropper().cropImage(
        sourcePath: pickedFile.path,
        compressQuality: 70,
        aspectRatio: CropAspectRatio(ratioX: 1, ratioY: 1),
        uiSettings: [
          AndroidUiSettings(toolbarTitle: 'Crop Icon', toolbarColor: TwitterTheme.blue, toolbarWidgetColor: Colors.white, lockAspectRatio: true),
          IOSUiSettings(title: 'Crop Icon', aspectRatioLockEnabled: true),
        ],
      );

      if (croppedFile == null) return;
      setState(() => _isUploadingImage = true);
      final String? downloadUrl = await _cloudinaryService.uploadImage(File(croppedFile.path));

      if (downloadUrl != null) {
        await FirebaseFirestore.instance.collection('communities').doc(widget.communityId).update({'imageUrl': downloadUrl});
        if (mounted) OverlayService().showTopNotification(context, "Icon updated!", Icons.check_circle, (){}, color: Colors.green);
      }
    } catch (e) {
      if (mounted) OverlayService().showTopNotification(context, "Error: $e", Icons.error, (){}, color: Colors.red);
    } finally {
      if (mounted) setState(() => _isUploadingImage = false);
    }
  }

  Future<void> _updateRole(String targetUid, String action) async {
    final docRef = FirebaseFirestore.instance.collection('communities').doc(widget.communityId);
    try {
      final batch = FirebaseFirestore.instance.batch();
      
      // Cleanup existing roles
      batch.update(docRef, {'admins': FieldValue.arrayRemove([targetUid])});
      batch.update(docRef, {'editors': FieldValue.arrayRemove([targetUid])});
      batch.update(docRef, {'moderators': FieldValue.arrayRemove([targetUid])});

      if (action == 'make_admin') {
        batch.update(docRef, {'admins': FieldValue.arrayUnion([targetUid])});
      } else if (action == 'make_editor') {
        batch.update(docRef, {'editors': FieldValue.arrayUnion([targetUid])});
      } else if (action == 'make_mod') {
        batch.update(docRef, {'moderators': FieldValue.arrayUnion([targetUid])});
      } else if (action == 'kick') {
        batch.update(docRef, {'followers': FieldValue.arrayRemove([targetUid])});
        batch.update(docRef, {'pendingMembers': FieldValue.arrayRemove([targetUid])});
      }

      await batch.commit();
      OverlayService().showTopNotification(context, "Updated successfully", Icons.check_circle, (){});
    } catch (e) {
      OverlayService().showTopNotification(context, "Action failed", Icons.error, (){}, color: Colors.red);
    }
  }

  Future<void> _deleteCommunity() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Delete Channel?"),
        content: Text("Are you sure? This will delete the identity and all data permanently."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text("Cancel")),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: Text("Delete")),
        ],
      ),
    );

    if (confirm != true) return;
    setState(() => _isDeleting = true);

    try {
      await FirebaseFirestore.instance.collection('communities').doc(widget.communityId).delete();
      if (mounted) {
        OverlayService().showTopNotification(context, "Channel Deleted", Icons.delete_forever, (){});
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isDeleting = false);
        OverlayService().showTopNotification(context, "Failed to delete", Icons.error, (){}, color: Colors.red);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text("Settings & Roles")),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('communities').doc(widget.communityId).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return Center(child: CircularProgressIndicator());
          
          final data = snapshot.data!.data() as Map<String, dynamic>;
          final String ownerId = data['ownerId'];
          final String imageUrl = data['imageUrl'] ?? '';
          
          // Flatten all users
          final Set<String> allUserIds = {};
          final List followers = data['followers'] ?? [];
          final List admins = data['admins'] ?? [];
          final List editors = data['editors'] ?? [];
          final List moderators = data['moderators'] ?? [];
          
          allUserIds.addAll(List<String>.from(followers));
          allUserIds.addAll(List<String>.from(admins));
          allUserIds.addAll(List<String>.from(editors));
          allUserIds.addAll(List<String>.from(moderators));
          allUserIds.add(ownerId);

          return Column(
            children: [
              // HEADER
              Container(
                padding: EdgeInsets.all(20),
                child: Column(
                  children: [
                    GestureDetector(
                      onTap: () => _pickAndUploadImage(ImageSource.gallery),
                      child: Stack(
                        children: [
                          CircleAvatar(
                            radius: 40,
                            backgroundImage: imageUrl.isNotEmpty ? CachedNetworkImageProvider(imageUrl) : null,
                            child: imageUrl.isEmpty ? Icon(Icons.camera_alt, size: 30) : null,
                          ),
                          if (_isUploadingImage) Positioned.fill(child: CircularProgressIndicator())
                        ],
                      ),
                    ),
                    SizedBox(height: 10),
                    Text("Tap to change icon", style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
              
              // TABS
              TabBar(
                controller: _tabController,
                labelColor: TwitterTheme.blue,
                unselectedLabelColor: Colors.grey,
                tabs: const [Tab(text: "General"), Tab(text: "Members & Roles")],
              ),
              
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // TAB 1: GENERAL
                    ListView(
                      children: [
                        SwitchListTile(
                          title: Text("Allow Members to Post"),
                          subtitle: Text("If off, only Admins/Editors can post."),
                          value: _allowMemberPosts,
                          onChanged: (widget.isOwner || widget.isAdmin) ? _updatePermission : null,
                        ),
                        Divider(),
                        if (widget.isOwner)
                          ListTile(
                            leading: Icon(Icons.delete_forever, color: Colors.red),
                            title: Text("Delete Community", style: TextStyle(color: Colors.red)),
                            subtitle: Text("Permanent action"),
                            onTap: _deleteCommunity,
                          )
                      ],
                    ),
                    
                    // TAB 2: ROLES
                    Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: TextField(
                            controller: _searchController,
                            decoration: InputDecoration(
                              hintText: "Search members...",
                              prefixIcon: Icon(Icons.search),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              contentPadding: EdgeInsets.symmetric(horizontal: 16),
                            ),
                            onChanged: (val) => setState(() => _searchQuery = val.toLowerCase()),
                          ),
                        ),
                        Expanded(
                          child: _buildMemberList(
                            allUserIds.toList(), 
                            ownerId, admins, editors, moderators, 
                            data
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildMemberList(
    List<String> userIds, 
    String ownerId, 
    List admins, 
    List editors, 
    List moderators, 
    Map<String, dynamic> communityData
  ) {
    if (userIds.isEmpty) return Center(child: Text("No members found."));

    return ListView.builder(
      itemCount: userIds.length,
      itemBuilder: (context, index) {
        final userId = userIds[index];
        
        return FutureBuilder<DocumentSnapshot>(
          future: FirebaseFirestore.instance.collection('users').doc(userId).get(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return SizedBox.shrink();
            
            final userData = snapshot.data!.data() as Map<String, dynamic>? ?? {};
            final String name = userData['name'] ?? 'Unknown';
            final String email = userData['email'] ?? '';
            final String? avatarUrl = userData['profileImageUrl'];

            // SEARCH FILTER
            if (_searchQuery.isNotEmpty && !name.toLowerCase().contains(_searchQuery) && !email.toLowerCase().contains(_searchQuery)) {
              return SizedBox.shrink();
            }

            // DETERMINE ROLE
            String role = "Member";
            Color roleColor = Colors.grey;
            if (userId == ownerId) { role = "OWNER"; roleColor = Colors.red; }
            else if (admins.contains(userId)) { role = "Admin"; roleColor = Colors.blue; }
            else if (editors.contains(userId)) { role = "Editor"; roleColor = Colors.green; }
            else if (moderators.contains(userId)) { role = "Moderator"; roleColor = Colors.orange; }

            // ACTION PERMISSIONS
            // Owner can modify anyone. Admin can modify anyone EXCEPT Owner.
            // Using FirebaseAuth.instance.currentUser here correctly now that import is added.
            final bool canModify = widget.isOwner || (widget.isAdmin && userId != ownerId);

            return ListTile(
              leading: CircleAvatar(
                backgroundImage: avatarUrl != null ? CachedNetworkImageProvider(avatarUrl) : null,
                child: avatarUrl == null ? Icon(Icons.person) : null,
              ),
              title: Text(name),
              subtitle: Text(role, style: TextStyle(color: roleColor, fontWeight: FontWeight.bold, fontSize: 12)),
              trailing: (canModify && userId != FirebaseAuth.instance.currentUser?.uid) 
                ? PopupMenuButton<String>(
                    onSelected: (val) => _updateRole(userId, val),
                    itemBuilder: (context) => [
                      if (widget.isOwner) PopupMenuItem(value: 'make_admin', child: Text("Promote to Admin")),
                      PopupMenuItem(value: 'make_editor', child: Text("Set as Editor")),
                      PopupMenuItem(value: 'make_mod', child: Text("Set as Moderator")),
                      PopupMenuItem(value: 'remove_role', child: Text("Demote to Member")),
                      PopupMenuDivider(),
                      PopupMenuItem(value: 'kick', child: Text("Kick User", style: TextStyle(color: Colors.red))),
                    ],
                  ) 
                : null,
            );
          },
        );
      },
    );
  }
}