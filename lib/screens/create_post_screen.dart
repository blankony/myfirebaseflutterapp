// ignore_for_file: prefer_const_constructors
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../main.dart'; // Untuk tema

final FirebaseAuth _auth = FirebaseAuth.instance;
final FirebaseFirestore _firestore = FirebaseFirestore.instance;

class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({super.key});

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final TextEditingController _postController = TextEditingController();
  bool _isLoading = false;
  bool _canPost = false; // Untuk mengaktifkan/menonaktifkan tombol Post

  // Data user yang akan digunakan untuk posting
  String _userName = 'Anonymous User';
  String _userEmail = 'anon@mail.com';

  @override
  void initState() {
    super.initState();
    _loadUserData();
    // Dengarkan perubahan pada text field
    _postController.addListener(() {
      setState(() {
        _canPost = _postController.text.trim().isNotEmpty;
      });
    });
  }

  // Ambil data user saat halaman dibuka
  Future<void> _loadUserData() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (userDoc.exists) {
        _userName = userDoc.get('name') ?? _userName;
        _userEmail = user.email ?? _userEmail;
      }
    } catch (e) {
      // Gagal mengambil data, gunakan default
    }
  }

  Future<void> _submitPost() async {
    if (!_canPost || _isLoading) return; // Jangan post jika kosong atau sedang loading

    final user = _auth.currentUser;
    if (user == null) return;

    setState(() { _isLoading = true; });

    try {
      await _firestore.collection('posts').add({
        'text': _postController.text,
        'timestamp': FieldValue.serverTimestamp(),
        'userId': user.uid,
        'userName': _userName,
        'userEmail': _userEmail,
        'likes': {},
        'commentCount': 0,
        'retweetCount': 0,
      });

      if (context.mounted) {
        Navigator.of(context).pop(); // Tutup halaman jika sukses
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to post: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() { _isLoading = false; });
      }
    }
  }

  @override
  void dispose() {
    _postController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.close, color: theme.primaryColor),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          // Tombol Post
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: ElevatedButton(
              onPressed: _canPost && !_isLoading ? _submitPost : null, // Nonaktif jika tidak bisa post
              child: _isLoading 
                  ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text('Post'),
              style: ElevatedButton.styleFrom(
                backgroundColor: TwitterTheme.blue,
                foregroundColor: Colors.white,
                disabledBackgroundColor: TwitterTheme.blue.withOpacity(0.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Avatar User
            CircleAvatar(
              radius: 24,
              child: Icon(Icons.person), // TODO: Ganti dengan foto profil
            ),
            SizedBox(width: 16),
            // Text Input
            Expanded(
              child: TextField(
                controller: _postController,
                autofocus: true, // Langsung fokus saat halaman terbuka
                maxLines: null, // Izinkan multiline
                style: TextStyle(fontSize: 18),
                decoration: InputDecoration(
                  hintText: "What's happening?",
                  border: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                ),
              ),
            ),
          ],
        ),
      ),
      // TODO: Tambahkan toolbar di atas keyboard jika perlu
    );
  }
}