// ignore_for_file: prefer_const_constructors, use_build_context_synchronously
import 'dart:io'; 
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart'; 
import 'package:image_cropper/image_cropper.dart'; 
import '../../services/overlay_service.dart';
import '../../services/cloudinary_service.dart'; // Import Cloudinary
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
  final CloudinaryService _cloudinaryService = CloudinaryService(); // Instance Service
  bool _isDeleting = false;
  bool _isUploadingImage = false; // State untuk loading upload gambar

  // --- 1. IMAGE UPLOAD LOGIC (BARU) ---
  
  void _showImageSourceSelection() {
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
                  _pickAndUploadImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: Icon(Icons.photo_library, color: TwitterTheme.blue),
                title: Text("Choose from Gallery"),
                onTap: () {
                  Navigator.pop(context);
                  _pickAndUploadImage(ImageSource.gallery);
                },
              ),
              SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickAndUploadImage(ImageSource source) async {
    final picker = ImagePicker();
    try {
      final XFile? pickedFile = await picker.pickImage(source: source, imageQuality: 70);
      if (pickedFile == null) return;

      // Crop Image (Square for Avatar)
      final croppedFile = await ImageCropper().cropImage(
        sourcePath: pickedFile.path,
        compressQuality: 70,
        aspectRatio: CropAspectRatio(ratioX: 1, ratioY: 1), // Force Square
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop Icon',
            toolbarColor: TwitterTheme.blue,
            toolbarWidgetColor: Colors.white,
            initAspectRatio: CropAspectRatioPreset.square,
            lockAspectRatio: true,
          ),
          IOSUiSettings(title: 'Crop Icon', aspectRatioLockEnabled: true),
        ],
      );

      if (croppedFile == null) return;

      setState(() => _isUploadingImage = true);

      // Upload to Cloudinary
      final String? downloadUrl = await _cloudinaryService.uploadImage(File(croppedFile.path));

      if (downloadUrl != null) {
        // Update Firestore
        await FirebaseFirestore.instance
            .collection('communities')
            .doc(widget.communityId)
            .update({'imageUrl': downloadUrl});
        
        if (mounted) OverlayService().showTopNotification(context, "Icon updated!", Icons.check_circle, (){}, color: Colors.green);
      } else {
        if (mounted) OverlayService().showTopNotification(context, "Upload failed", Icons.error, (){}, color: Colors.red);
      }
    } catch (e) {
      if (mounted) OverlayService().showTopNotification(context, "Error: $e", Icons.error, (){}, color: Colors.red);
    } finally {
      if (mounted) setState(() => _isUploadingImage = false);
    }
  }

  // --- 2. EDIT INFO LOGIC ---
  Future<void> _showEditDialog(Map<String, dynamic> currentData) async {
    final nameController = TextEditingController(text: currentData['name']);
    final descController = TextEditingController(text: currentData['description']);
    bool isUpdating = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text("Edit Community Info"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: "Community Name",
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                SizedBox(height: 16),
                TextField(
                  controller: descController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: "Description",
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text("Cancel"),
              ),
              ElevatedButton(
                onPressed: isUpdating ? null : () async {
                  if (nameController.text.trim().isEmpty) return;
                  
                  setState(() => isUpdating = true);
                  
                  try {
                    await FirebaseFirestore.instance
                        .collection('communities')
                        .doc(widget.communityId)
                        .update({
                          'name': nameController.text.trim(),
                          'description': descController.text.trim(),
                        });
                    
                    if (mounted) {
                      Navigator.pop(ctx);
                      OverlayService().showTopNotification(context, "Info updated!", Icons.check_circle, (){}, color: Colors.green);
                    }
                  } catch (e) {
                    setState(() => isUpdating = false);
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: TwitterTheme.blue, foregroundColor: Colors.white),
                child: isUpdating 
                    ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text("Save"),
              ),
            ],
          );
        }
      ),
    );
  }

  // --- ROLES LOGIC ---
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
        final batch = FirebaseFirestore.instance.batch();
        batch.update(docRef, {'members': FieldValue.arrayRemove([targetUid])});
        batch.update(docRef, {'admins': FieldValue.arrayRemove([targetUid])});
        await batch.commit();
        OverlayService().showTopNotification(context, "User kicked", Icons.remove_circle, (){}, color: Colors.red);
      }
    } catch (e) {
      OverlayService().showTopNotification(context, "Action failed", Icons.error, (){}, color: Colors.red);
    }
  }

  // --- DELETE COMMUNITY LOGIC ---
  Future<void> _deleteCommunity() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Delete Community?"),
        content: Text("Are you sure? This action cannot be undone."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text("Cancel")),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: Text("Delete"),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isDeleting = true);

    try {
      await FirebaseFirestore.instance.collection('communities').doc(widget.communityId).delete();
      if (mounted) {
        OverlayService().showTopNotification(context, "Deleted", Icons.delete_forever, (){});
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
    return Scaffold(
      appBar: AppBar(title: Text("Community Settings")),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('communities').doc(widget.communityId).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return Center(child: CircularProgressIndicator());
          if (!snapshot.data!.exists) return Center(child: Text("Community no longer exists"));

          final data = snapshot.data!.data() as Map<String, dynamic>;
          final List members = data['members'] ?? [];
          final List admins = data['admins'] ?? [];
          final String ownerId = data['ownerId'];
          
          // Data untuk Header
          final String name = data['name'] ?? 'Community';
          final String? imageUrl = data['imageUrl'];

          return Column(
            children: [
              // --- HEADER BARU: FOTO PROFIL COMMUNITY ---
              Container(
                padding: EdgeInsets.symmetric(vertical: 24),
                alignment: Alignment.center,
                child: Stack(
                  children: [
                    // Avatar Image
                    CircleAvatar(
                      radius: 50,
                      backgroundColor: TwitterTheme.blue.withOpacity(0.1),
                      backgroundImage: imageUrl != null ? CachedNetworkImageProvider(imageUrl) : null,
                      child: imageUrl == null 
                          ? Text(name[0].toUpperCase(), style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: TwitterTheme.blue)) 
                          : null,
                    ),
                    
                    // Edit Icon Overlay (Hanya untuk Admin/Owner)
                    if (widget.isOwner || widget.isAdmin)
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: GestureDetector(
                          onTap: _showImageSourceSelection, // Trigger Upload
                          child: Container(
                            padding: EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: TwitterTheme.blue,
                              shape: BoxShape.circle,
                              border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 3),
                            ),
                            child: _isUploadingImage 
                                ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                : Icon(Icons.camera_alt, size: 16, color: Colors.white),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              
              // --- BAGIAN EDIT INFO TEXT ---
              if (widget.isOwner || widget.isAdmin)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Card(
                    elevation: 0,
                    color: Theme.of(context).cardColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Theme.of(context).dividerColor)
                    ),
                    child: ListTile(
                      leading: Icon(Icons.edit, color: TwitterTheme.blue),
                      title: Text("Edit Name & Description"),
                      trailing: Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                      onTap: () => _showEditDialog(data),
                    ),
                  ),
                ),

              // LABEL MEMBERS
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text("MEMBERS (${members.length})", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey, letterSpacing: 1.2)),
                ),
              ),

              // MEMBER LIST
              Expanded(
                child: ListView.separated(
                  padding: EdgeInsets.zero,
                  itemCount: members.length,
                  separatorBuilder: (context, index) => Divider(height: 1, indent: 70),
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
                          contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                          leading: CircleAvatar(
                            backgroundImage: userData['profileImageUrl'] != null ? CachedNetworkImageProvider(userData['profileImageUrl']) : null,
                            child: userData['profileImageUrl'] == null ? Icon(Icons.person) : null,
                          ),
                          title: Text(userData['name'] ?? "Unknown"),
                          subtitle: Text(roleLabel, style: TextStyle(color: roleColor, fontWeight: FontWeight.bold, fontSize: 12)),
                          trailing: _buildActionMenu(memberId, isTargetOwner, isTargetAdmin),
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
          );
        },
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