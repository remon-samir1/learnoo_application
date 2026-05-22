import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../models/watermark_config.dart';
import '../services/voice_watermark_service.dart';
import '../../features/auth/data/auth_repository.dart';

class WatermarkController extends ChangeNotifier {
  final WatermarkConfig config;
  final AuthRepository _authRepository = AuthRepository();
  
  String _displayText = '';
  String get displayText => _displayText;
  String _studentCode = '';
  String _phoneNumber = '';

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  Timer? _movementTimer;
  final Random _random = Random();

  /// Normalized coordinates (0.0 to 1.0)
  double positionX = 0.0;
  double positionY = 0.0;

  WatermarkController({required this.config, String? fallbackText}) {
    _displayText = config.text.isNotEmpty ? config.text : (fallbackText ?? 'Learnoo');
    _initInitialPosition();
    _init();
  }

  void _initInitialPosition() {
    if (config.randomCoordinates) {
      positionX = _random.nextDouble();
      positionY = _random.nextDouble();
    } else {
      switch (config.position) {
        case WatermarkPosition.topLeft:
          positionX = 0.0;
          positionY = 0.0;
          break;
        case WatermarkPosition.topRight:
          positionX = 1.0;
          positionY = 0.0;
          break;
        case WatermarkPosition.bottomLeft:
          positionX = 0.0;
          positionY = 1.0;
          break;
        case WatermarkPosition.bottomRight:
          positionX = 1.0;
          positionY = 1.0;
          break;
        case WatermarkPosition.center:
          positionX = 0.5;
          positionY = 0.5;
          break;
        case WatermarkPosition.full:
          positionX = 0.5;
          positionY = 0.5;
          break;
      }
    }
  }

  Future<void> _init() async {
    if (!config.enabled) {
      _isInitialized = true;
      notifyListeners();
      return;
    }

    if (config.useStudentCode || config.usePhoneNumber) {
      await _fetchUserInfo();
    }

    if (config.voiceEnabled && _displayText.isNotEmpty) {
      VoiceWatermarkService().start(
        text: _displayText,
        intervalSeconds: config.voiceInterval,
      );
    }

    if (config.dynamicPosition) {
      _startMovementTimer();
    }
    
    _isInitialized = true;
    notifyListeners();
  }

  Future<void> _fetchUserInfo() async {
    try {
      final result = await _authRepository.getProfile();
      if (result['success'] == true && result['data'] != null) {
        final attributes = result['data']['attributes'];
        if (attributes != null) {
          // Get student code if enabled
          if (config.useStudentCode) {
            final code = attributes['student_code'];
            if (code != null && code.toString().isNotEmpty) {
              _studentCode = code.toString();
            }
          }

          // Get phone number if enabled
          if (config.usePhoneNumber) {
            final phone = attributes['phone'];
            if (phone != null && phone.toString().isNotEmpty) {
              _phoneNumber = phone.toString();
            }
          }

          // Build display text based on available info
          _buildDisplayText();
        }
      } else {
        // API failed or offline - use cached data
        _loadCachedWatermarkData();
      }
    } catch (e) {
      debugPrint("Error fetching user info for watermark: $e");
      // On error (likely offline), use cached data
      _loadCachedWatermarkData();
    }
  }

  /// Load watermark data from local cache (for offline use)
  void _loadCachedWatermarkData() {
    try {
      final cachedData = _authRepository.getCachedWatermarkData();

      if (config.useStudentCode) {
        final cachedCode = cachedData['student_code'];
        if (cachedCode != null && cachedCode.isNotEmpty) {
          _studentCode = cachedCode;
        }
      }

      if (config.usePhoneNumber) {
        final cachedPhone = cachedData['phone'];
        if (cachedPhone != null && cachedPhone.isNotEmpty) {
          _phoneNumber = cachedPhone;
        }
      }

      _buildDisplayText();
      debugPrint('[Watermark] Using cached data: studentCode=$_studentCode, phone=$_phoneNumber');
    } catch (e) {
      debugPrint("Error loading cached watermark data: $e");
    }
  }

  /// Build display text from student code and phone number
  void _buildDisplayText() {
    final parts = <String>[];
    if (_studentCode.isNotEmpty) {
      parts.add(_studentCode);
    }
    if (_phoneNumber.isNotEmpty) {
      parts.add(_phoneNumber);
    }

    if (parts.isNotEmpty) {
      _displayText = parts.join(' | ');
    } else if (config.text.isNotEmpty) {
      _displayText = config.text;
    }
  }

  void _startMovementTimer() {
    if (config.dynamicInterval <= 0) return;
    
    _movementTimer = Timer.periodic(Duration(seconds: config.dynamicInterval), (_) {
      _switchPosition();
      notifyListeners();
    });
  }

  void _switchPosition() {
    if (config.randomCoordinates) {
      positionX = _random.nextDouble();
      positionY = _random.nextDouble();
    } else {
      final positions = const [
        [0.0, 0.0], [1.0, 0.0], [1.0, 1.0], [0.0, 1.0], [0.5, 0.5], [0.5, 0.5]
      ];
      
      // Find closest position to round correctly due to double precision
      int currentIdx = positions.indexWhere((p) => (p[0] - positionX).abs() < 0.01 && (p[1] - positionY).abs() < 0.01);
      if (currentIdx == -1) currentIdx = 0;
      
      final nextIdx = (currentIdx + 1) % (positions.length - 1); // skip center for predefined movement cycle, unless you want it in cycle.
      positionX = positions[nextIdx][0];
      positionY = positions[nextIdx][1];
    }
  }

  @override
  void dispose() {
    _movementTimer?.cancel();
    VoiceWatermarkService().stop();
    super.dispose();
  }
}
