// ignore_for_file: prefer_const_constructors
import 'dart:async'; 
import 'dart:io'; 
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart'; 
import 'package:image_editor_plus/image_editor_plus.dart'; 
import 'package:video_player/video_player.dart'; 
import 'package:path_provider/path_provider.dart'; 
import 'package:cached_network_image/cached_network_image.dart'; // Added Import
import '../main.dart'; 
import '../services/prediction_service.dart'; 
import '../services/cloudinary_service.dart'; 
import 'video_trimmer_screen.dart'; 

final FirebaseAuth _auth = FirebaseAuth.instance;
final FirebaseFirestore _firestore = FirebaseFirestore.instance;
final CloudinaryService _cloudinaryService = CloudinaryService(); 

class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({super.key});

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final TextEditingController _postController = TextEditingController();
  final PredictionService _predictionService = PredictionService(); 
  final FocusNode _postFocusNode = FocusNode(); 
  
  bool _isLoading = false;
  bool _canPost = false; 

  String _userName = 'Anonymous User';
  String _userEmail = 'anon@mail.com';
  
  int _avatarIconId = 0;
  String _avatarHex = '';
  String? _profileImageUrl; 

  String? _predictedText;
  Timer? _debounce;
  
  File? _selectedMediaFile;
  String? _mediaType; 
  
  @override
  void initState() {
    super.initState();
    _loadUserData(); 
  }
  
  Future<File?> _editAndCompressPostImage(XFile pickedFile) async {
    final imageBytes = await pickedFile.readAsBytes();
    
    if (!mounted) return null;

    final editedImageBytes = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ImageEditor(
          image: imageBytes,
        ),
      ),
    );
    
    if (editedImageBytes != null) {
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/${DateTime.now().microsecondsSinceEpoch}_post.jpg');
      await tempFile.writeAsBytes(editedImageBytes);
      return tempFile;
    }
    return null;
  }

  void _onTextChanged(String text) {
    setState(() {
      _canPost = text.trim().isNotEmpty || _selectedMediaFile != null;
      _predictedText = null; 
    });

    if (_debounce?.isActive ?? false) _debounce!.cancel();
    
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
      final separator = currentText.endsWith(' ') ? '' : ' ';
      final newText = "$currentText$separator$_predictedText ";
      
      _postController.text = newText;
      _postController.selection = TextSelection.fromPosition(
        TextPosition(offset: newText.length),
      );
      
      setState(() {
        _predictedText = null; 
        _canPost = newText.trim().isNotEmpty || _selectedMediaFile != null;
      });
    }
  }

  Future<void> _loadUserData() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (userDoc.exists && mounted) {
        final data = userDoc.data() as Map<String, dynamic>;
        setState(() {
          _userName = data['name'] ?? _userName;
          _userEmail = user.email ?? _userEmail;
          _avatarIconId = data['avatarIconId'] ?? 0;
          _avatarHex = data['avatarHex'] ?? '';
          _profileImageUrl = data['profileImageUrl'];
        });
      }
    } catch (e) {
      // Fail silently
    }
  }
  
  Future<void> _pickMedia(ImageSource source, {bool isVideo = false}) async {
    final picker = ImagePicker();
    XFile? pickedFile;
    
    try {
      if (isVideo) {
        pickedFile = await picker.pickVideo(source: source);
        if (pickedFile != null && mounted) {
          // Open Manual Trimmer
          final result = await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => VideoTrimmerScreen(file: File(pickedFile!.path))
            ),
          );
          
          if (result != null && result['file'] is File) {
             setState(() {
                _mediaType = 'video';
                _selectedMediaFile = result['file'];
                _canPost = true;
             });
             return;
          }
        }
      } else { 
        pickedFile = await picker.pickImage(source: source, imageQuality: 80);
        if (pickedFile != null && mounted) {
          final processedFile = await _editAndCompressPostImage(pickedFile);
          if (processedFile != null) {
            setState(() {
               _mediaType = 'image';
               _selectedMediaFile = processedFile;
               _canPost = true;
            });
            return;
          }
        }
      }
    } catch (e) {
      print("Error picking media: $e");
    }
  }
  
  void _clearMedia() {
    setState(() {
      _selectedMediaFile = null;
      _mediaType = null;
      _canPost = _postController.text.trim().isNotEmpty;
    });
  }

  Future<void> _submitPost() async {
    if (!_canPost || _isLoading) return; 
    final user = _auth.currentUser;
    if (user == null) return;

    // 1. Close screen immediately - Background process starts
    if (mounted) {
      FocusScope.of(context).unfocus();
      Navigator.of(context).pop(); 
    }
    
    // 2. Create Pending Post
    final Map<String, dynamic> pendingPostData = {
      'text': _postController.text,
      'timestamp': FieldValue.serverTimestamp(),
      'userId': user.uid,
      'userName': _userName,
      'userEmail': _userEmail,
      'avatarIconId': _avatarIconId,
      'avatarHex': _avatarHex,
      'profileImageUrl': _profileImageUrl,
      'likes': {},
      'commentCount': 0,
      'repostedBy': [],
      'isUploading': _selectedMediaFile != null,
      'uploadProgress': 0.0,
    };
    
    try {
      final newPostRef = await _firestore.collection('posts').add(pendingPostData);
      
      if (_selectedMediaFile != null) {
        // 3. Upload to Cloudinary
        final mediaUrl = await _cloudinaryService.uploadMedia(_selectedMediaFile!);
        
        if (mediaUrl != null) {
          await newPostRef.update({
            'mediaUrl': mediaUrl,
            'mediaType': _mediaType,
            'isUploading': false,
            'uploadProgress': 1.0,
          });
        } else {
          await newPostRef.update({
            'isUploading': false,
            'uploadFailed': true,
            'text': '⚠️ Upload Failed: ' + _postController.text,
          });
        }
        
        if (_selectedMediaFile!.existsSync()) {
          _selectedMediaFile!.deleteSync();
        }
      }
    } catch (e) {
       print("Critical upload error: $e");
    }
  }

  @override
  void dispose() {
    _postController.dispose();
    _postFocusNode.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      // PENTING: ResizeToAvoidBottomInset true agar keyboard mendorong layout
      resizeToAvoidBottomInset: true, 
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.close, color: theme.primaryColor),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: ElevatedButton(
              onPressed: _canPost ? _submitPost : null, 
              child: Text('Post'),
              style: ElevatedButton.styleFrom(
                backgroundColor: TwitterTheme.blue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
            ),
          ),
        ],
      ),
      // LAYOUT FIX: Column + Expanded pushes content properly
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Changed to use CachedNetworkImageProvider for caching
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: _profileImageUrl != null ? Colors.transparent : AvatarHelper.getColor(_avatarHex),
                    backgroundImage: _profileImageUrl != null ? CachedNetworkImageProvider(_profileImageUrl!) : null,
                    child: _profileImageUrl == null ? 
                      Icon(AvatarHelper.getIcon(_avatarIconId), color: Colors.white, size: 24) : null,
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _postController,
                          focusNode: _postFocusNode, 
                          onChanged: _onTextChanged, 
                          autofocus: false, // JANGAN Autofocus
                          maxLines: null, 
                          style: TextStyle(fontSize: 18),
                          decoration: InputDecoration(
                            hintText: "What's happening?",
                            border: InputBorder.none,
                          ),
                        ),
                        
                        if (_selectedMediaFile != null)
                          _MediaPreviewWidget(
                            file: _selectedMediaFile!, 
                            type: _mediaType ?? 'image',
                            onRemove: _clearMedia,
                          ),
                        
                        if (_predictedText != null)
                          GestureDetector(
                            onTap: _acceptPrediction,
                            child: Container(
                              margin: EdgeInsets.only(top: 8),
                              padding: EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: TwitterTheme.blue.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8)
                              ),
                              child: Text("AI Suggestion: $_predictedText", style: TextStyle(color: TwitterTheme.blue)),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Bottom Actions - Always visible above keyboard
          Container(
            decoration: BoxDecoration(border: Border(top: BorderSide(color: theme.dividerColor))),
            padding: EdgeInsets.only(
              left: 16, 
              right: 16, 
              top: 8, 
              bottom: MediaQuery.of(context).viewInsets.bottom + 16 // Menghindari Keyboard
            ),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(Icons.image, color: TwitterTheme.blue),
                  onPressed: () => _pickMedia(ImageSource.gallery),
                ),
                IconButton(
                  icon: Icon(Icons.videocam, color: TwitterTheme.blue),
                  onPressed: () => _pickMedia(ImageSource.gallery, isVideo: true),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}

class _MediaPreviewWidget extends StatelessWidget {
  final File file;
  final String type;
  final VoidCallback onRemove;

  const _MediaPreviewWidget({required this.file, required this.type, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          margin: EdgeInsets.only(top: 10),
          height: 200,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(12),
          ),
          child: type == 'image' 
            ? Image.file(file, fit: BoxFit.contain)
            : Center(child: Icon(Icons.play_circle_fill, color: Colors.white, size: 50)),
        ),
        Positioned(
          right: 5, top: 15,
          child: IconButton(
            icon: Icon(Icons.cancel, color: Colors.white),
            onPressed: onRemove,
          ),
        )
      ],
    );
  }
}