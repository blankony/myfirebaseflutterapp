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

// Tambahkan Mixin agar state tidak hilang saat discroll (PENTING untuk performa feed)
class _PostMediaPreviewState extends State<PostMediaPreview> with AutomaticKeepAliveClientMixin {
  int _currentIndex = 0;
  
  // State lokal untuk path thumbnail. 
  // Kita tidak menggunakan FutureBuilder di build method agar UI tidak flickering/reload.
  String? _cachedThumbnailPath;
  bool _isPlaying = false;

  @override
  bool get wantKeepAlive => true; // Menjaga widget tetap hidup di memori

  @override
  void initState() {
    super.initState();
    
    // LOGIKA UTAMA: Trigger ekstraksi thumbnail otomatis saat pertama kali render
    if (widget.mediaType == 'video' && widget.mediaUrls.isNotEmpty) {
      _initializeThumbnailLogic(widget.mediaUrls.first);
      
      // Listener untuk sinkronisasi tombol play/pause UI
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
      setState(() {
        _isPlaying = isPlaying;
      });
    }
  }

  /// Fungsi ini menjalankan 3 langkah wajib:
  /// 1. Cek Cache Lokal.
  /// 2. Jika kosong, Ekstrak Frame (Silent Load).
  /// 3. Simpan dan Update UI.
  Future<void> _initializeThumbnailLogic(String videoUrl) async {
    try {
      final directory = await getApplicationSupportDirectory();
      // Naming convention unik berdasarkan Post ID dan URL Hash
      final String fileName = "thumb_${widget.postId}_${videoUrl.hashCode}.jpg";
      final String fullPath = p.join(directory.path, fileName);
      final File cachedFile = File(fullPath);

      // STEP 1: Cek apakah thumbnail sudah ada (Fast Path)
      if (await cachedFile.exists()) {
        if (mounted) {
          setState(() {
            _cachedThumbnailPath = fullPath;
          });
        }
        return;
      }

      // STEP 2: Jika belum ada, lakukan ekstraksi frame (Silent Background Process)
      // Ini memenuhi syarat "memuat video max 1 detik secara internal"
      final File? thumbnail = await VideoCompress.getFileThumbnail(
        videoUrl,
        quality: 60, // Kualitas medium-high
        position: 1000, // Ambil tepat di detik ke-1 (atau 0 jika durasi pendek)
      );

      if (thumbnail != null) {
        // STEP 3: Pindahkan file temp ke cache permanen
        await thumbnail.copy(fullPath);
        
        if (mounted) {
          setState(() {
            _cachedThumbnailPath = fullPath;
          });
        }
      }
    } catch (e) {
      debugPrint("Thumbnail generation failed: $e");
      // Fallback silent, UI akan tetap menampilkan container hitam/loading
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
    widget.videoController?.pause();
    final String heroTag = '${widget.heroContextId}_${widget.postId}_$url';
    
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (_, __, ___) => ImageViewerScreen(
          imageUrl: url,
          mediaType: widget.mediaType,
          postData: widget.postData,
          postId: widget.postId,
          heroTag: heroTag,
          videoController: widget.videoController,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Wajib untuk KeepAlive
    final theme = Theme.of(context);

    // --- RENDER LOGIC: VIDEO ---
    if (widget.mediaType == 'video' && widget.mediaUrls.isNotEmpty) {
      final String videoUrl = widget.mediaUrls.first;
      final String heroTag = '${widget.heroContextId}_${widget.postId}_$videoUrl';

      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: GestureDetector(
          onTap: () => _navigateToViewer(context, videoUrl),
          child: Hero(
            tag: heroTag,
            child: AspectRatio(
              aspectRatio: 4 / 3, // Rasio Container Kaku
              child: VideoPlayerWidget(
                // Controller hanya di-pass, tapi Widget di dalam yang menentukan kapan merendernya
                controller: widget.videoController,
                thumbnailPath: _cachedThumbnailPath,
                isPlaying: _isPlaying,
              ),
            ),
          ),
        ),
      );
    }

    // --- RENDER LOGIC: IMAGE (Existing) ---
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
                        return GestureDetector(
                          onTap: () => _navigateToViewer(context, url),
                          child: CachedNetworkImage(
                            imageUrl: url,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Container(color: theme.dividerColor.withOpacity(0.1)),
                            errorWidget: (context, url, error) => const Icon(Icons.error),
                          ),
                        );
                      },
                    ),
                  )
                : AspectRatio(
                    aspectRatio: 4 / 3,
                    child: GestureDetector(
                      onTap: () => _navigateToViewer(context, widget.mediaUrls.first),
                      child: CachedNetworkImage(
                        imageUrl: widget.mediaUrls.first,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(color: theme.dividerColor.withOpacity(0.1)),
                        errorWidget: (context, url, error) => const Icon(Icons.error),
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

    // --- RENDER LOGIC: EXTERNAL LINK ---
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