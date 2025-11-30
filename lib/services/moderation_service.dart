import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart'; // REQUIRED

class ModerationService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // --- REPORTING ---

  Future<void> reportContent({
    required String targetId,
    required String targetType, // 'post', 'comment', 'user'
    required String reason,
    String? description,
  }) async {
    final user = _auth.currentUser;
    
    final String subject = "SAPA PNJ Report: $targetType ($reason)";
    final String body = "Reporter ID: ${user?.uid ?? 'Anonymous'}\n"
        "Target ID: $targetId\n"
        "Target Type: $targetType\n"
        "Reason: $reason\n"
        "Description: ${description ?? 'No details provided'}\n\n"
        "Time: ${DateTime.now()}\n\n"
        "Please review this content.";

    // Construct the mailto URI
    final Uri emailLaunchUri = Uri(
      scheme: 'mailto',
      path: 'arnoldholyridho@gmail.com,aryastiawn@gmail.com',
      query: _encodeQueryParameters(<String, String>{
        'subject': subject,
        'body': body,
      }),
    );

    try {
      // Try to launch the email app
      await launchUrl(emailLaunchUri, mode: LaunchMode.externalApplication);
    } catch (e) {
      print("Could not launch email client: $e");
    }
  }

  // Helper to encode query parameters properly
  String? _encodeQueryParameters(Map<String, String> params) {
    return params.entries
        .map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');
  }

  // --- BLOCKING ---

  Future<void> blockUser(String targetUserId) async {
    final user = _auth.currentUser;
    if (user == null || user.uid == targetUserId) return;

    final batch = _firestore.batch();

    // 1. Add to my 'blockedUsers' list
    final myDocRef = _firestore.collection('users').doc(user.uid);
    batch.update(myDocRef, {
      'blockedUsers': FieldValue.arrayUnion([targetUserId])
    });

    // 2. Unfollow them if I am following
    batch.update(myDocRef, {
      'following': FieldValue.arrayRemove([targetUserId])
    });

    // 3. Remove them from my followers if they follow me
    final targetDocRef = _firestore.collection('users').doc(targetUserId);
    batch.update(targetDocRef, {
      'followers': FieldValue.arrayRemove([user.uid])
    });

    await batch.commit();
  }

  Future<void> unblockUser(String targetUserId) async {
    final user = _auth.currentUser;
    if (user == null) return;

    await _firestore.collection('users').doc(user.uid).update({
      'blockedUsers': FieldValue.arrayRemove([targetUserId])
    });
  }

  Stream<List<String>> streamBlockedUsers() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value([]);

    return _firestore.collection('users').doc(user.uid).snapshots().map((doc) {
      if (!doc.exists) return [];
      final data = doc.data() as Map<String, dynamic>;
      final blocked = data['blockedUsers'] as List<dynamic>?;
      return blocked?.map((e) => e.toString()).toList() ?? [];
    });
  }
}

// Global Instance
final moderationService = ModerationService();