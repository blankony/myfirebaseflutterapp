import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_compress/video_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../../screens/image_viewer_screen.dart';
import 'video_player_widget.dart';

class PostMediaPreview extends StatefulWidget {
  final List<String> mediaUrls;
  final String? mediaType;
  final String text;
  final Map<String, dynamic> postData;
  final String postId;
  final String heroContextId;
  final VideoPlayerController? videoController;

  const PostMediaPreview({
    super.key,
    required this.mediaUrls,
    this.mediaType,
    required this.text,
    required this.postData,
    required this.postId,
    required this.heroContextId,
    this.videoController,
  });

  @override
  State<PostMediaPreview> createState() => _PostMediaPreviewState();
}

class _PostMediaPreviewState extends State<PostMediaPreview> with AutomaticKeepAliveClientMixin {
  int _currentIndex = 0;
  String? _cachedThumbnailPath;
  bool _isPlaying = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    if (widget.mediaType == 'video' && widget.mediaUrls.isNotEmpty) {
      _initializeThumbnailLogic(widget.mediaUrls.first);
      widget.videoController?.addListener(_videoListener);
    }
  }

  @override
  void dispose() {
    widget.videoController?.removeListener(_videoListener);
    super.dispose();
  }

  void _videoListener() {
    if (!mounted || widget.videoController == null) return;
    final isPlaying = widget.videoController!.value.isPlaying;
    if (isPlaying != _isPlaying) {
      setState(() => _isPlaying = isPlaying);
    }
  }

  Future<void> _initializeThumbnailLogic(String videoUrl) async {
    try {
      final directory = await getApplicationSupportDirectory();
      final String fileName = "thumb_${widget.postId}_${videoUrl.hashCode}.jpg";
      final String fullPath = p.join(directory.path, fileName);
      final File cachedFile = File(fullPath);

      if (await cachedFile.exists()) {
        if (mounted) setState(() => _cachedThumbnailPath = fullPath);
        return;
      }

      final File? thumbnail = await VideoCompress.getFileThumbnail(
        videoUrl,
        quality: 60,
        position: 1000,
      );

      if (thumbnail != null) {
        await thumbnail.copy(fullPath);
        if (mounted) setState(() => _cachedThumbnailPath = fullPath);
      }
    } catch (e) {
      debugPrint("Thumbnail generation failed: $e");
    }
  }

  String? _getVideoId(String url) {
    if (url.contains('youtube.com') || url.contains('youtu.be')) {
      final regExp = RegExp(r"youtu(?:.*\/v\/|.*v\=|\.be\/)([A-Za-z0-9_\-]+)");
      return regExp.firstMatch(url)?.group(1);
    }
    return null;
  }

  String? _extractLinkInText() {
    final linkRegExp = RegExp(r'(https?:\/\/[^\s]+)');
    final match = linkRegExp.firstMatch(widget.text);
    return match?.group(0);
  }

  void _navigateToViewer(BuildContext context, String url) {
    // Pause video di feed agar tidak bersuara ganda
    widget.videoController?.pause();
    
    final String heroTag = '${widget.heroContextId}_${widget.postId}_$url';
    
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false, // Penting agar background feed tetap terlihat samar di awal
        barrierColor: Colors.black, // Warna latar belakang saat transisi selesai
        transitionDuration: const Duration(milliseconds: 350), // Durasi sedikit diperlambat untuk kehalusan
        reverseTransitionDuration: const Duration(milliseconds: 300),
        // FadeTransition di sini hanya mempengaruhi opacity background (scrim),
        // TIDAK mempengaruhi konten Hero yang terbang di atasnya.
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        pageBuilder: (_, __, ___) => ImageViewerScreen(
          imageUrl: url,
          mediaType: widget.mediaType,
          postData: widget.postData,
          postId: widget.postId,
          heroTag: heroTag,
          videoController: widget.videoController,
          thumbnailPath: _cachedThumbnailPath, 
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);

    // --- BAGIAN VIDEO ---
    if (widget.mediaType == 'video' && widget.mediaUrls.isNotEmpty) {
      final String videoUrl = widget.mediaUrls.first;
      final String heroTag = '${widget.heroContextId}_${widget.postId}_$videoUrl';

      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: GestureDetector(
          onTap: () => _navigateToViewer(context, videoUrl),
          // Hero membungkus konten visual utama
          child: Hero(
            tag: heroTag,
            // flightShuttleBuilder opsional: menjaga tampilan tetap solid selama terbang
            flightShuttleBuilder: (flightContext, animation, direction, fromContext, toContext) {
              return Material(
                color: Colors.transparent,
                child: AspectRatio(
                  aspectRatio: 4 / 3, // Pertahankan rasio saat terbang
                  child: VideoPlayerWidget(
                    controller: widget.videoController,
                    thumbnailPath: _cachedThumbnailPath,
                    isPlaying: _isPlaying,
                  ),
                ),
              );
            },
            child: Material(
              color: Colors.transparent,
              child: AspectRatio(
                aspectRatio: 4 / 3,
                child: VideoPlayerWidget(
                  controller: widget.videoController,
                  thumbnailPath: _cachedThumbnailPath,
                  isPlaying: _isPlaying,
                ),
              ),
            ),
          ),
        ),
      );
    }

    // --- BAGIAN GAMBAR ---
    if (widget.mediaUrls.isNotEmpty) {
      final bool isMulti = widget.mediaUrls.length > 1;
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            isMulti
                ? AspectRatio(
                    aspectRatio: 1.0,
                    child: PageView.builder(
                      itemCount: widget.mediaUrls.length,
                      onPageChanged: (index) => setState(() => _currentIndex = index),
                      itemBuilder: (context, index) {
                        final url = widget.mediaUrls[index];
                        final tag = '${widget.heroContextId}_${widget.postId}_$url';
                        return GestureDetector(
                          onTap: () => _navigateToViewer(context, url),
                          child: Hero(
                            tag: tag,
                            child: CachedNetworkImage(
                              imageUrl: url,
                              fit: BoxFit.cover,
                              placeholder: (context, url) => Container(color: theme.dividerColor.withOpacity(0.1)),
                              errorWidget: (context, url, error) => const Icon(Icons.error),
                            ),
                          ),
                        );
                      },
                    ),
                  )
                : AspectRatio(
                    aspectRatio: 4 / 3,
                    child: GestureDetector(
                      onTap: () => _navigateToViewer(context, widget.mediaUrls.first),
                      child: Hero(
                        tag: '${widget.heroContextId}_${widget.postId}_${widget.mediaUrls.first}',
                        child: CachedNetworkImage(
                          imageUrl: widget.mediaUrls.first,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Container(color: theme.dividerColor.withOpacity(0.1)),
                          errorWidget: (context, url, error) => const Icon(Icons.error),
                        ),
                      ),
                    ),
                  ),
            if (isMulti)
              Positioned(
                top: 12,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    "${_currentIndex + 1}/${widget.mediaUrls.length}",
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    // --- BAGIAN LINK EXTERNAL (Tetap sama) ---
    final externalLink = _extractLinkInText();
    final youtubeId = externalLink != null ? _getVideoId(externalLink) : null;

    if (youtubeId != null) {
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: GestureDetector(
          onTap: () async {
            final url = Uri.parse(externalLink!);
            if (await canLaunchUrl(url)) {
              await launchUrl(url, mode: LaunchMode.externalApplication);
            }
          },
          child: Container(
            margin: const EdgeInsets.only(top: 12),
            decoration: BoxDecoration(
              color: Colors.red.shade900,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.ondemand_video, color: Colors.white, size: 50),
                  SizedBox(height: 8),
                  Text('Watch on YouTube', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}