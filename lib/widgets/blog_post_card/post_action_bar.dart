import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../main.dart'; // TwitterTheme

class PostActionBar extends StatelessWidget {
  final String postId;
  final int commentCount;
  final int repostCount;
  final int likeCount;
  final bool isReposted;
  final bool isLiked;
  final bool isSharing;
  final bool isDetailView;
  final VoidCallback onCommentTap;
  final VoidCallback onRepostTap;
  final VoidCallback onLikeTap;
  final VoidCallback onShareTap;
  final Function(bool isBookmarked) onBookmarkTap;
  
  // Animation Controllers passed from parent to keep state centralized
  final Animation<double> likeAnimation;
  final Animation<double> repostAnimation;
  final Animation<double> shareAnimation;

  const PostActionBar({
    super.key,
    required this.postId,
    required this.commentCount,
    required this.repostCount,
    required this.likeCount,
    required this.isReposted,
    required this.isLiked,
    required this.isSharing,
    required this.isDetailView,
    required this.onCommentTap,
    required this.onRepostTap,
    required this.onLikeTap,
    required this.onShareTap,
    required this.onBookmarkTap,
    required this.likeAnimation,
    required this.repostAnimation,
    required this.shareAnimation,
  });

  @override
  Widget build(BuildContext context) {
    if (isDetailView) {
      return Padding(
        padding: const EdgeInsets.only(top: 16.0, bottom: 4.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildActionButton(context, Icons.repeat, repostCount.toString(), isReposted ? Colors.green : null, onRepostTap, repostAnimation),
            _buildActionButton(context, isLiked ? Icons.favorite : Icons.favorite_border, likeCount.toString(), isLiked ? Colors.pink : null, onLikeTap, likeAnimation),
            _buildBookmarkButton(context),
            _buildActionButton(context, Icons.share_outlined, 'Share', isSharing ? TwitterTheme.blue : null, onShareTap, shareAnimation),
          ],
        ),
      );
    } else {
      return Padding(
        padding: const EdgeInsets.only(top: 12.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildActionButton(context, Icons.chat_bubble_outline, commentCount.toString(), null, onCommentTap),
            _buildActionButton(context, Icons.repeat, repostCount.toString(), isReposted ? Colors.green : null, onRepostTap, repostAnimation),
            _buildActionButton(context, isLiked ? Icons.favorite : Icons.favorite_border, likeCount.toString(), isLiked ? Colors.pink : null, onLikeTap, likeAnimation),
            _buildBookmarkButton(context),
            _buildActionButton(context, Icons.share_outlined, null, isSharing ? TwitterTheme.blue : null, onShareTap, shareAnimation),
          ],
        ),
      );
    }
  }

  Widget _buildBookmarkButton(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return _buildActionButton(context, Icons.bookmark_border, null, null, () => onBookmarkTap(false));
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(user.uid).collection('bookmarks').doc(postId).snapshots(),
      builder: (context, snapshot) {
        final bool isBookmarked = snapshot.hasData && snapshot.data!.exists;
        return _buildActionButton(
          context,
          isBookmarked ? Icons.bookmark : Icons.bookmark_border,
          null,
          isBookmarked ? TwitterTheme.blue : null,
          () => onBookmarkTap(isBookmarked),
        );
      },
    );
  }

  Widget _buildActionButton(
    BuildContext context, 
    IconData icon, 
    String? text, 
    Color? color, 
    VoidCallback onTap, 
    [Animation<double>? animation]
  ) {
    final theme = Theme.of(context);
    final iconColor = color ?? theme.textTheme.bodySmall?.color ?? Colors.grey;
    Widget iconWidget = Icon(icon, size: 20, color: iconColor);
    
    if (animation != null) {
      iconWidget = ScaleTransition(scale: animation, child: iconWidget);
    }

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
        child: Row(
          children: [
            iconWidget,
            if (text != null && text != "0" && text.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 6.0),
                child: Text(text, style: TextStyle(color: iconColor, fontSize: 13)),
              ),
          ],
        ),
      ),
    );
  }
}