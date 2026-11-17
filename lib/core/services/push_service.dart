import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../network/api_client.dart';
import '../network/api_constants.dart';
import '../session/session_manager.dart';
import 'notification_service.dart';

/// A push message that belongs to a row of the student's notifications list
/// (`App\Support\Push\PushMessage` on the backend puts the row id in
/// `notification_id`). Anything else is not ours to route.
@immutable
class PushPayload {
  const PushPayload({required this.notificationId, this.type, this.courseId});

  final String notificationId;
  final String? type;
  final String? courseId;

  static PushPayload? fromData(Map<String, dynamic> data) {
    final id = data['notification_id']?.toString().trim() ?? '';
    if (id.isEmpty) return null;
    String? text(String key) {
      final value = data[key]?.toString().trim() ?? '';
      return value.isEmpty ? null : value;
    }

    return PushPayload(
      notificationId: id,
      type: text('type'),
      courseId: text('course_id'),
    );
  }
}

/// The phone side of the push provider (Firebase Cloud Messaging).
abstract class PushMessaging {
  /// `fcm` or `hms`, as the backend stores it.
  String get provider;

  Future<bool> requestPermission();

  /// Registers this app install with the provider; the id to send pushes to
  /// then arrives on [onRegistered] (again whenever the provider changes it).
  Future<void> register();
  Stream<String> get onRegistered;
}

/// `POST` / `DELETE /v1/push-tokens`.
abstract class PushTokenApi {
  /// Returns whether the server delivers pushes to this provider now.
  Future<bool> register({
    required String token,
    required String provider,
    required String platform,
  });

  Future<void> unregister(String token);
}

class ApiPushTokenApi implements PushTokenApi {
  const ApiPushTokenApi();

  @override
  Future<bool> register({
    required String token,
    required String provider,
    required String platform,
  }) async {
    final body = await ApiClient().post(
      ApiConstants.pushTokens,
      body: {'token': token, 'provider': provider, 'platform': platform},
      // A failed registration must never sign the student out.
      skipAuthRedirect: true,
    );
    final data = body is Map ? body['data'] : null;
    return data is Map && data['push_enabled'] == true;
  }

  @override
  Future<void> unregister(String token) async {
    await ApiClient().delete(
      ApiConstants.pushTokens,
      body: {'token': token},
      skipAuthRedirect: true,
    );
  }
}

class _FirebasePushMessaging implements PushMessaging {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  @override
  String get provider => 'fcm';

