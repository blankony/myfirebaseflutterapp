import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import 'package:url_launcher/url_launcher.dart';
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

class _PostMediaPreviewState extends State<PostMediaPreview> {
  int _currentIndex = 0;

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
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (widget.mediaType == 'video' && widget.mediaUrls.isNotEmpty && widget.videoController != null) {
      final String videoUrl = widget.mediaUrls.first;
      final String heroTag = '${widget.heroContextId}_${widget.postId}_$videoUrl';

      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: GestureDetector(
          onTap: () => _navigateToViewer(context, videoUrl),
          child: Hero(
            tag: heroTag,
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: VideoPlayerWidget(
                controller: widget.videoController!,
                isThumbnail: true,
              ),
            ),
          ),
        ),
      );
    }

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
                      onPageChanged: (index) {
                        setState(() => _currentIndex = index);
                      },
                      itemBuilder: (context, index) {
                        final url = widget.mediaUrls[index];
                        return GestureDetector(
                          onTap: () => _navigateToViewer(context, url),
                          child: Hero(
                            tag: '${widget.heroContextId}_${widget.postId}_$url',
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