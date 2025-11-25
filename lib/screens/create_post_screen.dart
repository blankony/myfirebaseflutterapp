// ignore_for_file: prefer_const_constructors
import 'dart:async'; // Perlu untuk Timer
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../main.dart'; 
import '../services/prediction_service.dart'; // Import Service Baru

final FirebaseAuth _auth = FirebaseAuth.instance;
final FirebaseFirestore _firestore = FirebaseFirestore.instance;

class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({super.key});

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final TextEditingController _postController = TextEditingController();
  final PredictionService _predictionService = PredictionService(); // Init Service
  
  bool _isLoading = false;
  bool _canPost = false; 

  String _userName = 'Anonymous User';
  String _userEmail = 'anon@mail.com';
  
  // Avatar Defaults
  int _avatarIconId = 0;
  String _avatarHex = '';

  // Predictive Text State
  String? _predictedText;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _loadUserData(); 
  }

  // Fungsi listener manual untuk handle debounce dan state change
  void _onTextChanged(String text) {
    setState(() {
      _canPost = text.trim().isNotEmpty;
      _predictedText = null; // Reset prediksi saat user mengetik
    });

    if (_debounce?.isActive ?? false) _debounce!.cancel();
    
    // Tunggu 800ms setelah user berhenti mengetik (Debouncing)
    _debounce = Timer(const Duration(milliseconds: 800), () async {
      if (text.trim().isEmpty) return;
      
      final suggestion = await _predictionService.getCompletion(text, 'post');
      if (mounted && suggestion != null && suggestion.isNotEmpty) {
        setState(() {
          _predictedText = suggestion;
        });
      }
    });
  }

  void _acceptPrediction() {
    if (_predictedText != null) {
      final currentText = _postController.text;
      // Tambahkan spasi jika belum ada di akhir kalimat
      final separator = currentText.endsWith(' ') ? '' : ' ';
      final newText = "$currentText$separator$_predictedText ";
      
      _postController.text = newText;
      
      // Pindahkan kursor ke paling akhir
      _postController.selection = TextSelection.fromPosition(
        TextPosition(offset: newText.length),
      );
      
      setState(() {
        _predictedText = null; // Sembunyikan saran setelah dipakai
      });
    }
  }

  Future<void> _loadUserData() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (userDoc.exists) {
        final data = userDoc.data() as Map<String, dynamic>;
        setState(() {
          _userName = data['name'] ?? _userName;
          _userEmail = user.email ?? _userEmail;
          _avatarIconId = data['avatarIconId'] ?? 0;
          _avatarHex = data['avatarHex'] ?? '';
        });
      }
    } catch (e) {
      // Fail silently
    }
  }

  Future<void> _submitPost() async {
    if (!_canPost || _isLoading) return; 

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
        'avatarIconId': _avatarIconId,
        'avatarHex': _avatarHex,
        'likes': {},
        'commentCount': 0,
        'retweetCount': 0, 
        'repostedBy': [],
      });

      if (context.mounted) {
        Navigator.of(context).pop(); 
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
    _debounce?.cancel();
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: ElevatedButton(
              onPressed: _canPost && !_isLoading ? _submitPost : null, 
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
            // Preview Current Avatar
            CircleAvatar(
              radius: 24,
              backgroundColor: AvatarHelper.getColor(_avatarHex),
              child: Icon(
                AvatarHelper.getIcon(_avatarIconId),
                color: Colors.white,
                size: 24,
              ),
            ),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _postController,
                    onChanged: _onTextChanged, // Listener di sini
                    autofocus: true, 
                    maxLines: null, 
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
                  
                  // === AI PREDICTION WIDGET ===
                  if (_predictedText != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: GestureDetector(
                        onTap: _acceptPrediction,
                        child: Container(
                          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: TwitterTheme.blue.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: TwitterTheme.blue.withOpacity(0.3)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.auto_awesome, size: 14, color: TwitterTheme.blue),
                              SizedBox(width: 6),
                              Flexible(
                                child: RichText(
                                  text: TextSpan(
                                    children: [
                                      TextSpan(
                                        text: "Suggestion: ",
                                        style: TextStyle(color: TwitterTheme.blue, fontWeight: FontWeight.bold, fontSize: 13),
                                      ),
                                      TextSpan(
                                        text: " ...$_predictedText",
                                        style: TextStyle(color: TwitterTheme.blue, fontStyle: FontStyle.italic, fontSize: 13),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}