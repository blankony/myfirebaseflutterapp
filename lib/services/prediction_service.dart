import 'package:cloud_firestore/cloud_firestore.dart';

class PredictionService {
  // --- 1. PERSONALIZED KNOWLEDGE BASE (Markov Chain) ---
  final Map<String, Map<String, int>> _userMarkovChain = {};

  final Map<String, List<String>> _globalPhraseDatabase = {
    'selamat': ['pagi', 'siang', 'malam', 'datang', 'jalan', 'ulang tahun'],
    'good': ['morning', 'night', 'luck', 'job', 'vibes', 'day'],
    'tomorrow': ['is monday', 'is friday', 'will be better'],
    'kuliah': ['umum', 'pengganti', 'libur', 'offline', 'online'],
    'politeknik': ['negeri jakarta'],
    'terima': ['kasih', 'kasih banyak'],
  };

  // --- 2. LEARNING ENGINE ---
  void learnFromUserPosts(List<String> posts) {
    _userMarkovChain.clear();
    for (String post in posts) {
      String cleanPost = post.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '');
      List<String> words = cleanPost.split(RegExp(r'\s+'));

      for (int i = 0; i < words.length - 1; i++) {
        String current = words[i];
        String next = words[i + 1];
        if (!_userMarkovChain.containsKey(current)) {
          _userMarkovChain[current] = {};
        }
        _userMarkovChain[current]![next] = (_userMarkovChain[current]![next] ?? 0) + 1;
      }
    }
  }

  // --- 3. PREDICTIVE TEXT (Recursive Sentence Generation) ---
  Future<String?> getLocalPrediction(String currentText) async {
    if (currentText.trim().isEmpty) return null;

    final String text = currentText.toLowerCase();
    final List<String> words = text.trim().split(RegExp(r'\s+'));
    final String lastWord = words.last;

    String? personalizedPrediction = _generateChain(lastWord);
    
    if (personalizedPrediction == null && _globalPhraseDatabase.containsKey(lastWord)) {
      personalizedPrediction = _globalPhraseDatabase[lastWord]!.first;
    } else if (personalizedPrediction == null) {
      for (var key in _globalPhraseDatabase.keys) {
        if (key.startsWith(lastWord) && key != lastWord) {
          return key.substring(lastWord.length);
        }
      }
    }
    return personalizedPrediction;
  }

  String? _generateChain(String startWord) {
    if (!_userMarkovChain.containsKey(startWord)) return null;

    final StringBuffer prediction = StringBuffer();
    String current = startWord;
    int wordsAdded = 0;
    const int maxPredictionLength = 5;

    while (wordsAdded < maxPredictionLength) {
      final nextCandidates = _userMarkovChain[current];
      if (nextCandidates == null || nextCandidates.isEmpty) break;
      String bestNext = nextCandidates.entries.reduce((a, b) => a.value > b.value ? a : b).key;
      prediction.write("$bestNext ");
      current = bestNext;
      wordsAdded++;
    }
    return prediction.isEmpty ? null : prediction.toString().trim();
  }

  // --- 4. TRENDING ALGORITHM (Document Frequency + Deduplication) ---
  List<Map<String, dynamic>> analyzeTrendingTopics(List<QueryDocumentSnapshot> posts) {
    // Map Phrase -> Set of unique Post IDs (Document Frequency)
    final Map<String, Set<String>> phraseDocMap = {};
    
    final Set<String> stopWords = {
      'the', 'and', 'is', 'to', 'in', 'of', 'for', 'on', 'at', 'this',
      'di', 'dan', 'yang', 'ini', 'itu', 'ke', 'dari', 'ada', 'dengan', 
      'untuk', 'yg', 'gak', 'ya', 'aja', 'si', 'saya', 'aku', 'bisa', 'mau',
      'banget', 'sama', 'sudah', 'lagi', 'apa', 'kapan', 'dimana'
    };

    for (var doc in posts) {
      final data = doc.data() as Map<String, dynamic>;
      final text = (data['text'] ?? '').toString().toLowerCase();
      final postId = doc.id;
      
      // Clean: Keep alphanumeric, spaces, and hashtags
      final cleanText = text.replaceAll(RegExp(r'[^\w\s#]'), '');
      final words = cleanText.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

      for (int i = 0; i < words.length; i++) {
        // A. Hashtags (Always count)
        if (words[i].startsWith('#')) {
          phraseDocMap.putIfAbsent(words[i], () => {}).add(postId);
        }

        // B. N-Grams (2 and 3 words)
        // Only consider if not stop words
        if (i < words.length - 1) {
          if (!stopWords.contains(words[i]) && !stopWords.contains(words[i+1])) {
             String bigram = "${words[i]} ${words[i+1]}";
             phraseDocMap.putIfAbsent(bigram, () => {}).add(postId);
          }
        }
        if (i < words.length - 2) {
          // Allow middle stop words for sentences like "tomorrow is monday"
          String trigram = "${words[i]} ${words[i+1]} ${words[i+2]}";
          phraseDocMap.putIfAbsent(trigram, () => {}).add(postId);
        }
      }
    }

    // Convert to List and Filter Noise
    var candidates = phraseDocMap.entries
        .map((e) => {'tag': e.key, 'count': e.value.length})
        // Filter: Must appear in at least 2 different posts (unless hashtag)
        .where((e) => (e['count'] as int) > 1 || (e['tag'] as String).startsWith('#'))
        .toList();

    // Sort: Primary by Count (Desc), Secondary by Length (Desc) 
    // We prefer longer phrases if counts are equal
    candidates.sort((a, b) {
      int countCompare = (b['count'] as int).compareTo(a['count'] as int);
      if (countCompare != 0) return countCompare;
      return (b['tag'] as String).length.compareTo((a['tag'] as String).length);
    });

    // Deduplication (Subset Removal)
    // If "Tomorrow is Monday" is accepted, ignore "is Monday"
    final List<Map<String, dynamic>> finalTrends = [];
    
    for (var candidate in candidates) {
      String tag = candidate['tag'] as String;
      
      // Check if this tag is a substring of any already accepted trend
      bool isRedundant = false;
      for (var accepted in finalTrends) {
        String acceptedTag = accepted['tag'] as String;
        if (acceptedTag.contains(tag)) {
          isRedundant = true;
          break;
        }
      }

      if (!isRedundant) {
        finalTrends.add(candidate);
      }
      
      if (finalTrends.length >= 10) break;
    }

    return finalTrends;
  }

  // --- 5. DISCOVER ALGORITHM (Exploration & Novelty) ---
  // Prioritizes: Viral Content, Users NOT followed, Randomness
  List<QueryDocumentSnapshot> getDiscoverRecommendations(
    List<QueryDocumentSnapshot> allPosts, 
    String currentUserId,
    List<dynamic> followingList
  ) {
    List<Map<String, dynamic>> scoredPosts = [];

    for (var doc in allPosts) {
      final data = doc.data() as Map<String, dynamic>;
      final authorId = data['userId'];
      
      // Filter 1: Strictly exclude own posts
      if (authorId == currentUserId) continue;
      
      // Filter 2: Strictly exclude people I already follow (This is for discovery!)
      if (followingList.contains(authorId)) continue;

      double score = 0.0;

      // Factor 1: Engagement (Viral Factor)
      final int likes = (data['likes'] as Map?)?.length ?? 0;
      final int comments = data['commentCount'] ?? 0;
      score += (likes * 2.0) + (comments * 3.0); // Heavy weight on engagement

      // Factor 2: Recency (Lower weight than Recommended, allow evergreen viral posts)
      final Timestamp? ts = data['timestamp'];
      if (ts != null) {
        final hoursAgo = DateTime.now().difference(ts.toDate()).inHours;
        if (hoursAgo < 24) score += 20; // Bonus for today's viral hits
        else score += (100.0 / (hoursAgo + 5)); // Gentle decay
      }

      // Factor 3: Media Bonus (Visuals are better for discovery)
      if (data['mediaUrl'] != null) score += 15.0;

      scoredPosts.add({'doc': doc, 'score': score});
    }

    // Sort Descending
    scoredPosts.sort((a, b) => (b['score'] as double).compareTo(a['score'] as double));

    return scoredPosts.map((e) => e['doc'] as QueryDocumentSnapshot).toList();
  }

  // --- 6. RECOMMENDED ALGORITHM (Relevance & Familiarity) ---
  // Prioritizes: Friends, Interests, Recent
  List<QueryDocumentSnapshot> getPersonalizedRecommendations(
    List<QueryDocumentSnapshot> allPosts, 
    Map<String, dynamic> userProfile,
    String currentUserId
  ) {
    final userDept = userProfile['department'] as String?;
    final following = List<String>.from(userProfile['following'] ?? []);
    final Map<String, List<String>> deptKeywords = {
      'Teknik Sipil': ['beton', 'gedung', 'konstruksi', 'sipil'],
      'Teknik Mesin': ['mesin', 'energi', 'otomotif'],
      'Teknik Elektro': ['elektro', 'listrik', 'iot'],
      'Teknik Informatika & Komputer': ['coding', 'flutter', 'tik', 'komputer', 'program', 'bug'],
      'Akuntansi': ['akuntansi', 'keuangan', 'saham'],
      'Administrasi Niaga': ['bisnis', 'marketing', 'administrasi'],
      'Teknik Grafika & Penerbitan': ['desain', 'grafis', 'media'],
    };
    final interests = deptKeywords[userDept] ?? [];

    List<Map<String, dynamic>> scoredPosts = [];

    for (var doc in allPosts) {
      final data = doc.data() as Map<String, dynamic>;
      final authorId = data['userId'];
      
      if (authorId == currentUserId) continue;

      double score = 0.0; 

      // 1. Social (+50) - Strong bias for friends
      if (following.contains(authorId)) score += 50.0;

      // 2. Relevance (+30) - Bias for my major
      final text = (data['text'] ?? '').toString().toLowerCase();
      for (var keyword in interests) {
        if (text.contains(keyword)) {
          score += 30.0;
          break;
        }
      }

      // 3. Recency (High Decay) - We want *fresh* news from friends
      final Timestamp? ts = data['timestamp'];
      if (ts != null) {
        final hoursAgo = DateTime.now().difference(ts.toDate()).inHours;
        score += (80.0 / (hoursAgo + 1)); 
      }

      scoredPosts.add({'doc': doc, 'score': score});
    }

    scoredPosts.sort((a, b) => (b['score'] as double).compareTo(a['score'] as double));
    return scoredPosts.map((e) => e['doc'] as QueryDocumentSnapshot).toList();
  }
}