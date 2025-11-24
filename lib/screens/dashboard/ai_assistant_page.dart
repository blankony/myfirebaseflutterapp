// ignore_for_file: prefer_const_constructors
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../main.dart'; // Import for TwitterTheme

class AiAssistantPage extends StatefulWidget {
  const AiAssistantPage({super.key});

  @override
  State<AiAssistantPage> createState() => _AiAssistantPageState();
}

class _AiAssistantPageState extends State<AiAssistantPage> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = []; // Start empty
  bool _isTyping = false;

  // The "Big Bold Text" Greetings
  final List<String> _greetings = [
    'Hello, How is your day?',
    'How can I help you?',
    'Ask me anything!',
    'I am here to assist you.',
  ];
  late String _currentGreeting;

  final List<String> _randomResponses = [
    'That is an interesting perspective! Tell me more.',
    'I can certainly help with that. Here is what I found...',
    'Could you clarify what you mean?',
    'That sounds great! How does that make you feel?',
    'I am just a demo AI, but I am learning every day!',
  ];

  @override
  void initState() {
    super.initState();
    _currentGreeting = _greetings[Random().nextInt(_greetings.length)];
    // Note: We do NOT add an initial AI message here anymore.
  }

  void _handleSubmitted(String text) {
    _textController.clear();
    if (text.trim().isEmpty) return;

    // 1. Add User Message immediately
    setState(() {
      _messages.add(ChatMessage(
        text: text,
        isUser: true,
        timestamp: DateTime.now(),
      ));
      _isTyping = true;
    });
    
    // Scroll to bottom if list is visible
    if (_messages.isNotEmpty) _scrollToBottom();

    // 2. Simulate AI Response Delay
    Timer(Duration(milliseconds: 1500), () {
      if (mounted) {
        setState(() {
          _isTyping = false;
          _messages.add(ChatMessage(
            text: _randomResponses[Random().nextInt(_randomResponses.length)],
            isUser: false,
            timestamp: DateTime.now(),
          ));
        });
        _scrollToBottom();
      }
    });
  }

  void _scrollToBottom() {
    // Small delay to allow the list to build the new item first
    Future.delayed(Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: Duration(milliseconds: 300),
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
          // 1. Content Area (Empty State OR Chat List)
          Expanded(
            child: _messages.isEmpty
                ? _buildEmptyState(theme) // Show Big Bold Text
                : _buildChatList(),       // Show Chat Bubbles
          ),

          // 2. Input Area
          Container(
            decoration: BoxDecoration(
              color: theme.scaffoldBackgroundColor,
              border: Border(top: BorderSide(color: theme.dividerColor)),
            ),
            padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      onSubmitted: _handleSubmitted,
                      decoration: InputDecoration(
                        hintText: 'Ask anything...',
                        hintStyle: TextStyle(color: theme.hintColor),
                        filled: true,
                        fillColor: theme.brightness == Brightness.dark 
                            ? TwitterTheme.darkGrey.withOpacity(0.2) 
                            : TwitterTheme.extraLightGrey,
                        contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide(color: TwitterTheme.blue, width: 1.5),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 8),
                  
                  // Send Button
                  Container(
                    decoration: BoxDecoration(
                      color: TwitterTheme.blue,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: Icon(Icons.send_rounded, color: Colors.white, size: 20),
                      onPressed: () => _handleSubmitted(_textController.text),
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

  // The "Big Bold Text" View
  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Optional: Add an icon above the text
            Icon(Icons.auto_awesome, size: 48, color: TwitterTheme.blue.withOpacity(0.5)),
            SizedBox(height: 16),
            Text(
              _currentGreeting,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.textTheme.bodyLarge?.color,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // The Chat List View
  Widget _buildChatList() {
    return ListView.builder(
      controller: _scrollController,
      padding: EdgeInsets.fromLTRB(16, 120, 16, 16), // Top padding for AppBar clearance
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
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomRight: Radius.circular(16),
            bottomLeft: Radius.zero,
          ),
        ),
        child: SizedBox(
          width: 40,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(3, (index) => 
              Container(
                width: 6, 
                height: 6, 
                decoration: BoxDecoration(
                  color: TwitterTheme.blue.withOpacity(0.5), 
                  shape: BoxShape.circle
                )
              )
            ),
          ),
        ),
      ),
    );
  }
}

// --- HELPER WIDGETS & MODELS ---

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

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(bottom: 12),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isUser ? TwitterTheme.blue : theme.cardColor,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: isUser ? Radius.circular(16) : Radius.zero,
            bottomRight: isUser ? Radius.zero : Radius.circular(16),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 2,
              offset: Offset(0, 1),
            )
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message.text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: isUser ? Colors.white : theme.textTheme.bodyLarge?.color,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}