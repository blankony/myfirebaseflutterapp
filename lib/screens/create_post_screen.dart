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
import '../services/draft_service.dart'; 
import 'video_trimmer_screen.dart';
import '../services/app_localizations.dart';

final FirebaseAuth _auth = FirebaseAuth.instance;
final FirebaseFirestore _firestore = FirebaseFirestore.instance;
final CloudinaryService _cloudinaryService = CloudinaryService();

class CreatePostScreen extends StatefulWidget {
  final String? postId; // For editing published posts
  final Map<String, dynamic>? initialData; // For community context/prefill
  final DraftPost? draftData; // For loading a draft

  const CreatePostScreen({
    super.key,
    this.postId,
    this.initialData,
    this.draftData,
  });

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final TextEditingController _postController = TextEditingController();
  final PredictionService _predictionService = PredictionService();
  final DraftService _draftService = DraftService(); 
  final FocusNode _postFocusNode = FocusNode();
  final LanguageChecker _badwordGuard = LanguageChecker();

  bool _canPost = false;
  bool _isProcessing = false;
  bool _isSavingDraft = false; 

  String _visibility = 'public'; 
  bool _isAccountPrivate = false; 

  String _myUserName = 'Anonymous';
  String _myUserEmail = '';
  String? _myAvatarUrl;
  int _myAvatarIconId = 0;
  String _myAvatarHex = '';
  
  String? _communityId;
  String? _communityName;
  String? _communityIcon;
  bool _communityVerified = false;
  
  bool _isCommunityContext = false; 
  bool _hasOfficialAuthority = false; 
  bool _postAsCommunity = false; 
  bool _isRestricted = false; 

  String? _predictedText;
  Timer? _debounce;

  List<File> _selectedMediaFiles = []; 
  List<String> _existingMediaUrls = []; 
  List<String> _existingPublicIds = []; 
  String? _mediaType; 
  
  String? _currentDraftId;

  // State untuk melacak perubahan (Modified Check)
  String _initialText = '';
  List<String> _initialMediaUrls = [];

  bool get _isEditing => widget.postId != null;

  @override
  void initState() {
    super.initState();
    _checkEmailVerification(); 
    _loadIdentity(); 
    _trainAiModel();

    // Init Logic Priority: Edit Published > Load Draft > New Post
    if (widget.initialData != null && _isEditing) {
      _initFromPublishedPost();
    } else if (widget.draftData != null) {
      _initFromDraft(widget.draftData!);
    } else if (widget.initialData != null) {
      // Setup community context from navigation
      _communityId = widget.initialData!['communityId'];
      _communityName = widget.initialData!['communityName'];
      _communityIcon = widget.initialData!['communityIcon'];
    }
  }

