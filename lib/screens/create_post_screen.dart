// ignore_for_file: prefer_const_constructors, use_build_context_synchronously
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_editor_plus/image_editor_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_compress/video_compress.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:badword_guard/badword_guard.dart'; 
import 'package:visual_detector_ai/visual_detector_ai.dart'; 
import '../main.dart';
import '../services/prediction_service.dart';
import '../services/cloudinary_service.dart';
import '../services/overlay_service.dart';
import 'video_trimmer_screen.dart';

final FirebaseAuth _auth = FirebaseAuth.instance;
final FirebaseFirestore _firestore = FirebaseFirestore.instance;
final CloudinaryService _cloudinaryService = CloudinaryService();

class CreatePostScreen extends StatefulWidget {
  final String? postId;
  final Map<String, dynamic>? initialData;

  const CreatePostScreen({
    super.key,
    this.postId,
    this.initialData,
  });

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final TextEditingController _postController = TextEditingController();
  final PredictionService _predictionService = PredictionService();
  final FocusNode _postFocusNode = FocusNode();

  final LanguageChecker _badwordGuard = LanguageChecker();

  bool _canPost = false;
  bool _isProcessing = false;

  String _visibility = 'public'; 
  bool _isAccountPrivate = false; 

  String _userName = 'Anonymous User';
  String _userEmail = 'anon@mail.com';
  int _avatarIconId = 0;
  String _avatarHex = '';
  String? _profileImageUrl;

  String? _predictedText;
  Timer? _debounce;

  File? _selectedMediaFile;
  String? _existingMediaUrl;
  String? _mediaType;

  bool get _isEditing => widget.postId != null;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _trainAiModel();

