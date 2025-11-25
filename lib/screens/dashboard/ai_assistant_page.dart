import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
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

  final String _apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';

  late GenerativeModel _model;
  late ChatSession _chatSession;

  @override
  void initState() {
    super.initState();
    _initModel();
  }

  void _initModel() {
    // --- PERSONA DEFINITION ---
    // Instruksi ini memaksa AI untuk berperan sebagai Sapa PNJ
    final systemInstruction = Content.system("""
      Kamu adalah asisten virtual cerdas untuk aplikasi media sosial bernama "Sapa PNJ" (Sarana Pengguna Aplikasi Politeknik Negeri Jakarta).
      
      IDENTITAS KAMU:
      - Nama: Sapa PNJ Assistant.
      - Pembuat: Tim Pengembang Sapa PNJ (Arnold Holyridho R. dan Arya Setiawan), bukan Google.
      - Afiliasi: Politeknik Negeri Jakarta (PNJ).
      
      ATURAN PENTING:
      1. Jika ditanya "Siapa kamu?", jawablah: "Saya adalah asisten virtual Sapa PNJ, teman digitalmu di Politeknik Negeri Jakarta."
      2. JANGAN PERNAH mengaku sebagai "Gemini" atau "model buatan Google". Kamu harus tetap pada karakter (Roleplay).
      3. Gaya bicara: Ramah, sopan, gaul khas mahasiswa, suportif, dan informatif. Gunakan emoji sesekali.
      4. Konteks: Kamu tahu tentang kehidupan kampus, akademik, dan sosial di PNJ.
      5. Jika user bertanya hal teknis tentang model bahasamu, jawablah secara diplomatis bahwa kamu dikembangkan khusus untuk aplikasi ini.
    """);

    try {
      // Coba model Pro
      _model = GenerativeModel(
        model: 'gemini-2.5-pro', // Menggunakan versi stabil saat ini (bisa disesuaikan kembali ke 2.5 jika preview tersedia)
        apiKey: _apiKey,
        systemInstruction: systemInstruction, // Inject Persona
      );
      _chatSession = _model.startChat();
    } catch (e) {
      print('Model utama gagal -> fallback ke flash');
      // Fallback ke Flash
      _model = GenerativeModel(
        model: 'gemini-1.5-flash',
        apiKey: _apiKey,
        systemInstruction: systemInstruction, // Inject Persona juga di fallback
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
        if (response.text != null && response.text!.isNotEmpty) {
          aiText = response.text!;
        } else {
          aiText = "Maaf, saya tidak bisa memproses itu sekarang.";
        }
      } catch (e) {
        aiText = "Terjadi kesalahan parsing respons.";
      }

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
      print("ERROR AI: $e");

      if (mounted) {
        setState(() {
          _isTyping = false;
          _messages.add(ChatMessage(
            text: "Maaf, koneksi ke server Sapa PNJ sedang gangguan. Coba lagi nanti ya!",
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
                        hintText: 'Tanya seputar PNJ...',
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
            Icon(Icons.school, size: 48, // Ganti ikon jadi lebih relevan
                color: TwitterTheme.blue.withOpacity(0.5)),
            SizedBox(height: 16),
            Text(
              "Halo! Saya Asisten Sapa PNJ.\nAda yang bisa saya bantu tentang kampus?",
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 18,
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
            // Styling untuk list dan header agar konsisten dengan tema
            listBullet: TextStyle(color: textColor),
          ),
        ),
      ),
    );
  }
}