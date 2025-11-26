import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class PredictionService {
  late GenerativeModel _model;
  final String _apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';

  // --- NARROW AI DATABASE (Simple Local Dictionary) ---
  final Map<String, List<String>> _postPhrases = {
    'selamat': ['pagi', 'siang', 'malam', 'datang', 'jalan', 'ulang tahun'],
    'good': ['morning', 'night', 'luck', 'job', 'vibes', 'day'],
    'info': ['terbaru', 'penting', 'akademik', 'lomba', 'beasiswa'],
    'kuliah': ['umum', 'pengganti', 'libur', 'offline', 'online'],
    'tugas': ['akhir', 'kelompok', 'proyek', 'harian'],
    'mahasiswa': ['baru', 'berprestasi', 'pnj', 'teknik'],
    'politeknik': ['negeri jakarta', 'negeri', 'kreatif'],
    'seminar': ['nasional', 'internasional', 'proposal', 'hasil'],
    'terima': ['kasih', 'kasih banyak', 'kasih sebelumnya'],
    'mohon': ['bantuan', 'info', 'maaf', 'perhatian'],
    'kampus': ['merdeka', 'biru', 'kita', 'pnj'],
    'jurusan': ['teknik', 'akuntansi', 'administrasi', 'bisnis'],
    'ukm': ['terbaru', 'latihan', 'pendaftaran'],
    'dosen': ['pengampu', 'pembimbing', 'wali'],
    'praktikum': ['lab', 'laporan', 'dikerjakan'],
  };

  final Map<String, List<String>> _searchPhrases = {
    'user': ['profile', 'settings', 'account'],
    'post': ['new', 'trending', 'latest'],
    'sapa': ['pnj', 'kampus', 'mahasiswa'],
    'teknik': ['informatika', 'mesin', 'elektro', 'sipil'],
    'akuntansi': ['keuangan', 'manajemen'],
    'admin': ['instrasi niaga', 'kantor'],
  };

  // Knowledge Base for Personalization (Department Keywords)
  final Map<String, List<String>> _departmentKeywords = {
    'Teknik Sipil': ['sipil', 'konstruksi', 'beton', 'jembatan', 'gedung', 'ts'],
    'Teknik Mesin': ['mesin', 'energi', 'alat berat', 'manufaktur', 'tm'],
    'Teknik Elektro': ['elektro', 'listrik', 'telekomunikasi', 'instrumentasi', 'te'],
    'Teknik Informatika & Komputer': ['koding', 'coding', 'program', 'software', 'jaringan', 'tik', 'ti', 'komputer', 'app'],
    'Akuntansi': ['akuntansi', 'keuangan', 'pajak', 'saham', 'ak'],
    'Administrasi Niaga': ['bisnis', 'mice', 'event', 'kantor', 'an', 'administrasi'],
    'Teknik Grafika & Penerbitan': ['desain', 'grafis', 'cetak', 'penerbitan', 'tgp', 'kreatif'],
  };

  PredictionService() {
    if (_apiKey.isNotEmpty) {
      _model = GenerativeModel(model: 'gemini-1.5-flash', apiKey: _apiKey);
    }
  }

  // --- AUTOCOMPLETE / PREDICTION ---
  Future<String?> getCompletion(String currentText, String contextType) async {
    final text = currentText.trim().toLowerCase();
    if (text.length < 3) return null;

    // 1. Try Generative AI (if available)
    try {
      if (_apiKey.isNotEmpty) {
        final response = await _model.generateContent([
          Content.text(_buildPrompt(currentText, contextType))
        ]).timeout(const Duration(seconds: 2));

        final aiResult = response.text?.trim();
        if (aiResult != null && aiResult.isNotEmpty) {
          return aiResult.replaceAll('"', '').replaceAll("'", "");
        }
      }
    } catch (e) {
      // Fallback to Narrow AI
    }

    // 2. Narrow AI Fallback
    return _getLocalPrediction(text, contextType);
  }

  String _buildPrompt(String text, String type) {
    if (type == 'post') {
      return """
        Sebagai asisten PNJ, lengkapi kalimat postingan ini (max 5 kata) dengan tone mahasiswa:
        '$text'
      """;
    }
    return "Complete search query: '$text'";
  }

  String? _getLocalPrediction(String text, String contextType) {
    final words = text.split(' ');
    final lastWord = words.last;
    final db = (contextType == 'search') ? _searchPhrases : _postPhrases;

    if (db.containsKey(lastWord)) return db[lastWord]!.first;

    for (var key in db.keys) {
      if (key.startsWith(lastWord) && key != lastWord) {
        final suffix = key.substring(lastWord.length);
        final nextWords = db[key]?.first ?? ""; 
        return "$suffix $nextWords".trim();
      }
    }
    return null;
  }

  // --- TRENDING ENGINE (NARROW AI) ---
  // Analyzes a list of posts to find "Buzzing" topics
  List<Map<String, dynamic>> analyzeTrendingTopics(List<QueryDocumentSnapshot> posts) {
    final Map<String, int> frequencyMap = {};
    final Set<String> stopWords = {
      'THE', 'AND', 'IS', 'TO', 'IN', 'OF', 'FOR', 'WITH', 'ON', 'AT', 'THIS', 'THAT',
      'DI', 'DAN', 'YANG', 'INI', 'ITU', 'AKU', 'KAMU', 'KE', 'DARI', 'ADA', 'DENGAN', 
      'UNTUK', 'YG', 'GAK', 'YA', 'AJA', 'SI', 'SAYA', 'KITA', 'MEREKA', 'APA', 'KAPAN'
    };

    for (var doc in posts) {
      final data = doc.data() as Map<String, dynamic>;
      final text = (data['text'] ?? '').toString();
      
      // 1. Hashtags (High Weight: +5)
      final hashtagRegex = RegExp(r'\#[a-zA-Z0-9_]+');
      final hashtags = hashtagRegex.allMatches(text).map((m) => m.group(0)!).toList();
      for (var tag in hashtags) {
        final normalized = tag.toUpperCase();
        frequencyMap[normalized] = (frequencyMap[normalized] ?? 0) + 5;
      }

      // 2. Capitalized Keywords (Medium Weight: +1)
      // Heuristic: Important nouns/names often capitalized (e.g., PNJ, BEM, Kantin)
      final keywordRegex = RegExp(r'\b[A-Z][a-zA-Z0-9]+\b');
      final words = keywordRegex.allMatches(text).map((m) => m.group(0)!).toList();

      for (var word in words) {
        final normalized = word.toUpperCase();
        if (normalized.length > 2 && !stopWords.contains(normalized)) {
          frequencyMap[normalized] = (frequencyMap[normalized] ?? 0) + 1;
        }
      }
    }

    final sortedEntries = frequencyMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return sortedEntries.map((e) => {'tag': e.key, 'count': e.value}).toList();
  }

  // --- PERSONALIZED RECOMMENDATION ENGINE (NARROW AI) ---
  // Ranks posts based on user profile relevance and engagement
  List<QueryDocumentSnapshot> getPersonalizedRecommendations(
    List<QueryDocumentSnapshot> allPosts, 
    Map<String, dynamic> userProfile,
    String currentUserId
  ) {
    final userDept = userProfile['department'] as String?;
    final userInterests = _departmentKeywords[userDept] ?? [];
    final following = List<String>.from(userProfile['following'] ?? []);

    List<Map<String, dynamic>> scoredPosts = [];

    for (var doc in allPosts) {
      final data = doc.data() as Map<String, dynamic>;
      final authorId = data['userId'];
      
      // Filter: Skip own posts
      if (authorId == currentUserId) continue;

      double score = 1.0; // Base score

      // 1. Recency Decay (Newer is better)
      final Timestamp? ts = data['timestamp'];
      if (ts != null) {
        final hoursAgo = DateTime.now().difference(ts.toDate()).inHours;
        score += (50.0 / (hoursAgo + 5)); // Curve favors very recent posts
      }

      // 2. Social Connection (Friends of Friends / Following)
      if (following.contains(authorId)) {
        score += 20.0; // High boost for followed users
      }

      // 3. Content Relevance (Personalization)
      final text = (data['text'] ?? '').toString().toLowerCase();
      
      // Boost if text contains department-specific keywords (e.g., 'Coding' for TI anak)
      for (var keyword in userInterests) {
        if (text.contains(keyword)) {
          score += 15.0; 
          break; // Boost once per post
        }
      }

      // Boost if explicit PNJ mentions
      if (text.contains('pnj') || text.contains('politeknik')) {
        score += 5.0;
      }

      // 4. Viral/Buzz Factor
      final likes = (data['likes'] as Map?)?.length ?? 0;
      final comments = data['commentCount'] ?? 0;
      
      // Logarithmic boost prevents older viral posts from dominating forever
      score += (likes * 0.5) + (comments * 1.0);

      scoredPosts.add({'doc': doc, 'score': score});
    }

    // Sort descending by score
    scoredPosts.sort((a, b) => (b['score'] as double).compareTo(a['score'] as double));

    return scoredPosts.map((e) => e['doc'] as QueryDocumentSnapshot).toList();
  }
}