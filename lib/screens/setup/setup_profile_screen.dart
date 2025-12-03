// ignore_for_file: prefer_const_constructors
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import '../../main.dart';
import '../../services/cloudinary_service.dart';
import 'setup_department_screen.dart';
import '../../services/overlay_service.dart';

final FirebaseAuth _auth = FirebaseAuth.instance;
final FirebaseFirestore _firestore = FirebaseFirestore.instance;
final CloudinaryService _cloudinaryService = CloudinaryService();

class SetupProfileScreen extends StatefulWidget {
  const SetupProfileScreen({super.key});

  @override
  State<SetupProfileScreen> createState() => _SetupProfileScreenState();
}

class _SetupProfileScreenState extends State<SetupProfileScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  
  bool _isLoading = false;
  File? _avatarFile;
  File? _bannerFile;
  
  // --- NEW: Privacy Preference ---
  bool _isPrivateAccount = false; 

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<File?> _cropImage({required XFile imageFile, required bool isAvatar}) async {
    try {
      final dynamic cropped = await ImageCropper().cropImage(
        sourcePath: imageFile.path,
        compressQuality: 70,
        maxWidth: 1080,
        maxHeight: 1080,
        aspectRatio: isAvatar 
            ? CropAspectRatio(ratioX: 1, ratioY: 1) 
            : CropAspectRatio(ratioX: 3, ratioY: 1),
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: isAvatar ? 'Crop Avatar' : 'Crop Banner',
            toolbarColor: TwitterTheme.blue,
            toolbarWidgetColor: Colors.white,
            initAspectRatio: isAvatar ? CropAspectRatioPreset.square : CropAspectRatioPreset.ratio3x2,
            lockAspectRatio: true,
          ),
          IOSUiSettings(
            title: isAvatar ? 'Crop Avatar' : 'Crop Banner',
            aspectRatioLockEnabled: true,
          ),
        ],
      );
      if (cropped != null) return File(cropped.path);
    } catch (e) {
      debugPrint("Crop error: $e");
    }
    return null;
  }

  Future<void> _pickImage({required bool isAvatar}) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      maxHeight: 1200,
      imageQuality: 85,
    );

    if (pickedFile != null) {
      final processed = await _cropImage(imageFile: pickedFile, isAvatar: isAvatar);
      if (processed != null) {
        setState(() {
          if (isAvatar) {
            _avatarFile = processed;
          } else {
            _bannerFile = processed;
          }
        });
      }
    }
  }

  Future<void> _saveAndNext() async {
    setState(() { _isLoading = true; });
    final user = _auth.currentUser;
    if (user == null) return;

    String? avatarUrl;
    String? bannerUrl;

    try {
      if (_avatarFile != null) {
        avatarUrl = await _cloudinaryService.uploadImage(_avatarFile!);
      }
      if (_bannerFile != null) {
        bannerUrl = await _cloudinaryService.uploadImage(_bannerFile!);
      }

      final Map<String, dynamic> updateData = {
        'isPrivate': _isPrivateAccount, // Save Privacy Setting
      };
      
      if (avatarUrl != null) updateData['profileImageUrl'] = avatarUrl;
      if (bannerUrl != null) updateData['bannerImageUrl'] = bannerUrl;

      await _firestore.collection('users').doc(user.uid).update(updateData);

      if (mounted) {
        Navigator.of(context).push(
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) => SetupDepartmentScreen(),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(opacity: animation, child: child);
            },
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        OverlayService().showTopNotification(
          context, 
          "Error: $e", 
          Icons.error, 
          (){},
          color: Colors.red
        );
      }
    } finally {
      if (mounted) setState(() { _isLoading = false; });
    }
  }

  void _skip() {
    // Even on skip, save the privacy preference
    final user = _auth.currentUser;
    if (user != null) {
      _firestore.collection('users').doc(user.uid).update({'isPrivate': _isPrivateAccount});
    }

    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => SetupDepartmentScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: SingleChildScrollView( // Added scroll for smaller screens
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Image.asset('images/app_icon.png', height: 40),
                      TextButton(
                        onPressed: _skip,
                        child: Text("Skip", style: TextStyle(color: theme.hintColor)),
                      ),
                    ],
                  ),
                  SizedBox(height: 32),
                  Text(
                    "Personalize your account",
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: TwitterTheme.blue,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    "Add a profile picture and banner to let people recognize you.",
                    style: theme.textTheme.bodyLarge,
                  ),
                  SizedBox(height: 30),
            
                  Center(
                    child: Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.center,
                      children: [
                        GestureDetector(
                          onTap: () => _pickImage(isAvatar: false),
                          child: Container(
                            width: double.infinity,
                            height: 150,
                            decoration: BoxDecoration(
                              color: theme.cardColor,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: theme.dividerColor),
                              image: _bannerFile != null 
                                ? DecorationImage(image: FileImage(_bannerFile!), fit: BoxFit.cover)
                                : null,
                            ),
                            child: _bannerFile == null 
                              ? Center(child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.add_a_photo, color: TwitterTheme.blue),
                                    Text("Add Banner", style: TextStyle(color: TwitterTheme.blue))
                                  ],
                                ))
                              : null,
                          ),
                        ),
                        
                        Positioned(
                          bottom: -40,
                          child: GestureDetector(
                            onTap: () => _pickImage(isAvatar: true),
                            child: Container(
                              width: 100,
                              height: 100,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: theme.scaffoldBackgroundColor,
                                border: Border.all(color: theme.scaffoldBackgroundColor, width: 4),
                                image: _avatarFile != null
                                  ? DecorationImage(image: FileImage(_avatarFile!), fit: BoxFit.cover)
                                  : null,
                              ),
                              child: _avatarFile == null 
                                ? Icon(Icons.add_a_photo, color: TwitterTheme.blue, size: 30)
                                : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
            
                  SizedBox(height: 60),
                  
                  // --- NEW: Privacy Toggle ---
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: theme.cardColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: theme.dividerColor.withOpacity(0.5)),
                    ),
                    child: Row(
                      children: [
                        Icon(_isPrivateAccount ? Icons.lock : Icons.lock_open, color: theme.primaryColor),
                        SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("Private Account", style: TextStyle(fontWeight: FontWeight.bold)),
                              Text(
                                _isPrivateAccount ? "Only followers can see your content" : "Anyone can see your content",
                                style: TextStyle(fontSize: 12, color: theme.hintColor),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: _isPrivateAccount,
                          onChanged: (val) => setState(() => _isPrivateAccount = val),
                        ),
                      ],
                    ),
                  ),
                  
                  SizedBox(height: 30),
            
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _saveAndNext,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: TwitterTheme.blue,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                      ),
                      child: _isLoading 
                        ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : Text("Next"),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}