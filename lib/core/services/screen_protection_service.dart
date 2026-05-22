import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:screen_capture_event/screen_capture_event.dart';

/// Production-grade screen protection service with extreme security
class ScreenProtectionService {
  static final ScreenProtectionService _instance = ScreenProtectionService._internal();
  factory ScreenProtectionService() => _instance;
  ScreenProtectionService._internal();

  static const MethodChannel _channel = MethodChannel('com.learnoo.screen_protection');
  static const EventChannel _eventChannel = EventChannel('com.learnoo.screen_protection/events');

  final ScreenCaptureEvent _captureEvent = ScreenCaptureEvent();
  final StreamController<bool> _securityStatusController = StreamController<bool>.broadcast();
  
  bool _isInitialized = false;
  bool _isSecure = false;
  
  Stream<bool> get onSecurityStatusChanged => _securityStatusController.stream;
  bool get isSecure => _isSecure;

  Future<void> initialize() async {
    if (_isInitialized) return;

    // Hybrid Detection: Plugin + Native
    _captureEvent.addScreenShotListener((_) => _handleSecurityBreach());
    _captureEvent.addScreenRecordListener((recording) {
      if (recording) _handleSecurityBreach();
    });
    _captureEvent.watch();

    _eventChannel.receiveBroadcastStream().listen((data) {
      if (data is Map && (data['event'] == 'recording_started' || data['event'] == 'screenshot')) {
        _handleSecurityBreach();
      } else if (data is Map && data['event'] == 'recording_stopped') {
        _resetSecurityStatus();
      }
    });

    _isInitialized = true;
    _checkInitialStatus();
  }

  void _handleSecurityBreach() {
    _isSecure = false;
    _securityStatusController.add(false);
  }

  void _resetSecurityStatus() {
    _isSecure = true;
    _securityStatusController.add(true);
  }

  Future<void> _checkInitialStatus() async {
    final status = await getProtectionStatus();
    _isSecure = !(status['isRecording'] ?? false) && !(status['isJailbroken'] ?? false);
    _securityStatusController.add(_isSecure);
  }

  Future<void> enableGlobalProtection() async {
    await _channel.invokeMethod('enableGlobalProtection');
  }

  Future<void> disableGlobalProtection() async {
    await _channel.invokeMethod('disableGlobalProtection');
  }

  Future<Map<String, dynamic>> getProtectionStatus() async {
    final result = await _channel.invokeMethod<Map<dynamic, dynamic>>('getProtectionStatus');
    return result?.cast<String, dynamic>() ?? {};
  }

  Future<bool> detectSuspiciousApps() async {
    if (!Platform.isAndroid) return false;
    final List<dynamic>? apps = await _channel.invokeMethod('detectSuspiciousApps');
    return apps != null && apps.isNotEmpty;
  }

  Future<bool> isUsageStatsPermissionGranted() async {
    if (!Platform.isAndroid) return true;
    return await _channel.invokeMethod('isUsageStatsPermissionGranted');
  }

  Future<void> requestUsageStatsPermission() async {
    if (Platform.isAndroid) {
      await _channel.invokeMethod('requestUsageStatsPermission');
    }
  }
}
