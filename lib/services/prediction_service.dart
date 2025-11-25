import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class PredictionService {
  late GenerativeModel _model;
  final String _apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';

  // --- NARROW AI DATABASE (Simple Local Dictionary) ---
  // Database sederhana untuk fallback jika AI gagal/lelet
  final Map<String, List<String>> _postPhrases = {
    'selamat': ['pagi', 'siang', 'malam', 'datang', 'jalan', 'ulang tahun'],
    'good': ['morning', 'night', 'luck', 'job', 'vibes', 'day'],
    'info': ['terbaru', 'penting', 'akademik', 'lomba', 'beasiswa'],
    'kuliah': ['umum', 'pengganti', 'libur', 'offline', 'online'],
    'tugas': ['akhir', 'kelompok', 'proyek', 'harian'],
    'mahasiswa': ['baru', 'berprestasi', 'pnj', 'teknik'],
    'politeknik': ['negeri jakarta', 'negeri', 'kreatif'],
    'seminar': ['nasional', 'internasional', 'proposal', 'hasil'],
    'how': ['are you', 'to make', 'is it', 'much'],
    'what': ['is this', 'happened', 'are you doing'],
    'terima': ['kasih', 'kasih banyak', 'kasih sebelumnya'],
    'mohon': ['bantuan', 'info', 'maaf', 'perhatian'],
    // PENAMBAHAN: Frasa spesifik kampus PNJ
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

  PredictionService() {
    if (_apiKey.isEmpty) {
      // NOTE: This throws an exception if the key is missing, which is good practice.
      // However, the Narrow AI fallback allows the app to run without the key for basic functionality.
    }
    // Menggunakan flash model untuk kecepatan
    _model = GenerativeModel(model: 'gemini-1.5-flash', apiKey: _apiKey);
  }

  // Fungsi utama: Coba AI dulu, kalau gagal/lama -> Local
  Future<String?> getCompletion(String currentText, String contextType) async {
    final text = currentText.trim().toLowerCase();
    if (text.length < 3) return null;

    try {
      // 1. COBA GEMINI (dengan Timeout 2 detik)
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
      // 2. JIKA ERROR / TIMEOUT -> GUNAKAN LOCAL FALLBACK
      // print("Gemini failed/slow ($e), switching to Narrow AI...");
    }

    // Kembalikan hasil dari database lokal
    return _getLocalPrediction(text, contextType);
  }

  String _buildPrompt(String text, String type) {
    if (type == 'post') {
      // ENHANCED PROMPT: Instruksi yang lebih spesifik untuk konteks PNJ
      return """
        Sebagai asisten cerdas untuk mahasiswa Politeknik Negeri Jakarta (PNJ), berikan kelanjutan kalimat yang singkat dan relevan (maksimal 7 kata) untuk postingan media sosial di lingkungan kampus.
        Topik harus bersemangat, informatif (akademik/organisasi), atau santai (kehidupan kampus).
        Jangan gunakan markdown atau tanda kutip. Berikan HANYA teks.

        Kalimat saat ini: '$text'
      """;
    } else if (type == 'search') {
      return "Autocomplete search query (max 3 words). Return ONLY text: '$text'";
    }
    return "Complete: '$text'";
  }

  // Logic Narrow AI (Pencocokan Kata Sederhana)
  String? _getLocalPrediction(String text, String contextType) {
    // Ambil kata terakhir untuk dicocokkan
    final words = text.split(' ');
    final lastWord = words.last;
    
    // Pilih database berdasarkan konteks
    final db = (contextType == 'search') ? _searchPhrases : _postPhrases;

    // 1. Cek 'Exact Match' pada key database
    if (db.containsKey(lastWord)) {
      final suggestions = db[lastWord];
      if (suggestions != null && suggestions.isNotEmpty) {
        // Ambil saran pertama (atau bisa di-random)
        return suggestions.first;
      }
    }

    // 2. Cek 'Partial Match' (jika user baru ngetik setengah kata: "selam")
    for (var key in db.keys) {
      if (key.startsWith(lastWord) && key != lastWord) {
        // Kembalikan sisa katanya (misal: ngetik "selam", saran "at pagi")
        final suffix = key.substring(lastWord.length);
        // Cek apakah punya lanjutan kata
        final nextWords = db[key]?.first ?? ""; 
        return "$suffix $nextWords".trim();
      }
    }

    return null;
  }
}