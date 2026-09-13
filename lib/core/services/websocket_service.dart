import 'dart:async';

import 'package:flutter/foundation.dart';

import '../network/api_constants.dart';
import '../realtime/reverb_client.dart';
import '../session/session_manager.dart';

/// Realtime notifications, now carried over Laravel Reverb.
///
/// The previous implementation opened `wss://api.learnoo.app/ws` and spoke a
/// hand-rolled `{type: 'subscribe'}` protocol that the backend does not
/// implement, so notifications never arrived. The web dashboard listens on the
/// public `global` channel (`components/student/Navbar.tsx` binds every event
/// on it); this does the same through [ReverbClient].
///
/// The public API is unchanged so `NotificationBloc` and `main.dart` keep
/// working as-is.
class WebSocketService {
  static final WebSocketService _instance = WebSocketService._internal();
  factory WebSocketService() => _instance;
  WebSocketService._internal();

  final ReverbClient _reverb = ReverbClient();

  final StreamController<Map<String, dynamic>> _notificationController =
      StreamController<Map<String, dynamic>>.broadcast();

  StreamSubscription<ReverbEvent>? _eventSubscription;
  bool _subscribed = false;

  Stream<Map<String, dynamic>> get notificationStream =>
      _notificationController.stream;

  bool get isConnected => _reverb.isConnected;

  /// Opens the Reverb connection. No-op when the student is not signed in.
  Future<void> connect() async {
    final token = await SessionManager().getActiveToken();
    if (token == null || token.isEmpty) {
      debugPrint('[Notifications] no session — not connecting');
      return;
    }
    await _reverb.connect();
  }

  /// Subscribes to the public `global` channel and forwards every broadcast
  /// on it as a notification, mirroring the web's `bind_global`.
  Future<void> subscribeToNotifications() async {
    if (_subscribed) return;

    final token = await SessionManager().getActiveToken();
    if (token == null || token.isEmpty) return;

    _subscribed = true;

    _eventSubscription ??= _reverb.events.listen((event) {
      if (event.channel != ApiConstants.globalChannel) return;
      final payload = event.dataMap;
      if (payload == null) return;
      _notificationController.add(payload);
    });

    await _reverb.subscribe(ApiConstants.globalChannel);
  }

  void unsubscribeFromNotifications() {
    if (!_subscribed) return;
    _subscribed = false;
    _reverb.unsubscribe(ApiConstants.globalChannel);
  }

  Future<void> disconnect() async {
    unsubscribeFromNotifications();
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    await _reverb.disconnect();
  }

  void dispose() {
    disconnect();
    _notificationController.close();
  }
}
