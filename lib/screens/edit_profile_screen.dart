// ignore_for_file: prefer_const_constructors
import 'dart:async'; 
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../main.dart'; // Untuk tema
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

  @override
  void initState() {
    super.initState();
    if (_user != null) {
      _isEmailVerified = _user!.emailVerified;
      _loadCurrentData();
      if (!_isEmailVerified) {
        _verificationTimer = Timer.periodic(
          const Duration(seconds: 3),
          _checkEmailVerification,
        );
      }
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

      await _updateAllUsernames(_user!.uid, newName);

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

  Future<void> _updateAllUsernames(String userId, String newName) async {
    final writeBatch = _firestore.batch();
    
    final postsQuery = _firestore
        .collection('posts')
        .where('userId', isEqualTo: userId);
    
    final postsSnapshot = await postsQuery.get();
    for (final doc in postsSnapshot.docs) {
      writeBatch.update(doc.reference, {'userName': newName});
    }

    final commentsQuery = _firestore
        .collectionGroup('comments')
        .where('userId', isEqualTo: userId);
        
    final commentsSnapshot = await commentsQuery.get();
    for (final doc in commentsSnapshot.docs) {
      writeBatch.update(doc.reference, {'userName': newName});
    }
    
    try {
      await writeBatch.commit();
    } catch (e) {
      print('Error updating denormalized usernames: $e');
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
            Container(
              height: 200, 
              width: double.infinity,
              decoration: BoxDecoration(
                color: TwitterTheme.darkGrey,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  "Image upload feature\nnot yet available",
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleSmall,
                ),
              ),
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
        crossAxisAlignment: CrossAxisAlignment.center, // Sejajarkan secara vertikal
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
          
          // ### PERUBAHAN DI SINI ###
          _isEmailVerified
              ? Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green, size: 18),
                    SizedBox(width: 4),
                    Text("Verified", style: TextStyle(color: Colors.green)),
                  ],
                )
              : Column( // Ganti dari TextButton ke Column
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      "Email is not verified",
                      style: TextStyle(color: Colors.red, fontSize: 13),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero, // Kurangi padding
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap, // Kecilkan area klik
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
          // ### AKHIR PERUBAHAN ###
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