  void _initFromPublishedPost() {
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

  void _initFromDraft(DraftPost draft) {
    _currentDraftId = draft.id;
    _postController.text = draft.text;
    _mediaType = draft.mediaType;
    _visibility = draft.visibility;
    _existingMediaUrls = List<String>.from(draft.mediaUrls);
    _existingPublicIds = List<String>.from(draft.publicIds);
    
    // Simpan state awal untuk perbandingan
    _initialText = draft.text;
    _initialMediaUrls = List<String>.from(draft.mediaUrls);
    
    if (draft.communityId != null) {
      _communityId = draft.communityId;
      _communityName = draft.communityName;
      _communityIcon = draft.communityIcon;
      _isCommunityContext = true;
    }
    _checkCanPost();
  }

  // Cek apakah ada perubahan dari kondisi awal
  bool _hasChanges() {
    bool textChanged = _postController.text.trim() != _initialText.trim();
    bool mediaChanged = _selectedMediaFiles.isNotEmpty || 
                        _existingMediaUrls.length != _initialMediaUrls.length;
    return textChanged || mediaChanged;
  }

  Future<void> _checkEmailVerification() async {
    final user = _auth.currentUser;
    if (user != null) {
      try { await user.reload(); } catch (_) {}
      if (!user.emailVerified) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          // LOCALIZATION
          var t = AppLocalizations.of(context)!;
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              title: Row(children: [Icon(Icons.mark_email_unread, color: Colors.orange), SizedBox(width: 8), Expanded(child: Text(t.translate('verify_required'), overflow: TextOverflow.ellipsis))]),
              content: Text(t.translate('verify_email_msg')),
              actions: [
                TextButton(
                  onPressed: () { 
                    user.sendEmailVerification(); 
                    Navigator.pop(context); 
                    Navigator.pop(context); 
                    OverlayService().showTopNotification(context, t.translate('post_verify_sent'), Icons.check, (){}); 
                  }, 
                  child: Text(t.translate('verify_resend'))
                ),
                ElevatedButton(onPressed: () { Navigator.pop(context); Navigator.pop(context); }, child: Text(t.translate('general_close'))),
              ],
            ),
          );
        });
      }
    }
  }

  Future<void> _loadIdentity() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (userDoc.exists) {
        final data = userDoc.data()!;
        setState(() {
          _myUserName = data['name'] ?? 'User';
          _myUserEmail = user.email ?? '';
          _myAvatarIconId = data['avatarIconId'] ?? 0;
          _myAvatarHex = data['avatarHex'] ?? '';
          _myAvatarUrl = data['profileImageUrl'];
          _isAccountPrivate = data['isPrivate'] ?? false;
        });
      }
    } catch (_) {}

    if (_communityId != null) {
      _isCommunityContext = true;
      _visibility = 'public'; 

      try {
        final comDoc = await _firestore.collection('communities').doc(_communityId).get();
        if (comDoc.exists) {
          final data = comDoc.data()!;
          _communityVerified = data['isVerified'] ?? false;
          final bool allowMembers = data['allowMemberPosts'] ?? false;
          final String ownerId = data['ownerId'];
          final List admins = data['admins'] ?? [];
          final List editors = data['editors'] ?? [];
          final bool isStaff = ownerId == user.uid || admins.contains(user.uid) || editors.contains(user.uid);
          
          setState(() {
            _hasOfficialAuthority = isStaff;
            _postAsCommunity = isStaff; 
            _communityName = data['name'];
            _communityIcon = data['imageUrl'];
          });

          if (!allowMembers && !isStaff) {
            setState(() => _isRestricted = true);
            if(mounted) {
              OverlayService().showTopNotification(context, "Posting restricted to Admins", Icons.lock, (){}, color: Colors.red);
              Navigator.pop(context);
            }
          }
        }
      } catch (e) { debugPrint("Error checking community permissions: $e"); }
    } else if (!_isEditing && widget.draftData == null) {
      if (mounted) setState(() { _visibility = _isAccountPrivate ? 'followers' : 'public'; });
    }
  }

  void _checkCanPost() {
    final textNotEmpty = _postController.text.trim().isNotEmpty;
    final hasMedia = _selectedMediaFiles.isNotEmpty || _existingMediaUrls.isNotEmpty;
    setState(() => _canPost = textNotEmpty || hasMedia);
  }

  Future<void> _trainAiModel() async {
    final user = _auth.currentUser;
    if (user == null) return;
    try {
      final snapshot = await _firestore.collection('posts').where('userId', isEqualTo: user.uid).limit(20).get();
      List<String> postHistory = snapshot.docs.map((doc) => (doc.data()['text'] ?? '').toString()).toList();
      _predictionService.learnFromUserPosts(postHistory);
    } catch (_) {}
  }

  Future<bool> _checkImageSafety() async {
    if (_mediaType != 'image' || _selectedMediaFiles.isEmpty) return true;
    setState(() => _isProcessing = true);
    
    // LOCALIZATION
    var t = AppLocalizations.of(context)!;
    OverlayService().showTopNotification(context, t.translate('post_scan_images'), Icons.remove_red_eye, (){}, color: Colors.orange);

    try {
      final apiKey = dotenv.env['GEMINI_API_KEY'];
      if (apiKey == null || apiKey.isEmpty) return true;

      int limit = _selectedMediaFiles.length > 3 ? 3 : _selectedMediaFiles.length;
      for (int i = 0; i < limit; i++) {
        final result = await VisualDetectorAi.analyzeImage(image: _selectedMediaFiles[i], geminiApiKey: apiKey);
        final String description = result.toString().toLowerCase(); 
        
        final List<String> dangerKeywords = [
          'nude', 'naked', 'sex', 'genitals', 'porn', 'erotic', 
          'blood', 'gore', 'violence', 'weapon', 'gun', 'knife', 'kill',
          'telanjang', 'bugil', 'darah', 'membunuh' 
        ];

        for (var word in dangerKeywords) {
          if (description.contains(word)) {
            if (mounted) _showRejectDialog(t.translate('post_sensitive_content')); // "Image contains sensitive content"
            return false;
          }
        }

        if (_badwordGuard.containsBadLanguage(description)) {
          if (mounted) _showRejectDialog(t.translate('post_image_inappropriate')); // "Image flagged..."
          return false;
        }
      }
      return true; 
    } catch (e) {
      return true; 
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _showRejectDialog(String reason) {
    var t = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [Icon(Icons.gpp_bad, color: Colors.red), SizedBox(width: 8), Text(t.translate('general_rejected'))]),
        content: Text("${t.translate('post_rejected_desc')}$reason"),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t.translate('general_edit'), style: TextStyle(color: TwitterTheme.blue)))],
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
      if (mounted && suggestion != null && suggestion.isNotEmpty) setState(() => _predictedText = suggestion);
    });
  }

  void _acceptPrediction() {
    if (_predictedText != null) {
      final newText = "${_postController.text.trimRight()} $_predictedText ";
      _postController.text = newText;
      _postController.selection = TextSelection.fromPosition(TextPosition(offset: newText.length));
      setState(() { _predictedText = null; _canPost = true; });
      _onTextChanged(newText);
    }
  }

  void _showMediaSourceSelection({required bool isVideo}) {
    var t = AppLocalizations.of(context)!;
    FocusScope.of(context).unfocus();
    showModalBottomSheet(context: context, builder: (context) {
      return SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(leading: const Icon(Icons.camera_alt), title: Text(t.translate('profile_camera')), onTap: () { Navigator.pop(context); _pickMedia(ImageSource.camera, isVideo: isVideo); }),
        ListTile(leading: const Icon(Icons.photo_library), title: Text(t.translate('profile_gallery')), onTap: () { Navigator.pop(context); _pickMedia(ImageSource.gallery, isVideo: isVideo); }),
      ]));
    });
  }

  Future<void> _pickMedia(ImageSource source, {bool isVideo = false}) async {
    final picker = ImagePicker();
    try {
      if (isVideo) {
        final XFile? pickedFile = await picker.pickVideo(source: source, maxDuration: const Duration(minutes: 10));
        if (pickedFile != null && mounted) {
          final result = await Navigator.of(context).push(MaterialPageRoute(builder: (_) => VideoTrimmerScreen(file: File(pickedFile.path))));
          if (result != null && result['file'] is File) {
            setState(() { 
              _mediaType = 'video'; 
              _selectedMediaFiles = [result['file']]; 
              _existingMediaUrls = []; 
              _existingPublicIds = [];
              _checkCanPost(); 
            });
          }
        }
      } else {
        if (source == ImageSource.gallery) {
          final List<XFile> pickedFiles = await picker.pickMultiImage(imageQuality: 80);
          if (pickedFiles.isNotEmpty) {
            setState(() { 
              if (_mediaType == 'video') { _selectedMediaFiles = []; _existingMediaUrls = []; _existingPublicIds = []; } 
              _mediaType = 'image'; 
              _selectedMediaFiles.addAll(pickedFiles.map((x) => File(x.path))); 
              _checkCanPost(); 
            });
          }
        } else {
          final XFile? pickedFile = await picker.pickImage(source: source, imageQuality: 80);
          if (pickedFile != null) {
             setState(() { 
               if (_mediaType == 'video') { _selectedMediaFiles = []; _existingMediaUrls = []; _existingPublicIds = []; } 
               _mediaType = 'image'; 
               _selectedMediaFiles.add(File(pickedFile.path)); 
               _checkCanPost(); 
             });
          }
        }
      }
    } catch (e) { debugPrint("Error picking media: $e"); }
  }

  void _removeFile(int index) {
    setState(() { _selectedMediaFiles.removeAt(index); _checkCanPost(); if (_selectedMediaFiles.isEmpty && _existingMediaUrls.isEmpty) _mediaType = null; });
  }

  void _removeExistingUrl(int index) {
    setState(() { 
      _existingMediaUrls.removeAt(index);
      if (_existingPublicIds.length > index) _existingPublicIds.removeAt(index); 
      _checkCanPost(); 
      if (_selectedMediaFiles.isEmpty && _existingMediaUrls.isEmpty) _mediaType = null; 
    });
  }

  void _showVisibilityPicker() {
    var t = AppLocalizations.of(context)!;
    FocusScope.of(context).unfocus(); 
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(t.translate('post_visibility_title'), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)), // "Who can see this?"
              ),
              if (_isAccountPrivate) ...[
                 ListTile(
                  leading: const Icon(Icons.people, color: TwitterTheme.blue),
                  title: Text(t.translate('profile_followers')), // "Followers"
                  subtitle: Text(t.translate('post_vis_followers_desc')), // "Only your followers..."
                  trailing: _visibility == 'followers' ? const Icon(Icons.check, color: TwitterTheme.blue) : null,
                  onTap: () {
                    setState(() => _visibility = 'followers');
                    Navigator.pop(context);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.public, color: Colors.grey),
                  title: Text(t.translate('post_vis_public')), // "Public"
                  subtitle: Text(t.translate('post_vis_private_warn')), // "Account is private..."
                  enabled: false, 
                ),
              ] else ...[
                ListTile(
                  leading: const Icon(Icons.public, color: TwitterTheme.blue),
                  title: Text(t.translate('post_vis_public')), // "Public"
                  subtitle: Text(t.translate('post_vis_public_desc')), // "Anyone on Sapa PNJ"
                  trailing: _visibility == 'public' ? const Icon(Icons.check, color: TwitterTheme.blue) : null,
                  onTap: () {
                    setState(() => _visibility = 'public');
                    Navigator.pop(context);
                  },
                ),
              ],
              ListTile(
                leading: const Icon(Icons.lock, color: Colors.red),
                title: Text(t.translate('post_vis_me')), // "Only Me"
                trailing: _visibility == 'private' ? const Icon(Icons.check, color: TwitterTheme.blue) : null,
                onTap: () {
                  setState(() => _visibility = 'private');
                  Navigator.pop(context);
                },
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  Widget _buildVisibilityButtonContent() {
    var t = AppLocalizations.of(context)!;
    IconData icon;
    String label;
    Color color = TwitterTheme.blue;

    if (_visibility == 'private') {
      icon = Icons.lock;
      label = t.translate('post_vis_me'); // "Only Me"
      color = Colors.red;
    } else if (_visibility == 'followers') {
      icon = Icons.people;
      label = t.translate('profile_followers'); // "Followers"
    } else {
      icon = Icons.public;
      label = t.translate('post_vis_public'); // "Public"
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(width: 4),
        Icon(Icons.keyboard_arrow_down, color: color, size: 18),
      ],
    );
  }

  // --- INTERCEPT BACK NAVIGATION ---
  Future<bool> _onWillPop() async {
    var t = AppLocalizations.of(context)!;

    // 1. Jika kosong total dan bukan draft, langsung keluar
    if (!_canPost && _currentDraftId == null) return true;

    // 2. Jika Draft sudah ada DAN TIDAK ADA PERUBAHAN, langsung keluar
    if (_currentDraftId != null && !_hasChanges()) {
      return true;
    }

    // 3. Jika sedang edit post yang sudah publish (bukan draft), konfirmasi discard changes
    if (_isEditing) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(t.translate('post_discard_title')), // "Discard changes?"
          content: Text(t.translate('post_discard_desc')), // "You have unsaved changes..."
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(t.translate('post_keep_editing')), // "Keep Editing"
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(t.translate('post_discard'), style: TextStyle(color: Colors.red)), // "Discard"
            ),
          ],
        ),
      );
      return confirm ?? false;
    }

    // 4. Untuk Post Baru atau Draft yang diubah -> Tawarkan Save
    final String title = _currentDraftId != null ? t.translate('post_draft_update_title') : t.translate('post_draft_save_title');
    final String content = _currentDraftId != null ? t.translate('post_draft_update_desc') : t.translate('post_draft_save_desc');

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop('discard'),
            child: Text(t.translate('post_discard'), style: TextStyle(color: Colors.red)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop('cancel'),
            child: Text(t.translate('general_cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop('save'),
            style: ElevatedButton.styleFrom(backgroundColor: TwitterTheme.blue, foregroundColor: Colors.white),
            child: Text(t.translate('general_save')),
          ),
        ],
      ),
    );

    if (result == 'save') {
      await _saveToDrafts();
      return true; 
    } else if (result == 'discard') {
      return true;
    }
    
    return false; // Stay
  }

  // --- SAVE DRAFT LOGIC ---
  Future<void> _saveToDrafts() async {
    setState(() => _isSavingDraft = true);
    var t = AppLocalizations.of(context)!;
    
    try {
      List<String> finalUrls = [..._existingMediaUrls];
      List<String> finalPublicIds = [..._existingPublicIds];

      if (_selectedMediaFiles.isNotEmpty) {
        OverlayService().showTopNotification(context, t.translate('post_draft_uploading'), Icons.cloud_upload, (){});
        
        for (var file in _selectedMediaFiles) {
          File fileToUp = file;
          if (_mediaType == 'video') {
             try {
               final MediaInfo? info = await VideoCompress.compressVideo(file.path, quality: VideoQuality.MediumQuality, deleteOrigin: false);
               if (info != null && info.file != null) fileToUp = info.file!;
             } catch(e) {}
          }
          
          final response = await _cloudinaryService.uploadFileWithDetails(fileToUp, _mediaType == 'video' ? 'video' : 'auto');
          
          if (response.secureUrl != null) {
            finalUrls.add(response.secureUrl!);
            if (response.publicId != null) finalPublicIds.add(response.publicId!);
          }
        }
      }

      // Create Draft Object
      final draft = DraftPost(
        id: _currentDraftId ?? DateTime.now().millisecondsSinceEpoch.toString(),
        text: _postController.text,
        mediaUrls: finalUrls,
        publicIds: finalPublicIds,
        mediaType: _mediaType,
        visibility: _visibility,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        communityId: _communityId,
        communityName: _communityName,
        communityIcon: _communityIcon,
      );

      await _draftService.saveDraft(draft);

      if (mounted) {
        OverlayService().showTopNotification(context, t.translate('post_draft_saved'), Icons.save, (){}, color: Colors.green);
      }
    } catch (e) {
      if(mounted) OverlayService().showTopNotification(context, t.translate('post_draft_failed'), Icons.error, (){}, color: Colors.red);
    } finally {
      if(mounted) setState(() => _isSavingDraft = false);
    }
  }

  Future<void> _submitPost() async {
    if (!_canPost) return;
    
    var t = AppLocalizations.of(context)!;
    final user = _auth.currentUser;
    if (user == null) return;

    final text = _postController.text;
    if (_badwordGuard.containsBadLanguage(text)) {
      _showRejectDialog(t.translate('post_bad_words'));
      return;
    }

    final isImageSafe = await _checkImageSafety();
    if (!isImageSafe) return; 

    FocusScope.of(context).unfocus();
    Navigator.of(context).pop();

    final OverlayState? overlayState = Overlay.maybeOf(context);
    
    // Prepare translated status strings
    final Map<String, String> localizedStrings = {
      'uploading': t.translate('post_uploading_count'), // "Uploading..."
      'no_content': t.translate('post_no_content'),
      'posted': t.translate('post_success'),
      'failed': t.translate('post_failed'),
    };

    if (overlayState != null) {
      _BackgroundUploader.startUploadSequence(
        overlayState: overlayState,
        text: _postController.text,
        filesToUpload: _selectedMediaFiles, 
        existingMediaUrls: _existingMediaUrls, 
        mediaType: _mediaType,
        visibility: _visibility,
        isEditing: _isEditing,
        postId: widget.postId,
        
        uid: user.uid, 
        userName: _postAsCommunity ? (_communityName ?? 'Community') : _myUserName,
        userEmail: _myUserEmail,
        avatarIconId: _postAsCommunity ? 0 : _myAvatarIconId,
        avatarHex: _postAsCommunity ? '' : _myAvatarHex,
        profileImageUrl: _postAsCommunity ? _communityIcon : _myAvatarUrl,
        
        communityId: _communityId,
        communityName: _communityName,
        communityIcon: _communityIcon,
        communityVerified: _communityVerified,
        isCommunityIdentity: _postAsCommunity,
        
        draftIdToDelete: _currentDraftId,
        localizedStrings: localizedStrings, // PASS LOCALIZED STRINGS
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
    if (_isRestricted) return const SizedBox.shrink(); 
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    var t = AppLocalizations.of(context)!;

    final String? currentAvatarUrl = _postAsCommunity ? _communityIcon : _myAvatarUrl;
    final String currentDisplayName = _postAsCommunity ? (_communityName ?? 'Community') : _myUserName;

    // Wrap with WillPopScope to handle "Back" logic
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        appBar: AppBar(
          leading: IconButton(
            icon: Icon(Icons.close, color: theme.primaryColor),
            // Manually trigger pop check
            onPressed: () async {
              if (await _onWillPop()) {
                if (mounted) Navigator.of(context).pop();
              }
            },
          ),
          title: _isCommunityContext
              ? Row(
                  children: [
                    const Icon(Icons.groups, color: TwitterTheme.blue, size: 20),
                    const SizedBox(width: 8),
                    Flexible(child: Text(_communityName ?? "Community", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                  ],
                ) 
              : Text(_isEditing ? t.translate('post_edit_title') : t.translate('post_create_title'), style: const TextStyle(fontWeight: FontWeight.bold)),
          centerTitle: false,
          actions: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: ElevatedButton(
                onPressed: _canPost && !_isProcessing && !_isSavingDraft ? _submitPost : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: TwitterTheme.blue,
                  foregroundColor: Colors.white,
                  shape: const StadiumBorder()
                ),
                child: Text(t.translate('post_button')), // "Post"
              ),
            )
          ],
        ),
        body: Stack(
          children: [
            Positioned.fill(
              child: SingleChildScrollView(
                padding: EdgeInsets.only(top: 16, left: 16, right: 16, bottom: bottomInset + 80),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_hasOfficialAuthority)
                      Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: theme.cardColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: theme.dividerColor)
                        ),
                        child: Row(
                          children: [
                            Text(t.translate('post_identity_label'), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            const Spacer(),
                            ChoiceChip(
                              label: Text(t.translate('post_identity_me')), // "Me"
                              selected: !_postAsCommunity,
                              onSelected: (val) => setState(() => _postAsCommunity = false),
                              visualDensity: VisualDensity.compact,
                            ),
                            const SizedBox(width: 8),
                            ChoiceChip(
                              label: Text(t.translate('nav_community')), // "Community"
                              selected: _postAsCommunity,
                              onSelected: (val) => setState(() => _postAsCommunity = true),
                              selectedColor: TwitterTheme.blue.withOpacity(0.2),
                              labelStyle: TextStyle(color: _postAsCommunity ? TwitterTheme.blue : null),
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ),
                      ),

                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: currentAvatarUrl != null ? Colors.transparent : AvatarHelper.getColor(_myAvatarHex),
                          backgroundImage: currentAvatarUrl != null ? CachedNetworkImageProvider(currentAvatarUrl) : null,
                          child: currentAvatarUrl == null 
                              ? (_postAsCommunity 
                                  ? const Icon(Icons.groups, color: Colors.white) 
                                  : Icon(AvatarHelper.getIcon(_myAvatarIconId), color: Colors.white)) 
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                currentDisplayName, 
                                style: TextStyle(
                                  fontWeight: FontWeight.bold, 
                                  fontSize: 16,
                                  color: _postAsCommunity ? TwitterTheme.blue : null
                                )
                              ),
                              if (_isCommunityContext)
                                Text(
                                  _postAsCommunity 
                                    ? t.translate('post_as_comm_id')
                                    : "${t.translate('post_in_comm')} $_communityName",
                                  style: const TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic)
                                ),
                            
                              TextField(
                                controller: _postController,
                                focusNode: _postFocusNode,
                                onChanged: _onTextChanged,
                                autofocus: !_isEditing,
                                maxLines: null,
                                style: const TextStyle(fontSize: 18),
                                decoration: InputDecoration(
                                  hintText: _postAsCommunity ? t.translate('post_hint_official') : t.translate('post_hint'),
                                  border: InputBorder.none,
                                ),
                              ),
                              
                              if (_existingMediaUrls.isNotEmpty || _selectedMediaFiles.isNotEmpty)
                                Container(
                                  height: 100,
                                  margin: const EdgeInsets.only(top: 10),
                                  child: ListView(
                                    scrollDirection: Axis.horizontal,
                                    children: [
                                      ..._existingMediaUrls.asMap().entries.map((e) => _buildPreviewItem(CachedNetworkImageProvider(e.value), () => _removeExistingUrl(e.key), _mediaType == 'video')),
                                      ..._selectedMediaFiles.asMap().entries.map((e) => _buildPreviewItem(FileImage(e.value), () => _removeFile(e.key), _mediaType == 'video')),
                                    ],
                                  ),
                                ),
                            
                              if (_predictedText != null)
                                GestureDetector(
                                  onTap: _acceptPrediction,
                                  child: Container(
                                    margin: const EdgeInsets.only(top: 8),
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(color: TwitterTheme.blue.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                                    child: Text("${t.translate('search_suggestion_prefix')} $_predictedText", style: const TextStyle(color: TwitterTheme.blue)),
                                  ),
                                )
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            
            Positioned(
              left: 0, right: 0, bottom: bottomInset,
              child: Container(
                color: theme.scaffoldBackgroundColor,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    IconButton(icon: const Icon(Icons.image, color: TwitterTheme.blue), onPressed: () => _showMediaSourceSelection(isVideo: false)),
                    IconButton(icon: const Icon(Icons.videocam, color: TwitterTheme.blue), onPressed: () => _showMediaSourceSelection(isVideo: true)),
                    
                    if (!_isCommunityContext)
                      InkWell(
                        onTap: _showVisibilityPicker,
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: theme.brightness == Brightness.dark ? Colors.white10 : Colors.grey[200],
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: _buildVisibilityButtonContent(),
                        ),
                      ),
                  ],
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewItem(ImageProvider imageProvider, VoidCallback onRemove, bool isVideo) {
    return Stack(
      children: [
        Container(
          width: 100, margin: const EdgeInsets.only(right: 8),
          decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(8), image: !isVideo ? DecorationImage(image: imageProvider, fit: BoxFit.cover) : null),
          child: isVideo ? const Center(child: Icon(Icons.play_circle_fill, color: Colors.white)) : null,
        ),
        Positioned(top: 4, right: 12, child: GestureDetector(onTap: onRemove, child: Container(padding: const EdgeInsets.all(2), decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle), child: const Icon(Icons.close, size: 14, color: Colors.white))))
      ],
    );
  }
}

// Background Uploader Class (Modified to accept localized strings)
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
    bool isCommunityIdentity = false,
    String? draftIdToDelete,
    required Map<String, String> localizedStrings, // NEW PARAMETER
  }) {
    final GlobalKey<_PostUploadOverlayState> overlayKey = GlobalKey();
    late OverlayEntry overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) => _PostUploadOverlay(
        key: overlayKey,
        onDismissRequest: () {
          overlayKey.currentState?.dismissToIcon();
        },
        initialMessage: localizedStrings['uploading'] ?? "Uploading...", // Use localized
      ),
    );

    overlayState.insert(overlayEntry);

    _processUpload(
      text, filesToUpload, existingMediaUrls, mediaType, visibility, isEditing, postId,
      uid, userName, userEmail, avatarIconId, avatarHex, profileImageUrl, communityId,
      communityName, communityIcon, communityVerified, isCommunityIdentity, draftIdToDelete,
      localizedStrings,
      (status) => overlayKey.currentState?.updateStatus(status),
      () {
        overlayKey.currentState?.handleSuccess(localizedStrings['posted'] ?? "Posted");
        Future.delayed(const Duration(seconds: 7), () { if (overlayEntry.mounted) overlayEntry.remove(); });
      },
      (error) {
        overlayKey.currentState?.handleFailure(localizedStrings['failed'] ?? "Failed");
        Future.delayed(const Duration(seconds: 4), () { if (overlayEntry.mounted) overlayEntry.remove(); });
      },
    );
  }

  static Future<void> _processUpload(
    String text, List<File> files, List<String> urls, String? type, String vis, bool edit, String? pid,
    String uid, String uName, String uEmail, int icon, String hex, String? img, String? comId,
    String? comName, String? comIcon, bool? comVerified, bool isCommunityIdentity, String? draftId,
    Map<String, String> locStrings,
    Function(String) onProgress, VoidCallback onSuccess, Function(dynamic) onFailure,
  ) async {
    try {
      List<String> finalUrls = [...urls];
      if (files.isNotEmpty) {
        int count = 1;
        for (var file in files) {
          // Replace placeholders manually if needed or just use "Uploading..."
          // Ideally: "Uploading 1/3..."
          // We can use a simple replace if we want better localization support, but for now:
          String msg = locStrings['uploading'] ?? "Uploading...";
          onProgress("$msg ($count/${files.length})");
          
          File fileToUp = file;
          if (type == 'video') {
             try {
               final MediaInfo? info = await VideoCompress.compressVideo(file.path, quality: VideoQuality.MediumQuality, deleteOrigin: false);
               if (info != null && info.file != null) fileToUp = info.file!;
             } catch(e) {}
          }
          String? url = await CloudinaryService().uploadMedia(fileToUp);
          if (url != null) finalUrls.add(url);
          count++;
        }
      }

      if (finalUrls.isEmpty && text.isEmpty) { onFailure(locStrings['no_content'] ?? "No content"); return; }

      final Map<String, dynamic> postData = {
        'text': text,
        'mediaType': type,
        'visibility': vis, 
        'isUploading': false,
        'mediaUrls': finalUrls, 
        'mediaUrl': finalUrls.isNotEmpty ? finalUrls.first : null,
      };

      if (edit && pid != null) {
        postData['editedAt'] = FieldValue.serverTimestamp();
        await FirebaseFirestore.instance.collection('posts').doc(pid).update(postData);
      } else {
        postData.addAll({
          'timestamp': FieldValue.serverTimestamp(),
          'userId': uid,
          'userName': uName,
          'userEmail': uEmail,
          'avatarIconId': icon,
          'avatarHex': hex,
          'profileImageUrl': img,
          'likes': {},
          'commentCount': 0,
          'repostedBy': [],
        });

        if (comId != null) {
          postData['communityId'] = comId;
          postData['communityName'] = comName;
          postData['communityIcon'] = comIcon;
          postData['communityVerified'] = comVerified;
          postData['isCommunityPost'] = isCommunityIdentity; 
        }

        await FirebaseFirestore.instance.collection('posts').add(postData);
        
        if (draftId != null) {
          await DraftService().discardDraftAfterPosting(draftId);
        }
      }

      if (type == 'video') await VideoCompress.deleteAllCache();
      onSuccess();
    } catch (e) {
      onFailure(e);
    }
  }
}

