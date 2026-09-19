import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/services.dart';
import 'package:screen_capture_event/screen_capture_event.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'feature_manager.dart';

/// Production-grade screen protection service with extreme security.
///
/// Whether protection is on is controlled from the admin dashboard
/// (Feature Control -> "Block Screenshots & Recording"), stored by the backend
/// as the platform feature `feature_block_screenshots` (`GET /v1/feature`,
/// value `'1'`/`'0'`). The policy fails closed: when the value is unknown
/// (never fetched, missing key, fetch failure) the app stays protected.
class ScreenProtectionService {
  static final ScreenProtectionService _instance = ScreenProtectionService._internal();
  factory ScreenProtectionService() => _instance;
  ScreenProtectionService._internal();

  static const MethodChannel _channel = MethodChannel('com.learnoo.screen_protection');
  static const EventChannel _eventChannel = EventChannel('com.learnoo.screen_protection/events');

  /// Dashboard keys for the "Block Screenshots & Recording" toggle. The web
  /// dashboard writes `feature_*`; `enable_*` is the legacy alias.
  static const List<String> dashboardKeys = [
    'feature_block_screenshots',
    'enable_block_screenshots',
  ];

  /// Last dashboard value seen, so the policy survives restarts offline.
  static const String _policyCacheKey = 'screen_protection_policy_enabled';

  final ScreenCaptureEvent _captureEvent = ScreenCaptureEvent();
  final StreamController<bool> _securityStatusController = StreamController<bool>.broadcast();
  final StreamController<bool> _policyController = StreamController<bool>.broadcast();

  bool _isInitialized = false;
  bool _isSecure = false;
  FeatureManager? _boundFeatureManager;

  /// Dashboard policy. Defaults to protected until a value is known.
  bool _policyEnabled = true;

  Stream<bool> get onSecurityStatusChanged => _securityStatusController.stream;
  bool get isSecure => _isSecure;

  /// Emits whenever the dashboard policy changes.
  Stream<bool> get onPolicyChanged => _policyController.stream;

  /// Whether the dashboard currently requires screenshot/recording blocking.
  bool get isPolicyEnabled => _policyEnabled;

  /// Whether protection is actually enforced on this build: the dashboard
  /// policy, except in debug builds (see [screenCaptureAllowed]).
  bool get isProtectionActive => _policyEnabled && !screenCaptureAllowed;

  /// Debug builds only: report the device as safe and never react to
  /// screenshot/recording events, so the app can be screen-recorded for the
  /// Play Console permission-declaration videos. The native side skips
  /// FLAG_SECURE under the same condition (debuggable build). Release builds
  /// are unaffected and always follow the dashboard policy.
  static const bool screenCaptureAllowed = kDebugMode;

  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;

    await _loadCachedPolicy();
    await _pushPolicyToNative();

    if (screenCaptureAllowed) {
      _resetSecurityStatus();
      return;
    }

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

    unawaited(_checkInitialStatus());
  }

  /// Follow the dashboard value held by [manager], now and whenever the
  /// features are refreshed.
  void bindFeatureManager(FeatureManager manager) {
    if (identical(_boundFeatureManager, manager)) return;
    _boundFeatureManager?.removeListener(_onFeaturesChanged);
    _boundFeatureManager = manager;
    manager.addListener(_onFeaturesChanged);
    _onFeaturesChanged();
  }

  void _onFeaturesChanged() {
    final manager = _boundFeatureManager;
    if (manager == null) return;
    unawaited(setPolicyEnabled(resolvePolicy(manager)));
  }

  /// Resolve the dashboard policy from the feature list, failing closed.
  ///
  /// A key that is present decides the policy. When no key is present, the
  /// last known dashboard value is kept (which itself defaults to protected).
  bool resolvePolicy(FeatureManager manager) {
    for (final key in dashboardKeys) {
      if (manager.hasFeature(key)) return manager.isEnabled(key);
    }
    return _policyEnabled;
  }

  /// Apply a dashboard policy value: persist it and update native protection.
  Future<void> setPolicyEnabled(bool enabled) async {
    if (enabled == _policyEnabled) {
      // Still re-assert natively so the window flag matches after restarts.
      await _pushPolicyToNative();
      return;
    }
    _policyEnabled = enabled;
    debugPrint('[ScreenProtection] Dashboard policy: ${enabled ? 'protected' : 'allowed'}');
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_policyCacheKey, enabled);
    } catch (e) {
      debugPrint('[ScreenProtection] Failed to cache policy: $e');
    }
    await _pushPolicyToNative();
    _policyController.add(enabled);
    if (!isProtectionActive) {
      // Clear any breach overlay raised while protection was on.
      _resetSecurityStatus();
    } else if (_isInitialized && !screenCaptureAllowed) {
      unawaited(_checkInitialStatus());
    }
  }

  Future<void> _loadCachedPolicy() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _policyEnabled = prefs.getBool(_policyCacheKey) ?? true;
    } catch (e) {
      debugPrint('[ScreenProtection] Failed to read cached policy: $e');
      _policyEnabled = true;
    }
  }

  /// Native sides persist the value themselves (Android SharedPreferences,
  /// iOS UserDefaults) so it applies before Dart runs on the next cold start.
  Future<void> _pushPolicyToNative() async {
    try {
      await _channel.invokeMethod(
        _policyEnabled ? 'enableGlobalProtection' : 'disableGlobalProtection',
      );
    } on MissingPluginException {
      // Platform without the native channel (e.g. tests/desktop).
    } on PlatformException catch (e) {
      debugPrint('[ScreenProtection] Native policy update failed: ${e.code}');
    }
  }

  void _handleSecurityBreach() {
    if (!isProtectionActive) return;
    _isSecure = false;
    _securityStatusController.add(false);
  }

  void _resetSecurityStatus() {
    _isSecure = true;
    _securityStatusController.add(true);
  }

  Future<void> _checkInitialStatus() async {
    try {
      final status = await getProtectionStatus();
      _isSecure = !isProtectionActive ||
          (!(status['isRecording'] ?? false) && !(status['isJailbroken'] ?? false));
    } catch (e) {
      debugPrint('[ScreenProtection] Status check failed: $e');
      return;
    }
    _securityStatusController.add(_isSecure);
  }

  Future<Map<String, dynamic>> getProtectionStatus() async {
    if (screenCaptureAllowed) {
      return {
        'isGlobalEnabled': false,
        'isSecure': false,
        'isRecording': false,
        'isJailbroken': false,
        'isMultiWindow': false,
      };
    }
    final result = await _channel.invokeMethod<Map<dynamic, dynamic>>('getProtectionStatus');
    return result?.cast<String, dynamic>() ?? {};
  }

  Future<bool> detectSuspiciousApps() async {
    if (!isProtectionActive || !Platform.isAndroid) return false;
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
