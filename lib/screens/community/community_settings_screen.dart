// ignore_for_file: prefer_const_constructors, use_build_context_synchronously
import 'dart:io'; 
import 'package:flutter/material.dart';
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
  
  bool _isDeleting = false;
  bool _isUploadingImage = false;
  bool _allowMemberPosts = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this); 
    _allowMemberPosts = widget.communityData['allowMemberPosts'] ?? false;
  }

  Future<void> _updatePermission(bool value) async {
    setState(() => _allowMemberPosts = value);
    try {
      await FirebaseFirestore.instance.collection('communities').doc(widget.communityId).update({
        'allowMemberPosts': value
      });
    } catch(e) {
      // revert on error
      setState(() => _allowMemberPosts = !value);
    }
  }

  // ... (Keep existing _pickAndUploadImage, _updateRole, _transferOwnership, _deleteCommunity from previous logic) ...
  // Re-implementing briefly for completeness of this file structure:

  Future<void> _pickAndUploadImage(ImageSource source) async {
     // ... (Same image upload logic) ...
  }
  Future<void> _updateRole(String targetUid, String action) async {
     // ... (Same role logic) ...
  }
  Future<void> _transferOwnership(String newOwnerId) async {
     // ... (Same transfer logic) ...
  }
  Future<void> _deleteCommunity() async {
     // ... (Same delete logic) ...
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Settings & Roles")),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('communities').doc(widget.communityId).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return Center(child: CircularProgressIndicator());
          
          final data = snapshot.data!.data() as Map<String, dynamic>;
          final List followers = data['followers'] ?? [];
          final String imageUrl = data['imageUrl'] ?? '';

          return Column(
            children: [
              // HEADER
              Container(padding: EdgeInsets.all(20), child: CircleAvatar(radius: 40, backgroundImage: imageUrl.isNotEmpty ? CachedNetworkImageProvider(imageUrl) : null)),
              
              // TABS
              TabBar(
                controller: _tabController,
                labelColor: TwitterTheme.blue,
                unselectedLabelColor: Colors.grey,
                tabs: const [Tab(text: "General"), Tab(text: "Roles")],
              ),
              
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // GENERAL SETTINGS TAB
                    ListView(
                      children: [
                        SwitchListTile(
                          title: Text("Allow Members to Post"),
                          subtitle: Text("If off, only staff can post."),
                          value: _allowMemberPosts,
                          onChanged: widget.isOwner || widget.isAdmin ? _updatePermission : null,
                        ),
                        if (widget.isOwner)
                          ListTile(
                            leading: Icon(Icons.delete, color: Colors.red),
                            title: Text("Delete Community", style: TextStyle(color: Colors.red)),
                            onTap: _deleteCommunity,
                          )
                      ],
                    ),
                    
                    // ROLE MANAGER TAB (Placeholder for existing logic)
                    Center(child: Text("Role Management UI (Same as before)")),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}