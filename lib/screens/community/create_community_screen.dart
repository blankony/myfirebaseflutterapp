// ignore_for_file: prefer_const_constructors
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../main.dart';
import '../../services/overlay_service.dart';

class CreateCommunityScreen extends StatefulWidget {
  const CreateCommunityScreen({super.key});

  @override
  State<CreateCommunityScreen> createState() => _CreateCommunityScreenState();
}

class _CreateCommunityScreenState extends State<CreateCommunityScreen> {
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  bool _isLoading = false;

  Future<void> _create() async {
    if (_nameController.text.isEmpty) return;
    
    setState(() => _isLoading = true);
    final user = FirebaseAuth.instance.currentUser;
    
    try {
      await FirebaseFirestore.instance.collection('communities').add({
        'name': _nameController.text.trim(),
        'description': _descController.text.trim(),
        'ownerId': user!.uid,
        'admins': [user.uid], // Owner otomatis jadi admin
        'members': [user.uid], // Owner otomatis jadi member
        'createdAt': FieldValue.serverTimestamp(),
        'imageUrl': null, // Bisa ditambahkan fitur upload image nanti
      });
      
      if(mounted) {
        OverlayService().showTopNotification(context, "Community Created!", Icons.check, (){}, color: Colors.green);
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
    return Scaffold(
      appBar: AppBar(title: Text("New Community")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: "Community Name",
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            SizedBox(height: 16),
            TextField(
              controller: _descController,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: "Description",
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _create,
                style: ElevatedButton.styleFrom(
                  backgroundColor: TwitterTheme.blue,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isLoading ? CircularProgressIndicator(color: Colors.white) : Text("Create"),
              ),
            )
          ],
        ),
      ),
    );
  }
}