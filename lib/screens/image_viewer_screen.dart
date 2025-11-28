// ignore_for_file: prefer_const_constructors, use_build_context_synchronously
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:path_provider/path_provider.dart'; 
import 'package:path/path.dart' as p;
import 'package:video_player/video_player.dart'; 
import 'package:intl/intl.dart'; 
import '../main.dart';

class ImageViewerScreen extends StatefulWidget {
  final String imageUrl;
  final String? mediaType;
  final Map<String, dynamic>? postData;
  final String? postId; 
  final String heroTag;
  final VideoPlayerController? videoController; 

  const ImageViewerScreen({
    super.key,
    required this.imageUrl,
    required this.heroTag,
    this.mediaType,
    this.postData,
    this.postId,
    this.videoController,
  });

  @override
  State<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<ImageViewerScreen> with SingleTickerProviderStateMixin {
  bool _showOverlays = true;
  Timer? _hideTimer; 

  late AnimationController _menuController;
  late Animation<Offset> _menuAnimation;
  bool _isMenuOpen = false;

  bool _isLiked = false;
  int _likeCount = 0;
  bool _isReposted = false;
  int _repostCount = 0;
  
  // Video Player State
  VideoPlayerController? _videoController;
  bool _isVideoInitialized = false;
  bool _isPlaying = false;
  bool _isBuffering = false;
  bool _isExternalController = false; 
  double _currentVolume = 1.0;
  
  // Seekbar State
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;
  bool _isDraggingSlider = false;

  bool get _isPostContent => widget.postId != null;
  bool get _isVideo => widget.mediaType == 'video';

  @override
  void initState() {
    super.initState();
    _initStats();
    _menuController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _menuAnimation = Tween<Offset>(
      begin: const Offset(1.5, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _menuController,
      curve: Curves.easeOutQuart,
    ));

    if (_isVideo) {
      _initVideo();
    }
    
    _resetHideTimer();
  }

  void _initVideo() {
    if (widget.videoController != null) {
      // REUSE EXISTING CONTROLLER
      _videoController = widget.videoController;
      _isExternalController = true;
      _isVideoInitialized = true;
      _isPlaying = _videoController!.value.isPlaying;
      _totalDuration = _videoController!.value.duration;
      _videoController!.addListener(_videoListener);
      
      // Auto play if not playing
      if (!_isPlaying) {
        _videoController!.play();
        _isPlaying = true;
      }
    } else {
      // INIT NEW CONTROLLER (Fallback)
      _videoController = VideoPlayerController.networkUrl(Uri.parse(widget.imageUrl))
        ..initialize().then((_) {
          setState(() {
            _isVideoInitialized = true;
            _isPlaying = true;
            _totalDuration = _videoController!.value.duration;
          });
          _videoController!.play();
          _videoController!.setLooping(true);
          _videoController!.addListener(_videoListener);
        });
    }
  }

  void _videoListener() {
    if (_videoController == null || !mounted) return;
    
    final bool isBuffering = _videoController!.value.isBuffering;
    if (isBuffering != _isBuffering) {
      setState(() {
        _isBuffering = isBuffering;
      });
    }

    if (!_isDraggingSlider) {
      setState(() {
        _currentPosition = _videoController!.value.position;
        if (_videoController!.value.duration != Duration.zero) {
           _totalDuration = _videoController!.value.duration;
        }
      });
    }
  }

  void _onSeekStart(double value) {
    _isDraggingSlider = true;
    _hideTimer?.cancel();
  }

  void _onSeekChanged(double value) {
    setState(() {
      _currentPosition = Duration(milliseconds: value.toInt());
    });
  }

  void _onSeekEnd(double value) {
    _videoController?.seekTo(Duration(milliseconds: value.toInt()));
    _isDraggingSlider = false;
    _resetHideTimer();
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    if (duration.inHours > 0) {
      return "${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
    }
    return "$twoDigitMinutes:$twoDigitSeconds";
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _menuController.dispose();
    _videoController?.removeListener(_videoListener);
    
    if (!_isExternalController) {
      _videoController?.dispose();
    }
    super.dispose();
  }

  void _initStats() {
    if (widget.postData == null) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    final likes = widget.postData!['likes'] as Map<String, dynamic>? ?? {};
    final reposts = widget.postData!['repostedBy'] as List? ?? [];

    setState(() {
      _likeCount = likes.length;
      _isLiked = uid != null && likes.containsKey(uid);
      _repostCount = reposts.length;
      _isReposted = uid != null && reposts.contains(uid);
    });
  }

  void _toggleOverlays() {
    setState(() {
      _showOverlays = !_showOverlays;
    });
    
    if (_showOverlays) {
      _resetHideTimer();
    } else {
      _hideTimer?.cancel();
      _closeMenu();
    }
  }

  void _resetHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _isPlaying && !_isDraggingSlider) { 
        setState(() {
          _showOverlays = false;
          _isMenuOpen = false; 
        });
        _menuController.reverse();
      }
    });
  }

  void _openMenu() {
    setState(() {
      _isMenuOpen = true;
    });
    _menuController.forward();
    _resetHideTimer(); 
  }

  void _closeMenu() {
    _menuController.reverse().then((_) {
      if (mounted) {
        setState(() {
          _isMenuOpen = false;
        });
      }
    });
  }

  void _togglePlayPause() {
    if (_videoController == null || !_isVideoInitialized) return;
    setState(() {
      if (_videoController!.value.isPlaying) {
        _videoController!.pause();
        _isPlaying = false;
        _showOverlays = true; 
        _hideTimer?.cancel(); 
      } else {
        _videoController!.play();
        _isPlaying = true;
        _resetHideTimer(); 
      }
    });
  }

  void _changeSpeed(double speed) {
    _videoController?.setPlaybackSpeed(speed);
    Navigator.pop(context); 
    _resetHideTimer();
  }

  Future<void> _toggleLike() async {
    if (!_isPostContent) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() { _isLiked = !_isLiked; _isLiked ? _likeCount++ : _likeCount--; });
    try {
      final docRef = FirebaseFirestore.instance.collection('posts').doc(widget.postId);
      if (_isLiked) await docRef.update({'likes.${user.uid}': true});
      else await docRef.update({'likes.${user.uid}': FieldValue.delete()});
    } catch (e) { setState(() { _isLiked = !_isLiked; _isLiked ? _likeCount++ : _likeCount--; }); }
  }

  Future<void> _toggleRepost() async {
    if (!_isPostContent) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() { _isReposted = !_isReposted; _isReposted ? _repostCount++ : _repostCount--; });
    try {
      final docRef = FirebaseFirestore.instance.collection('posts').doc(widget.postId);
      if (_isReposted) await docRef.update({'repostedBy': FieldValue.arrayUnion([user.uid])});
      else await docRef.update({'repostedBy': FieldValue.arrayRemove([user.uid])});
    } catch (e) { setState(() { _isReposted = !_isReposted; _isReposted ? _repostCount++ : _repostCount--; }); }
  }

  Future<void> _shareImage() async {
    try {
      final file = await DefaultCacheManager().getSingleFile(widget.imageUrl);
      await Share.shareXFiles([XFile(file.path)], text: 'Check out this media from Sapa PNJ!');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to share.')));
    }
  }

  Future<void> _downloadMedia() async {
    _closeMenu();
    final OverlayState overlayState = Overlay.of(context);
    _DownloadManager.startDownloadSequence(
      overlayState: overlayState,
      url: widget.imageUrl,
      isImage: !_isVideo,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      body: GestureDetector(
        onTap: _isVideo ? _togglePlayPause : _toggleOverlays,
        child: Stack(
          fit: StackFit.expand,
          alignment: Alignment.center,
          children: [
            // 1. CONTENT
            if (_isVideo)
              _isVideoInitialized 
                  ? Center(
                      child: AspectRatio(
                        aspectRatio: _videoController!.value.aspectRatio,
                        child: VideoPlayer(_videoController!),
                      ),
                    )
                  : Center(child: CircularProgressIndicator(color: Colors.white))
            else
              PhotoView(
                imageProvider: CachedNetworkImageProvider(widget.imageUrl),
                backgroundDecoration: BoxDecoration(color: Colors.black),
                initialScale: PhotoViewComputedScale.contained,
                minScale: PhotoViewComputedScale.contained,
                maxScale: PhotoViewComputedScale.covered * 2.5,
                heroAttributes: PhotoViewHeroAttributes(tag: widget.heroTag),
              ),

            // 2. BUFFERING
            if (_isVideo && _isBuffering && _isPlaying)
              Center(
                child: Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle
                  ),
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              ),

            // 3. CENTER PLAY BUTTON
            if (_isVideo && !_isPlaying && _isVideoInitialized && !_showOverlays)
               Center(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2)
                  ),
                  padding: EdgeInsets.all(20),
                  child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 50),
                ),
              ),

            // 4. TOP BAR
            AnimatedOpacity(
              opacity: _showOverlays ? 1.0 : 0.0,
              duration: Duration(milliseconds: 200),
              child: Positioned(
                top: 0, left: 0, right: 0,
                child: Container(
                  height: 100,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.black.withOpacity(0.8), Colors.transparent],
                    ),
                  ),
                  child: SafeArea(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        IconButton(
                          icon: Icon(Icons.arrow_back, color: Colors.white),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        IconButton(
                          icon: Icon(Icons.more_vert, color: Colors.white),
                          onPressed: _openMenu,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // 5. MENU
            if (_isMenuOpen)
              Positioned(
                top: 50, right: 10,
                child: SlideTransition(
                  position: _menuAnimation,
                  child: Container(
                    width: 200,
                    decoration: BoxDecoration(
                      color: const Color(0xFF15202B),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 10)],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          leading: Icon(Icons.save_alt, color: Colors.white),
                          title: Text('Save to Device', style: TextStyle(color: Colors.white)),
                          onTap: _downloadMedia,
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // 6. VIDEO CONTROLS
            if (_isVideo && _isVideoInitialized)
              AnimatedPositioned(
                duration: Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                bottom: _showOverlays ? (_isPostContent ? 80 : 20) : -150, 
                left: 16,
                right: 16,
                child: AnimatedOpacity(
                  opacity: _showOverlays ? 1.0 : 0.0,
                  duration: Duration(milliseconds: 200),
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // TIME & SLIDER
                        Row(
                          children: [
                            Text(_formatDuration(_currentPosition), style: TextStyle(color: Colors.white, fontSize: 12)),
                            Expanded(
                              child: SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
                                  overlayShape: RoundSliderOverlayShape(overlayRadius: 14),
                                  trackHeight: 2,
                                  thumbColor: TwitterTheme.blue,
                                  activeTrackColor: TwitterTheme.blue,
                                  inactiveTrackColor: Colors.white24, // FIXED: Use inactiveColor in Slider directly if needed, but Theme handles it generally
                                ),
                                child: Slider(
                                  value: _currentPosition.inMilliseconds.toDouble().clamp(0.0, _totalDuration.inMilliseconds.toDouble()),
                                  min: 0.0,
                                  max: _totalDuration.inMilliseconds.toDouble(),
                                  activeColor: TwitterTheme.blue,
                                  inactiveColor: Colors.white24, // FIXED PARAMETER NAME
                                  onChangeStart: _onSeekStart,
                                  onChanged: _onSeekChanged,
                                  onChangeEnd: _onSeekEnd,
                                ),
                              ),
                            ),
                            Text(_formatDuration(_totalDuration), style: TextStyle(color: Colors.white, fontSize: 12)),
                          ],
                        ),
                        // CONTROLS
                        Row(
                          children: [
                            IconButton(
                              icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white),
                              onPressed: _togglePlayPause,
                              padding: EdgeInsets.zero,
                              constraints: BoxConstraints(),
                            ),
                            SizedBox(width: 8),
                            Icon(_currentVolume == 0 ? Icons.volume_off : Icons.volume_up, color: Colors.white, size: 20),
                            Expanded(
                              child: SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
                                  trackHeight: 2,
                                  overlayShape: RoundSliderOverlayShape(overlayRadius: 12),
                                ),
                                child: Slider(
                                  value: _currentVolume,
                                  min: 0.0,
                                  max: 1.0,
                                  activeColor: Colors.white,
                                  inactiveColor: Colors.white24, // FIXED PARAMETER NAME
                                  onChanged: (val) {
                                    setState(() => _currentVolume = val);
                                    _videoController?.setVolume(val);
                                    _resetHideTimer();
                                  },
                                ),
                              ),
                            ),
                            PopupMenuButton<double>(
                              initialValue: _videoController?.value.playbackSpeed ?? 1.0,
                              onSelected: _changeSpeed,
                              itemBuilder: (context) => [
                                PopupMenuItem(value: 0.5, child: Text("0.5x")),
                                PopupMenuItem(value: 1.0, child: Text("1.0x")),
                                PopupMenuItem(value: 1.5, child: Text("1.5x")),
                                PopupMenuItem(value: 2.0, child: Text("2.0x")),
                              ],
                              child: Container(
                                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(border: Border.all(color: Colors.white54), borderRadius: BorderRadius.circular(4)),
                                child: Text("${_videoController?.value.playbackSpeed}x", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                              ),
                            ),
                            SizedBox(width: 8),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // 7. BOTTOM ACTION BAR
            if (_showOverlays && _isPostContent)
              Positioned(
                bottom: 0, left: 0, right: 0,
                child: Container(
                  padding: EdgeInsets.only(bottom: 20, top: 20, left: 16, right: 16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Colors.black.withOpacity(0.9), Colors.transparent],
                    ),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildActionIcon(Icons.chat_bubble_outline, widget.postData?['commentCount']?.toString() ?? "0", () => Navigator.pop(context)),
                        _buildActionIcon(Icons.repeat, _repostCount.toString(), _toggleRepost, color: _isReposted ? Colors.green : null),
                        _buildActionIcon(_isLiked ? Icons.favorite : Icons.favorite_border, _likeCount.toString(), _toggleLike, color: _isLiked ? Colors.pink : null),
                        _buildActionIcon(Icons.share, "", _shareImage),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionIcon(IconData icon, String text, VoidCallback onTap, {Color? color}) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, color: color ?? Colors.white, size: 24),
          if (text.isNotEmpty && text != "0") ...[
            SizedBox(width: 6),
            Text(text, style: TextStyle(color: color ?? Colors.white, fontWeight: FontWeight.bold)),
          ]
        ],
      ),
    );
  }
}