    if (_isEditing && widget.initialData != null) {
      _postController.text = widget.initialData!['text'] ?? '';
      _existingMediaUrl = widget.initialData!['mediaUrl'];
      _mediaType = widget.initialData!['mediaType'];
      _visibility = widget.initialData!['visibility'] ?? 'public';
      _checkCanPost();
    }
  }

  void _checkCanPost() {
    final textNotEmpty = _postController.text.trim().isNotEmpty;
    final hasMedia = _selectedMediaFile != null || _existingMediaUrl != null;

    setState(() {
      _canPost = textNotEmpty || hasMedia;
    });
  }

  Future<void> _trainAiModel() async {
    final user = _auth.currentUser;
    if (user == null) return;
    try {
      final snapshot = await _firestore
          .collection('posts')
          .where('userId', isEqualTo: user.uid)
          .orderBy('timestamp', descending: true)
          .limit(50)
          .get();
      List<String> postHistory = snapshot.docs
          .map((doc) => (doc.data()['text'] ?? '').toString())
          .where((text) => text.isNotEmpty)
          .toList();
      _predictionService.learnFromUserPosts(postHistory);
    } catch (e) {
      // Silent error
    }
  }

  Future<bool> _checkImageSafety() async {
    if (_selectedMediaFile == null || _mediaType != 'image') return true;

    setState(() => _isProcessing = true);
    OverlayService().showTopNotification(context, "Scanning image...", Icons.remove_red_eye, (){}, color: Colors.orange);

    try {
      final apiKey = dotenv.env['GEMINI_API_KEY'];
      if (apiKey == null || apiKey.isEmpty) return true;

      final result = await VisualDetectorAi.analyzeImage(
        image: _selectedMediaFile!,
        geminiApiKey: apiKey,
      );

      final String description = result.toString().toLowerCase(); 
      debugPrint("Visual Analysis Result: $description");

      final List<String> dangerKeywords = [
        'nude', 'naked', 'sex', 'genitals', 'porn', 'erotic', 
        'blood', 'gore', 'violence', 'weapon', 'gun', 'knife', 'kill',
        'telanjang', 'bugil', 'darah', 'membunuh' 
      ];

      for (var word in dangerKeywords) {
        if (description.contains(word)) {
          if (mounted) _showRejectDialog("Image contains sensitive content ($word).");
          return false;
        }
      }

      if (_badwordGuard.containsBadLanguage(description)) {
        if (mounted) _showRejectDialog("Image content flagged as inappropriate.");
        return false;
      }

      return true; 

    } catch (e) {
      debugPrint("Visual Detector Error: $e");
      if (mounted) _showRejectDialog("AI Security check failed.");
      return false;
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _showRejectDialog(String reason) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [Icon(Icons.gpp_bad, color: Colors.red), SizedBox(width: 8), Text("Rejected")]),
        content: Text("Your content cannot be posted.\n\nReason: $reason"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text("Edit", style: TextStyle(color: TwitterTheme.blue)))
        ],
      ),
    );
  }

  Future<File?> _editAndCompressPostImage(XFile pickedFile) async {
    final imageBytes = await pickedFile.readAsBytes();
    if (!mounted) return null;

    final editedImageBytes = await Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => ImageEditor(image: imageBytes)),
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
    _checkCanPost();
    _predictedText = null;

    if (_debounce?.isActive ?? false) _debounce!.cancel();

    _debounce = Timer(const Duration(milliseconds: 300), () async {
      if (text.trim().isEmpty) return;
      final suggestion = await _predictionService.getLocalPrediction(text);
      if (mounted && suggestion != null && suggestion.isNotEmpty) {
        setState(() => _predictedText = suggestion);
      }
    });
  }

  void _acceptPrediction() {
    if (_predictedText != null) {
      final currentText = _postController.text;
      final separator = currentText.endsWith(' ') ? '' : ' ';
      final newText = "$currentText$separator$_predictedText ";
      _postController.text = newText;
      _postController.selection = TextSelection.fromPosition(TextPosition(offset: newText.length));
      setState(() {
        _predictedText = null;
        _canPost = true;
      });
      _onTextChanged(newText);
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
          _isAccountPrivate = data['isPrivate'] ?? false;
          
          // Initial visibility setup based on account type
          if (!_isEditing) {
            _visibility = _isAccountPrivate ? 'followers' : 'public';
          }
        });
      }
    } catch (e) {}
  }

  void _showMediaSourceSelection({required bool isVideo}) {
    FocusScope.of(context).unfocus();
    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(height: 12),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
              SizedBox(height: 16),
              ListTile(
                leading: Icon(Icons.camera_alt, color: TwitterTheme.blue),
                title: Text("Take from Camera"),
                onTap: () {
                  Navigator.pop(context);
                  _pickMedia(ImageSource.camera, isVideo: isVideo);
                },
              ),
              ListTile(
                leading: Icon(Icons.photo_library, color: TwitterTheme.blue),
                title: Text("Choose from Gallery"),
                onTap: () {
                  Navigator.pop(context);
                  _pickMedia(ImageSource.gallery, isVideo: isVideo);
                },
              ),
              SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickMedia(ImageSource source, {bool isVideo = false}) async {
    final picker = ImagePicker();
    XFile? pickedFile;

    try {
      if (isVideo) {
        pickedFile = await picker.pickVideo(source: source, maxDuration: const Duration(minutes: 10));
        if (pickedFile != null && mounted) {
          final result = await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => VideoTrimmerScreen(file: File(pickedFile!.path))),
          );
          if (result != null && result['file'] is File) {
            setState(() {
              _mediaType = 'video';
              _selectedMediaFile = result['file'];
              _existingMediaUrl = null;
              _checkCanPost();
            });
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
              _existingMediaUrl = null;
              _checkCanPost();
            });
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
      _existingMediaUrl = null;
      _mediaType = null;
      _checkCanPost();
    });
  }

  Future<void> _submitPost() async {
    if (!_canPost) return;
    final user = _auth.currentUser;
    if (user == null) return;

    final text = _postController.text;
    if (_badwordGuard.containsBadLanguage(text)) {
      _showRejectDialog("Caption contains prohibited words.");
      return;
    }

    final isImageSafe = await _checkImageSafety();
    if (!isImageSafe) return; 

    final File? mediaFile = _selectedMediaFile;
    final String? existingUrl = _existingMediaUrl;
    final String? mediaType = _mediaType;
    final bool isEditing = _isEditing;
    final String? postId = widget.postId;
    
    // IMPORTANT: If account is private and visibility is 'public', force it to 'followers'
    // This prevents the bug where private posts appear as "public" data
    String finalVisibility = _visibility;
    if (_isAccountPrivate && _visibility == 'public') {
      finalVisibility = 'followers';
    }

    final String uid = user.uid;
    final String uName = _userName;
    final String uEmail = _userEmail;
    final int uIcon = _avatarIconId;
    final String uHex = _avatarHex;
    final String? uProfileImg = _profileImageUrl;

    FocusScope.of(context).unfocus();
    Navigator.of(context).pop();

    final OverlayState? overlayState = Overlay.maybeOf(context);
    
    if (overlayState != null) {
      _BackgroundUploader.startUploadSequence(
        overlayState: overlayState,
        text: text,
        mediaFile: mediaFile,
        existingMediaUrl: existingUrl,
        mediaType: mediaType,
        visibility: finalVisibility, // Use the corrected visibility
        isEditing: isEditing,
        postId: postId,
        uid: uid,
        userName: uName,
        userEmail: uEmail,
        avatarIconId: uIcon,
        avatarHex: uHex,
        profileImageUrl: uProfileImg,
      );
    }
  }

  void _showPrivacyRestrictionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.lock, color: Colors.orange),
            SizedBox(width: 8),
            Text("Private Account"),
          ],
        ),
        content: Text(
          "Your account is set to Private. You cannot create Public posts. Switch your account to Public in Account Center to change this."
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context), 
            child: Text("OK")
          ),
        ],
      ),
    );
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
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.close, color: theme.primaryColor),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: _isEditing ? Text("Edit Post", style: TextStyle(fontWeight: FontWeight.bold)) : null,
        centerTitle: false,
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10.0),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: theme.brightness == Brightness.dark ? Colors.white10 : Colors.grey[200],
                borderRadius: BorderRadius.circular(20),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _visibility,
                  icon: Icon(Icons.arrow_drop_down, color: theme.primaryColor),
                  style: TextStyle(
                    color: theme.textTheme.bodyLarge?.color, 
                    fontWeight: FontWeight.bold, 
                    fontSize: 13
                  ),
                  onChanged: (String? newValue) {
                    if (newValue == 'public_attempt' && _isAccountPrivate) {
                      _showPrivacyRestrictionDialog();
                      return;
                    }
                    if (newValue != null && newValue != 'public_attempt') {
                      setState(() => _visibility = newValue);
                    }
                  },
                  items: [
                    // Logic: If Private, show 'Followers' (value='followers') and a dummy 'Public'
                    // If Public, show 'Public' (value='public')
                    
                    if (_isAccountPrivate)
                      DropdownMenuItem(
                        value: 'followers',
                        child: Row(
                          children: [
                            Icon(Icons.people, size: 16, color: Colors.blue),
                            SizedBox(width: 6), 
                            Text("Followers")
                          ]
                        ),
                      )
                    else
                      DropdownMenuItem(
                        value: 'public',
                        child: Row(
                          children: [
                            Icon(Icons.public, size: 16, color: Colors.blue),
                            SizedBox(width: 6), 
                            Text("Public")
                          ]
                        ),
                      ),
                    
                    if (_isAccountPrivate)
                      DropdownMenuItem(
                        value: 'public_attempt',
                        child: Row(
                          children: [
                            Icon(Icons.public, size: 16, color: Colors.grey),
                            SizedBox(width: 6), 
                            Text("Public", style: TextStyle(color: Colors.grey))
                          ]
                        ),
                      ),

                    DropdownMenuItem(
                      value: 'private',
                      child: Row(
                        children: [
                          Icon(Icons.lock, size: 16, color: Colors.red),
                          SizedBox(width: 6), 
                          Text("Only Me") 
                        ]
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: ElevatedButton(
              onPressed: _canPost && !_isProcessing ? _submitPost : null,
              child: _isProcessing 
                ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : Text(_isEditing ? 'Save' : 'Post'),
              style: ElevatedButton.styleFrom(
                backgroundColor: TwitterTheme.blue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: SingleChildScrollView(
              padding: EdgeInsets.only(top: 16, left: 16, right: 16, bottom: bottomInset + 80),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: _profileImageUrl != null ? Colors.transparent : AvatarHelper.getColor(_avatarHex),
                    backgroundImage: _profileImageUrl != null ? CachedNetworkImageProvider(_profileImageUrl!) : null,
                    child: _profileImageUrl == null ? Icon(AvatarHelper.getIcon(_avatarIconId), color: Colors.white, size: 24) : null,
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
                          autofocus: !_isEditing,
                          maxLines: null,
                          style: TextStyle(fontSize: 18),
                          decoration: InputDecoration(
                            hintText: "What's happening?",
                            border: InputBorder.none,
                          ),
                        ),
                        if (_selectedMediaFile != null)
                          _MediaPreviewWidget(
                            fileOrUrl: _selectedMediaFile, 
                            type: _mediaType ?? 'image', 
                            onRemove: _clearMedia,
                          )
                        else if (_existingMediaUrl != null)
                          _MediaPreviewWidget(
                            fileOrUrl: _existingMediaUrl, 
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
                                  color: TwitterTheme.blue.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.auto_awesome, size: 16, color: TwitterTheme.blue),
                                  SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      "Suggestion: ...$_predictedText", 
                                      style: TextStyle(color: TwitterTheme.blue, fontWeight: FontWeight.bold),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 0, right: 0, bottom: bottomInset,
            child: Container(
              decoration: BoxDecoration(
                color: theme.scaffoldBackgroundColor,
                border: Border(top: BorderSide(color: theme.dividerColor)),
              ),
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SafeArea(
                top: false,
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.image, color: TwitterTheme.blue),
                      onPressed: () => _showMediaSourceSelection(isVideo: false),
                    ),
                    IconButton(
                      icon: Icon(Icons.videocam, color: TwitterTheme.blue),
                      onPressed: () => _showMediaSourceSelection(isVideo: true),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MediaPreviewWidget extends StatelessWidget {
  final dynamic fileOrUrl;
  final String type;
  final VoidCallback onRemove;

  const _MediaPreviewWidget({
    required this.fileOrUrl, 
    required this.type, 
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    ImageProvider imageProvider;
    if (fileOrUrl is File) {
      imageProvider = FileImage(fileOrUrl);
    } else {
      imageProvider = CachedNetworkImageProvider(fileOrUrl as String);
    }
    return Stack(
      children: [
        Container(
          margin: EdgeInsets.only(top: 10),
          height: 200, width: double.infinity,
          decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(12)),
          child: type == 'image'
              ? Image(image: imageProvider, fit: BoxFit.contain)
              : Center(child: Icon(Icons.play_circle_fill, color: Colors.white, size: 50)),
        ),
        Positioned(
          right: 5, top: 15,
          child: IconButton(icon: Icon(Icons.cancel, color: Colors.white), onPressed: onRemove),
        ),
      ],
    );
  }
}

class _BackgroundUploader {
  static void startUploadSequence({
    required OverlayState overlayState,
    required String text,
    required File? mediaFile,
    required String? existingMediaUrl,
    required String? mediaType,
    required String visibility,
    required bool isEditing,
    required String? postId,
    required String uid,
    required String userName,
    required String userEmail,
    required int avatarIconId,
    required String avatarHex,
    required String? profileImageUrl,
  }) {
    final GlobalKey<_PostUploadOverlayState> overlayKey = GlobalKey();
    late OverlayEntry overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) => _PostUploadOverlay(
        key: overlayKey,
        onDismissRequest: () {
          overlayKey.currentState?.dismissToIcon();
        },
      ),
    );

    overlayState.insert(overlayEntry);

    _processUpload(
      text: text,
      mediaFile: mediaFile,
      existingMediaUrl: existingMediaUrl,
      mediaType: mediaType,
      visibility: visibility,
      isEditing: isEditing,
      postId: postId,
      uid: uid,
      userName: userName,
      userEmail: userEmail,
      avatarIconId: avatarIconId,
      avatarHex: avatarHex,
      profileImageUrl: profileImageUrl,
      onProgress: (status) {
        overlayKey.currentState?.updateStatus(status);
      },
      onSuccess: () {
        overlayKey.currentState?.handleSuccess();
        Future.delayed(Duration(seconds: 7), () {
           if (overlayEntry.mounted) overlayEntry.remove();
        });
      },
      onFailure: (error) {
        overlayKey.currentState?.handleFailure(error.toString());
        Future.delayed(Duration(seconds: 4), () {
          if (overlayEntry.mounted) overlayEntry.remove();
        });
      },
    );
  }

  static Future<void> _processUpload({
    required String text,
    File? mediaFile,
    String? existingMediaUrl,
    String? mediaType,
    required String visibility,
    required bool isEditing,
    String? postId,
    required String uid,
    required String userName,
    required String userEmail,
    required int avatarIconId,
    required String avatarHex,
    required String? profileImageUrl,
    required Function(String) onProgress,
    required VoidCallback onSuccess,
    required Function(dynamic) onFailure,
  }) async {
    try {
      String? finalMediaUrl = existingMediaUrl;
      File? fileToUpload = mediaFile;

      if (mediaType == 'video' && fileToUpload != null) {
        onProgress("Processing...");
        try {
          final MediaInfo? info = await VideoCompress.compressVideo(
            fileToUpload.path,
            quality: VideoQuality.MediumQuality,
            deleteOrigin: false,
          );
          if (info != null && info.file != null) {
            fileToUpload = info.file!;
          }
        } catch (e) {
          print("Compression failed, using original: $e");
        }
      }

      if (fileToUpload != null) {
        onProgress("Uploading...");
        finalMediaUrl = await _cloudinaryService.uploadMedia(fileToUpload);
        if (finalMediaUrl == null) {
          onFailure("Media upload failed.");
          return;
        }
      }

      if (isEditing && postId != null) {
        await _firestore.collection('posts').doc(postId).update({
          'text': text,
          'mediaUrl': finalMediaUrl,
          'mediaType': mediaType,
          'visibility': visibility, 
          'isUploading': false,
          'editedAt': FieldValue.serverTimestamp(),
        });
      } else {
        await _firestore.collection('posts').add({
          'text': text,
          'timestamp': FieldValue.serverTimestamp(),
          'userId': uid,
          'userName': userName,
          'userEmail': userEmail,
          'avatarIconId': avatarIconId,
          'avatarHex': avatarHex,
          'profileImageUrl': profileImageUrl,
          'likes': {},
          'commentCount': 0,
          'repostedBy': [],
          'mediaUrl': finalMediaUrl,
          'mediaType': mediaType,
          'visibility': visibility, 
          'isUploading': false,
        });
      }

      if (visibility == 'public' || visibility == 'followers') {
        await _firestore.collection('users').doc(uid).collection('notifications').add({
          'type': 'upload_complete',
          'senderId': 'system', 
          'postId': null,
          'postTextSnippet': 'Your ${mediaType ?? 'post'} was uploaded successfully.',
          'timestamp': FieldValue.serverTimestamp(),
          'isRead': false,
        });
      }

      if (mediaFile != null && mediaFile.existsSync()) {
        try { mediaFile.deleteSync(); } catch (_) {}
      }
      if (mediaType == 'video') {
        await VideoCompress.deleteAllCache();
      }

      onSuccess();
    } catch (e) {
      onFailure(e);
    }
  }
}

class _PostUploadOverlay extends StatefulWidget {
  final VoidCallback onDismissRequest;
  const _PostUploadOverlay({super.key, required this.onDismissRequest});

  @override
  State<_PostUploadOverlay> createState() => _PostUploadOverlayState();
}

class _PostUploadOverlayState extends State<_PostUploadOverlay> {
  bool _isCardVisible = true;
  bool _isMiniVisible = false;
  bool _isSuccess = false;
  bool _isError = false;
  String _message = "Uploading media...";
  
  String _statusText = "Uploading...";
  Timer? _autoDismissTimer;

  double get _targetTop => MediaQuery.of(context).padding.top + 10;
  double get _targetRight => 12.0;
  double get _miniRight => 60.0; 

  @override
  void dispose() {
    _autoDismissTimer?.cancel();
    super.dispose();
  }

  void updateStatus(String status) {
    if (!mounted) return;
    setState(() {
      _message = "$status media...";
      _statusText = status;
    });
  }

  void dismissToIcon() {
    setState(() { _isCardVisible = false; });
    Future.delayed(Duration(milliseconds: 400), () {
      if (mounted) setState(() { _isMiniVisible = true; });
    });
  }

  void _expandToCard() {
    setState(() { _isMiniVisible = false; });
    Future.delayed(Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() { _isCardVisible = true; });
        _autoDismissTimer?.cancel();
        _autoDismissTimer = Timer(Duration(seconds: 2), () {
          dismissToIcon();
        });
      }
    });
  }

  void handleSuccess() {
    setState(() { _isSuccess = true; _message = "Posted"; _statusText = "Done"; });
    if (_isMiniVisible) {
      Future.delayed(Duration(seconds: 5), () { if (mounted) setState(() => _isMiniVisible = false); });
    } else if (_isCardVisible) {
      Future.delayed(Duration(seconds: 5), () { if (mounted) setState(() => _isCardVisible = false); });
    }
  }

  void handleFailure(String error) {
    setState(() { _isError = true; _message = "Failed"; _statusText = "Error"; });
    if (!_isCardVisible) setState(() => _isCardVisible = true);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        AnimatedPositioned(
          duration: Duration(milliseconds: 400),
          curve: Curves.easeOutQuart,
          top: _targetTop, 
          right: _isMiniVisible ? _miniRight : _targetRight, 
          child: AnimatedOpacity(
            duration: Duration(milliseconds: 300),
            opacity: _isMiniVisible ? 1.0 : 0.0,
            child: GestureDetector(
              onTap: _expandToCard,
              child: Material(
                elevation: 4,
                shape: CircleBorder(),
                color: _isSuccess ? Colors.green : TwitterTheme.white,
                child: Container(
                  width: 36, height: 36, padding: EdgeInsets.all(8),
                  child: _isSuccess 
                    ? Icon(Icons.check, size: 20, color: Colors.white)
                    : CircularProgressIndicator(strokeWidth: 3, color: TwitterTheme.blue),
                ),
              ),
            ),
          ),
        ),
        AnimatedPositioned(
          duration: Duration(milliseconds: 500),
          curve: Curves.easeInOutBack,
          top: _isCardVisible ? MediaQuery.of(context).padding.top + 10 : _targetTop,
          left: _isCardVisible ? 16 : MediaQuery.of(context).size.width - 50, 
          right: _isCardVisible ? 16 : _targetRight, 
          child: AnimatedOpacity(
            duration: Duration(milliseconds: 300),
            opacity: _isCardVisible ? 1.0 : 0.0,
            child: Transform.scale(
              scale: _isCardVisible ? 1.0 : 0.1, 
              child: _UploadCard(
                isSuccess: _isSuccess,
                isError: _isError,
                message: _message,
                onDismiss: widget.onDismissRequest,
              ),
            ),
          ),
        )
      ],
    );
  }
}

class _UploadCard extends StatelessWidget {
  final bool isSuccess;
  final bool isError;
  final String message;
  final VoidCallback onDismiss;

  const _UploadCard({required this.isSuccess, required this.isError, required this.message, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Dismissible(
      key: ValueKey("upload_card_dismiss"),
      direction: DismissDirection.horizontal,
      onDismissed: (_) => onDismiss(),
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(12),
        color: isDark ? TwitterTheme.darkGrey : Colors.white,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  if (isSuccess) Icon(Icons.check_circle, color: TwitterTheme.blue)
                  else if (isError) Icon(Icons.error, color: Colors.red)
                  else SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(message, style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
                  ),
                  Container(width: 4, height: 24, decoration: BoxDecoration(color: Colors.grey.withOpacity(0.5), borderRadius: BorderRadius.circular(2)))
                ],
              ),
              if (!isSuccess && !isError)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: LinearProgressIndicator(
                    backgroundColor: TwitterTheme.blue.withOpacity(0.1),
                    valueColor: AlwaysStoppedAnimation(TwitterTheme.blue),
                  ),
                )
            ],
          ),
        ),
      ),
    );
  }
}