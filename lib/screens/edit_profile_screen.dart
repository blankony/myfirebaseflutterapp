// ignore_for_file: prefer_const_constructors
import 'dart:io'; 
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart'; 
import 'package:image_cropper/image_cropper.dart'; 
import '../main.dart'; 
import 'change_password_screen.dart'; 
import '../services/cloudinary_service.dart'; 
import 'package:cached_network_image/cached_network_image.dart';
import '../../data/pnj_data.dart'; // Ensure this file exists from previous steps

final FirebaseAuth _auth = FirebaseAuth.instance;
final FirebaseFirestore _firestore = FirebaseFirestore.instance;
final CloudinaryService _cloudinaryService = CloudinaryService(); 

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final User? _user = _auth.currentUser;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _bioController = TextEditingController();
  bool _isLoading = false;
  
  int _selectedIconId = 0;
  Color _selectedColor = TwitterTheme.blue;
  String? _profileImageUrl; 
  File? _selectedImageFile; 
  
  String? _bannerImageUrl;
  File? _selectedBannerFile; 

  // Department & Prodi State
  String? _selectedDepartment;
  Map<String, String>? _selectedProdi;

  @override
  void initState() {
    super.initState();
    if (_user != null) {
      _loadCurrentData();
    }
  }

  Future<void> _loadCurrentData() async {
    if (_user == null) return;
    final userDoc = await _firestore.collection('users').doc(_user!.uid).get();
    if (userDoc.exists) {
      final data = userDoc.data() as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _nameController.text = data['name'] ?? '';
          _bioController.text = data['bio'] ?? '';
          _profileImageUrl = data['profileImageUrl']; 
          _bannerImageUrl = data['bannerImageUrl']; 
          _selectedIconId = data['avatarIconId'] ?? 0;
          _selectedColor = AvatarHelper.getColor(data['avatarHex']);
          if (_profileImageUrl != null && _profileImageUrl!.isNotEmpty) {
            _selectedIconId = -1; 
          }

          // Load Department Info
          _selectedDepartment = data['department'];
          final savedProdiName = data['studyProgram'];
          
          // Restore Prodi selection if department matches
          if (_selectedDepartment != null && savedProdiName != null) {
            final prodis = PnjData.departments[_selectedDepartment];
            if (prodis != null) {
              _selectedProdi = prodis.firstWhere(
                (p) => p['name'] == savedProdiName, 
                orElse: () => prodis.first
              );
            }
          }

          // Auto-detect if not set
          if (_selectedDepartment == null) {
            _tryAutoDetectDepartment();
          }
        });
      }
    }
  }

  void _tryAutoDetectDepartment() {
    final email = _user?.email;
    if (email == null) return;
    
    // Regex to find .codeYear in email (e.g., name.te23@stu.pnj.ac.id)
    final RegExp regex = RegExp(r'\.([a-z]+)\d+@');
    final match = regex.firstMatch(email);
    
    if (match != null) {
      final code = match.group(1);
      if (code != null) {
        final detectedDept = _mapEmailCodeToDepartment(code);
        if (detectedDept != null && PnjData.departments.containsKey(detectedDept)) {
          setState(() {
            _selectedDepartment = detectedDept;
            _selectedProdi = null; // Reset prodi as we can't strictly determine it
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("Auto-detected department: $detectedDept"))
            );
          }
        }
      }
    }
  }

  String? _mapEmailCodeToDepartment(String code) {
    switch (code.toLowerCase()) {
      case 'te': return 'Teknik Elektro';
      case 'tm': return 'Teknik Mesin';
      case 'ts': return 'Teknik Sipil';
      case 'ti': 
      case 'tik': return 'Teknik Informatika & Komputer';
      case 'ak': return 'Akuntansi';
      case 'an': return 'Administrasi Niaga';
      case 'tg':
      case 'tgp': return 'Teknik Grafika & Penerbitan';
      default: return null;
    }
  }
  
  // Dedicated Cropper Function with Aggressive Memory Optimization
  Future<File?> _cropImage({required XFile imageFile, required bool isAvatar}) async {
    try {
      final dynamic cropped = await ImageCropper().cropImage(
        sourcePath: imageFile.path,
        compressQuality: 60, // Low quality to prevent OOM crashes
        maxWidth: 800,       // Limit resolution
        maxHeight: 800,
        // Force 1:1 for Avatar, 3:1 for Banner
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
            hideBottomControls: false,
          ),
          IOSUiSettings(
            title: isAvatar ? 'Crop Avatar' : 'Crop Banner',
            aspectRatioLockEnabled: true,
          ),
        ],
      );
      
      if (cropped != null) {
        // Handle different version return types
        if (cropped is File) return cropped;
        try { return File((cropped as dynamic).path); } catch (_) {}
      }
    } catch (e) {
      debugPrint("Cropping failed: $e");
      return File(imageFile.path);
    }
    return null;
  }

  Future<void> _pickImage({required bool isAvatar}) async {
    FocusScope.of(context).unfocus();
    final picker = ImagePicker();
    
    // Aggressive memory optimization for Picker
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery, 
      imageQuality: 70,
      maxWidth: 1000, 
      maxHeight: 1000
    );

    if (pickedFile != null) {
      final processedFile = await _cropImage(imageFile: pickedFile, isAvatar: isAvatar);
      if (processedFile != null) {
        setState(() {
          if (isAvatar) {
            _selectedImageFile = processedFile;
            _selectedIconId = -1; 
            _profileImageUrl = null; 
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Profile picture selected. Tap Save to apply.")));
          } else {
            _selectedBannerFile = processedFile;
            _bannerImageUrl = null;
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Banner selected. Tap Save to apply.")));
          }
        });
      }
    }
  }

  Future<void> _saveChanges() async {
    FocusScope.of(context).unfocus();

    if (_user == null || _nameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Name cannot be empty.')));
      return;
    }
    setState(() { _isLoading = true; });

    String? finalImageUrl = _profileImageUrl;
    String? finalBannerUrl = _bannerImageUrl;

    // Upload Avatar
    if (_selectedImageFile != null) {
      final uploadUrl = await _cloudinaryService.uploadImage(_selectedImageFile!);
      if (uploadUrl == null) {
        if (mounted) { setState(() { _isLoading = false; }); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to upload profile image.'))); }
        return;
      }
      finalImageUrl = "$uploadUrl?v=${DateTime.now().millisecondsSinceEpoch}";
    }
    
    // Upload Banner
    if (_selectedBannerFile != null) {
      final uploadUrl = await _cloudinaryService.uploadImage(_selectedBannerFile!);
      if (uploadUrl == null) {
        if (mounted) { setState(() { _isLoading = false; }); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to upload banner image.'))); }
        return;
      }
      finalBannerUrl = "$uploadUrl?v=${DateTime.now().millisecondsSinceEpoch}";
    }
    
    final int finalIconId = finalImageUrl != null ? -1 : _selectedIconId;

    try {
      // Prepare Data
      final Map<String, dynamic> userUpdateData = {
        'name': _nameController.text.trim(),
        'bio': _bioController.text.trim(),
        'avatarIconId': finalIconId, 
        'avatarHex': finalIconId != -1 ? '0x${_selectedColor.value.toRadixString(16).toUpperCase()}' : null, 
        'profileImageUrl': finalImageUrl, 
        'bannerImageUrl': finalBannerUrl, 
      };

      // Add Department info if selected
      if (_selectedDepartment != null) {
        userUpdateData['department'] = _selectedDepartment;
      }
      if (_selectedProdi != null) {
        userUpdateData['studyProgram'] = _selectedProdi!['name'];
        userUpdateData['departmentCode'] = _selectedProdi!['code']; // Important for the Badge
      }

      // 1. Update Main User Doc
      await _firestore.collection('users').doc(_user!.uid).update(userUpdateData);

      // 2. Update Denormalized Data (in chunks)
      await _updateDenormalizedData(
        _user!.uid, 
        _nameController.text.trim(), 
        finalIconId, 
        finalIconId != -1 ? '0x${_selectedColor.value.toRadixString(16).toUpperCase()}' : null, 
        finalImageUrl
      ); 

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Profile updated successfully!')));
        // Pass true to signal success to previous screen
        Navigator.of(context).pop(true); 
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Update failed: $e')));
      }
    } finally {
      if (mounted) {
        setState(() { _isLoading = false; });
      }
    }
  }

  Future<void> _updateDenormalizedData(
    String userId, 
    String newName, 
    int iconId, 
    String? hex, 
    String? imageUrl,
  ) async {
    final Map<String, dynamic> updateData = {
      'userName': newName,
      'avatarIconId': iconId,
      'avatarHex': hex,
      'profileImageUrl': imageUrl, 
    };
    
    final postsQuery = _firestore.collection('posts').where('userId', isEqualTo: userId);
    final postsSnapshot = await postsQuery.get();
    
    final commentsQuery = _firestore.collectionGroup('comments').where('userId', isEqualTo: userId);
    final commentsSnapshot = await commentsQuery.get();

    final allDocs = [...postsSnapshot.docs, ...commentsSnapshot.docs];
    
    if (allDocs.isEmpty) return;

    const int batchSize = 500;
    for (var i = 0; i < allDocs.length; i += batchSize) {
      final batch = _firestore.batch();
      final end = (i + batchSize < allDocs.length) ? i + batchSize : allDocs.length;
      
      for (var j = i; j < end; j++) {
        batch.update(allDocs[j].reference, updateData);
      }
      await batch.commit();
    }
  }

  Widget _buildProfileAvatar() {
    if (_selectedImageFile != null) {
      return CircleAvatar(
        radius: 45, 
        backgroundColor: Colors.grey,
        backgroundImage: FileImage(_selectedImageFile!),
      );
    }
    if (_profileImageUrl != null && _profileImageUrl!.isNotEmpty) {
      return CircleAvatar(
        radius: 45,
        backgroundColor: Colors.grey,
        backgroundImage: CachedNetworkImageProvider(_profileImageUrl!),
      );
    }
    return CircleAvatar(
      radius: 45,
      backgroundColor: _selectedColor,
      child: Icon(AvatarHelper.getIcon(_selectedIconId), size: 50, color: Colors.white),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool isCustomImageSet = _selectedImageFile != null || (_profileImageUrl != null && _profileImageUrl!.isNotEmpty);
    final bool isCustomBannerSet = _selectedBannerFile != null || (_bannerImageUrl != null && _bannerImageUrl!.isNotEmpty);

    return GestureDetector(
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      child: Scaffold(
        appBar: AppBar(
          title: Text('Edit Profile', style: TextStyle(fontWeight: FontWeight.bold)),
          centerTitle: true,
          elevation: 0,
          backgroundColor: theme.scaffoldBackgroundColor,
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: TextButton(
                onPressed: _isLoading ? null : _saveChanges,
                style: TextButton.styleFrom(
                  backgroundColor: TwitterTheme.blue, 
                  shape: StadiumBorder(), 
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 0),
                ),
                child: _isLoading 
                    ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text('Save', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
        body: SingleChildScrollView(
          child: Column(
            children: [
              // --- MODERN HEADER SECTION ---
              SizedBox(
                height: 180, 
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.topCenter,
                  children: [
                    // Banner
                    GestureDetector(
                      onTap: () => _pickImage(isAvatar: false),
                      child: Container(
                        height: 140,
                        width: double.infinity,
                        color: theme.cardColor,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (_selectedBannerFile != null)
                              Image.file(_selectedBannerFile!, fit: BoxFit.cover)
                            else if (_bannerImageUrl != null && _bannerImageUrl!.isNotEmpty)
                              CachedNetworkImage(
                                imageUrl: _bannerImageUrl!,
                                fit: BoxFit.cover,
                                placeholder: (context, url) => Center(child: CircularProgressIndicator(color: TwitterTheme.blue)),
                                errorWidget: (context, url, error) => Icon(Icons.error_outline, color: Colors.grey),
                              ),
                            Container(
                              color: Colors.black26, 
                              child: Center(
                                child: Icon(Icons.add_a_photo_outlined, color: Colors.white.withOpacity(0.8), size: 32),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    
                    if (isCustomBannerSet)
                      Positioned(
                        top: 10, right: 10,
                        child: GestureDetector(
                          onTap: () => setState(() { _selectedBannerFile = null; _bannerImageUrl = null; }),
                          child: Container(
                            padding: EdgeInsets.all(6),
                            decoration: BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                            child: Icon(Icons.close, color: Colors.white, size: 16),
                          ),
                        ),
                      ),

                    // Avatar
                    Positioned(
                      bottom: 0, left: 20,
                      child: GestureDetector(
                        onTap: () => _pickImage(isAvatar: true),
                        child: Stack(
                          children: [
                            Container(
                              padding: EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: theme.scaffoldBackgroundColor, 
                              ),
                              child: _buildProfileAvatar(),
                            ),
                            Positioned(
                              bottom: 0, right: 0,
                              child: Container(
                                padding: EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: TwitterTheme.blue,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: theme.scaffoldBackgroundColor, width: 2)
                                ),
                                child: Icon(Icons.camera_alt, size: 14, color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isCustomImageSet)
                      Padding(
                        padding: const EdgeInsets.only(left: 8.0, bottom: 16.0),
                        child: GestureDetector(
                          onTap: () => setState(() { _selectedImageFile = null; _profileImageUrl = null; _selectedIconId = 0; }),
                          child: Text("Remove photo", style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600, fontSize: 13)),
                        ),
                      ),

                    SizedBox(height: 10),

                    TextField(
                      controller: _nameController,
                      autofocus: false,
                      decoration: InputDecoration(
                        labelText: 'Display Name',
                        hintText: 'Enter your name',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      ),
                    ),
                    SizedBox(height: 20),
                    TextField(
                      controller: _bioController,
                      autofocus: false,
                      maxLength: 200,
                      decoration: InputDecoration(
                        labelText: 'Bio',
                        hintText: 'Tell the world about yourself',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        alignLabelWithHint: true,
                      ),
                      maxLines: 4,
                      minLines: 1,
                    ),
                    
                    SizedBox(height: 30),

                    // --- ACADEMIC INFO SECTION (Added back) ---
                    Text("Academic Info", style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    SizedBox(height: 16),
                    
                    DropdownButtonFormField<String>(
                      decoration: InputDecoration(
                        labelText: "Department (Jurusan)",
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        filled: true,
                        fillColor: theme.cardColor,
                      ),
                      value: _selectedDepartment,
                      isExpanded: true,
                      items: PnjData.departments.keys.map((String dept) {
                        return DropdownMenuItem(value: dept, child: Text(dept, overflow: TextOverflow.ellipsis));
                      }).toList(),
                      onChanged: (val) {
                        setState(() {
                          _selectedDepartment = val;
                          _selectedProdi = null; 
                        });
                      },
                    ),
                    SizedBox(height: 16),
                    
                    DropdownButtonFormField<Map<String, String>>(
                      decoration: InputDecoration(
                        labelText: "Study Program (Prodi)",
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        filled: true,
                        fillColor: theme.cardColor,
                      ),
                      value: _selectedProdi,
                      isExpanded: true,
                      items: _selectedDepartment == null 
                        ? [] 
                        : PnjData.departments[_selectedDepartment]!.map((Map<String, String> prodi) {
                            return DropdownMenuItem<Map<String, String>>(
                              value: prodi,
                              child: Text(prodi['name']!, overflow: TextOverflow.ellipsis),
                            );
                          }).toList(),
                      onChanged: _selectedDepartment == null ? null : (val) {
                        setState(() {
                          _selectedProdi = val;
                        });
                      },
                    ),

                    SizedBox(height: 30),
                    
                    // --- AVATAR PRESETS ---
                    if (!isCustomImageSet) ...[
                      Divider(),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12.0),
                        child: Text("Or choose an avatar preset", style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold, color: theme.hintColor)),
                      ),
                      SizedBox(
                        height: 60,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: 10,
                          separatorBuilder: (_,__) => SizedBox(width: 16),
                          itemBuilder: (context, index) {
                            final isSelected = _selectedIconId == index;
                            return GestureDetector(
                              onTap: () {
                                FocusScope.of(context).unfocus();
                                setState(() => _selectedIconId = index);
                              },
                              child: Container(
                                width: 50,
                                height: 50,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isSelected ? theme.primaryColor.withOpacity(0.1) : theme.cardColor,
                                  border: isSelected ? Border.all(color: theme.primaryColor, width: 2) : Border.all(color: theme.dividerColor),
                                ),
                                child: Icon(
                                  AvatarHelper.getIcon(index), 
                                  color: isSelected ? theme.primaryColor : theme.hintColor,
                                  size: 24
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      SizedBox(height: 16),
                      SizedBox(
                        height: 40,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: AvatarHelper.presetColors.length,
                          separatorBuilder: (_,__) => SizedBox(width: 12),
                          itemBuilder: (context, index) {
                            final color = AvatarHelper.presetColors[index];
                            final isSelected = _selectedColor.value == color.value;
                            return GestureDetector(
                              onTap: () {
                                FocusScope.of(context).unfocus();
                                setState(() => _selectedColor = color);
                              },
                              child: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: color,
                                  shape: BoxShape.circle,
                                  border: isSelected ? Border.all(color: theme.textTheme.bodyLarge!.color!, width: 2) : null,
                                ),
                                child: isSelected ? Icon(Icons.check, color: Colors.white, size: 20) : null,
                              ),
                            );
                          },
                        ),
                      ),
                    ],

                    SizedBox(height: 30),
                    Divider(),
                    
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Container(
                        padding: EdgeInsets.all(8),
                        decoration: BoxDecoration(color: theme.cardColor, borderRadius: BorderRadius.circular(8)),
                        child: Icon(Icons.lock_outline, color: theme.primaryColor),
                      ),
                      title: Text('Change Password'),
                      trailing: Icon(Icons.arrow_forward_ios, size: 14, color: theme.hintColor),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (context) => ChangePasswordScreen()),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}