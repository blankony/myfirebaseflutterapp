// ignore_for_file: prefer_const_constructors
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
  
  // New Avatar State
  int _selectedIconId = 0;
  Color _selectedColor = TwitterTheme.blue;

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
      setState(() {
        _nameController.text = data['name'] ?? '';
        _bioController.text = data['bio'] ?? '';
        // Load Avatar Data
        _selectedIconId = data['avatarIconId'] ?? 0;
        _selectedColor = AvatarHelper.getColor(data['avatarHex']);
      });
    }
  }
  
  Future<void> _saveChanges() async {
    if (_user == null || _nameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Name cannot be empty.')));
      return;
    }
    setState(() { _isLoading = true; });

    final String newName = _nameController.text.trim();
    final String newBio = _bioController.text.trim();
    final String colorHex = '0x${_selectedColor.value.toRadixString(16).toUpperCase()}';

    try {
      // 1. Update User Profile
      await _firestore.collection('users').doc(_user!.uid).update({
        'name': newName,
        'bio': newBio,
        'avatarIconId': _selectedIconId,
        'avatarHex': colorHex,
      });

      // 2. Update Old Posts/Comments (Denormalization)
      await _updateDenormalizedData(_user!.uid, newName, _selectedIconId, colorHex);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Profile updated successfully!')));
        // Correctly pop back to the previous screen (ProfilePage or AccountCenterPage)
        Navigator.of(context).pop(); 
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

  Future<void> _updateDenormalizedData(String userId, String newName, int iconId, String hex) async {
    final writeBatch = _firestore.batch();
    
    final Map<String, dynamic> updateData = {
      'userName': newName,
      'avatarIconId': iconId,
      'avatarHex': hex,
    };
    
    // Update posts
    final postsQuery = _firestore.collection('posts').where('userId', isEqualTo: userId);
    final postsSnapshot = await postsQuery.get();
    for (final doc in postsSnapshot.docs) {
      writeBatch.update(doc.reference, updateData);
    }

    // Update comments
    final commentsQuery = _firestore.collectionGroup('comments').where('userId', isEqualTo: userId);
    final commentsSnapshot = await commentsQuery.get();
    for (final doc in commentsSnapshot.docs) {
      writeBatch.update(doc.reference, updateData);
    }
    
    await writeBatch.commit();
  }

  Widget _buildProfileAvatar() {
    return CircleAvatar(
      radius: 50,
      backgroundColor: _selectedColor,
      child: Icon(
        AvatarHelper.getIcon(_selectedIconId),
        size: 60,
        color: Colors.white,
      ),
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
    
    return Scaffold(
      appBar: AppBar(
        title: Text('Edit Profile'),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _saveChanges,
            child: _isLoading 
                ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : Text('Save', style: TextStyle(color: TwitterTheme.blue, fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Avatar Preview
            Center(
              child: _buildProfileAvatar(),
            ),
            SizedBox(height: 24),

            // Icon Selection
            Text("Choose Avatar Icon", style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              alignment: WrapAlignment.center,
              // Generate 10 icons (0-9)
              children: List.generate(10, (index) {
                final bool isSelected = _selectedIconId == index;
                return GestureDetector(
                  onTap: () => setState(() => _selectedIconId = index),
                  child: Container(
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isSelected ? theme.primaryColor.withOpacity(0.2) : Colors.transparent,
                      border: isSelected ? Border.all(color: theme.primaryColor, width: 2) : null,
                    ),
                    child: Icon(
                      AvatarHelper.getIcon(index),
                      size: 30,
                      color: isSelected ? theme.primaryColor : theme.hintColor,
                    ),
                  ),
                );
              }),
            ),

            SizedBox(height: 24),

            // Color Selection
            Text("Choose Background", style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: AvatarHelper.presetColors.map((color) {
                final bool isSelected = _selectedColor.value == color.value;
                return GestureDetector(
                  onTap: () => setState(() => _selectedColor = color),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: isSelected ? Border.all(color: theme.textTheme.bodyLarge!.color!, width: 3) : null,
                      boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
                    ),
                    child: isSelected ? Icon(Icons.check, color: Colors.white, size: 20) : null,
                  ),
                );
              }).toList(),
            ),

            SizedBox(height: 32),
            Divider(),
            SizedBox(height: 16),

            // Text Fields
            TextField(
              controller: _nameController,
              decoration: InputDecoration(labelText: 'Name', prefixIcon: Icon(Icons.person_outline)),
            ),
            SizedBox(height: 16),
            TextField(
              controller: _bioController,
              decoration: InputDecoration(labelText: 'Bio', prefixIcon: Icon(Icons.info_outline)),
              maxLines: 3,
            ),
            
            SizedBox(height: 24),
            ListTile(
              leading: Icon(Icons.lock_outline, color: theme.primaryColor),
              title: Text('Change Password'),
              trailing: Icon(Icons.arrow_forward_ios, size: 16),
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
}