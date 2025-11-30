// ignore_for_file: prefer_const_constructors
import 'dart:async';
import 'dart:ui';
import 'dart:math';
import 'dart:io'; // REQUIRED for Platform check
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // REQUIRED for Clipboard
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:share_plus/share_plus.dart'; // REQUIRED for Share
import '../../main.dart';
import '../../services/ai_event_bus.dart';
import '../../widgets/common_error_widget.dart';
import '../../services/overlay_service.dart';

// --- ENHANCED LANGUAGE DETECTOR ---
class LanguageDetector {
  // Indonesian indicators (expanded)
  static const Set<String> _idWords = {
    // Pronouns
    'aku', 'kamu', 'dia', 'kita', 'kami', 'mereka', 'saya', 'anda', 'kalian',
    'gue', 'lu', 'elo', 'gw', 'lo', 'beliau',
    
    // Common particles (VERY strong indicators)
    'yang', 'nya', 'di', 'ke', 'dari', 'pada', 'untuk', 'buat',
    'dan', 'atau', 'tapi', 'tetapi', 'karena', 'jika', 'kalau',
    
    // Verbs & auxiliaries
    'ada', 'adalah', 'ialah', 'jadi', 'bisa', 'dapat', 'mau', 'ingin',
    'akan', 'sudah', 'telah', 'belum', 'pernah', 'harus', 'bantu', 'tolong',
    'minta', 'ngetes',
    
    // Negation
    'tidak', 'tak', 'bukan', 'jangan', 'gak', 'nggak', 'kagak', 'enggak',
    
    // Questions
    'apa', 'siapa', 'kapan', 'dimana', 'kemana', 'kenapa', 'mengapa',
    'bagaimana', 'berapa', 'mana', 'ngapain', 'gimana',
    
    // Time & quantity
    'hari', 'besok', 'kemarin', 'sekarang', 'nanti', 'tadi',
    'banyak', 'sedikit', 'semua',
    
    // Greetings
    'halo', 'hai', 'selamat', 'pagi', 'siang', 'sore', 'malam', 'terima', 'kasih',
    
    // Colloquial
    'dong', 'sih', 'deh', 'kok', 'yuk', 'nih', 'tuh', 'lain', 'lainnya'
  };

  // English common words (for better differentiation)
  static const Set<String> _enWords = {
    'the', 'is', 'are', 'was', 'were', 'be', 'been', 'being',
    'have', 'has', 'had', 'do', 'does', 'did',
    'will', 'would', 'should', 'could', 'can', 'may', 'might',
    'what', 'where', 'when', 'why', 'how', 'who', 'which',
    'this', 'that', 'these', 'those',
    'not', 'no', 'yes',
  };

  /// Detects language from text with improved accuracy
  static String detect(String text) {
    if (text.trim().isEmpty) return 'en-US';
    
    final cleanText = text.toLowerCase().trim();
    
    // Score counters
    int idScore = 0;
    int enScore = 0;
    
    // 1. Check for strong Indonesian affixes (highest priority)
    if (RegExp(r'\b(meng|peng|ber|ter|ke|se)\w+').hasMatch(cleanText)) idScore += 3;
    if (RegExp(r'\w+nya\b').hasMatch(cleanText)) idScore += 3;
    if (RegExp(r'\bdi\s+\w+').hasMatch(cleanText)) idScore += 2; // "di rumah", "di sini"
    
    // 2. Tokenize and check word matches
    final words = cleanText
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 1) // Ignore single chars
        .toList();
    
    for (var word in words) {
      if (_idWords.contains(word)) {
        idScore += 2;
      }
      if (_enWords.contains(word)) {
        enScore += 2;
      }
    }
    
    // 3. Character pattern analysis
    // Indonesian uses fewer consecutive consonants
    if (RegExp(r'[bcdfghjklmnpqrstvwxyz]{4,}').hasMatch(cleanText)) {
      enScore += 1; // English tends to have more consonant clusters
    }
    
