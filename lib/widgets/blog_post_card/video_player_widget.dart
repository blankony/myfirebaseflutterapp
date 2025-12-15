import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../main.dart'; // Untuk akses TwitterTheme

class VideoPlayerWidget extends StatelessWidget {
  final VideoPlayerController controller;
  final bool isThumbnail;

  const VideoPlayerWidget({
    super.key,
    required this.controller,
    this.isThumbnail = false,
  });

  @override
  Widget build(BuildContext context) {
    if (!controller.value.isInitialized) {
      return Container(
        color: Colors.black,
        height: isThumbnail ? null : 300,
        width: double.infinity,
        child: Center(child: CircularProgressIndicator(color: TwitterTheme.blue)),
      );
    }

    Widget videoDisplay;

    if (isThumbnail) {
      videoDisplay = SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: controller.value.size.width,
            height: controller.value.size.height,
            child: VideoPlayer(controller),
          ),
        ),
      );
    } else {
      videoDisplay = AspectRatio(
        aspectRatio: controller.value.aspectRatio,
        child: VideoPlayer(controller),
      );
    }

    return Container(
      color: Colors.black,
      constraints: isThumbnail ? null : const BoxConstraints(maxHeight: 400),
      width: double.infinity,
      child: Stack(
        alignment: Alignment.center,
        children: [
          videoDisplay,
          Container(color: Colors.black.withOpacity(0.2)),
          Center(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.25),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 32),
            ),
          ),
        ],
      ),
    );
  }
}