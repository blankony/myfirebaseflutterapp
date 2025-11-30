// ignore_for_file: prefer_const_constructors
import 'dart:async';
import 'dart:ui';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../main.dart';
import '../../services/ai_event_bus.dart';
import '../../widgets/common_error_widget.dart';

class AiAssistantPage extends StatefulWidget {
  const AiAssistantPage({super.key});

  @override
  State<AiAssistantPage> createState() => _AiAssistantPageState();
}

class _AiAssistantPageState extends State<AiAssistantPage> with TickerProviderStateMixin {
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
  
  late AnimationController _typingController;

  // Randomized Suggestions Data
  final List<Map<String, dynamic>> _allSuggestions = [
    {'text': "What is PNJ?", 'icon': Icons.school_outlined},
    {'text': "Help me write a bio", 'icon': Icons.edit_note},
    {'text': "Campus facilities info", 'icon': Icons.map_outlined},
    {'text': "Scholarship opportunities", 'icon': Icons.school},
    {'text': "Student organizations", 'icon': Icons.groups_outlined},
    {'text': "Academic calendar dates", 'icon': Icons.calendar_month_outlined},
    {'text': "Library opening hours", 'icon': Icons.access_time},
    {'text': "How to contact admin?", 'icon': Icons.contact_support_outlined},
    {'text': "Translate this text", 'icon': Icons.translate},
    {'text': "Draft a formal email", 'icon': Icons.email_outlined},
  ];
  late List<Map<String, dynamic>> _activeSuggestions;

  // System instruction updated to "Spirit AI"
  final Content _systemInstruction = Content.system("""
      You are "Spirit AI", a friendly, intelligent, and spirited virtual assistant for the Politeknik Negeri Jakarta (PNJ) community app "Sapa PNJ".
      
      Your Persona:
      - Name: Spirit AI
      - Tone: Energetic, helpful, student-friendly, and polite.
      - Language: English (default), but adapt to the user's language if they speak Indonesian.
      - Style: Concise, direct, and encouraging.
      
      Your Capabilities:
      - Answer questions about campus life, academics, and facilities.
      - Assist with drafting emails, bios, or messages.
      - Provide emotional support or casual chat for students.
    """);

  @override
  void initState() {
    super.initState();
    _initModel();
    
    // Randomize suggestions
    _allSuggestions.shuffle();
    _activeSuggestions = _allSuggestions.take(3).toList();
    
    _typingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat();

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
    _textController.dispose();
    _scrollController.dispose();
    _typingController.dispose();
    super.dispose();
  }

