import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../services/draft_service.dart';
import '../services/overlay_service.dart';
import '../main.dart';
import 'create_post_screen.dart';

class DraftsScreen extends StatefulWidget {
  const DraftsScreen({super.key});

  @override
  State<DraftsScreen> createState() => _DraftsScreenState();
}

class _DraftsScreenState extends State<DraftsScreen> {
  final DraftService _draftService = DraftService();
  List<DraftPost> _drafts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDrafts();
  }

  Future<void> _loadDrafts() async {
    final drafts = await _draftService.getDrafts();
    if (mounted) {
      setState(() {
        _drafts = drafts;
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteDraft(DraftPost draft) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete Draft?"),
        content: const Text("This will permanently delete the draft and any attached media."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Delete", style: TextStyle(color: Colors.red))),
        ],
      )
    ) ?? false;

    if (confirm) {
      setState(() => _isLoading = true);
      await _draftService.deleteDraft(draft.id);
      await _loadDrafts();
      if (mounted) OverlayService().showTopNotification(context, "Draft deleted", Icons.delete_outline, (){});
    }
  }

  void _openDraft(DraftPost draft) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreatePostScreen(
          draftData: draft, 
        ),
      ),
    ).then((_) => _loadDrafts());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text("Drafts"),
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : _drafts.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.drafts_outlined, size: 64, color: theme.hintColor.withOpacity(0.5)),
                  const SizedBox(height: 16),
                  Text("No drafts saved", style: TextStyle(color: theme.hintColor)),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _drafts.length,
              itemBuilder: (context, index) {
                final draft = _drafts[index];
                final hasMedia = draft.mediaUrls.isNotEmpty;
                
                return Dismissible(
                  key: Key(draft.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    color: Colors.red,
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  confirmDismiss: (dir) async {
                    await _deleteDraft(draft);
                    return false; 
                  },
                  child: Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      contentPadding: const EdgeInsets.only(left: 12, right: 8, top: 8, bottom: 8),
                      leading: hasMedia 
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: draft.mediaType == 'video'
                              ? Container(width: 50, height: 50, color: Colors.black, child: const Icon(Icons.videocam, color: Colors.white))
                              : CachedNetworkImage(
                                  imageUrl: draft.mediaUrls.first,
                                  width: 50, height: 50, fit: BoxFit.cover,
                                  placeholder: (_,__) => Container(color: Colors.grey[300]),
                                ),
                          )
                        : Container(
                            width: 50, height: 50,
                            decoration: BoxDecoration(color: theme.dividerColor.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
                            child: Icon(Icons.text_fields, color: theme.hintColor),
                          ),
                      title: Text(
                        draft.text.isEmpty ? (hasMedia ? "Media Post" : "Empty Draft") : draft.text,
                        maxLines: 1, 
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (draft.communityName != null)
                            Text("in ${draft.communityName}", style: TextStyle(fontSize: 11, color: TwitterTheme.blue)),
                          Text(
                            timeago.format(DateTime.fromMillisecondsSinceEpoch(draft.timestamp)),
                            style: TextStyle(fontSize: 12, color: theme.hintColor),
                          ),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit, size: 20, color: Colors.blue),
                            onPressed: () => _openDraft(draft),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                            onPressed: () => _deleteDraft(draft),
                          ),
                        ],
                      ),
                      onTap: () => _openDraft(draft),
                    ),
                  ),
                );
              },
            ),
    );
  }
}