import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../main.dart'; 

class VideoPlayerWidget extends StatelessWidget {
  final VideoPlayerController? controller;
  final String? thumbnailPath;
  final bool isPlaying;

  const VideoPlayerWidget({
    super.key,
    this.controller,
    this.thumbnailPath,
    this.isPlaying = false,
  });

  @override
  Widget build(BuildContext context) {
    if (controller == null && thumbnailPath == null) {
      return Container(
        color: Colors.black,
        child: Center(
          child: CircularProgressIndicator(color: TwitterTheme.blue),
        ),
      );
    }

    return Container(
      color: Colors.black,
      width: double.infinity,
      height: double.infinity,
      child: Stack(
        fit: StackFit.expand, 
        children: [
          // Layer 1: Thumbnail (Selalu ada di bawah)
          if (thumbnailPath != null)
            Image.file(
              File(thumbnailPath!),
              fit: BoxFit.cover, 
              errorBuilder: (context, error, stack) => Container(color: Colors.black),
            ),

          // Layer 2: Video Player (Hanya jika playing)
          if (controller != null && controller!.value.isInitialized)
            Visibility(
              visible: isPlaying,
              maintainState: true,
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: controller!.value.size.width,
                  height: controller!.value.size.height,
                  child: VideoPlayer(controller!),
                ),
              ),
            ),

          // Layer 3: Overlay & Play Button (Hanya jika NOT playing)
          // Inilah SATU-SATUNYA tempat ikon play dirender.
          if (!isPlaying) ...[
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
        ],
      ),
    );
  }
}