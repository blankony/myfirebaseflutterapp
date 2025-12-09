// ignore_for_file: prefer_const_constructors, use_build_context_synchronously
import 'dart:io'; 
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart'; // REQUIRED IMPORT
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
  
  // Controllers for "Instantly Editable" fields
  late TextEditingController _nameController;
  late TextEditingController _descController;
  
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";

  bool _isDeleting = false;
  bool _isUploadingImage = false;
  bool _isSavingInfo = false; // Loading state for saving info
  bool _allowMemberPosts = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this); 
    
    // Initialize permissions and text fields with current data
    _allowMemberPosts = widget.communityData['allowMemberPosts'] ?? false;
    _nameController = TextEditingController(text: widget.communityData['name'] ?? '');
    _descController = TextEditingController(text: widget.communityData['description'] ?? '');
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nameController.dispose();
    _descController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // --- SAVE INFO LOGIC ---
  Future<void> _saveInfo() async {
    if (_nameController.text.trim().isEmpty) {
      OverlayService().showTopNotification(context, "Name cannot be empty", Icons.warning, (){}, color: Colors.orange);
      return;
    }

    setState(() => _isSavingInfo = true);
    FocusScope.of(context).unfocus();

    try {
      await FirebaseFirestore.instance.collection('communities').doc(widget.communityId).update({
        'name': _nameController.text.trim(),
        'description': _descController.text.trim(),
      });
      if(mounted) OverlayService().showTopNotification(context, "Info Updated", Icons.check_circle, (){}, color: Colors.green);
    } catch(e) {
      if(mounted) OverlayService().showTopNotification(context, "Update Failed", Icons.error, (){}, color: Colors.red);
    } finally {
      if(mounted) setState(() => _isSavingInfo = false);
    }
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

  Future<void> _pickAndUploadImage({required bool isBanner, required ImageSource source}) async {
    final picker = ImagePicker();
    try {
      final XFile? pickedFile = await picker.pickImage(source: source, imageQuality: 70);
      if (pickedFile == null) return;

      final croppedFile = await ImageCropper().cropImage(
        sourcePath: pickedFile.path,
        compressQuality: 70,
        aspectRatio: isBanner 
            ? CropAspectRatio(ratioX: 3, ratioY: 1)
            : CropAspectRatio(ratioX: 1, ratioY: 1),
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: isBanner ? 'Crop Banner' : 'Crop Icon',
            toolbarColor: TwitterTheme.blue,
            toolbarWidgetColor: Colors.white,
            initAspectRatio: isBanner ? CropAspectRatioPreset.ratio3x2 : CropAspectRatioPreset.square,
            lockAspectRatio: true,
          ),
          IOSUiSettings(title: isBanner ? 'Crop Banner' : 'Crop Icon', aspectRatioLockEnabled: true),
        ],
      );

      if (croppedFile == null) return;
      setState(() => _isUploadingImage = true);
      final String? downloadUrl = await _cloudinaryService.uploadImage(File(croppedFile.path));

      if (downloadUrl != null) {
        final Map<String, dynamic> update = isBanner 
            ? {'bannerImageUrl': downloadUrl} 
            : {'imageUrl': downloadUrl};
            
        await FirebaseFirestore.instance.collection('communities').doc(widget.communityId).update(update);
        if (mounted) OverlayService().showTopNotification(context, "Updated successfully!", Icons.check_circle, (){}, color: Colors.green);
      }
    } catch (e) {
      if (mounted) OverlayService().showTopNotification(context, "Error: $e", Icons.error, (){}, color: Colors.red);
    } finally {
      if (mounted) setState(() => _isUploadingImage = false);
    }
  }

  void _showImageSourceSelection({required bool isBanner}) {
    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(height: 12),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
              SizedBox(height: 16),
              ListTile(
                leading: Icon(Icons.camera_alt, color: TwitterTheme.blue),
                title: Text("Take Photo"),
                onTap: () {
                  Navigator.pop(context);
                  _pickAndUploadImage(isBanner: isBanner, source: ImageSource.camera);
                },
              ),
              ListTile(
                leading: Icon(Icons.photo_library, color: TwitterTheme.blue),
                title: Text("Choose from Gallery"),
                onTap: () {
                  Navigator.pop(context);
                  _pickAndUploadImage(isBanner: isBanner, source: ImageSource.gallery);
                },
              ),
              SizedBox(height: 12),
            ],
          ),
        );
      },
    );
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
        // Also remove any pending reqs just in case
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
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: Text("Settings & Roles")),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('communities').doc(widget.communityId).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return Center(child: CircularProgressIndicator());
          
          final data = snapshot.data!.data() as Map<String, dynamic>;
          final String ownerId = data['ownerId'];
          final String imageUrl = data['imageUrl'] ?? '';
          final String bannerUrl = data['bannerImageUrl'] ?? '';

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
              // --- HEADER SECTION (Banner + Avatar + Edit) ---
              SizedBox(
                height: 180,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.topCenter,
                  children: [
                    // Banner
                    GestureDetector(
                      onTap: (widget.isOwner || widget.isAdmin) ? () => _showImageSourceSelection(isBanner: true) : null,
                      child: Container(
                        width: double.infinity,
                        height: 120,
                        decoration: BoxDecoration(
                          color: isDark ? Colors.grey[800] : Colors.grey[300],
                          image: bannerUrl.isNotEmpty 
                              ? DecorationImage(image: CachedNetworkImageProvider(bannerUrl), fit: BoxFit.cover)
                              : null,
                        ),
                        child: bannerUrl.isEmpty && (widget.isOwner || widget.isAdmin)
                            ? Center(child: Icon(Icons.add_a_photo, color: Colors.white70))
                            : null,
                      ),
                    ),
                    
                    // Avatar
                    Positioned(
                      bottom: 0,
                      left: 20,
                      child: GestureDetector(
                        onTap: (widget.isOwner || widget.isAdmin) ? () => _showImageSourceSelection(isBanner: false) : null,
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: theme.scaffoldBackgroundColor, width: 4),
                          ),
                          child: CircleAvatar(
                            radius: 40,
                            backgroundImage: imageUrl.isNotEmpty ? CachedNetworkImageProvider(imageUrl) : null,
                            child: imageUrl.isEmpty ? Icon(Icons.groups, size: 40) : null,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // --- TABS ---
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
                    // TAB 1: GENERAL (Editable Info)
                    ListView(
                      padding: EdgeInsets.all(16),
                      children: [
                        // Editable Name
                        Text("Community Name", style: TextStyle(fontWeight: FontWeight.bold, color: theme.hintColor)),
                        SizedBox(height: 8),
                        TextField(
                          controller: _nameController,
                          decoration: InputDecoration(
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            prefixIcon: Icon(Icons.badge_outlined),
                          ),
                        ),
                        
                        SizedBox(height: 16),
                        
                        // Editable Description
                        Text("Description", style: TextStyle(fontWeight: FontWeight.bold, color: theme.hintColor)),
                        SizedBox(height: 8),
                        TextField(
                          controller: _descController,
                          maxLines: 3,
                          decoration: InputDecoration(
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            alignLabelWithHint: true,
                          ),
                        ),

                        SizedBox(height: 16),

                        // Save Button
                        if (widget.isOwner || widget.isAdmin)
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _isSavingInfo ? null : _saveInfo,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: TwitterTheme.blue,
                                foregroundColor: Colors.white,
                                padding: EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: _isSavingInfo 
                                  ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                                  : Text("Save Changes"),
                            ),
                          ),
                        
                        SizedBox(height: 24),
                        Divider(),

                        // Permissions
                        SwitchListTile(
                          title: Text("Allow Members to Post"),
                          subtitle: Text("If off, only Admins/Editors can post."),
                          value: _allowMemberPosts,
                          onChanged: (widget.isOwner || widget.isAdmin) ? _updatePermission : null,
                          contentPadding: EdgeInsets.zero,
                        ),
                        
                        Divider(),
                        
                        // Delete
                        if (widget.isOwner)
                          ListTile(
                            leading: Icon(Icons.delete_forever, color: Colors.red),
                            title: Text("Delete Community", style: TextStyle(color: Colors.red)),
                            subtitle: Text("Permanent action"),
                            onTap: _deleteCommunity,
                            contentPadding: EdgeInsets.zero,
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
            final bool canModify = widget.isOwner || (widget.isAdmin && userId != ownerId);

            return ListTile(
              leading: CircleAvatar(
                backgroundImage: avatarUrl != null ? CachedNetworkImageProvider(avatarUrl) : null,
                child: avatarUrl == null ? Icon(Icons.person) : null,
              ),
              title: Text(name),
              subtitle: Text(role, style: TextStyle(color: roleColor, fontWeight: FontWeight.bold, fontSize: 12)),
              
              // FIX: FirebaseAuth Access
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