    // 4. Decision logic
    if (idScore > enScore) {
      return 'id-ID';
    } else if (enScore > idScore) {
      return 'en-US';
    }
    
    // 5. Fallback: Check if text contains any Indonesian particles
    if (RegExp(r'\b(yang|nya|di|ke|dari|untuk|dan)\b').hasMatch(cleanText)) {
      return 'id-ID';
    }
    
    return 'en-US'; // Default
  }
}

// --- TTS MANAGER WITH ROBUST ERROR HANDLING ---
class TTSManager {
  final FlutterTts _tts = FlutterTts();
  bool _isInitialized = false;
  Map<String, dynamic>? _availableVoices;
  
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Basic TTS settings
      await _tts.setSpeechRate(0.5);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      
      // Cache available voices
      _availableVoices = await _getAvailableVoices();
      
      // Platform-specific setup
      if (Platform.isAndroid) {
        await _tts.awaitSpeakCompletion(true);
      }

      // Setup Handlers
      _tts.setCompletionHandler(() {
        OverlayService().hideAudioPlayer();
      });
      _tts.setCancelHandler(() {
        OverlayService().hideAudioPlayer();
      });
      
      _isInitialized = true;
      debugPrint("TTS Initialized successfully");
    } catch (e) {
      debugPrint("TTS Initialization Error: $e");
    }
  }
  
  Future<Map<String, dynamic>> _getAvailableVoices() async {
    try {
      final voices = await _tts.getVoices;
      final Map<String, dynamic> voiceMap = {
        'id-ID': [],
        'en-US': [],
        'en-GB': [],
      };
      
      if (voices != null && voices is List) {
        for (var voice in voices) {
          if (voice is Map) {
            final locale = voice['locale']?.toString() ?? '';
            final name = voice['name']?.toString() ?? '';
            
            if (locale.startsWith('id') || name.contains('Indonesia')) {
              voiceMap['id-ID']!.add(voice);
            } else if (locale.startsWith('en-US') || name.contains('United States')) {
              voiceMap['en-US']!.add(voice);
            } else if (locale.startsWith('en')) {
              voiceMap['en-GB']!.add(voice);
            }
          }
        }
      }
      
      debugPrint("Available voices: ${voiceMap.keys.where((k) => voiceMap[k]!.isNotEmpty).join(', ')}");
      return voiceMap;
    } catch (e) {
      debugPrint("Voice enumeration failed: $e");
      return {};
    }
  }
  
  Future<void> speak(BuildContext context, String text) async {
    if (!_isInitialized) await initialize();
    if (text.trim().isEmpty) return;
    
    try {
      await _tts.stop();
      
      // 1. Detect language
      final detectedLang = LanguageDetector.detect(text);
      debugPrint("Detected language: $detectedLang");
      
      // 2. Set language with fallback chain
      bool success = await _setLanguageWithFallback(detectedLang);
      
      if (!success) {
        debugPrint("No suitable voice found, using system default");
        // Ensure we at least try to set the language code
        await _tts.setLanguage(detectedLang);
      }
      
      // 3. Clean text (remove markdown)
      final cleanText = text
          .replaceAll(RegExp(r'[*#_`~\[\]()]'), '')
          .replaceAll(RegExp(r'\n+'), '. ')
          .trim();
      
      if (cleanText.isEmpty) return;
      
      // 4. Show player overlay
      OverlayService().showAudioPlayer(context, () async {
        await _tts.stop();
      });
      
      // 5. Speak
      debugPrint("Speaking: ${cleanText.substring(0, min(50, cleanText.length))}...");
      await _tts.speak(cleanText);
      
    } catch (e) {
      debugPrint("TTS Speak Error: $e");
      OverlayService().hideAudioPlayer();
    }
  }
  
  Future<bool> _setLanguageWithFallback(String targetLang) async {
    // Fallback chain: target -> en-US -> en-GB -> system default
    final fallbackChain = [
      targetLang,
      if (targetLang != 'en-US') 'en-US',
      'en-GB',
    ];
    
    for (String lang in fallbackChain) {
      try {
        // Check if language is available
        final isAvailable = await _tts.isLanguageAvailable(lang);
        
        if (isAvailable) {
          await _tts.setLanguage(lang);
          
          // Try to set a specific voice if available
          if (Platform.isAndroid && _availableVoices != null) {
            final voices = _availableVoices![lang] as List?;
            if (voices != null && voices.isNotEmpty) {
              try {
                await _tts.setVoice(voices.first);
                debugPrint("Voice set: ${voices.first['name']} ($lang)");
              } catch (e) {
                debugPrint("Voice selection failed, using language default");
              }
            }
          }
          
          debugPrint("Language set: $lang");
          return true;
        }
      } catch (e) {
        debugPrint("Failed to set $lang: $e");
      }
    }
    
    return false;
  }
  
  Future<void> stop() async {
    await _tts.stop();
    OverlayService().hideAudioPlayer();
  }
  
  void dispose() {
    _tts.stop();
    OverlayService().hideAudioPlayer();
  }
}

