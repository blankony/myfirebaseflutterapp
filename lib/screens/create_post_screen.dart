// ignore_for_file: prefer_const_constructors, use_build_context_synchronously
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
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

  // Identity State
  String _displayName = 'Anonymous User';
  String _userEmail = 'anon@mail.com';
  String? _displayAvatarUrl;
  int _avatarIconId = 0;
  String _avatarHex = '';
  
  // Community Broadcasting State
  String? _communityId;
  String? _communityName;
  String? _communityIcon;
  bool _communityVerified = false; // NEW: Track verification status
  bool _isBroadcasting = false;
  bool _isRestricted = false; 

  String? _predictedText;
  Timer? _debounce;

  List<File> _selectedMediaFiles = []; 
  List<String> _existingMediaUrls = []; 
  String? _mediaType; 

  bool get _isEditing => widget.postId != null;

  @override
  void initState() {
    super.initState();
    _loadIdentity(); 
    _trainAiModel();

    if (widget.initialData != null) {
      if (_isEditing) {
        _postController.text = widget.initialData!['text'] ?? '';
        _mediaType = widget.initialData!['mediaType'];
        _visibility = widget.initialData!['visibility'] ?? 'public';
        
        if (widget.initialData!['mediaUrls'] != null) {
          _existingMediaUrls = List<String>.from(widget.initialData!['mediaUrls']);
        } else if (widget.initialData!['mediaUrl'] != null) {
          _existingMediaUrls = [widget.initialData!['mediaUrl']];
        }
        _checkCanPost();
      } 
    }
  }

  Future<void> _loadIdentity() async {
    final user = _auth.currentUser;
    if (user == null) return;

    // Load User Data First
    try {
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (userDoc.exists) {
        final data = userDoc.data()!;
        setState(() {
          _displayName = data['name'] ?? 'User';
          _userEmail = user.email ?? '';
          _avatarIconId = data['avatarIconId'] ?? 0;
          _avatarHex = data['avatarHex'] ?? '';
          _displayAvatarUrl = data['profileImageUrl'];
          _isAccountPrivate = data['isPrivate'] ?? false;
        });
      }
    } catch (_) {}

    // Check Community Context
    if (widget.initialData != null && widget.initialData!.containsKey('communityId')) {
      _communityId = widget.initialData!['communityId'];
      // Use passed data initially for speed, but fetch fresh data for verification status
      _communityName = widget.initialData!['communityName'];
      _communityIcon = widget.initialData!['communityIcon'];
      _isBroadcasting = true;
      _visibility = 'public'; 

      try {
        final comDoc = await _firestore.collection('communities').doc(_communityId).get();
        if (comDoc.exists) {
          final data = comDoc.data()!;
          
          setState(() {
            _communityName = data['name']; // Update with fresh name
            _communityIcon = data['imageUrl']; // Update with fresh icon
            _communityVerified = data['isVerified'] ?? false; // Update verified status
          });

          final bool allowMembers = data['allowMemberPosts'] ?? false;
          final String ownerId = data['ownerId'];
          final List admins = data['admins'] ?? [];
          final List editors = data['editors'] ?? [];
          
          final bool isStaff = ownerId == user.uid || admins.contains(user.uid) || editors.contains(user.uid);
          
          if (!allowMembers && !isStaff) {
            setState(() => _isRestricted = true);
            if(mounted) {
              OverlayService().showTopNotification(context, "Posting restricted by Admin", Icons.lock, (){}, color: Colors.red);
              Navigator.pop(context);
            }
          }
        }
      } catch (e) {
        debugPrint("Error checking community permissions: $e");
      }
    } else if (!_isEditing) {
      if (mounted) {
        setState(() {
          _visibility = _isAccountPrivate ? 'followers' : 'public';
        });
      }
    }
  }

  void _checkCanPost() {
    final textNotEmpty = _postController.text.trim().isNotEmpty;
    final hasMedia = _selectedMediaFiles.isNotEmpty || _existingMediaUrls.isNotEmpty;

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
    if (_mediaType != 'image' || _selectedMediaFiles.isEmpty) return true;

    setState(() => _isProcessing = true);
    OverlayService().showTopNotification(context, "Scanning images...", Icons.remove_red_eye, (){}, color: Colors.orange);

    try {
      final apiKey = dotenv.env['GEMINI_API_KEY'];
      if (apiKey == null || apiKey.isEmpty) return true;

      int limit = _selectedMediaFiles.length > 3 ? 3 : _selectedMediaFiles.length;

      for (int i = 0; i < limit; i++) {
        final result = await VisualDetectorAi.analyzeImage(
          image: _selectedMediaFiles[i],
          geminiApiKey: apiKey,
        );

        final String description = result.toString().toLowerCase(); 
        
        final List<String> dangerKeywords = [
          'nude', 'naked', 'sex', 'genitals', 'porn', 'erotic', 
          'blood', 'gore', 'violence', 'weapon', 'gun', 'knife', 'kill',
          'telanjang', 'bugil', 'darah', 'membunuh' 
        ];

        for (var word in dangerKeywords) {
          if (description.contains(word)) {
            if (mounted) _showRejectDialog("Image ${i+1} contains sensitive content ($word).");
            return false;
          }
        }

        if (_badwordGuard.containsBadLanguage(description)) {
          if (mounted) _showRejectDialog("Image ${i+1} flagged as inappropriate.");
          return false;
        }
      }

      return true; 

    } catch (e) {
      debugPrint("Visual Detector Error: $e");
      return true; 
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

    try {
      if (isVideo) {
        final XFile? pickedFile = await picker.pickVideo(source: source, maxDuration: const Duration(minutes: 10));
        if (pickedFile != null && mounted) {
          final result = await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => VideoTrimmerScreen(file: File(pickedFile.path))),
          );
          if (result != null && result['file'] is File) {
            setState(() {
              _mediaType = 'video';
              _selectedMediaFiles = [result['file']]; 
              _existingMediaUrls = []; 
              _checkCanPost();
            });
          }
        }
      } else {
        if (source == ImageSource.gallery) {
          final List<XFile> pickedFiles = await picker.pickMultiImage(imageQuality: 80);
          if (pickedFiles.isNotEmpty) {
            setState(() {
              if (_mediaType == 'video') {
                _selectedMediaFiles = [];
                _existingMediaUrls = [];
              }
              _mediaType = 'image';
              _selectedMediaFiles.addAll(pickedFiles.map((x) => File(x.path)));
              _checkCanPost();
            });
          }
        } else {
          final XFile? pickedFile = await picker.pickImage(source: source, imageQuality: 80);
          if (pickedFile != null) {
             setState(() {
              if (_mediaType == 'video') {
                _selectedMediaFiles = [];
                _existingMediaUrls = [];
              }
              _mediaType = 'image';
              _selectedMediaFiles.add(File(pickedFile.path));
              _checkCanPost();
            });
          }
        }
      }
    } catch (e) {
      debugPrint("Error picking media: $e");
    }
  }

  void _removeFile(int index) {
    setState(() {
      _selectedMediaFiles.removeAt(index);
      if (_selectedMediaFiles.isEmpty && _existingMediaUrls.isEmpty) {
        _mediaType = null;
      }
      _checkCanPost();
    });
  }

  void _removeExistingUrl(int index) {
    setState(() {
      _existingMediaUrls.removeAt(index);
      if (_selectedMediaFiles.isEmpty && _existingMediaUrls.isEmpty) {
        _mediaType = null;
      }
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

    // Prepare Data
    final List<File> filesToUpload = _selectedMediaFiles;
    final List<String> currentUrls = _existingMediaUrls;
    final String? mediaType = _mediaType;
    final bool isEditing = _isEditing;
    final String? postId = widget.postId;
    
    // Visibility Logic
    String finalVisibility = _visibility;
    if (_communityId != null) {
        finalVisibility = 'public'; // Broadcasting is always public
    } else if (_isAccountPrivate && _visibility == 'public') {
      finalVisibility = 'followers';
    }

    final String uid = user.uid; // Actual Operator ID
    final String uName = _displayName; // Display Name (User)
    final String uEmail = _userEmail;
    final int uIcon = _avatarIconId;
    final String uHex = _avatarHex;
    final String? uProfileImg = _displayAvatarUrl;

    FocusScope.of(context).unfocus();
    Navigator.of(context).pop();

    final OverlayState? overlayState = Overlay.maybeOf(context);
    
    if (overlayState != null) {
      _BackgroundUploader.startUploadSequence(
        overlayState: overlayState,
        text: text,
        filesToUpload: filesToUpload, 
        existingMediaUrls: currentUrls, 
        mediaType: mediaType,
        visibility: finalVisibility,
        isEditing: isEditing,
        postId: postId,
        uid: uid,
        userName: uName,
        userEmail: uEmail,
        avatarIconId: uIcon,
        avatarHex: uHex,
        profileImageUrl: uProfileImg,
        
        communityId: _communityId,
        communityName: _communityName,
        communityIcon: _communityIcon,
        communityVerified: _communityVerified, // PASS VERIFIED STATUS
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
          TextButton(onPressed: () => Navigator.pop(context), child: Text("OK")),
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
    if (_isRestricted) return SizedBox.shrink(); 

    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.close, color: theme.primaryColor),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: _isBroadcasting 
            ? Row(
                children: [
                  Icon(Icons.campaign, color: TwitterTheme.blue, size: 20),
                  SizedBox(width: 8),
                  Text("Broadcasting", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ) 
            : Text(_isEditing ? "Edit Post" : "Create Post", style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: false,
        actions: [
          if (!_isBroadcasting) 
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
                    style: TextStyle(color: theme.textTheme.bodyLarge?.color, fontWeight: FontWeight.bold, fontSize: 13),
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
                      if (_isAccountPrivate)
                        DropdownMenuItem(value: 'followers', child: Row(children: [Icon(Icons.people, size: 16, color: Colors.blue), SizedBox(width: 6), Text("Followers")]))
                      else
                        DropdownMenuItem(value: 'public', child: Row(children: [Icon(Icons.public, size: 16, color: Colors.blue), SizedBox(width: 6), Text("Public")])),
                      
                      if (_isAccountPrivate)
                        DropdownMenuItem(value: 'public_attempt', child: Row(children: [Icon(Icons.public, size: 16, color: Colors.grey), SizedBox(width: 6), Text("Public", style: TextStyle(color: Colors.grey))])),

                      DropdownMenuItem(value: 'private', child: Row(children: [Icon(Icons.lock, size: 16, color: Colors.red), SizedBox(width: 6), Text("Only Me")])),
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
                    backgroundColor: _displayAvatarUrl != null ? Colors.transparent : AvatarHelper.getColor(_avatarHex),
                    backgroundImage: _displayAvatarUrl != null ? CachedNetworkImageProvider(_displayAvatarUrl!) : null,
                    child: _displayAvatarUrl == null ? Icon(AvatarHelper.getIcon(_avatarIconId), color: Colors.white, size: 24) : null,
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isBroadcasting && _communityName != null ? _communityName! : _displayName, 
                          style: TextStyle(
                            fontWeight: FontWeight.bold, 
                            fontSize: 16,
                            color: _isBroadcasting ? TwitterTheme.blue : null
                          )
                        ),
                        if (_isBroadcasting)
                          Text("Posting as Community Identity", style: TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic)),
                        
                        TextField(
                          controller: _postController,
                          focusNode: _postFocusNode,
                          onChanged: _onTextChanged,
                          autofocus: !_isEditing,
                          maxLines: null,
                          style: TextStyle(fontSize: 18),
                          decoration: InputDecoration(
                            hintText: _isBroadcasting ? "What's the official news?" : "What's happening?",
                            border: InputBorder.none,
                          ),
                        ),
                        
                        // --- MULTI IMAGE PREVIEW SECTION ---
                        if (_existingMediaUrls.isNotEmpty || _selectedMediaFiles.isNotEmpty)
                          Container(
                            margin: EdgeInsets.only(top: 12),
                            height: 120, // Height for horizontal scroll
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              children: [
                                // 1. Show Existing URLs (Edit Mode)
                                ..._existingMediaUrls.asMap().entries.map((entry) {
                                  return _buildPreviewItem(
                                    imageProvider: CachedNetworkImageProvider(entry.value),
                                    onRemove: () => _removeExistingUrl(entry.key),
                                    isVideo: _mediaType == 'video',
                                  );
                                }),
                                
                                // 2. Show New Files
                                ..._selectedMediaFiles.asMap().entries.map((entry) {
                                  return _buildPreviewItem(
                                    imageProvider: FileImage(entry.value),
                                    onRemove: () => _removeFile(entry.key),
                                    isVideo: _mediaType == 'video',
                                  );
                                }),
                              ],
                            ),
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

  Widget _buildPreviewItem({required ImageProvider imageProvider, required VoidCallback onRemove, required bool isVideo}) {
    return Stack(
      children: [
        Container(
          width: 100,
          margin: EdgeInsets.only(right: 8),
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(8),
            image: !isVideo ? DecorationImage(image: imageProvider, fit: BoxFit.cover) : null,
          ),
          child: isVideo 
              ? Center(child: Icon(Icons.play_circle_fill, color: Colors.white)) 
              : null,
        ),
        Positioned(
          top: 4, right: 12,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              padding: EdgeInsets.all(2),
              decoration: BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
              child: Icon(Icons.close, size: 14, color: Colors.white),
            ),
          ),
        )
      ],
    );
  }
}

class _BackgroundUploader {
  static void startUploadSequence({
    required OverlayState overlayState,
    required String text,
    required List<File> filesToUpload,
    required List<String> existingMediaUrls,
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
    required String? communityId,
    String? communityName,
    String? communityIcon,
    bool? communityVerified,
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
      filesToUpload: filesToUpload,
      existingMediaUrls: existingMediaUrls,
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
      communityId: communityId,
      communityName: communityName,
      communityIcon: communityIcon,
      communityVerified: communityVerified,
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
    required List<File> filesToUpload,
    required List<String> existingMediaUrls,
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
    required String? communityId,
    String? communityName,
    String? communityIcon,
    bool? communityVerified,
    required Function(String) onProgress,
    required VoidCallback onSuccess,
    required Function(dynamic) onFailure,
  }) async {
    try {
      List<String> finalUrls = [...existingMediaUrls];

      // 1. Process New Files
      if (filesToUpload.isNotEmpty) {
        int count = 1;
        for (var file in filesToUpload) {
          onProgress("Uploading ${count}/${filesToUpload.length}...");
          
          File fileToUp = file;
          
          // Compress Video
          if (mediaType == 'video') {
             try {
                final MediaInfo? info = await VideoCompress.compressVideo(
                  file.path,
                  quality: VideoQuality.MediumQuality,
                  deleteOrigin: false,
                );
                if (info != null && info.file != null) fileToUp = info.file!;
             } catch(e) { debugPrint("Compress fail: $e"); }
          }

          String? url = await _cloudinaryService.uploadMedia(fileToUp);
          if (url != null) finalUrls.add(url);
          
          count++;
        }
      }

      if (finalUrls.isEmpty && text.isEmpty) {
        onFailure("No content to post.");
        return;
      }

      // 2. Prepare Data
      final Map<String, dynamic> postData = {
        'text': text,
        'mediaType': mediaType,
        'visibility': visibility, 
        'isUploading': false,
        'mediaUrls': finalUrls, 
        'mediaUrl': finalUrls.isNotEmpty ? finalUrls.first : null, // Backward compat
      };

      if (isEditing && postId != null) {
        postData['editedAt'] = FieldValue.serverTimestamp();
        await _firestore.collection('posts').doc(postId).update(postData);
      } else {
        postData.addAll({
          'timestamp': FieldValue.serverTimestamp(),
          'userId': uid, // The Real Operator ID
          'userName': userName, // User Name
          'userEmail': userEmail,
          'avatarIconId': avatarIconId,
          'avatarHex': avatarHex,
          'profileImageUrl': profileImageUrl,
          'likes': {},
          'commentCount': 0,
          'repostedBy': [],
        });

        if (communityId != null) {
          postData['communityId'] = communityId;
          postData['isCommunityPost'] = true;
          // SAVE COMMUNITY DISPLAY INFO
          postData['communityName'] = communityName;
          postData['communityIcon'] = communityIcon;
          postData['communityVerified'] = communityVerified; // Important: Save verification status
        }

        await _firestore.collection('posts').add(postData);
      }

      // 3. Notify Followers
      if (visibility == 'public' || visibility == 'followers') {
        if (communityId == null) {
          await _firestore.collection('users').doc(uid).collection('notifications').add({
            'type': 'upload_complete',
            'senderId': 'system', 
            'postId': null,
            'postTextSnippet': 'Your post was uploaded successfully.',
            'timestamp': FieldValue.serverTimestamp(),
            'isRead': false,
          });
        }
      }

      // Cleanup
      if (mediaType == 'video') await VideoCompress.deleteAllCache();

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
      _message = status;
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
    setState(() { _isSuccess = true; _message = "Posted"; });
    if (_isMiniVisible) {
      Future.delayed(Duration(seconds: 5), () { if (mounted) setState(() => _isMiniVisible = false); });
    } else if (_isCardVisible) {
      Future.delayed(Duration(seconds: 5), () { if (mounted) setState(() => _isCardVisible = false); });
    }
  }

  void handleFailure(String error) {
    setState(() { _isError = true; _message = "Failed"; });
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
                key: UniqueKey(), // FIX: UniqueKey for Dismissible
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

  const _UploadCard({super.key, required this.isSuccess, required this.isError, required this.message, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Dismissible(
      key: UniqueKey(),
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