class _PostUploadOverlay extends StatefulWidget {
  final VoidCallback onDismissRequest;
  final String initialMessage; // Added
  const _PostUploadOverlay({super.key, required this.onDismissRequest, required this.initialMessage});
  @override State<_PostUploadOverlay> createState() => _PostUploadOverlayState();
}

class _PostUploadOverlayState extends State<_PostUploadOverlay> {
  bool _isCardVisible = true;
  bool _isMiniVisible = false;
  bool _isSuccess = false;
  bool _isError = false;
  late String _message; 
  Timer? _autoDismissTimer;

  @override
  void initState() {
    super.initState();
    _message = widget.initialMessage;
  }

  double get _targetTop => MediaQuery.of(context).padding.top + 10;
  double get _targetRight => 12.0;
  double get _miniRight => 60.0; 

  @override void dispose() { _autoDismissTimer?.cancel(); super.dispose(); }
  void updateStatus(String status) { if (!mounted) return; setState(() => _message = status); }
  void dismissToIcon() { setState(() => _isCardVisible = false); Future.delayed(const Duration(milliseconds: 400), () { if (mounted) setState(() => _isMiniVisible = true); }); }
  
  void _expandToCard() {
    setState(() { _isMiniVisible = false; });
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() { _isCardVisible = true; });
        _autoDismissTimer?.cancel();
        _autoDismissTimer = Timer(const Duration(seconds: 2), dismissToIcon);
      }
    });
  }

  void handleSuccess(String msg) { setState(() { _isSuccess = true; _message = msg; }); if (_isMiniVisible) Future.delayed(const Duration(seconds: 5), () { if (mounted) setState(() => _isMiniVisible = false); }); else if (_isCardVisible) Future.delayed(const Duration(seconds: 5), () { if (mounted) setState(() => _isCardVisible = false); }); }
  void handleFailure(String msg) { setState(() { _isError = true; _message = msg; }); if (!_isCardVisible) setState(() => _isCardVisible = true); }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Stack(
      children: [
        AnimatedPositioned(
          duration: const Duration(milliseconds: 400), curve: Curves.easeOutQuart,
          top: _targetTop, right: _isMiniVisible ? _miniRight : _targetRight, 
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 300), 
            opacity: _isMiniVisible ? 1.0 : 0.0, 
            child: GestureDetector(
              onTap: _expandToCard,
              child: Material(
                elevation: 4,
                shape: const CircleBorder(),
                color: _isSuccess ? Colors.green : theme.cardColor,
                child: Container(
                  width: 36, height: 36, padding: const EdgeInsets.all(8),
                  child: _isSuccess 
                    ? const Icon(Icons.check, size: 20, color: Colors.white)
                    : const CircularProgressIndicator(strokeWidth: 3, color: TwitterTheme.blue),
                ),
              ),
            ),
          ),
        ),
        AnimatedPositioned(
          duration: const Duration(milliseconds: 500), curve: Curves.easeInOutBack,
          top: _isCardVisible ? _targetTop : -100, left: 16, right: _targetRight, 
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 300), opacity: _isCardVisible ? 1.0 : 0.0,
            child: Dismissible(
              key: const ValueKey('upload_card_dismiss'),
              direction: DismissDirection.horizontal,
              onDismissed: (_) {
                widget.onDismissRequest();
              },
              child: Material(
                elevation: 8, borderRadius: BorderRadius.circular(12), color: theme.cardColor,
                child: Padding(padding: const EdgeInsets.all(16), child: Row(children: [
                  if (_isSuccess) const Icon(Icons.check_circle, color: TwitterTheme.blue) else if (_isError) const Icon(Icons.error, color: Colors.red) else const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 12), Expanded(child: Text(_message, style: TextStyle(fontWeight: FontWeight.bold, color: theme.textTheme.bodyLarge?.color))),
                ])),
              ),
            ),
          ),
        )
      ],
    );
  }
}