import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../main.dart'; // Pastikan path ini benar untuk akses TwitterTheme

class AiHistoryDrawer extends StatelessWidget {
  final Function(String sessionId) onChatSelected;
  final VoidCallback onNewChat;

  const AiHistoryDrawer({
    super.key,
    required this.onChatSelected,
    required this.onNewChat,
  });

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    return Drawer(
      backgroundColor: theme.scaffoldBackgroundColor,
      child: Column(
        children: [
          // --- HEADER PANEL ---
          SafeArea(
            bottom: false,
            child: Container(
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: theme.dividerColor)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Chat History",
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: TwitterTheme.blue
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close, color: theme.hintColor),
                        onPressed: () => Navigator.pop(context),
                      )
                    ],
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context); // Tutup drawer dulu
                      onNewChat();
                    },
                    icon: const Icon(Icons.add_comment_rounded, color: Colors.white),
                    label: const Text("New Chat"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: TwitterTheme.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // --- LIST HISTORY ---
          Expanded(
            child: user == null
                ? const Center(child: Text("Please log in."))
                : StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('users')
                        .doc(user.uid)
                        .collection('chat_sessions')
                        .orderBy('lastUpdated', descending: true)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.history_toggle_off, size: 64, color: theme.hintColor.withOpacity(0.3)),
                              const SizedBox(height: 16),
                              Text("No history yet", style: TextStyle(color: theme.hintColor)),
                            ],
                          ),
                        );
                      }

                      return ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: snapshot.data!.docs.length,
                        separatorBuilder: (context, index) => Divider(height: 1, color: theme.dividerColor.withOpacity(0.3)),
                        itemBuilder: (context, index) {
                          final doc = snapshot.data!.docs[index];
                          final data = doc.data() as Map<String, dynamic>;
                          final String title = data['title'] ?? 'New Conversation';
                          final Timestamp? timestamp = data['lastUpdated'];

                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            title: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w500),
                            ),
                            subtitle: Text(
                              timestamp != null ? timeago.format(timestamp.toDate(), locale: 'en_short') : '',
                              style: TextStyle(fontSize: 12, color: theme.hintColor),
                            ),
                            onTap: () {
                              Navigator.pop(context);
                              onChatSelected(doc.id);
                            },
                            trailing: IconButton(
                              icon: Icon(Icons.delete_outline, size: 20, color: theme.hintColor),
                              onPressed: () {
                                // Hapus Sesi
                                showDialog(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text("Delete Chat?"),
                                    content: const Text("This conversation will be deleted permanently."),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
                                      TextButton(
                                        onPressed: () {
                                          doc.reference.delete();
                                          Navigator.pop(ctx);
                                        },
                                        child: const Text("Delete", style: TextStyle(color: Colors.red)),
                                      )
                                    ],
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}