import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_auth/firebase_auth.dart';     // PENTING
import 'package:cloud_firestore/cloud_firestore.dart'; // PENTING
import '../../main.dart';
import 'home_dashboard.dart'; // Akses aiPageEventBus

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

  // STATE UNTUK SESSION
  String? _currentSessionId;
  StreamSubscription? _eventBusSubscription;

  final String _apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
  late GenerativeModel _model;
  late ChatSession _chatSession;

  // Persona
  final Content _systemInstruction = Content.system("""
      Kamu adalah asisten virtual cerdas untuk aplikasi media sosial bernama "Sapa PNJ" (Sarana Pengguna Aplikasi Politeknik Negeri Jakarta).
      
      IDENTITAS KAMU:
      - Nama: Sapa PNJ Assistant.
      - Pembuat: Tim Pengembang Sapa PNJ (Arnold Holyridho R. dan Arya Setiawan), bukan Google.
      - Afiliasi: Politeknik Negeri Jakarta (PNJ).
      
      KONTEKS KALENDER AKADEMIK PNJ (Tahun 2025/2026):
      1. Semester Ganjil (2025/2026):
         - Awal Perkuliahan: 25 Agustus 2025.
         - UTS: 13 - 17 Oktober 2025.
         - UAS: 15 - 19 Desember 2025.
         - Libur Semester: 26 Januari - 06 Februari 2026.

      2. Semester Genap (2025/2026):
         - Awal Perkuliahan: 09 Februari 2026.
         - UTS: 30 Maret - 06 April 2026.
         - UAS: 02 - 08 Juni 2026.
         - Libur Semester: 26 Juni - 21 Agustus 2026.

      ATURAN PENTING:
      1. Jawab ramah khas mahasiswa.
      2. Jangan mengaku sebagai Gemini.
    """);

  @override
  void initState() {
    super.initState();
    _initModel();

    // LISTEN EVENT DARI DRAWER
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
    if (_apiKey.isEmpty) return;
    try {
      _model = GenerativeModel(
        model: 'gemini-2.5-pro', 
        apiKey: _apiKey,
        systemInstruction: _systemInstruction,
      );
      _chatSession = _model.startChat();
    } catch (e) {
      print('Model Error: $e');
    }
  }

  // === FUNGSI LOGIKA BARU ===

  void _startNewChat() {
    setState(() {
      _messages.clear();
      _currentSessionId = null;
      _isTyping = false;
      _chatSession = _model.startChat();
    });
  }

  Future<void> _loadChatSession(String sessionId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() {
      _isLoadingHistory = true;
      _messages.clear();
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

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final text = data['text'] ?? '';
        final isUser = data['isUser'] ?? true;
        
        loadedUiMessages.add(ChatMessage(
          text: text,
          isUser: isUser,
          timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
        ));

        // Format history untuk Gemini agar konteks nyambung
        geminiHistory.add(Content(isUser ? 'user' : 'model', [TextPart(text)]));
      }

      setState(() {
        _messages.addAll(loadedUiMessages);
        _isLoadingHistory = false;
        // Restore session Gemini dengan history
        _chatSession = _model.startChat(history: geminiHistory);
      });

      _scrollToBottom();
    } catch (e) {
      print("Error loading history: $e");
      setState(() => _isLoadingHistory = false);
    }
  }

  Future<void> _handleSubmitted(String text) async {
    _textController.clear();
    if (text.trim().isEmpty) return;

    final user = FirebaseAuth.instance.currentUser;

    // 1. Tambah User Message ke UI
    setState(() {
      _messages.add(ChatMessage(
        text: text,
        isUser: true,
        timestamp: DateTime.now(),
      ));
      _isTyping = true;
    });
    _scrollToBottom();

    // 2. Simpan User Message ke Firestore
    if (user != null) {
      await _saveMessageToFirestore(user.uid, text, true);
    }

    try {
      // 3. Kirim ke Gemini
      final response = await _chatSession.sendMessage(Content.text(text));
      final aiText = response.text ?? "Maaf, saya tidak dapat menjawab saat ini.";

      if (mounted) {
        // 4. Tambah AI Message ke UI
        setState(() {
          _isTyping = false;
          _messages.add(ChatMessage(
            text: aiText,
            isUser: false,
            timestamp: DateTime.now(),
          ));
        });
        _scrollToBottom();

        // 5. Simpan AI Message ke Firestore
        if (user != null) {
          await _saveMessageToFirestore(user.uid, aiText, false);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isTyping = false;
          _messages.add(ChatMessage(
            text: "Error: $e (Cek koneksi atau kuota API)",
            isUser: false,
            timestamp: DateTime.now(),
          ));
        });
        _scrollToBottom();
      }
    }
  }

  Future<void> _saveMessageToFirestore(String uid, String text, bool isUser) async {
    final sessionsRef = FirebaseFirestore.instance.collection('users').doc(uid).collection('chat_sessions');

    // Buat Session baru jika belum ada
    if (_currentSessionId == null) {
      // Judul otomatis dari pesan pertama (max 30 char)
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
      // Update waktu terakhir sesi
      sessionsRef.doc(_currentSessionId).update({
        'lastUpdated': FieldValue.serverTimestamp(),
      });
    }

    // Simpan pesan
    await sessionsRef.doc(_currentSessionId).collection('messages').add({
      'text': text,
      'isUser': isUser,
      'timestamp': FieldValue.serverTimestamp(),
    });
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

    // Tampilan Loading saat memuat history
    if (_isLoadingHistory) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? _buildEmptyState(theme)
                : _buildChatList(),
          ),
          // Input Area
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
            Icon(Icons.school, size: 60, color: TwitterTheme.blue.withOpacity(0.5)),
            const SizedBox(height: 16),
            Text(
              "Halo! Saya Asisten Sapa PNJ.\nSilakan tanya jadwal atau info kampus.",
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Tips: Geser dari kanan layar untuk lihat History.",
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
      padding: const EdgeInsets.fromLTRB(16, 100, 16, 16), // Top padding for AppBar
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