  void _initModel() {
    if (_apiKey.isEmpty) {
      setState(() => _hasConnectionError = true);
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
      // Reshuffle suggestions on new chat
      _allSuggestions.shuffle();
      _activeSuggestions = _allSuggestions.take(3).toList();
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
      final aiText = response.text ?? "I didn't catch that.";

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
          _messages.add(ChatMessage(
            text: "Connection error. Please try again.",
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
        if (!isUser) title = "New Chat";

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
      // Silent fail on save
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOutQuart,
        );
      }
    });
  }

  // --- HANDLER FOR SWIPE NAVIGATION ---
  void _handleHorizontalSwipe(DragEndDetails details) {
    if (details.primaryVelocity! > 0) {
      // Swiping Right -> Open Left Drawer (Side Panel)
      Scaffold.of(context).openDrawer();
    } else if (details.primaryVelocity! < 0) {
      // Swiping Left -> Open Right Drawer (History)
      Scaffold.of(context).openEndDrawer();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (_isLoadingHistory) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_hasConnectionError && _messages.isEmpty) {
      return Scaffold(
        body: CommonErrorWidget(
          message: "Unable to connect to Spirit AI.",
          isConnectionError: true,
          onRetry: () => _startNewChat(),
        ),
      );
    }

    // WRAP WITH GESTURE DETECTOR FOR SWIPE
    return GestureDetector(
      onHorizontalDragEnd: _handleHorizontalSwipe,
      child: Scaffold(
        body: Stack(
          children: [
            // Only show background decoration when chat is empty
            if (_messages.isEmpty) ...[
               Positioned(
                top: -100,
                right: -100,
                child: Container(
                  width: 300,
                  height: 300,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: TwitterTheme.blue.withOpacity(isDark ? 0.15 : 0.1),
                  ),
                ),
              ),
              Positioned(
                bottom: 150,
                left: -50,
                child: Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: TwitterTheme.blue.withOpacity(isDark ? 0.1 : 0.05),
                  ),
                ),
              ),
            ],

            Column(
              children: [
                Expanded(
                  child: _messages.isEmpty
                      ? _buildEmptyState(theme, isDark)
                      : _buildChatList(theme, isDark),
                ),
                _buildInputArea(theme, isDark),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme, bool isDark) {
    return SingleChildScrollView(
      child: Container(
        height: MediaQuery.of(context).size.height, // Full height for centering
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Added Top Padding for AppBar overlap
            SizedBox(height: kToolbarHeight + 40), 

            // LOGO
            Container(
              padding: EdgeInsets.all(24),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.cardColor,
                boxShadow: [
                  BoxShadow(
                    color: TwitterTheme.blue.withOpacity(0.25),
                    blurRadius: 30,
                    spreadRadius: 2,
                  )
                ]
              ),
              child: Image.asset('images/app_icon.png', height: 70, width: 70),
            ),
            
            const SizedBox(height: 32),
            
            // TITLE
            Text(
              "Spirit AI",
              style: theme.textTheme.displayMedium?.copyWith(
                fontWeight: FontWeight.w900,
                color: TwitterTheme.blue,
              ),
            ),
            Text(
              "Your Virtual Assistant",
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.hintColor,
                fontWeight: FontWeight.normal
              ),
            ),
            
            const SizedBox(height: 40),
            
            // SHORTCUTS (Randomized)
            Column(
              children: _activeSuggestions.map((suggestion) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: _buildShortcutCard(
                    theme, 
                    suggestion['text'] as String, 
                    suggestion['icon'] as IconData
                  ),
                );
              }).toList(),
            ),

            Spacer(flex: 3),
          ],
        ),
      ),
    );
  }

  Widget _buildShortcutCard(ThemeData theme, String text, IconData icon) {
    return InkWell(
      onTap: () => _handleSubmitted(text),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.dividerColor.withOpacity(0.5)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 10,
              offset: Offset(0, 4),
            )
          ]
        ),
        child: Row(
          children: [
            Icon(icon, color: TwitterTheme.blue, size: 20),
            SizedBox(width: 16),
            Expanded(
              child: Text(
                text, 
                style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(Icons.arrow_forward_ios, size: 12, color: theme.hintColor),
          ],
        ),
      ),
    );
  }

  Widget _buildChatList(ThemeData theme, bool isDark) {
    return ListView.builder(
      controller: _scrollController,
      // Added Top padding to avoid collision with transparent AppBar
      padding: const EdgeInsets.fromLTRB(16, kToolbarHeight + 60, 16, 16),
      itemCount: _messages.length + (_isTyping ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _messages.length) {
          return _buildTypingIndicator(theme);
        }
        return _ChatBubble(message: _messages[index]);
      },
    );
  }

  Widget _buildTypingIndicator(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16, left: 0),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: TwitterTheme.blue.withOpacity(0.1),
            child: Image.asset('images/app_icon.png', height: 16, color: TwitterTheme.blue),
          ),
          SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(20),
                bottomRight: Radius.circular(20),
                bottomLeft: Radius.circular(20),
              ),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5, offset: Offset(0, 2))
              ]
            ),
            child: FadeTransition(
              opacity: _typingController,
              child: Text("Thinking...", style: TextStyle(color: theme.hintColor, fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputArea(ThemeData theme, bool isDark) {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? TwitterTheme.darkGrey.withOpacity(0.2) : TwitterTheme.extraLightGrey,
                borderRadius: BorderRadius.circular(30),
              ),
              child: TextField(
                controller: _textController,
                onSubmitted: _isTyping ? null : _handleSubmitted,
                textCapitalization: TextCapitalization.sentences,
                style: TextStyle(fontSize: 16),
                decoration: InputDecoration(
                  hintText: 'Ask Spirit AI...',
                  hintStyle: TextStyle(color: theme.hintColor),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  isDense: true,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: _isTyping ? null : () => _handleSubmitted(_textController.text),
            child: Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _isTyping ? theme.disabledColor : TwitterTheme.blue,
                shape: BoxShape.circle,
                boxShadow: [
                  if (!_isTyping)
                    BoxShadow(color: TwitterTheme.blue.withOpacity(0.4), blurRadius: 10, offset: Offset(0, 4))
                ]
              ),
              child: Icon(Icons.send_rounded, color: Colors.white, size: 22),
            ),
          ),
        ],
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
    final isDark = theme.brightness == Brightness.dark;
    final isUser = message.isUser;
    
    final textColor = isUser ? Colors.white : (theme.textTheme.bodyLarge?.color ?? Colors.black);
    final bgColor = isUser ? TwitterTheme.blue : theme.cardColor;
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 20.0),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 18,
              backgroundColor: TwitterTheme.blue.withOpacity(0.1),
              child: Image.asset('images/app_icon.png', height: 20, color: TwitterTheme.blue),
            ),
            SizedBox(width: 10),
          ],
          Flexible(
            child: Container(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                  bottomLeft: isUser ? Radius.circular(24) : Radius.circular(4),
                  bottomRight: isUser ? Radius.circular(4) : Radius.circular(24),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 8,
                    offset: Offset(0, 4),
                  )
                ],
              ),
              child: MarkdownBody(
                data: message.text,
                selectable: true,
                styleSheet: MarkdownStyleSheet(
                  p: TextStyle(color: textColor, fontSize: 15, height: 1.5),
                  strong: TextStyle(color: textColor, fontWeight: FontWeight.bold),
                  listBullet: TextStyle(color: textColor),
                  code: TextStyle(
                    color: isUser ? Colors.white70 : theme.primaryColor,
                    backgroundColor: isUser ? Colors.black26 : theme.scaffoldBackgroundColor,
                    fontFamily: 'monospace',
                    fontSize: 13,
                  ),
                  blockquote: TextStyle(color: isUser ? Colors.white70 : theme.hintColor),
                  blockquoteDecoration: BoxDecoration(
                    border: Border(left: BorderSide(color: isUser ? Colors.white30 : theme.dividerColor, width: 3))
                  ),
                ),
              ),
            ),
          ),
          if (isUser) ...[
             SizedBox(width: 10),
             _UserAvatar(),
          ],
        ],
      ),
    );
  }
}

class _UserAvatar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return SizedBox(width: 32);

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
      builder: (context, snapshot) {
        String? profileUrl;
        int iconId = 0;
        String? colorHex;

        if (snapshot.hasData && snapshot.data!.exists) {
           final data = snapshot.data!.data() as Map<String, dynamic>;
           profileUrl = data['profileImageUrl'];
           iconId = data['avatarIconId'] ?? 0;
           colorHex = data['avatarHex'];
        }

        return CircleAvatar(
          radius: 18,
          backgroundColor: profileUrl != null ? Colors.transparent : AvatarHelper.getColor(colorHex),
          backgroundImage: profileUrl != null ? CachedNetworkImageProvider(profileUrl) : null,
          child: profileUrl == null 
            ? Icon(AvatarHelper.getIcon(iconId), size: 18, color: Colors.white) 
            : null,
        );
      },
    );
  }
}