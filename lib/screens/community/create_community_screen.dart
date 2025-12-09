// ignore_for_file: prefer_const_constructors, use_build_context_synchronously
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import '../../main.dart';
import '../../services/overlay_service.dart';
import '../../services/cloudinary_service.dart';

class CreateCommunityScreen extends StatefulWidget {
  const CreateCommunityScreen({super.key});

  @override
  State<CreateCommunityScreen> createState() => _CreateCommunityScreenState();
}

class _CreateCommunityScreenState extends State<CreateCommunityScreen> {
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  final CloudinaryService _cloudinaryService = CloudinaryService();
  
  bool _isLoading = false;
  String _selectedCategory = 'casual';
  File? _verificationDoc; 
  
  // NEW: Member Posting Permission
  bool _allowMemberPosts = false; 

  Future<void> _pickVerificationDoc() async {
    final picker = ImagePicker();
    final XFile? pickedFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80); 
    if (pickedFile != null) {
      setState(() {
        _verificationDoc = File(pickedFile.path);
      });
    }
  }

  Future<void> _create() async {
    if (_nameController.text.isEmpty) {
      OverlayService().showTopNotification(context, "Community name required", Icons.warning, (){}, color: Colors.orange);
      return;
    }

    if (_selectedCategory != 'casual' && _verificationDoc == null) {
      OverlayService().showTopNotification(context, "Verification document required", Icons.attach_file, (){}, color: Colors.red);
      return;
    }
    
    setState(() => _isLoading = true);
    final user = FirebaseAuth.instance.currentUser;
    
    try {
      String? docUrl;
      if (_verificationDoc != null) {
        docUrl = await _cloudinaryService.uploadImage(_verificationDoc!);
      }

      bool isVerified = _selectedCategory != 'casual' && docUrl != null;

      await FirebaseFirestore.instance.collection('communities').add({
        'name': _nameController.text.trim(),
        'description': _descController.text.trim(),
        'category': _selectedCategory,
        'isVerified': isVerified, 
        'verificationDocUrl': docUrl,
        'allowMemberPosts': _allowMemberPosts, // Save Preference
        
        'ownerId': user!.uid,
        'admins': [], 
        'editors': [], 
        'moderators': [], 
        'followers': [user.uid], 
        'pendingFollowers': [],
        
        'createdAt': FieldValue.serverTimestamp(),
        'imageUrl': null, 
        'bannerImageUrl': null,
      });
      
      if(mounted) {
        OverlayService().showTopNotification(context, "Channel Identity Created!", Icons.check_circle, (){}, color: Colors.green);
        Navigator.pop(context);
      }
    } catch (e) {
      if(mounted) OverlayService().showTopNotification(context, "Error creating community", Icons.error, (){}, color: Colors.red);
    } finally {
      if(mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool isOfficial = _selectedCategory != 'casual';

    return Scaffold(
      appBar: AppBar(title: Text("Create Public Channel")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Establish a new voice on PNJ Campus.",
              style: theme.textTheme.bodyLarge?.copyWith(color: theme.hintColor),
            ),
            SizedBox(height: 24),
            
            // TYPE SELECTION
            Text("Channel Type", style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(border: Border.all(color: theme.dividerColor), borderRadius: BorderRadius.circular(12), color: theme.cardColor),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedCategory,
                  isExpanded: true,
                  items: [
                    DropdownMenuItem(value: 'casual', child: Row(children: const [Icon(Icons.tag_faces, color: Colors.orange), SizedBox(width: 8), Text("Casual (Fun, Hobbies)")])),
                    DropdownMenuItem(value: 'partner_official', child: Row(children: const [Icon(Icons.verified_outlined, color: Colors.blueGrey), SizedBox(width: 8), Text("External Organization")])),
                    DropdownMenuItem(value: 'pnj_official', child: Row(children: const [Icon(Icons.account_balance, color: TwitterTheme.blue), SizedBox(width: 8), Text("PNJ Official Unit")])),
                  ],
                  onChanged: (val) => setState(() => _selectedCategory = val!),
                ),
              ),
            ),
            
            // VERIFICATION UPLOAD
            if (isOfficial) ...[
              SizedBox(height: 24),
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(color: TwitterTheme.blue.withOpacity(0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: TwitterTheme.blue.withOpacity(0.3))),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [Icon(Icons.gpp_good, color: TwitterTheme.blue), SizedBox(width: 8), Text("Verification Required", style: TextStyle(fontWeight: FontWeight.bold, color: TwitterTheme.blue))]),
                    SizedBox(height: 8),
                    Text("Upload an official document (Letter of Assignment / SK) to prove your authority.", style: TextStyle(fontSize: 13, color: theme.textTheme.bodyMedium?.color)),
                    SizedBox(height: 12),
                    InkWell(
                      onTap: _pickVerificationDoc,
                      child: Container(
                        height: 120, width: double.infinity,
                        decoration: BoxDecoration(color: theme.cardColor, borderRadius: BorderRadius.circular(8), border: Border.all(color: theme.dividerColor)),
                        child: _verificationDoc == null
                          ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.cloud_upload_outlined, size: 32, color: theme.hintColor), SizedBox(height: 8), Text("Tap to upload Document", style: TextStyle(color: theme.hintColor))])
                          : Image.file(_verificationDoc!, fit: BoxFit.cover),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            SizedBox(height: 24),

            // DETAILS
            TextField(
              controller: _nameController,
              decoration: InputDecoration(labelText: "Channel Name", border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), prefixIcon: Icon(Icons.badge_outlined)),
            ),
            SizedBox(height: 16),
            TextField(
              controller: _descController,
              maxLines: 3,
              decoration: InputDecoration(labelText: "Description", border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
            ),
            
            SizedBox(height: 24),
            
            // PERMISSIONS
            SwitchListTile(
              title: Text("Allow Members to Post"),
              subtitle: Text("If disabled, only Admins/Editors can post."),
              value: _allowMemberPosts,
              onChanged: (val) => setState(() => _allowMemberPosts = val),
              contentPadding: EdgeInsets.zero,
            ),

            SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _create,
                style: ElevatedButton.styleFrom(backgroundColor: TwitterTheme.blue, foregroundColor: Colors.white, padding: EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))),
                child: _isLoading ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : Text(isOfficial ? "Submit for Verification & Create" : "Create Community"),
              ),
            )
          ],
        ),
      ),
    );
  }
}