// --- MAIN PAGE ---
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

  // --- TEXT TO SPEECH MANAGER ---
  late TTSManager _ttsManager;

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
    
    // Initialize TTS Manager
    _ttsManager = TTSManager();
    _ttsManager.initialize();
    
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
    _ttsManager.dispose();
    super.dispose();
  }

  // --- TTS HELPER ---
  Future<void> _speak(String text) async {
    await _ttsManager.speak(context, text);
  }
  
  // --- ACTION HANDLERS ---
  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    OverlayService().showTopNotification(context, "Copied to clipboard", Icons.copy_rounded, (){});
  }

  void _shareResponse(String text) {
    Share.share(text);
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
      _allSuggestions.shuffle();
      _activeSuggestions = _allSuggestions.take(3).toList();
      _ttsManager.stop();
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
    
    _ttsManager.stop();

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
        
        // Auto-speak the response
        _speak(aiText);

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

  void _handleHorizontalSwipe(DragEndDetails details) {
    if (details.primaryVelocity! > 0) {
      Scaffold.of(context).openDrawer();
    } else if (details.primaryVelocity! < 0) {
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

    return GestureDetector(
      onHorizontalDragEnd: _handleHorizontalSwipe,
      child: Scaffold(
        body: Stack(
          children: [
            // Background Decoration
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
        height: MediaQuery.of(context).size.height, 
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(height: kToolbarHeight + 40), 
            
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
      padding: const EdgeInsets.fromLTRB(16, kToolbarHeight + 60, 16, 16),
      itemCount: _messages.length + (_isTyping ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _messages.length) {
          return _buildTypingIndicator(theme);
        }
        return _ChatBubble(
          message: _messages[index],
          onSpeak: _speak,
          onCopy: _copyToClipboard,
          onShare: _shareResponse,
        );
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
      padding: EdgeInsets.fromLTRB(12, 12, 16, MediaQuery.of(context).padding.bottom + 12),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
      ),
      child: Row(
        children: [
          // Expanded Input
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
  final Function(String) onSpeak;
  final Function(String) onCopy;
  final Function(String) onShare;

  const _ChatBubble({
    required this.message,
    required this.onSpeak,
    required this.onCopy,
    required this.onShare,
  });

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
            child: Column(
              crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Container(
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
                
                // ACTION BUTTONS FOR AI REPLIES ONLY
                if (!isUser)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0, left: 4.0),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildActionIcon(context, Icons.volume_up_rounded, () => onSpeak(message.text)),
                        SizedBox(width: 16),
                        _buildActionIcon(context, Icons.copy_rounded, () => onCopy(message.text)),
                        SizedBox(width: 16),
                        _buildActionIcon(context, Icons.share_rounded, () => onShare(message.text)),
                      ],
                    ),
                  ),
              ],
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

  Widget _buildActionIcon(BuildContext context, IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(4.0),
        child: Icon(
          icon,
          size: 18,
          color: Theme.of(context).hintColor.withOpacity(0.6),
        ),
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