// ... (Download Manager logic remains unchanged)
class _DownloadManager {
  static void startDownloadSequence({
    required OverlayState overlayState,
    required String url,
    required bool isImage,
  }) {
    final GlobalKey<_DownloadStatusOverlayState> overlayKey = GlobalKey();
    late OverlayEntry overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) => _DownloadStatusOverlay(
        key: overlayKey,
        onDismissRequest: () {
          overlayKey.currentState?.dismissToIcon();
        },
      ),
    );

    overlayState.insert(overlayEntry);

    _processDownload(
      url: url,
      isImage: isImage,
      onSuccess: () {
        overlayKey.currentState?.handleSuccess();
        Future.delayed(Duration(seconds: 7), () {
           if (overlayEntry.mounted) overlayEntry.remove();
        });
      },
      onFailure: (error) {
        overlayKey.currentState?.handleFailure();
        Future.delayed(Duration(seconds: 4), () {
          if (overlayEntry.mounted) overlayEntry.remove();
        });
      },
    );
  }

  static Future<void> _processDownload({
    required String url,
    required bool isImage,
    required VoidCallback onSuccess,
    required Function(dynamic) onFailure,
  }) async {
    try {
      final File cacheFile = await DefaultCacheManager().getSingleFile(url);
      final String dateStr = DateFormat('ddMMyy').format(DateTime.now());
      final String ext = p.extension(url).isEmpty ? (isImage ? '.jpg' : '.mp4') : p.extension(url);
      final String fileName = "SapaPNJ_$dateStr$ext";

      String basePath;
      if (isImage) {
        basePath = '/storage/emulated/0/Pictures/SapaPNJ';
      } else {
        basePath = '/storage/emulated/0/Download/SapaPNJ';
      }

      final Directory dir = Directory(basePath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final String savePath = '$basePath/$fileName';
      await cacheFile.copy(savePath);

      onSuccess();
    } catch (e) {
      print("Download Error: $e");
      onFailure(e);
    }
  }
}

