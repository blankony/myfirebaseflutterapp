// ignore_for_file: prefer_const_constructors
import 'dart:async'; 
import 'dart:io'; 
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart'; 
import 'package:image_cropper/image_cropper.dart'; 
import 'package:path_provider/path_provider.dart'; 
import 'package:path/path.dart' as p; 
import 'package:shared_preferences/shared_preferences.dart'; 
import '../main.dart'; 
import 'change_password_screen.dart'; 

final FirebaseAuth _auth = FirebaseAuth.instance;
final FirebaseFirestore _firestore = FirebaseFirestore.instance;

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

  bool _isEmailVerified = false;
  Timer? _verificationTimer;

  File? _localImageFile;
  String? _selectedAvatarIconName;

  @override
  void initState() {
    super.initState();
    if (_user != null) {
      _isEmailVerified = _user!.emailVerified;
      _loadCurrentData();
      _loadLocalAvatar();
      if (!_isEmailVerified) {
        _verificationTimer = Timer.periodic(
          const Duration(seconds: 3),
          _checkEmailVerification,
        );
      }
    }
  }

  Future<void> _loadLocalAvatar() async {
    if (_user == null) return;
    final prefs = await SharedPreferences.getInstance();
    final String? imagePath = prefs.getString('profile_picture_path_${_user!.uid}');
    final String? iconName = prefs.getString('profile_avatar_icon_${_user!.uid}');

    File? newFile;
    String? newIconName;

    if (imagePath != null) {
      final file = File(imagePath);
      if (await file.exists()) {
        newFile = file;
        newIconName = null;
      } else {
        await prefs.remove('profile_picture_path_${_user!.uid}');
      }
    } else if (iconName != null) {
      newFile = null;
      newIconName = iconName;
    }

    if (mounted) {
      setState(() {
        _localImageFile = newFile;
        _selectedAvatarIconName = newIconName;
      });
    }
  }

  Future<void> _checkEmailVerification(Timer timer) async {
    await _user?.reload();
    final freshUser = _auth.currentUser;
    if (freshUser?.emailVerified ?? false) {
      timer.cancel(); 
      setState(() {
        _isEmailVerified = true;
      });
    }
  }

  Future<void> _sendVerificationEmail() async {
    try {
      await _user?.sendEmailVerification();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Verification email sent! Please check your inbox.')),
        );
      }
    } catch (e) {
      String errorMessage = 'Failed to send email: $e'; 
      if (e is FirebaseAuthException && e.code == 'too-many-requests') {
        errorMessage = 'Please wait for a few moments to resend verification...';
      }
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage)),
        );
      }
    }
  }

  Future<void> _loadCurrentData() async {
    if (_user == null) return;
    final userDoc = await _firestore.collection('users').doc(_user!.uid).get();
    if (userDoc.exists) {
      final data = userDoc.data() as Map<String, dynamic>;
      _nameController.text = data['name'] ?? '';
      _bioController.text = data['bio'] ?? '';
    }
  }

  Future<void> _showPickOptions() async {
    // Reload state sebelum menampilkan modal
    await _loadLocalAvatar();
    
    if (!mounted) return;

    // Cek apakah ada foto atau avatar
    final bool hasAvatar = _localImageFile != null || _selectedAvatarIconName != null;

    showModalBottomSheet(
      context: context,
      builder: (BuildContext ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.photo_library),
                title: Text('Pick from Gallery'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _pickImage(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: Icon(Icons.camera_alt),
                title: Text('Take a picture'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _pickImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: Icon(Icons.auto_awesome),
                title: Text('Choose Avatar Template'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _showAvatarPicker();
                },
              ),
              if (hasAvatar)
                ListTile(
                  leading: Icon(Icons.delete_outline, color: Colors.red),
                  title: Text(
                    'Remove Photo/Avatar',
                    style: TextStyle(color: Colors.red),
                  ),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _removeAvatar();
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showAvatarPicker() async {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Choose an Avatar'),
          content: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildAvatarOption(context, 'face', Icons.face),
              _buildAvatarOption(context, 'rocket', Icons.rocket_launch),
              _buildAvatarOption(context, 'pet', Icons.pets),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAvatarOption(BuildContext context, String iconName, IconData iconData) {
    return InkWell(
      onTap: () => _selectAvatarIcon(iconName),
      child: CircleAvatar(
        radius: 30,
        backgroundColor: TwitterTheme.blue.withOpacity(0.2),
        child: Icon(iconData, size: 30, color: TwitterTheme.blue),
      ),
    );
  }

  Future<void> _selectAvatarIcon(String iconName) async {
    if (_user == null) return;
    Navigator.of(context).pop();

    final prefs = await SharedPreferences.getInstance();
    
    await prefs.setString('profile_avatar_icon_${_user!.uid}', iconName);
    
    final String? imagePath = prefs.getString('profile_picture_path_${_user!.uid}');
    if (imagePath != null) {
      final file = File(imagePath);
      if (await file.exists()) {
        await file.delete();
      }
      await prefs.remove('profile_picture_path_${_user!.uid}');
    }

    setState(() {
      _localImageFile = null;
      _selectedAvatarIconName = iconName;
    });
  }
  
  Future<void> _removeAvatar() async {
    if (_user == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final String? imagePath = prefs.getString('profile_picture_path_${_user!.uid}');
      
      if (imagePath != null) {
        final file = File(imagePath);
        if (await file.exists()) {
          await file.delete();
        }
        await prefs.remove('profile_picture_path_${_user!.uid}');
      }
      await prefs.remove('profile_avatar_icon_${_user!.uid}');

      setState(() {
        _localImageFile = null;
        _selectedAvatarIconName = null;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Avatar removed.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to remove avatar: $e')),
        );
      }
    }
  }
  
  Future<void> _pickImage(ImageSource source) async {
    if (_user == null) return;
    final ImagePicker picker = ImagePicker();
    
    final XFile? pickedFile = await picker.pickImage(source: source);
    if (pickedFile == null) return;

    final CroppedFile? croppedFile = await ImageCropper().cropImage(
      sourcePath: pickedFile.path,
      aspectRatio: CropAspectRatio(ratioX: 1, ratioY: 1),
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Crop Profile Photo',
          toolbarColor: TwitterTheme.blue,
          toolbarWidgetColor: Colors.white,
          initAspectRatio: CropAspectRatioPreset.square,
          lockAspectRatio: true,
          hideBottomControls: false,
        ),
        IOSUiSettings(
          title: 'Crop Profile Photo',
          aspectRatioLockEnabled: true,
          resetAspectRatioEnabled: false,
        ),
      ],
    );

    if (croppedFile == null) return;

    final appDir = await getApplicationDocumentsDirectory();
    final fileName = 'profile_pic_${_user!.uid}.jpg'; 
    final localFile = File(p.join(appDir.path, fileName));

    final newFile = await File(croppedFile.path).copy(localFile.path);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('profile_picture_path_${_user!.uid}', newFile.path);
    await prefs.remove('profile_avatar_icon_${_user!.uid}');
    
    setState(() {
      _localImageFile = newFile;
      _selectedAvatarIconName = null;
    });
  }

  Future<void> _saveChanges() async {
    if (_user == null || _nameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Name cannot be empty.')),
      );
      return;
    }
    setState(() { _isLoading = true; });

    final String newName = _nameController.text.trim();
    final String newBio = _bioController.text.trim();

    try {
      await _firestore.collection('users').doc(_user!.uid).update({
        'name': newName,
        'bio': newBio,
      });

      await _updateDenormalizedData(_user!.uid, newName);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Profile updated successfully!')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Update failed. Error: ${e.toString()}'),
            duration: Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() { _isLoading = false; });
      }
    }
  }

  Future<void> _updateDenormalizedData(String userId, String newName) async {
    final writeBatch = _firestore.batch();
    
    final Map<String, dynamic> updateData = {
      'userName': newName,
    };
    
    final postsQuery = _firestore
        .collection('posts')
        .where('userId', isEqualTo: userId);
    
    final postsSnapshot = await postsQuery.get();
    for (final doc in postsSnapshot.docs) {
      writeBatch.update(doc.reference, updateData);
    }

    final commentsQuery = _firestore
        .collectionGroup('comments')
        .where('userId', isEqualTo: userId);
        
    final commentsSnapshot = await commentsQuery.get();
    for (final doc in commentsSnapshot.docs) {
      writeBatch.update(doc.reference, updateData);
    }
    
    try {
      await writeBatch.commit();
    } catch (e) {
      print('Error updating denormalized data: $e');
      throw Exception('Failed to update old posts/comments: $e');
    }
  }

  @override
  void dispose() {
    _verificationTimer?.cancel(); 
    _nameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  IconData _getIconDataFromString(String? iconName) {
    switch (iconName) {
      case 'face':
        return Icons.face;
      case 'rocket':
        return Icons.rocket_launch;
      case 'pet':
        return Icons.pets;
      default:
        return Icons.person;
    }
  }

  Widget _buildProfileAvatar() {
    if (_localImageFile != null) {
      return CircleAvatar(
        radius: 50,
        backgroundImage: FileImage(_localImageFile!),
      );
    }

    if (_selectedAvatarIconName != null) {
      return CircleAvatar(
        radius: 50,
        backgroundColor: TwitterTheme.blue.withOpacity(0.2),
        child: Icon(
          _getIconDataFromString(_selectedAvatarIconName),
          size: 60,
          color: TwitterTheme.blue,
        ),
      );
    }
    
    return ValueListenableBuilder(
      valueListenable: _nameController,
      builder: (context, value, child) {
        String initial = value.text.isNotEmpty ? value.text[0].toUpperCase() : 'U';
        return CircleAvatar(
          radius: 50,
          child: Text(initial, style: TextStyle(fontSize: 40)),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      appBar: AppBar(
        title: Text('Edit Profile'),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _saveChanges,
            child: _isLoading 
                ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : Text(
                    'Save',
                    style: TextStyle(
                      color: TwitterTheme.blue,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  height: 150, 
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: TwitterTheme.darkGrey,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                Positioned(
                  bottom: -30,
                  left: 16,
                  child: CircleAvatar(
                    radius: 52, 
                    backgroundColor: theme.scaffoldBackgroundColor,
                    child: _buildProfileAvatar(),
                  ),
                ),
              ],
            ),
            
            SizedBox(height: 40),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: _showPickOptions,
                  child: Text('Change Photo'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.textTheme.bodyLarge?.color,
                    side: BorderSide(color: theme.dividerColor),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                ),
              ],
            ),

            SizedBox(height: 24), 
            _buildEmailStatus(theme),
            SizedBox(height: 16),
            
            TextField(
              controller: _nameController,
              decoration: InputDecoration(labelText: 'Name'),
            ),
            SizedBox(height: 16),
            TextField(
              controller: _bioController,
              decoration: InputDecoration(labelText: 'Bio'),
              maxLines: 4,
            ),
            SizedBox(height: 24),
            Divider(),

            _buildSettingsTile(
              context: context,
              icon: Icons.lock_outline,
              title: 'Change Password',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => ChangePasswordScreen()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmailStatus(ThemeData theme) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.inputDecorationTheme.fillColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center, 
        children: [
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Email", style: theme.textTheme.titleSmall),
                SizedBox(height: 2),
                Text(
                  _user?.email ?? 'No email found',
                  style: theme.textTheme.bodyLarge,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          
          _isEmailVerified
              ? Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green, size: 18),
                    SizedBox(width: 4),
                    Text("Verified", style: TextStyle(color: Colors.green)),
                  ],
                )
              : Column( 
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      "Email is not verified",
                      style: TextStyle(color: Colors.red, fontSize: 13),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero, 
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap, 
                        alignment: Alignment.centerRight
                      ),
                      onPressed: _sendVerificationEmail,
                      child: Text(
                        "Verify", 
                        style: TextStyle(color: TwitterTheme.blue, fontWeight: FontWeight.bold)
                      ),
                    ),
                  ],
                )
        ],
      ),
    );
  }

  Widget _buildSettingsTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(icon, color: theme.primaryColor),
      title: Text(title, style: TextStyle(color: theme.textTheme.bodyLarge?.color)),
      onTap: onTap,
    );
  }
}