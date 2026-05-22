import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

class VoiceWatermarkService {
  static final VoiceWatermarkService _instance = VoiceWatermarkService._internal();
  factory VoiceWatermarkService() => _instance;

  final FlutterTts _flutterTts = FlutterTts();
  Timer? _timer;
  bool _isPlaying = false;
  bool _isInitialized = false;
  String _currentText = '';

  VoiceWatermarkService._internal() {
    _initTts();
  }

  Future<void> _initTts() async {
    try {
      await _flutterTts.setLanguage("en-US");
      await _flutterTts.setSpeechRate(0.5);
      await _flutterTts.setVolume(0.5);
      await _flutterTts.setPitch(1.0);

      _flutterTts.setStartHandler(() {
        _isPlaying = true;
      });

      _flutterTts.setCompletionHandler(() {
        _isPlaying = false;
      });

      _flutterTts.setErrorHandler((msg) {
        debugPrint("TTS Error: $msg");
        _isPlaying = false;
      });

      _isInitialized = true;
    } catch (e) {
      debugPrint("Error initializing TTS: $e");
      _isInitialized = false;
    }
  }

  /// Starts the voice watermark timer
  /// [text] to be spoken
  /// [intervalSeconds] time between each voice overlay
  void start({required String text, required int intervalSeconds}) {
    stop(); // cancel previous timer if any
    
    if (text.trim().isEmpty || intervalSeconds <= 0) return;
    
    _currentText = text;

    // Speak initial
    _speak();
    
    // Set up periodic timer
    _timer = Timer.periodic(Duration(seconds: intervalSeconds), (_) {
      _speak();
    });
  }

  Future<void> _speak() async {
    if (!_isInitialized) {
      await _initTts();
    }

    if (_currentText.isNotEmpty && !_isPlaying) {
      try {
        _isPlaying = true;
        await _flutterTts.speak(_currentText);

        // Safety timeout: reset _isPlaying if completion handler never fires
        Future.delayed(const Duration(seconds: 30), () {
          if (_isPlaying) {
            _isPlaying = false;
          }
        });
      } catch (e) {
        debugPrint("Voice Watermark speak error: $e");
        _isPlaying = false;
      }
    }
  }

  /// Stops current timer and TTS playback
  void stop() {
    _timer?.cancel();
    _timer = null;
    _flutterTts.stop();
    _isPlaying = false;
  }
}
