import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';

class VoiceService {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isAvailable = false;

  Future<bool> initialize() async {
    // Request permission explicitly
    var status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
      debugPrint('Microphone permission denied');
      return false;
    }

    try {
      _isAvailable = await _speech.initialize(
        onStatus: (status) => debugPrint('Voice Status: $status'),
        onError: (error) => debugPrint('Voice Error: ${error.errorMsg}'),
        debugLogging: true,
      );
      return _isAvailable;
    } catch (e) {
      debugPrint('Voice Init Error: $e');
      return false;
    }
  }

  Future<void> startListening({
    required Function(String) onResult,
    required Function(bool) onListeningStateChanged,
  }) async {
    if (!_isAvailable) {
      bool initSuccess = await initialize();
      if (!initSuccess) {
        debugPrint("Speech initialization failed, cannot start listening.");
        return;
      }
    }

    // Jika sedang mendengarkan, jangan mulai lagi
    if (_speech.isListening) return;

    onListeningStateChanged(true);

    await _speech.listen(
      onResult: (val) {
        onResult(val.recognizedWords);
        // Otomatis stop listening jika final result sudah didapat
        if (val.finalResult) {
          onListeningStateChanged(false);
        }
      },
      // PERBAIKAN: Gunakan 'id-ID' (dash) bukan 'id_ID' (underscore)
      localeId: 'id-ID', 
      
      listenOptions: stt.SpeechListenOptions(
        onDevice: false, 
        listenMode: stt.ListenMode.dictation,
        cancelOnError: true, // Ubah ke true agar error mereset state
        partialResults: true,
        autoPunctuation: false,
      ),
      listenFor: const Duration(seconds: 30), 
      pauseFor: const Duration(seconds: 5),  
    );
  }

  Future<void> stopListening() async {
    await _speech.stop();
  }

  bool get isListening => _speech.isListening;
}

final voiceService = VoiceService();