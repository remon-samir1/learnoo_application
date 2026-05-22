import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:better_player_plus/better_player_plus.dart';
import '../../features/auth/data/auth_repository.dart';
import 'feature_manager.dart';

/// Production-ready audio watermark service for chapter videos.
/// 
/// Features:
/// - Video-position-synced triggering (modulo-based)
/// - Dynamic feature flag control
/// - Duplicate prevention
/// - Overlap prevention
/// - Proper lifecycle management
/// - Zero UI impact
class ChapterAudioWatermarkService {
  final FlutterTts _flutterTts = FlutterTts();
  final AuthRepository _authRepository = AuthRepository();
  final FeatureManager _featureManager = FeatureManager();

  // Timer and state
  Timer? _positionCheckTimer;
  BetterPlayerController? _betterPlayerController;
  
  // Configuration
  int _interval = 0;
  bool _isEnabled = false;
  String _studentCode = '';
  String _watermarkMessage = '';
  
  // Duplicate prevention
  int? _lastTriggeredSecond;
  bool _isSpeaking = false;
  bool _isDisposed = false;
  bool _isInitialized = false;

  /// Initialize TTS engine
  Future<void> init() async {
    if (_isDisposed) return;
    
    try {
      await _flutterTts.setLanguage('en-US');
      await _flutterTts.setSpeechRate(0.5);
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);

      _flutterTts.setStartHandler(() {
        _isSpeaking = true;
      });

      _flutterTts.setCompletionHandler(() {
        _isSpeaking = false;
      });

      _flutterTts.setErrorHandler((msg) {
        debugPrint('[AudioWatermark] TTS Error: $msg');
        _isSpeaking = false;
      });

      _isInitialized = true;
      debugPrint('[AudioWatermark] TTS initialized successfully');
    } catch (e) {
      debugPrint('[AudioWatermark] Error initializing TTS: $e');
    }
  }

  /// Load configuration from feature flags and user data
  /// Note: interval from API is in MINUTES, converted to seconds internally
  Future<void> loadConfiguration() async {
    if (_isDisposed) return;

    try {
      // Check if enabled via feature flag
      _isEnabled = _featureManager.isEnabled('watermark_chapters_voice_enabled');
      
      // Get interval from feature flag (API returns MINUTES, convert to seconds)
      final intervalMinutes = _featureManager.getInt('watermark_chapters_voice_interval', defaultValue: 0);
      _interval = intervalMinutes * 60; // Convert minutes to seconds
      
      debugPrint('[AudioWatermark] Config loaded: enabled=$_isEnabled, interval=${intervalMinutes}min ($_interval sec)');

      // If disabled or invalid interval, don't proceed
      if (!_isEnabled || _interval <= 0) {
        debugPrint('[AudioWatermark] Disabled or invalid interval, skipping user data fetch');
        return;
      }

      // Fetch student code from profile
      await _fetchStudentCode();
      
      // Build watermark message
      _buildWatermarkMessage();
      
    } catch (e) {
      debugPrint('[AudioWatermark] Error loading configuration: $e');
    }
  }

  /// Fetch student code from me API
  Future<void> _fetchStudentCode() async {
    try {
      final result = await _authRepository.getProfile();
      
      if (result['success'] == true && result['data'] != null) {
        final data = result['data'];
        final attributes = data['attributes'];
        
        // Try student_code first
        if (attributes != null && attributes['student_code'] != null) {
          final code = attributes['student_code'].toString();
          if (code.isNotEmpty) {
            _studentCode = code;
            debugPrint('[AudioWatermark] Student code found: $_studentCode');
            return;
          }
        }
        
        // Fallback to user id
        final userId = data['id']?.toString();
        if (userId != null && userId.isNotEmpty) {
          _studentCode = userId;
          debugPrint('[AudioWatermark] Using user ID as fallback: $_studentCode');
          return;
        }
      }
      
      debugPrint('[AudioWatermark] Could not fetch student code');
    } catch (e) {
      debugPrint('[AudioWatermark] Error fetching student code: $e');
    }
  }

  /// Build the watermark message
  void _buildWatermarkMessage() {
    if (_studentCode.isNotEmpty) {
      _watermarkMessage = 'student $_studentCode';
    } else {
      _watermarkMessage = 'This content is protected';
    }
    debugPrint('[AudioWatermark] Message: $_watermarkMessage');
  }

  /// Start watermark tracking using a [BetterPlayerController].
  /// Must call [loadConfiguration] before this.
  void start(BetterPlayerController controller) {
    if (_isDisposed) return;

    // Ensure configuration is loaded
    if (_interval <= 0 || !_isEnabled) {
      debugPrint('[AudioWatermark] Cannot start: not enabled or invalid interval');
      return;
    }

    // Stop any existing tracking
    stop();

    _betterPlayerController = controller;

    // Start position checking timer (1-second precision)
    _positionCheckTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _checkAndTrigger(),
    );

    debugPrint('[AudioWatermark] Started tracking for video');
  }

  /// Stop watermark tracking
  void stop() {
    _positionCheckTimer?.cancel();
    _positionCheckTimer = null;
    _betterPlayerController = null;
    _lastTriggeredSecond = null;

    // Stop any ongoing TTS
    _flutterTts.stop();
    _isSpeaking = false;

    debugPrint('[AudioWatermark] Stopped tracking');
  }

  /// Pause watermark (for temporary pauses like app background)
  void pause() {
    _positionCheckTimer?.cancel();
    _positionCheckTimer = null;
    
    // Don't stop TTS mid-sentence, just don't trigger new ones
    debugPrint('[AudioWatermark] Paused');
  }

  /// Resume watermark after pause
  void resume() {
    if (_betterPlayerController == null || _interval <= 0 || !_isEnabled) return;

    // Restart position checking
    _positionCheckTimer?.cancel();
    _positionCheckTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _checkAndTrigger(),
    );

    debugPrint('[AudioWatermark] Resumed');
  }

  /// Check video position and trigger watermark if needed
  void _checkAndTrigger() async {
    if (_isDisposed || _betterPlayerController == null) return;

    // Safely get the underlying VideoPlayerController from BetterPlayer
    final vc = _betterPlayerController!.videoPlayerController;
    if (vc == null) return;

    // Only trigger if video is playing and initialized (duration > zero = initialized)
    if (vc.value.duration == Duration.zero || !vc.value.isPlaying) return;

    final position = vc.value.position;
    final currentSecond = position.inSeconds;

    // Don't trigger at second 0 (video start)
    if (currentSecond <= 0) return;

    // Check if this second is a trigger point (modulo interval)
    if (currentSecond % _interval != 0) return;

    // Prevent duplicate triggers within the same second
    if (_lastTriggeredSecond == currentSecond) return;

    // Update last triggered second BEFORE triggering to prevent race conditions
    _lastTriggeredSecond = currentSecond;

    // Trigger the watermark
    await _triggerWatermark();
  }

  /// Trigger the audio watermark
  Future<void> _triggerWatermark() async {
    if (_watermarkMessage.isEmpty) return;
    
    try {
      // Prevent overlap: stop any ongoing speech first
      if (_isSpeaking) {
        await _flutterTts.stop();
        // Small delay to ensure TTS engine resets
        await Future.delayed(const Duration(milliseconds: 100));
      }
      
      await _flutterTts.speak(_watermarkMessage);
      debugPrint('[AudioWatermark] Triggered at video second $_lastTriggeredSecond');
    } catch (e) {
      debugPrint('[AudioWatermark] Error triggering watermark: $e');
    }
  }

  /// Dispose the service and clean up resources
  Future<void> dispose() async {
    if (_isDisposed) return;

    _isDisposed = true;

    // Cancel timer
    _positionCheckTimer?.cancel();
    _positionCheckTimer = null;

    // Stop TTS
    await _flutterTts.stop();

    // Clear references
    _betterPlayerController = null;
    _lastTriggeredSecond = null;

    debugPrint('[AudioWatermark] Disposed');
  }

  // Getters for external monitoring
  bool get isEnabled => _isEnabled;
  int get interval => _interval;
  String get studentCode => _studentCode;
  String get watermarkMessage => _watermarkMessage;
  bool get isTracking => _positionCheckTimer != null && _positionCheckTimer!.isActive;
}