  @override
  Future<bool> requestPermission() async {
    final settings = await _messaging.requestPermission();
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  // FCM now addresses an app install by its Firebase Installation ID (FID);
  // the backend sends to it as `message.fid` (the old registration token
  // API, getToken/onTokenRefresh, is deprecated).
  @override
  Future<void> register() async {
    // iOS: FCM refuses to register until iOS has handed the app its APNs
    // device token, which arrives a moment after permission is granted.
    // Without it, the next start (home screen shown again) retries.
    if (Platform.isIOS) {
      for (var i = 0; i < 10 && await _messaging.getAPNSToken() == null; i++) {
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
    await _messaging.register();
  }

  @override
  Stream<String> get onRegistered => _messaging.onRegistered;
}

/// Notifications while the app is in the background or closed.
///
/// The backend pushes every new row of the student's notifications list to
/// the phones registered here (Firebase Cloud Messaging; Android and iPhone).
/// The phone's system shows them; tapping one opens the notifications screen,
/// like a tap on the app's own notifications.
///
/// Firebase is optional: without `google-services.json` /
/// `GoogleService-Info.plist` in the build, [initialize] leaves push off and
/// the app keeps showing notifications itself while it runs
/// ([NotificationSyncService]).
class PushService {
  PushService._internal();
  static PushService _instance = PushService._internal();
  factory PushService() => _instance;

  @visibleForTesting
  PushService.test({
    required PushMessaging messaging,
    required PushTokenApi api,
    required String platform,
  }) : _messaging = messaging,
       _api = api,
       _platform = platform;

  @visibleForTesting
  static set instance(PushService service) => _instance = service;

  /// The server confirmed it pushes to this phone: the app then leaves
  /// notifications that arrived while it was closed to the phone's system
  /// instead of showing them again.
  static const String _deliveryActiveKey = 'push_delivery_active';
  static const String _tokenKey = 'push_registered_token';

  PushMessaging? _messaging;

  /// Android channel the pushes name (see [NotificationService]).
  @visibleForTesting
  Future<void> Function() ensureChannel =
      () => NotificationService().ensureGeneralChannel();
  PushTokenApi _api = const ApiPushTokenApi();
  String _platform = Platform.isIOS ? 'ios' : 'android';
  StreamSubscription<String>? _registeredSubscription;
  bool _sessionListener = false;

  /// Firebase is configured in this build.
  bool get available => _messaging != null;

  /// Called once from `main()`. Never throws.
  Future<void> initialize() async {
    try {
      await Firebase.initializeApp();
    } catch (e) {
      debugPrint('[Push] Firebase not configured in this build — push off');
      return;
    }
    try {
      _messaging = _FirebasePushMessaging();
      // In the foreground the app shows the notification itself (once,
      // through NotificationSyncService); the system must not add a second.
      await FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions();
      FirebaseMessaging.onMessage.listen((message) {
        if (PushPayload.fromData(message.data) != null) onForegroundMessage();
      });
      FirebaseMessaging.onMessageOpenedApp.listen((m) => openFromTap(m.data));
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) openFromTap(initial.data);
    } catch (e) {
      debugPrint('[Push] messaging setup failed: ${e.runtimeType}');
    }
  }

  /// Set by the app root: fetch the list now and show what is new.
  VoidCallback onForegroundMessage = () {};

  /// A tap on a pushed notification (app in the background or closed).
  /// Returns whether it was one of the student's notifications.
  bool openFromTap(Map<String, dynamic> data) {
    if (PushPayload.fromData(data) == null) return false;
    NotificationService().openNotificationsScreen();
    return true;
  }

  /// The student is signed in (home screen): ask for permission, register
  /// this phone's token and keep it current. Safe to call repeatedly.
  Future<void> start() async {
    final messaging = _messaging;
    if (messaging == null) {
      // No push in this build: the app's own notifications still need it.
      await NotificationService().requestPermissions();
      return;
    }
    if (!_sessionListener) {
      _sessionListener = true;
      SessionManager().sessionRevoked.addListener(_onSessionEnded);
    }
    // Listen before registering: the id arrives on the stream.
    _registeredSubscription ??= messaging.onRegistered.listen((id) {
      if (id.isEmpty) return;
      unawaited(_register(id).catchError((Object e) {
        debugPrint('[Push] sending the push id failed: ${e.runtimeType}');
      }));
    });
    try {
      await ensureChannel();
      await messaging.requestPermission();
      await messaging.register();
    } catch (e) {
      debugPrint('[Push] registration failed: ${e.runtimeType}');
    }
  }

  Future<void> _register(String token) async {
    if (!await SessionManager().isSignedIn) return;
    final enabled = await _api.register(
      token: token,
      provider: _messaging!.provider,
      platform: _platform,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    await prefs.setBool(_deliveryActiveKey, enabled);
  }

  /// Signing out: this phone stops getting the student's notifications. The
  /// backend also drops the phone's token on logout; this covers a logout
  /// request that fails.
  Future<void> unregister() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);
    await _forget();
    if (token == null || token.isEmpty) return;
    try {
      await _api.unregister(token);
    } catch (e) {
      debugPrint('[Push] unregister failed: ${e.runtimeType}');
    }
  }

  /// Whether the server pushes this student's notifications to this phone.
  Future<bool> deliveryActive() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_deliveryActiveKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  void _onSessionEnded() => unawaited(_forget());

  Future<void> _forget() async {
    await _registeredSubscription?.cancel();
    _registeredSubscription = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_deliveryActiveKey);
  }
}
