import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:huawei_push/huawei_push.dart' as hms;
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

/// The phone side of the push provider: Firebase Cloud Messaging, or Huawei
/// Push Kit on phones without Google Play services.
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

class _HuaweiPushMessaging implements PushMessaging {
  @override
  String get provider => 'hms';

  // Push Kit has no permission prompt of its own; Android 13+ still needs
  // the app's notification permission for the system to show its pushes.
  @override
  Future<bool> requestPermission() =>
      NotificationService().requestPermissions();

  // The token arrives on [onRegistered] (Push.getTokenStream).
  @override
  Future<void> register() async => hms.Push.getToken('');

  @override
  Stream<String> get onRegistered => hms.Push.getTokenStream.handleError(
    (Object e) => debugPrint('[Push] Huawei token request failed: $e'),
  );
}

/// The data of a Huawei push the student tapped, from the plugin's
/// notification-open event: the push's `data` keys arrive as intent extras,
/// and again in `remoteMessage.dataOfMap` (a JSON object string).
@visibleForTesting
Map<String, dynamic> huaweiTapData(Object? event) {
  final data = <String, dynamic>{};
  if (event is! Map) return data;
  final extras = event['extras'];
  if (extras is Map) {
    extras.forEach((key, value) => data[key.toString()] = value);
  }
  final message = event['remoteMessage'];
  final dataOfMap = message is Map ? message['dataOfMap'] : null;
  if (dataOfMap is String && dataOfMap.isNotEmpty) {
    try {
      final decoded = jsonDecode(dataOfMap);
      if (decoded is Map) {
        decoded.forEach(
          (key, value) => data.putIfAbsent(key.toString(), () => value),
        );
      }
    } on FormatException {
      // Not ours.
    }
  }
  return data;
}

/// Notifications while the app is in the background or closed.
///
/// The backend pushes every new row of the student's notifications list to
/// the phones registered here: Firebase Cloud Messaging (iPhone and Android),
/// or Huawei Push Kit on Android phones that have Huawei Mobile Services but
/// no Google Play services (`agconnect-services.json` in the Android build).
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
  Future<void> Function() ensureChannel = () =>
      NotificationService().ensureGeneralChannel();
  PushTokenApi _api = const ApiPushTokenApi();
  String _platform = Platform.isIOS ? 'ios' : 'android';
  StreamSubscription<String>? _registeredSubscription;
  bool _sessionListener = false;

  /// Push is set up on this phone (Firebase configured, or Huawei Push).
  bool get available => _messaging != null;

  static const MethodChannel _providerChannel = MethodChannel(
    'com.learnoo.push_provider',
  );

  /// `hms` on an Android phone with Huawei Mobile Services and no Google
  /// Play services (PushProviderChannel.kt); `fcm` everywhere else.
  @visibleForTesting
  Future<String> Function() providerLookup = () async {
    if (!Platform.isAndroid) return 'fcm';
    try {
      return await _providerChannel.invokeMethod<String>('provider') ?? 'fcm';
    } catch (e) {
      debugPrint('[Push] push provider check failed: ${e.runtimeType}');
      return 'fcm';
    }
  };

  /// Called once from `main()`. Never throws.
  Future<void> initialize() async {
    if (await providerLookup() == 'hms') {
      await _initializeHuawei();
      return;
    }
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

  Future<void> _initializeHuawei() async {
    try {
      // The plugin otherwise reports its own method-call statistics to Huawei.
      await hms.Push.disableLogger();
      _messaging = _HuaweiPushMessaging();
      // In the foreground Push Kit hands the push to the app instead of
      // showing it (the backend sends `foreground_show: false`), and the app
      // shows it once through NotificationSyncService, as with Firebase.
      hms.Push.onMessageReceivedStream.listen((message) {
        if (PushPayload.fromData(message.dataOfMap ?? const {}) != null) {
          onForegroundMessage();
        }
      }, onError: (Object e) => debugPrint('[Push] Huawei message error: $e'));
      hms.Push.onNotificationOpenedApp.listen(
        (event) => _openHuaweiTap(huaweiTapData(event)),
        onError: (Object e) => debugPrint('[Push] Huawei open error: $e'),
      );
      final initial = await hms.Push.getInitialNotification();
      if (initial != null) _openHuaweiTap(huaweiTapData(initial));
    } catch (e) {
      debugPrint('[Push] Huawei push setup failed: ${e.runtimeType}');
    }
  }

  String? _openedHuaweiNotification;

  /// A cold start can report the same tap twice (the initial notification
  /// and the open event); open the screen once.
  void _openHuaweiTap(Map<String, dynamic> data) {
    final id = PushPayload.fromData(data)?.notificationId;
    if (id == null || id == _openedHuaweiNotification) return;
    _openedHuaweiNotification = id;
    openFromTap(data);
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
      unawaited(
        _register(id).catchError((Object e) {
          debugPrint('[Push] sending the push id failed: ${e.runtimeType}');
        }),
      );
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
