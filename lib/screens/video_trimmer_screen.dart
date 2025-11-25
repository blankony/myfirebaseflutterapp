// ignore_for_file: prefer_const_constructors
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../main.dart';

class VideoTrimmerScreen extends StatefulWidget {
  final File file;
  final int maxDurationSeconds; // Limit in seconds (e.g. 600 for 10 mins)

  const VideoTrimmerScreen({
    super.key, 
    required this.file, 
    this.maxDurationSeconds = 600 // Default 10 mins
  });

  @override
  State<VideoTrimmerScreen> createState() => _VideoTrimmerScreenState();
}

class _VideoTrimmerScreenState extends State<VideoTrimmerScreen> {
  late VideoPlayerController _videoController;
  bool _isInitialized = false;
  bool _isPlaying = false;

  // Trimming state
  double _startValue = 0.0;
  double _endValue = 1.0;
  double _totalDuration = 0.0;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    _videoController = VideoPlayerController.file(widget.file);
    await _videoController.initialize();
    
    setState(() {
      _isInitialized = true;
      _totalDuration = _videoController.value.duration.inMilliseconds.toDouble();
      _endValue = _totalDuration;
      
      // Pre-trim to max limit if video is too long
      final maxMs = widget.maxDurationSeconds * 1000.0;
      if (_totalDuration > maxMs) {
        _endValue = maxMs; 
      }
      
      // Auto play loop selection
      _videoController.setLooping(true);
      _playTrimmedSection();
    });
    
    // Listen to enforce trim boundaries during playback
    _videoController.addListener(_enforceTrimPlayback);
  }

  void _enforceTrimPlayback() {
    if (!_isInitialized) return;
    final currentPos = _videoController.value.position.inMilliseconds;
    if (currentPos >= _endValue) {
      _videoController.seekTo(Duration(milliseconds: _startValue.toInt()));
    }
  }
  
  void _playTrimmedSection() {
    _videoController.seekTo(Duration(milliseconds: _startValue.toInt()));
    _videoController.play();
    setState(() => _isPlaying = true);
  }

  @override
  void dispose() {
    _videoController.removeListener(_enforceTrimPlayback);
    _videoController.dispose();
    super.dispose();
  }

  void _saveTrimmedVideo() {
    // In a real production app with FFmpeg, we would physically trim the file here.
    // Since we are avoiding heavy dependencies, we will return the trim metadata
    // (start/end times) so the backend or a separate process can handle it,
    // OR we just upload the full file but treat it as trimmed in the UI logic.
    
    // For this project scope: Return original file but with duration metadata.
    Navigator.of(context).pop({
      'file': widget.file,
      'startTime': _startValue,
      'endTime': _endValue,
      'duration': _endValue - _startValue
    }); 
  }

  String _formatDuration(double ms) {
    final int seconds = (ms / 1000).round();
    final int minutes = seconds ~/ 60;
    final int remainingSeconds = seconds % 60;
    return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      appBar: AppBar(
        title: Text('Trim Video'),
        actions: [
          TextButton(
            onPressed: _isInitialized ? _saveTrimmedVideo : null,
            child: Text("Done", style: TextStyle(fontWeight: FontWeight.bold, color: TwitterTheme.blue)),
          ),
        ],
      ),
      body: _isInitialized ? Column(
        children: [
          // 1. Video Preview Area (Fixed 4:3 or Aspect Ratio)
          Expanded(
            child: Container(
              color: Colors.black,
              child: Center(
                child: AspectRatio(
                  aspectRatio: _videoController.value.aspectRatio,
                  child: VideoPlayer(_videoController),
                ),
              ),
            ),
          ),

          // 2. Controls & Slider
          Container(
            padding: EdgeInsets.all(16),
            color: theme.scaffoldBackgroundColor,
            child: Column(
              children: [
                // Play/Pause Control
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      iconSize: 40,
                      icon: Icon(_isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled),
                      color: TwitterTheme.blue,
                      onPressed: () {
                        setState(() {
                          if (_isPlaying) {
                            _videoController.pause();
                            _isPlaying = false;
                          } else {
                            _playTrimmedSection();
                          }
                        });
                      },
                    ),
                  ],
                ),
                
                SizedBox(height: 8),
                
                // Time Info
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_formatDuration(_startValue)),
                    Text("Duration: ${_formatDuration(_endValue - _startValue)}", style: TextStyle(fontWeight: FontWeight.bold)),
                    Text(_formatDuration(_endValue)),
                  ],
                ),

                // Range Slider (The Trimmer UI)
                RangeSlider(
                  activeColor: TwitterTheme.blue,
                  inactiveColor: Colors.grey.shade300,
                  min: 0.0,
                  max: _totalDuration,
                  values: RangeValues(_startValue, _endValue),
                  onChanged: (RangeValues values) {
                    setState(() {
                      _startValue = values.start;
                      _endValue = values.end;
                    });
                    // Seek to start when user drags start handle
                    _videoController.seekTo(Duration(milliseconds: _startValue.toInt()));
                  },
                ),
                
                SizedBox(height: 8),
                Text(
                  "Drag sliders to trim. Max length: ${widget.maxDurationSeconds ~/ 60} min.",
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ) : Center(child: CircularProgressIndicator()),
    );
  }
}