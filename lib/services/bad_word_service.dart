import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class BadWordService {
  // URL Raw GitHub untuk Badwords (Text format, dipisahkan baris baru)
  static const String _enBadWordsUrl = 
      'https://raw.githubusercontent.com/dikako/list_badword/refs/heads/master/en_badwords.txt';
  
  static const String _idBadWordsUrl = 
      'https://raw.githubusercontent.com/dikako/list_badword/refs/heads/master/id_badwords.txt';

  /// Mengambil daftar badwords dari kedua sumber (EN & ID) dan menggabungkannya
  Future<List<String>> fetchBadWords() async {
    try {
      // Request keduanya secara paralel agar lebih cepat
      final results = await Future.wait([
        _fetchList(_enBadWordsUrl),
        _fetchList(_idBadWordsUrl),
      ]);

      // Gabungkan hasil: results[0] (EN) + results[1] (ID)
      final allWords = [...results[0], ...results[1]];
      
      // Hapus duplikat (jika ada) menggunakan Set
      return allWords.toSet().toList();
      
    } catch (e) {
      debugPrint('Error fetching badwords: $e');
      return [];
    }
  }

  /// Helper untuk mengambil dan memparsing list dari URL text file
  Future<List<String>> _fetchList(String url) async {
    try {
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        // Split berdasarkan baris baru (\n) karena formatnya .txt
        // Trim spasi dan ubah ke lowercase
        return response.body
            .split('\n')
            .map((line) => line.trim().toLowerCase())
            .where((line) => line.isNotEmpty) // Hapus baris kosong
            .toList();
      } else {
        debugPrint('Gagal mengambil dari $url: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      debugPrint('Error request ke $url: $e');
      return [];
    }
  }
}