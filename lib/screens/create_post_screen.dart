// ignore_for_file: prefer_const_constructors
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_editor_plus/image_editor_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../main.dart';
import '../services/prediction_service.dart';
import '../services/cloudinary_service.dart';
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

  bool _canPost = false;

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

    if (_isEditing && widget.initialData != null) {
      _postController.text = widget.initialData!['text'] ?? '';
      _existingMediaUrl = widget.initialData!['mediaUrl'];
      _mediaType = widget.initialData!['mediaType'];
      _canPost = true;
    }
  }

  Future<File?> _editAndCompressPostImage(XFile pickedFile) async {
    final imageBytes = await pickedFile.readAsBytes();
    if (!mounted) return null;

    final editedImageBytes = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ImageEditor(image: imageBytes),
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
      _canPost = text.trim().isNotEmpty || _selectedMediaFile != null || _existingMediaUrl != null;
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
      _postController.selection = TextSelection.fromPosition(TextPosition(offset: newText.length));

      setState(() {
        _predictedText = null;
        _canPost = newText.trim().isNotEmpty || _selectedMediaFile != null || _existingMediaUrl != null;
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
    } catch (e) { /* Fail silently */ }
  }

  Future<void> _pickMedia(ImageSource source, {bool isVideo = false}) async {
    final picker = ImagePicker();
    XFile? pickedFile;

    try {
      if (isVideo) {
        pickedFile = await picker.pickVideo(source: source);
        if (pickedFile != null && mounted) {
          final result = await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => VideoTrimmerScreen(file: File(pickedFile!.path))),
          );
          if (result != null && result['file'] is File) {
            setState(() {
              _mediaType = 'video';
              _selectedMediaFile = result['file'];
              _existingMediaUrl = null;
              _canPost = true;
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
              _canPost = true;
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
      _canPost = _postController.text.trim().isNotEmpty;
    });
  }

  Future<void> _submitPost() async {
    if (!_canPost) return;
    final user = _auth.currentUser;
    if (user == null) return;

    // 1. Capture State
    final String text = _postController.text;
    final File? mediaFile = _selectedMediaFile;
    final String? existingUrl = _existingMediaUrl;
    final String? mediaType = _mediaType;
    final bool isEditing = _isEditing;
    final String? postId = widget.postId;

    // User Data
    final String uid = user.uid;
    final String uName = _userName;
    final String uEmail = _userEmail;
    final int uIcon = _avatarIconId;
    final String uHex = _avatarHex;
    final String? uProfileImg = _profileImageUrl;

    // 2. Dismiss UI Immediately
    FocusScope.of(context).unfocus();
    Navigator.of(context).pop();

    // 3. Hand off to Background Uploader (Static)
    final OverlayState? overlayState = Overlay.maybeOf(context);
    
    if (overlayState != null) {
      _BackgroundUploader.startUploadSequence(
        overlayState: overlayState,
        text: text,
        mediaFile: mediaFile,
        existingMediaUrl: existingUrl,
        mediaType: mediaType,
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
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: ElevatedButton(
              onPressed: _canPost ? _submitPost : null,
              child: Text(_isEditing ? 'Save' : 'Post'),
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
                          _MediaPreviewWidget(fileOrUrl: _selectedMediaFile, type: _mediaType ?? 'image', onRemove: _clearMedia)
                        else if (_existingMediaUrl != null)
                          _MediaPreviewWidget(fileOrUrl: _existingMediaUrl, type: _mediaType ?? 'image', onRemove: _clearMedia),
                        if (_predictedText != null)
                          GestureDetector(
                            onTap: _acceptPrediction,
                            child: Container(
                              margin: EdgeInsets.only(top: 8),
                              padding: EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                  color: TwitterTheme.blue.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
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
                      onPressed: () => _pickMedia(ImageSource.gallery),
                    ),
                    IconButton(
                      icon: Icon(Icons.videocam, color: TwitterTheme.blue),
                      onPressed: () => _pickMedia(ImageSource.gallery, isVideo: true),
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
  const _MediaPreviewWidget({required this.fileOrUrl, required this.type, required this.onRemove});

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
        )
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// ---------------------- BACKGROUND UPLOAD LOGIC ----------------------------
// ---------------------------------------------------------------------------

class _BackgroundUploader {
  static void startUploadSequence({
    required OverlayState overlayState,
    required String text,
    required File? mediaFile,
    required String? existingMediaUrl,
    required String? mediaType,
    required bool isEditing,
    required String? postId,
    required String uid,
    required String userName,
    required String userEmail,
    required int avatarIconId,
    required String avatarHex,
    required String? profileImageUrl,
  }) {
    // Key to control overlay state
    final GlobalKey<_PostUploadOverlayState> overlayKey = GlobalKey();
    late OverlayEntry overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) => _PostUploadOverlay(
        key: overlayKey,
        onDismissRequest: () {
          // Trigger dismiss animation logic
          overlayKey.currentState?.dismissToIcon();
        },
      ),
    );

    overlayState.insert(overlayEntry);

    // Run async upload
    _processUpload(
      text: text,
      mediaFile: mediaFile,
      existingMediaUrl: existingMediaUrl,
      mediaType: mediaType,
      isEditing: isEditing,
      postId: postId,
      uid: uid,
      userName: userName,
      userEmail: userEmail,
      avatarIconId: avatarIconId,
      avatarHex: avatarHex,
      profileImageUrl: profileImageUrl,
      onSuccess: () {
        // Handle success animation
        overlayKey.currentState?.handleSuccess();
        
        // Remove after animation (6s total: transition + wait)
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
    required bool isEditing,
    String? postId,
    required String uid,
    required String userName,
    required String userEmail,
    required int avatarIconId,
    required String avatarHex,
    required String? profileImageUrl,
    required VoidCallback onSuccess,
    required Function(dynamic) onFailure,
  }) async {
    try {
      String? finalMediaUrl = existingMediaUrl;

      // 1. Upload Media
      if (mediaFile != null) {
        finalMediaUrl = await _cloudinaryService.uploadMedia(mediaFile);
        if (finalMediaUrl == null) {
          onFailure("Media upload failed.");
          return;
        }
      }

      // 2. Write to Firestore
      if (isEditing && postId != null) {
        await _firestore.collection('posts').doc(postId).update({
          'text': text,
          'mediaUrl': finalMediaUrl,
          'mediaType': mediaType,
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
          'isUploading': false,
        });
      }

      // 3. Add Notification
      await _firestore.collection('users').doc(uid).collection('notifications').add({
        'type': 'upload_complete',
        'senderId': 'system', 
        'postId': null,
        'postTextSnippet': 'Your ${mediaType ?? 'post'} was uploaded successfully.',
        'timestamp': FieldValue.serverTimestamp(),
        'isRead': false,
      });

      // 4. Cleanup
      if (mediaFile != null && mediaFile.existsSync()) {
        try { mediaFile.deleteSync(); } catch (_) {}
      }

      onSuccess();
    } catch (e) {
      onFailure(e);
    }
  }
}

// ---------------------------------------------------------------------------
// ---------------------- ANIMATED OVERLAY WIDGET ----------------------------
// ---------------------------------------------------------------------------

class _PostUploadOverlay extends StatefulWidget {
  final VoidCallback onDismissRequest;
  const _PostUploadOverlay({super.key, required this.onDismissRequest});

  @override
  State<_PostUploadOverlay> createState() => _PostUploadOverlayState();
}

class _PostUploadOverlayState extends State<_PostUploadOverlay> {
  // Logic State
  bool _isCardVisible = true;
  bool _isMiniVisible = false;
  bool _isSuccess = false;
  bool _isError = false;
  String _message = "Uploading media...";
  Timer? _autoDismissTimer;

  // Coordinate Constants (Approximate to standard AppBar actions)
  // Bell Icon Target: ~Top 10 (inside safe area), Right 12
  double get _targetTop => MediaQuery.of(context).padding.top + 10;
  double get _targetRight => 12.0;

  // Slide Out Position: ~Left of Bell
  double get _miniRight => 60.0; 

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _autoDismissTimer?.cancel();
    super.dispose();
  }

  // --- PUBLIC METHODS (Controlled by Manager) ---

  void dismissToIcon() {
    setState(() {
      _isCardVisible = false;
    });
    // Wait for card to shrink, then slide out mini
    Future.delayed(Duration(milliseconds: 400), () {
      if (mounted) {
        setState(() {
          _isMiniVisible = true;
        });
      }
    });
  }

  void _expandToCard() {
    setState(() {
      _isMiniVisible = false;
    });
    // Wait for mini to hide, then show card
    Future.delayed(Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _isCardVisible = true;
        });
        
        // Auto-dismiss again after 2 seconds
        _autoDismissTimer?.cancel();
        _autoDismissTimer = Timer(Duration(seconds: 2), () {
          dismissToIcon();
        });
      }
    });
  }

  void handleSuccess() {
    setState(() {
      _isSuccess = true;
      _message = "Posted";
    });

    if (_isMiniVisible) {
      // If mini, turn into checkmark, wait 5s, then merge back
      Future.delayed(Duration(seconds: 5), () {
        if (mounted) {
          setState(() {
            _isMiniVisible = false; // Slides back to bell
          });
        }
      });
    } else if (_isCardVisible) {
      // If card, show success, then wait 5s
      Future.delayed(Duration(seconds: 5), () {
        if (mounted) {
          setState(() {
            _isCardVisible = false;
          });
        }
      });
    } else {
      // If hidden/transitioning, just ensure cleanup happens
    }
  }

  void handleFailure(String error) {
    setState(() {
      _isError = true;
      _message = "Failed";
    });
    // Force show card for error
    if (!_isCardVisible) {
      setState(() => _isCardVisible = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 1. The Main Card (Heads-up)
    // When visible: Top Center. When dismissed: Flies to Bell Icon.
    Widget buildCard() {
      return AnimatedPositioned(
        duration: Duration(milliseconds: 500),
        curve: Curves.easeInOutBack,
        top: _isCardVisible ? MediaQuery.of(context).padding.top + 10 : _targetTop,
        left: _isCardVisible ? 16 : MediaQuery.of(context).size.width - 50, // Move towards right
        right: _isCardVisible ? 16 : _targetRight, // Move towards bell
        child: AnimatedOpacity(
          duration: Duration(milliseconds: 300),
          opacity: _isCardVisible ? 1.0 : 0.0,
          child: Transform.scale(
            scale: _isCardVisible ? 1.0 : 0.1, // Shrink effect
            child: _UploadCard(
              isSuccess: _isSuccess,
              isError: _isError,
              message: _message,
              onDismiss: widget.onDismissRequest,
            ),
          ),
        ),
      );
    }

    // 2. The Mini Loader (Slide Out)
    // Starts at Bell position (hidden), slides left to _miniRight.
    Widget buildMiniLoader() {
      return AnimatedPositioned(
        duration: Duration(milliseconds: 400),
        curve: Curves.easeOutQuart,
        top: _targetTop, // Aligned with notification icon
        right: _isMiniVisible ? _miniRight : _targetRight, // Slides out
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
                width: 36,
                height: 36,
                padding: EdgeInsets.all(8),
                child: _isSuccess 
                  ? Icon(Icons.check, size: 20, color: Colors.white)
                  : CircularProgressIndicator(strokeWidth: 3, color: TwitterTheme.blue),
              ),
            ),
          ),
        ),
      );
    }

    return Stack(
      children: [
        buildMiniLoader(), // Render mini first (behind card conceptually)
        buildCard(),
      ],
    );
  }
}

class _UploadCard extends StatelessWidget {
  final bool isSuccess;
  final bool isError;
  final String message;
  final VoidCallback onDismiss;

  const _UploadCard({
    required this.isSuccess,
    required this.isError,
    required this.message,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Material(
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
                if (isSuccess)
                  Icon(Icons.check_circle, color: TwitterTheme.blue)
                else if (isError)
                  Icon(Icons.error, color: Colors.red)
                else
                  SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    message,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                ),
                if (!isSuccess && !isError)
                  GestureDetector(
                    onTap: onDismiss,
                    child: Padding(
                      padding: const EdgeInsets.all(4.0),
                      child: Text("Hide", style: TextStyle(color: TwitterTheme.blue, fontWeight: FontWeight.bold)),
                    ),
                  ),
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
    );
  }
}