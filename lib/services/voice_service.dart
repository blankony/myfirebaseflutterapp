import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';

class VoiceService {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isAvailable = false;

  // Inisialisasi Speech to Text
  Future<bool> initialize() async {
    // Request permission first
    var status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
      debugPrint('Microphone permission denied');
      return false;
    }

    try {
      _isAvailable = await _speech.initialize(
        onStatus: (status) => debugPrint('Voice Status: $status'),
        onError: (error) => debugPrint('Voice Error: $error'),
      );
      return _isAvailable;
    } catch (e) {
      debugPrint('Voice Init Error: $e');
      return false;
    }
  }

  // Mulai mendengarkan
  Future<void> startListening({
    required Function(String) onResult,
    required Function(bool) onListeningStateChanged,
  }) async {
    if (!_isAvailable) {
      bool initSuccess = await initialize();
      if (!initSuccess) return;
    }

    onListeningStateChanged(true);

    await _speech.listen(
      onResult: (val) {
        onResult(val.recognizedWords);
        if (val.hasConfidenceRating && val.confidence > 0) {
          debugPrint('Confidence: ${val.confidence}');
        }
        // Jika final result, stop listening status
        if (val.finalResult) {
          onListeningStateChanged(false);
        }
      },
      localeId: 'id_ID', 
      cancelOnError: true,
      partialResults: true,
      listenFor: const Duration(seconds: 10),
      pauseFor: const Duration(seconds: 3),
    );
  }

  Future<void> stopListening() async {
    await _speech.stop();
  }

  bool get isListening => _speech.isListening;
}

final voiceService = VoiceService();