class _DownloadStatusOverlay extends StatefulWidget {
  final VoidCallback onDismissRequest;
  const _DownloadStatusOverlay({super.key, required this.onDismissRequest});

  @override
  State<_DownloadStatusOverlay> createState() => _DownloadStatusOverlayState();
}

class _DownloadStatusOverlayState extends State<_DownloadStatusOverlay> {
  bool _isCardVisible = true;
  bool _isMiniVisible = false;
  bool _isSuccess = false;
  bool _isError = false;
  String _message = "Downloading media...";
  Timer? _autoDismissTimer;

  double get _targetTop => MediaQuery.of(context).padding.top + 10;
  double get _targetRight => 12.0;
  double get _miniRight => 60.0; 

  @override
  void dispose() {
    _autoDismissTimer?.cancel();
    super.dispose();
  }

  void dismissToIcon() {
    setState(() => _isCardVisible = false);
    Future.delayed(Duration(milliseconds: 400), () {
      if (mounted) setState(() => _isMiniVisible = true);
    });
  }

  void _expandToCard() {
    setState(() => _isMiniVisible = false);
    Future.delayed(Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() => _isCardVisible = true);
        _autoDismissTimer?.cancel();
        _autoDismissTimer = Timer(Duration(seconds: 2), dismissToIcon);
      }
    });
  }

  void handleSuccess() {
    setState(() { _isSuccess = true; _message = "Download Complete"; });
    if (_isMiniVisible) {
      Future.delayed(Duration(seconds: 5), () {
        if (mounted) setState(() => _isMiniVisible = false);
      });
    } else if (_isCardVisible) {
      Future.delayed(Duration(seconds: 5), () {
        if (mounted) setState(() => _isCardVisible = false);
      });
    }
  }

  void handleFailure() {
    setState(() { _isError = true; _message = "Download Failed"; });
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
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(12),
                color: Theme.of(context).brightness == Brightness.dark ? TwitterTheme.darkGrey : Colors.white,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          if (_isSuccess)
                            Icon(Icons.check_circle, color: TwitterTheme.blue)
                          else if (_isError)
                            Icon(Icons.error, color: Colors.red)
                          else
                            SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _message,
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          if (!_isSuccess && !_isError)
                            GestureDetector(
                              onTap: widget.onDismissRequest,
                              child: Padding(padding: const EdgeInsets.all(4.0), child: Icon(Icons.keyboard_arrow_up, color: Colors.grey)),
                            ),
                        ],
                      ),
                      if (!_isSuccess && !_isError)
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
            ),
          ),
        ),
      ],
    );
  }
}