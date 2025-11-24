import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../../main.dart';

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

  static const String _apiKey = 'AIzaSyDJskrMI0YRYQ6se0Lq0k-4K_evktY8XPI';

  late GenerativeModel _model;
  late ChatSession _chatSession;

  @override
  void initState() {
    super.initState();

    try {
      _model = GenerativeModel(
        model: 'gemini-2.5-pro',
        apiKey: _apiKey,
      );
      _chatSession = _model.startChat();
    } catch (e) {
      print('Model gemini-2.5-pro gagal -> fallback ke 2.5-flash');
      _model = GenerativeModel(
        model: 'gemini-2.5-flash',
        apiKey: _apiKey,
      );
      _chatSession = _model.startChat();
    }
  }

  Future<void> _handleSubmitted(String text) async {
    _textController.clear();
    if (text.trim().isEmpty) return;

    // Tambah pesan user
    setState(() {
      _messages.add(ChatMessage(
        text: text,
        isUser: true,
        timestamp: DateTime.now(),
      ));
      _isTyping = true;
    });

    _scrollToBottom();

    try {
      // Kirim ke Gemini
      final response = await _chatSession.sendMessage(Content.text(text));

      String aiText = "";

      // Parse berbagai format respons
      try {
        if (response == null) {
          aiText = "Tidak ada respons dari server.";
        } else {
          final dynamic maybeText = (response as dynamic).text;

          if (maybeText != null && maybeText is String && maybeText.isNotEmpty) {
            aiText = maybeText;
          } else {
            // === Format 1: candidates ===
            try {
              final c = (response as dynamic).candidates;
              if (c != null && c is List && c.isNotEmpty) {
                final part = c[0]?['content']?['parts']?[0]?['text'];
                if (part != null && part is String) aiText = part;
              }
            } catch (_) {}

            // === Format 2: outputs ===
            if (aiText.isEmpty) {
              try {
                final outputs = (response as dynamic).outputs;
                if (outputs != null && outputs is List && outputs.isNotEmpty) {
                  final outText =
                      outputs[0]?['content']?['text'] ?? outputs[0].toString();
                  if (outText is String) aiText = outText;
                }
              } catch (_) {}
            }

            // fallback
            if (aiText.isEmpty) {
              aiText = response.toString();
            }
          }
        }
      } catch (e) {
        aiText = "Terjadi kesalahan parsing respons: $e";
      }

      if (aiText.trim().isEmpty) aiText = "Maaf, saya tidak mengerti.";

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
      }
    } catch (e) {
      print("ERROR GEMINI: $e");

      if (mounted) {
        setState(() {
          _isTyping = false;
          _messages.add(ChatMessage(
            text: "Error terhubung ke AI:\n${e.toString()}",
            isUser: false,
            timestamp: DateTime.now(),
          ));
        });
      }
    }
  }

  // Scroll otomatis
  void _scrollToBottom() {
    Future.delayed(Duration(milliseconds: 120), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: Duration(milliseconds: 350),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? _buildEmptyState(theme)
                : _buildChatList(),
          ),

          // INPUT BAR
          Container(
            decoration: BoxDecoration(
              color: theme.scaffoldBackgroundColor,
              border: Border(top: BorderSide(color: theme.dividerColor)),
            ),
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      onSubmitted:
                          _isTyping ? null : _handleSubmitted,
                      decoration: InputDecoration(
                        hintText: 'Ask anything...',
                        filled: true,
                        fillColor: theme.brightness == Brightness.dark
                            ? TwitterTheme.darkGrey.withOpacity(0.2)
                            : TwitterTheme.extraLightGrey,
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 20, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: TwitterTheme.blue,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: Icon(Icons.send_rounded,
                          color: Colors.white, size: 20),
                      onPressed: _isTyping
                          ? null
                          : () => _handleSubmitted(_textController.text),
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

  // ================== UI builders ==================

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.auto_awesome, size: 48,
                color: TwitterTheme.blue.withOpacity(0.5)),
            SizedBox(height: 16),
            Text(
              "Hello! I am your AI Assistant.\nAsk me about anything.",
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatList() {
    return ListView.builder(
      controller: _scrollController,
      padding: EdgeInsets.fromLTRB(16, 120, 16, 16),
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
        margin: EdgeInsets.only(bottom: 16),
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: SizedBox(
          width: 40,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(
              3,
              (_) => Container(
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

// ======================================================
// ===================== MODEL =========================
// ======================================================

class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;

  ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
  });
}

class _ChatBubble extends StatelessWidget {
  final ChatMessage message;
  const _ChatBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = message.isUser;

    // Tentukan warna teks dasar
    final textColor = isUser ? Colors.white : theme.textTheme.bodyLarge?.color ?? Colors.black;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(bottom: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.85,
        ),
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isUser ? TwitterTheme.blue : theme.cardColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: MarkdownBody(
          data: message.text,
          selectable: true, 
          styleSheet: MarkdownStyleSheet(
            p: TextStyle(
              color: textColor,
              fontSize: 15,
            ),
            strong: TextStyle(
              color: textColor,
              fontWeight: FontWeight.bold,
            ),
            h1: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 24),
            h2: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 22),
            h3: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 20),
            h4: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 18),
            h5: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 16),
            h6: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 14),
            listBullet: TextStyle(
              color: textColor,
              fontSize: 16,
            ),
            code: TextStyle(
              color: isUser ? Colors.white70 : Colors.black87,
              backgroundColor: isUser ? Colors.white24 : Colors.grey.shade200,
              fontFamily: 'monospace',
            ),
            codeblockDecoration: BoxDecoration(
              color: isUser ? Colors.white24 : Colors.grey.shade200,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
    );
  }
}