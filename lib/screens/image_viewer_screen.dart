// ignore_for_file: prefer_const_constructors
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart'; 
import 'package:cached_network_image/cached_network_image.dart'; 
import 'package:flutter_cache_manager/flutter_cache_manager.dart'; 
import 'package:share_plus/share_plus.dart'; 
import 'package:cloud_firestore/cloud_firestore.dart'; 
import 'package:firebase_auth/firebase_auth.dart'; 
import '../main.dart'; 

class ImageViewerScreen extends StatefulWidget {
  final String imageUrl;
  final String? mediaType;
  final Map<String, dynamic>? postData; 
  final String? postId; 
  final String heroTag; 
  
  const ImageViewerScreen({
    super.key, 
    required this.imageUrl, 
    required this.heroTag, 
    this.mediaType,
    this.postData,
    this.postId,
  });

  @override
  State<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<ImageViewerScreen> with SingleTickerProviderStateMixin {
  bool _showOverlays = true;
  late AnimationController _menuController;
  late Animation<Offset> _menuAnimation;
  bool _isMenuOpen = false;
  
  bool _isLiked = false;
  int _likeCount = 0;
  bool _isReposted = false;
  int _repostCount = 0;

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
  }

  @override
  void dispose() {
    _menuController.dispose();
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
    if (_isMenuOpen) {
      _closeMenu();
    } else {
      setState(() {
        _showOverlays = !_showOverlays;
      });
    }
  }

  void _openMenu() {
    setState(() {
      _isMenuOpen = true;
    });
    _menuController.forward();
  }

  void _closeMenu() {
    _menuController.reverse().then((_) {
      setState(() {
        _isMenuOpen = false;
      });
    });
  }

  Future<void> _toggleLike() async {
    if (widget.postId == null) return;
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
    if (widget.postId == null) return;
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
      await Share.shareXFiles([XFile(file.path)], text: 'Check out this image!');
    } catch (e) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to load image.'))); }
  }

  Future<void> _saveImage() async {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Image saved to Gallery (Mock).')));
    _closeMenu();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true, 
      body: GestureDetector(
        onTap: _toggleOverlays,
        child: Stack(
          children: [
            // 1. THE IMAGE (PERBAIKAN DI SINI)
            // Widget Hero manual DIHAPUS, karena PhotoViewHeroAttributes sudah membuat Hero secara internal.
            Center(
              child: widget.mediaType == 'video'
                  ? Text('Video Placeholder', style: TextStyle(color: Colors.white))
                  : PhotoView(
                      imageProvider: CachedNetworkImageProvider(widget.imageUrl), 
                      backgroundDecoration: BoxDecoration(color: Colors.black),
                      initialScale: PhotoViewComputedScale.contained,
                      minScale: PhotoViewComputedScale.contained,
                      maxScale: PhotoViewComputedScale.covered * 2.5,
                      // INI SUDAH CUKUP UNTUK ANIMASI HERO:
                      heroAttributes: PhotoViewHeroAttributes(tag: widget.heroTag),
                    ),
            ),

            // 2. Top Bar Overlay
            AnimatedOpacity(
              opacity: _showOverlays ? 1.0 : 0.0,
              duration: Duration(milliseconds: 200),
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

            // 3. Menu
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
                      boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 10)],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          leading: Icon(Icons.save_alt, color: Colors.white),
                          title: Text('Save to Device', style: TextStyle(color: Colors.white)),
                          onTap: _saveImage,
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // 4. Bottom Action Bar
            if (_showOverlays)
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