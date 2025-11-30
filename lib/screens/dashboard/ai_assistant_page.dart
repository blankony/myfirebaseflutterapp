// ignore_for_file: prefer_const_constructors
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../main.dart';
import '../../services/ai_event_bus.dart'; 
import '../../widgets/common_error_widget.dart'; // REQUIRED

class AiAssistantPage extends StatefulWidget {
  const AiAssistantPage({super.key});

  @override
  State<AiAssistantPage> createState() => _AiAssistantPageState();
}

class _AiAssistantPageState extends State<AiAssistantPage> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  bool _isTyping = false;
  bool _isLoadingHistory = false;
  bool _hasConnectionError = false;

  String? _currentSessionId;
  StreamSubscription? _eventBusSubscription;

  final String _apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
  late GenerativeModel _model;
  late ChatSession _chatSession;

  final Content _systemInstruction = Content.system("""
      Kamu adalah asisten virtual cerdas untuk aplikasi "Sapa PNJ".
      Jawablah dengan gaya bahasa mahasiswa yang santai, sopan, dan membantu.
      Gunakan ingatan dari chat sebelumnya jika relevan.
    """);

  @override
  void initState() {
    super.initState();
    _initModel();

    _eventBusSubscription = aiPageEventBus.stream.listen((event) {
      if (event.type == AiEventType.newChat) {
        _startNewChat();
      } else if (event.type == AiEventType.loadChat && event.sessionId != null) {
        _loadChatSession(event.sessionId!);
      }
    });
  }

  @override
  void dispose() {
    _eventBusSubscription?.cancel();
    super.dispose();
  }

  void _initModel() {
    if (_apiKey.isEmpty) {
      // In production, handle missing API key better
      return;
    }
    try {
      _model = GenerativeModel(
        model: 'gemini-1.5-flash', 
        apiKey: _apiKey,
        systemInstruction: _systemInstruction,
      );
      _chatSession = _model.startChat();
    } catch (e) {
      setState(() => _hasConnectionError = true);
    }
  }

  void _startNewChat() {
    setState(() {
      _messages.clear();
      _currentSessionId = null;
      _isTyping = false;
      _hasConnectionError = false;
      _chatSession = _model.startChat();
    });
  }

  Future<void> _loadChatSession(String sessionId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() {
      _isLoadingHistory = true;
      _messages.clear();
      _hasConnectionError = false;
      _currentSessionId = sessionId;
    });

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('chat_sessions')
          .doc(sessionId)
          .collection('messages')
          .orderBy('timestamp', descending: false)
          .get();

      final List<ChatMessage> loadedUiMessages = [];
      final List<Content> geminiHistory = [];

      String? lastRole;
      List<Part> bufferParts = [];

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final text = data['text'] ?? '';
        final isUser = data['isUser'] ?? true;
        final String currentRole = isUser ? 'user' : 'model';

        loadedUiMessages.add(ChatMessage(
          text: text,
          isUser: isUser,
          timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
        ));

        if (lastRole == null) {
          lastRole = currentRole;
          bufferParts.add(TextPart(text));
        } else if (lastRole == currentRole) {
          bufferParts.add(TextPart("\n\n$text")); 
        } else {
          geminiHistory.add(Content(lastRole, [...bufferParts]));
          lastRole = currentRole;
          bufferParts = [TextPart(text)];
        }
      }

      if (lastRole != null && bufferParts.isNotEmpty) {
        geminiHistory.add(Content(lastRole, bufferParts));
      }

      setState(() {
        _messages.addAll(loadedUiMessages);
        _isLoadingHistory = false;
        _chatSession = _model.startChat(history: geminiHistory);
      });

      _scrollToBottom();
    } catch (e) {
      setState(() {
        _isLoadingHistory = false;
        _hasConnectionError = true;
      });
    }
  }

  Future<void> _handleSubmitted(String text) async {
    _textController.clear();
    if (text.trim().isEmpty) return;

    final user = FirebaseAuth.instance.currentUser;

    setState(() {
      _messages.add(ChatMessage(
        text: text,
        isUser: true,
        timestamp: DateTime.now(),
      ));
      _isTyping = true;
      _hasConnectionError = false;
    });
    _scrollToBottom();

    if (user != null) {
      await _saveMessageToFirestore(user.uid, text, true);
    }

    try {
      final response = await _chatSession.sendMessage(Content.text(text));
      final aiText = response.text ?? "Maaf, saya tidak mengerti.";

      if (mounted) {
        setState(() {
          _isTyping = false;
          _messages.add(ChatMessage(
            text: aiText,
            isUser: false,
            timestamp: DateTime.now(),
          ));
        });
        _scrollToBottom();

        if (user != null) {
          await _saveMessageToFirestore(user.uid, aiText, false);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isTyping = false;
          // Don't add error message to chat history, just show retry UI or snackbar?
          // For now, simpler to add a system message
          _messages.add(ChatMessage(
            text: "Koneksi terputus. Silakan coba lagi nanti.",
            isUser: false,
            timestamp: DateTime.now(),
          ));
        });
        _scrollToBottom();
      }
    }
  }

  Future<void> _saveMessageToFirestore(String uid, String text, bool isUser) async {
    try {
      final sessionsRef = FirebaseFirestore.instance.collection('users').doc(uid).collection('chat_sessions');

      if (_currentSessionId == null) {
        String title = text.replaceAll('\n', ' ');
        if (title.length > 30) title = "${title.substring(0, 30)}...";
        if (!isUser) title = "Chat Baru"; 

        final newSession = await sessionsRef.add({
          'title': title,
          'createdAt': FieldValue.serverTimestamp(),
          'lastUpdated': FieldValue.serverTimestamp(),
        });
        _currentSessionId = newSession.id;
      } else {
        sessionsRef.doc(_currentSessionId).update({
          'lastUpdated': FieldValue.serverTimestamp(),
        });
      }

      await sessionsRef.doc(_currentSessionId).collection('messages').add({
        'text': text,
        'isUser': isUser,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      // Silent fail on save (offline support via Firebase cache handles this mostly)
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoadingHistory) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_hasConnectionError && _messages.isEmpty) {
      return Scaffold(
        body: CommonErrorWidget(
          message: "Unable to connect to AI Assistant.",
          isConnectionError: true,
          onRetry: () => _startNewChat(),
        ),
      );
    }

    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? _buildEmptyState(theme)
                : _buildChatList(),
          ),
          Container(
            decoration: BoxDecoration(
              color: theme.scaffoldBackgroundColor,
              border: Border(top: BorderSide(color: theme.dividerColor)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      onSubmitted: _isTyping ? null : _handleSubmitted,
                      decoration: InputDecoration(
                        hintText: 'Tanya seputar PNJ...',
                        filled: true,
                        fillColor: theme.brightness == Brightness.dark
                            ? TwitterTheme.darkGrey.withOpacity(0.2)
                            : TwitterTheme.extraLightGrey,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: const BoxDecoration(
                      color: TwitterTheme.blue,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                      onPressed: _isTyping ? null : () => _handleSubmitted(_textController.text),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset('images/app_icon.png', height: 60, color: TwitterTheme.blue.withOpacity(0.8)), 
            const SizedBox(height: 16),
            Text(
              "Sapa PNJ Assistant",
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Siap membantu! Tanya jadwal, info kampus, atau curhat kuliah.",
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatList() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 100, 16, 16), 
      itemCount: _messages.length + (_isTyping ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _messages.length) {
          return _buildTypingIndicator();
        }
        return _ChatBubble(message: _messages[index]);
      },
    );
  }

  Widget _buildTypingIndicator() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: SizedBox(
          width: 40,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(3, (_) => Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: TwitterTheme.blue.withOpacity(0.5),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;
  ChatMessage({required this.text, required this.isUser, required this.timestamp});
}

class _ChatBubble extends StatelessWidget {
  final ChatMessage message;
  const _ChatBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = message.isUser;
    final textColor = isUser ? Colors.white : theme.textTheme.bodyLarge?.color ?? Colors.black;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isUser ? TwitterTheme.blue : theme.cardColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: MarkdownBody(
          data: message.text,
          selectable: true,
          styleSheet: MarkdownStyleSheet(
            p: TextStyle(color: textColor, fontSize: 15),
            strong: TextStyle(color: textColor, fontWeight: FontWeight.bold),
            listBullet: TextStyle(color: textColor),
          ),
        ),
      ),
    );
  }
}