import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';

class VoiceService {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isAvailable = false;

  // Inisialisasi Speech to Text
  Future<bool> initialize() async {
    var status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
      debugPrint('Microphone permission denied');
      return false;
    }

    try {
      _isAvailable = await _speech.initialize(
        onStatus: (status) => debugPrint('Voice Status: $status'),
        onError: (error) => debugPrint('Voice Error: ${error.errorMsg}'), // Debug pesan error lengkap
        debugLogging: true,
      );
      return _isAvailable;
    } catch (e) {
      debugPrint('Voice Init Error: $e');
      return false;
    }
  }

  // Mulai mendengarkan (FIXED FOR LANGUAGE ERROR)
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
      },
      // Gunakan localeId jika yakin device support, jika ragu bisa dikosongkan (auto detect)
      localeId: 'id_ID', 
      
      listenOptions: stt.SpeechListenOptions(
        // --- PERBAIKAN UTAMA ---
        onDevice: false, // Ubah ke FALSE agar tidak error jika bahasa offline tidak ada
        // -----------------------
        listenMode: stt.ListenMode.dictation, // Mode dikte (lebih sabar menunggu)
        cancelOnError: false, 
        partialResults: true,
        autoPunctuation: false,
      ),

      // Parameter Durasi
      // Saat online, pauseFor terlalu panjang bisa diputus server, 
      // jadi kita set moderate (5 detik hening = stop)
      listenFor: const Duration(seconds: 30), 
      pauseFor: const Duration(seconds: 5),  
    );
  }

  // Berhenti mendengarkan
  Future<void> stopListening() async {
    await _speech.stop();
  }

  bool get isListening => _speech.isListening;
}

final voiceService = VoiceService();