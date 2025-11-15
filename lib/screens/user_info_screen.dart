// ignore_for_file: prefer_const_constructors
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../auth_gate.dart'; 

final FirebaseAuth _auth = FirebaseAuth.instance;
final FirebaseFirestore _firestore = FirebaseFirestore.instance;

class UserInfoScreen extends StatefulWidget {
  const UserInfoScreen({super.key});

  @override
  State<UserInfoScreen> createState() => _UserInfoScreenState();
}

class _UserInfoScreenState extends State<UserInfoScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _nimController = TextEditingController(); 
  bool _isLoading = false;

  Future<void> _saveProfile() async {
    if (_nameController.text.isEmpty || _nimController.text.isEmpty) { 
       ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in your name and NIM.')), 
      );
      return;
    }

    setState(() { _isLoading = true; });

    try {
      final user = _auth.currentUser;
      if (user == null) return;

      await _firestore.collection('users').doc(user.uid).set({
        'name': _nameController.text.trim(),
        'nim': _nimController.text.trim(), 
        'bio': 'About me...', // Tambahkan bio default
      }, SetOptions(merge: true)); 

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile saved.')),
        );
         Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AuthGate()),
          (route) => false,
        );
      }

    } catch (e) {
      if(mounted) {
         ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save profile: $e')),
        );
      }
      setState(() { _isLoading = false; });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nimController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Complete Your Profile')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Welcome! Please complete your profile.'),
            const SizedBox(height: 20),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Full Name'),
            ),
            const SizedBox(height: 10),
             TextField( 
              controller: _nimController,
              decoration: const InputDecoration(labelText: 'NIM'),
            ),
            const SizedBox(height: 30),
            if (_isLoading) const CircularProgressIndicator(),
            if (!_isLoading) ElevatedButton(
              onPressed: _saveProfile,
              child: const Text('Save & Continue'),
            ),
          ],
        ),
      ),
    );
  }
}