import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'cloudinary_service.dart';

class DraftPost {
  final String id;
  final String text;
  final List<String> mediaUrls;
  final List<String> publicIds;
  final String? mediaType;
  final String visibility;
  final int timestamp;
  
  final String? communityId;
  final String? communityName;
  final String? communityIcon;

  DraftPost({
    required this.id,
    required this.text,
    required this.mediaUrls,
    required this.publicIds,
    this.mediaType,
    this.visibility = 'public',
    required this.timestamp,
    this.communityId,
    this.communityName,
    this.communityIcon,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'text': text,
      'mediaUrls': mediaUrls,
      'publicIds': publicIds,
      'mediaType': mediaType,
      'visibility': visibility,
      'timestamp': timestamp,
      'communityId': communityId,
      'communityName': communityName,
      'communityIcon': communityIcon,
    };
  }

  factory DraftPost.fromMap(Map<String, dynamic> map) {
    return DraftPost(
      id: map['id'],
      text: map['text'] ?? '',
      mediaUrls: List<String>.from(map['mediaUrls'] ?? []),
      publicIds: List<String>.from(map['publicIds'] ?? []),
      mediaType: map['mediaType'],
      visibility: map['visibility'] ?? 'public',
      timestamp: map['timestamp'] ?? DateTime.now().millisecondsSinceEpoch,
      communityId: map['communityId'],
      communityName: map['communityName'],
      communityIcon: map['communityIcon'],
    );
  }
}

class DraftService {
  static const String _keyDrafts = 'user_drafts';
  final CloudinaryService _cloudinaryService = CloudinaryService();

  Future<List<DraftPost>> getDrafts() async {
    final prefs = await SharedPreferences.getInstance();
    final String? draftsJson = prefs.getString(_keyDrafts);
    if (draftsJson == null) return [];

    final List<dynamic> decoded = json.decode(draftsJson);
    List<DraftPost> drafts = decoded.map((e) => DraftPost.fromMap(e)).toList();
    // Sort Descending (Newest First)
    drafts.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return drafts;
  }

  Future<void> saveDraft(DraftPost draft) async {
    final prefs = await SharedPreferences.getInstance();
    List<DraftPost> drafts = await getDrafts();
    
    // 1. Check if updating existing or adding new
    final index = drafts.indexWhere((d) => d.id == draft.id);
    if (index != -1) {
      drafts[index] = draft; 
    } else {
      drafts.insert(0, draft); 
    }

    // 2. Re-sort to ensure Newest is top
    drafts.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    // 3. FIFO LIMIT: If more than 3, delete the oldest (last)
    if (drafts.length > 3) {
      DraftPost oldestDraft = drafts.last;
      
      // Cleanup Cloudinary resources for the deleted draft
      if (oldestDraft.publicIds.isNotEmpty) {
        String resourceType = oldestDraft.mediaType == 'video' ? 'video' : 'image';
        for (String pubId in oldestDraft.publicIds) {
          _cloudinaryService.deleteResource(pubId, resourceType: resourceType);
        }
      }
      
      // Remove from list
      drafts.removeLast();
    }

    final String encoded = json.encode(drafts.map((d) => d.toMap()).toList());
    await prefs.setString(_keyDrafts, encoded);
  }

  Future<void> deleteDraft(String draftId) async {
    final prefs = await SharedPreferences.getInstance();
    List<DraftPost> drafts = await getDrafts();
    
    final index = drafts.indexWhere((d) => d.id == draftId);
    if (index != -1) {
      final draft = drafts[index];
      if (draft.publicIds.isNotEmpty) {
        String resourceType = draft.mediaType == 'video' ? 'video' : 'image';
        for (String pubId in draft.publicIds) {
          await _cloudinaryService.deleteResource(pubId, resourceType: resourceType);
        }
      }
      drafts.removeAt(index);
      final String encoded = json.encode(drafts.map((d) => d.toMap()).toList());
      await prefs.setString(_keyDrafts, encoded);
    }
  }

  Future<void> discardDraftAfterPosting(String draftId) async {
    final prefs = await SharedPreferences.getInstance();
    List<DraftPost> drafts = await getDrafts();
    drafts.removeWhere((d) => d.id == draftId);
    final String encoded = json.encode(drafts.map((d) => d.toMap()).toList());
    await prefs.setString(_keyDrafts, encoded);
  }
}