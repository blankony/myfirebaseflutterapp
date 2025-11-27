// ignore_for_file: prefer_const_constructors, use_build_context_synchronously
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart'; // IMPORT WAJIB
import 'package:path/path.dart' as p;             // IMPORT WAJIB
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
  bool _isSaving = false; 

  bool get _isPostContent => widget.postId != null;

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
      await Share.shareXFiles([XFile(file.path)], text: 'Check out this image from Sapa PNJ!');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to load image.')));
    }
  }

  // --- FUNGSI SAVE BARU MENGGUNAKAN GAL ---
  Future<void> _saveImage() async {
    _closeMenu();
    setState(() { _isSaving = true; });

    try {
      print("--- MULAI PROSES SAVE KE PICTURES ---");

      // 1. Download Gambar ke Cache
      final File cacheFile = await DefaultCacheManager().getSingleFile(widget.imageUrl);
      
      // 2. Tentukan Ekstensi File (Penting agar terbaca di Galeri)
      String extension = p.extension(widget.imageUrl);
      if (extension.isEmpty || extension.length > 5) { 
        extension = '.jpg'; 
      }
      
      // 3. Buat Nama File Baru yang Bersih di Folder Sementara
      final Directory tempDir = await getTemporaryDirectory();
      final String newFileName = "SapaPNJ_${DateTime.now().millisecondsSinceEpoch}$extension";
      final File newFile = await cacheFile.copy('${tempDir.path}/$newFileName');
      
      print("   - File siap disimpan: ${newFile.path}");

      // 4. Simpan menggunakan Gal
      await Gal.putImage(newFile.path, album: null); 
      
      print("   - BERHASIL DISIMPAN KE PICTURES");

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(children: const [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 8),
              Expanded(child: Text('Saved to "Pictures" folder!', style: TextStyle(color: Colors.white))),
            ]),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } on GalException catch (e) {
      print("❌ GAL ERROR: Type: ${e.type}, Message: $e");
      if (mounted) {
        String msg = "Gagal menyimpan.";
        if (e.type == GalExceptionType.accessDenied) msg = "Izin penyimpanan ditolak.";
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      print("❌ GENERAL ERROR: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() { _isSaving = false; });
    }
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
            // 1. THE IMAGE
            Center(
              child: widget.mediaType == 'video'
                  ? Text('Video Placeholder', style: TextStyle(color: Colors.white))
                  : PhotoView(
                      imageProvider: CachedNetworkImageProvider(widget.imageUrl),
                      backgroundDecoration: BoxDecoration(color: Colors.black),
                      initialScale: PhotoViewComputedScale.contained,
                      minScale: PhotoViewComputedScale.contained,
                      maxScale: PhotoViewComputedScale.covered * 2.5,
                      heroAttributes: PhotoViewHeroAttributes(tag: widget.heroTag),
                    ),
            ),

            // Loading Indicator saat menyimpan
            if (_isSaving)
              Center(
                child: Container(
                  padding: EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(10)
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      CircularProgressIndicator(color: Colors.white),
                      SizedBox(height: 10),
                      Text("Saving...", style: TextStyle(color: Colors.white))
                    ],
                  ),
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

            // 3. Menu (Save Image)
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
                          onTap: _saveImage,
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // 4. Bottom Action Bar (Hanya jika ini adalah postingan)
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