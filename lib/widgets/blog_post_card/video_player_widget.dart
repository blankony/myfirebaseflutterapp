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
    // Basic validation: Jika tidak ada controller DAN tidak ada thumbnail, tampilkan loader
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
      // StackFit.expand PENTING agar semua child dipaksa memenuhi container
      child: Stack(
        fit: StackFit.expand, 
        children: [
          
          // LAYER 1 (PALING BAWAH): Thumbnail Statis
          // Selalu dirender jika path tersedia. Ini mencegah black screen saat buffering video.
          if (thumbnailPath != null)
            Image.file(
              File(thumbnailPath!),
              fit: BoxFit.cover, // CROP CENTER (Mengisi penuh area 4:3)
              errorBuilder: (context, error, stack) => Container(color: Colors.black),
            ),

          // LAYER 2: Video Player
          // Hanya ditampilkan jika controller sudah siap.
          if (controller != null && controller!.value.isInitialized)
            Visibility(
              visible: isPlaying, // Hanya terlihat jika sedang PLAY
              maintainState: true, // Biarkan state video tetap ada di memori
              child: FittedBox(
                fit: BoxFit.cover, // CROP CENTER (Agar video match dengan thumbnail & tidak gepeng)
                child: SizedBox(
                  width: controller!.value.size.width,
                  height: controller!.value.size.height,
                  child: VideoPlayer(controller!),
                ),
              ),
            ),

          // LAYER 3 (PALING ATAS): Overlay & Play Button
          // Ditampilkan jika video TIDAK sedang playing (Pause atau Initial state)
          if (!isPlaying) ...[
            // Overlay hitam transparan agar icon play kontras
            Container(color: Colors.black.withOpacity(0.2)),
            
            // Tombol Play
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