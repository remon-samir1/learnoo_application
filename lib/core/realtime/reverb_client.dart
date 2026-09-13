import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../network/api_constants.dart';
import '../session/session_manager.dart';

/// Minimal Pusher-protocol client for Laravel Reverb.
///
/// This replaces the old `wss://api.learnoo.app/ws` service, which spoke a
/// bespoke protocol the backend never implemented. The web dashboard talks to
/// Reverb through `laravel-echo` + `pusher-js` (`src/lib/echo.ts`); this is the
/// same handshake written directly on `web_socket_channel`, so no new
/// dependency is needed:
///
///   1. connect to `wss://{host}:{port}/app/{key}?protocol=7`
///   2. wait for `pusher:connection_established` → gives us a `socket_id`
///   3. for a private channel, POST that `socket_id` + channel name to
///      `/broadcasting/auth` with the bearer token, and subscribe with the
///      returned signature
///   4. answer `pusher:ping` with `pusher:pong` to hold the connection
class ReverbClient {
  ReverbClient._internal();
  static final ReverbClient _instance = ReverbClient._internal();
  factory ReverbClient() => _instance;

  static const Duration _reconnectDelay = Duration(seconds: 3);
  static const int _maxReconnectAttempts = 6;

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _reconnectTimer;
  Timer? _activityTimer;

  String? _socketId;
  bool _connecting = false;
  bool _disposed = false;
  int _reconnectAttempts = 0;

  /// Channels the caller asked for, replayed after every reconnect.
  final Set<String> _wantedChannels = <String>{};
  final Set<String> _subscribedChannels = <String>{};

  /// Completers for callers awaiting a channel to actually join.
  final Map<String, Completer<bool>> _pendingSubscriptions =
      <String, Completer<bool>>{};

  final StreamController<ReverbEvent> _events =
      StreamController<ReverbEvent>.broadcast();

  /// Every event received on a subscribed channel.
  Stream<ReverbEvent> get events => _events.stream;

  bool get isConnected => _socketId != null;

  // ------------------------------------------------------------------
  // Connection
  // ------------------------------------------------------------------

  Future<void> connect() async {
    if (_connecting || _channel != null || _disposed) return;
    _connecting = true;

    final scheme = ApiConstants.reverbUseTls ? 'wss' : 'ws';
    final uri = Uri.parse(
      '$scheme://${ApiConstants.reverbHost}:${ApiConstants.reverbPort}'
      '/app/${ApiConstants.reverbKey}'
      '?protocol=7&client=flutter&version=1.0.0',
    );

    try {
      final channel = WebSocketChannel.connect(uri);
      _channel = channel;

      _subscription = channel.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
        cancelOnError: false,
      );

      debugPrint('[Reverb] connecting to $uri');
    } catch (e) {
      debugPrint('[Reverb] connect failed: $e');
      _scheduleReconnect();
    } finally {
      _connecting = false;
    }
  }

  void _onMessage(dynamic raw) {
    Map<String, dynamic> frame;
    try {
      final decoded = jsonDecode(raw as String);
      if (decoded is! Map) return;
      frame = Map<String, dynamic>.from(decoded);
    } catch (_) {
      return;
    }

    final event = frame['event']?.toString() ?? '';
    final channel = frame['channel']?.toString();

    // Pusher wraps payloads as a JSON *string*.
    dynamic data = frame['data'];
    if (data is String && data.isNotEmpty) {
      try {
        data = jsonDecode(data);
      } catch (_) {
        // leave as string
      }
    }

    switch (event) {
      case 'pusher:connection_established':
        _socketId = (data is Map) ? data['socket_id']?.toString() : null;
        _reconnectAttempts = 0;
        debugPrint('[Reverb] connected, socket_id=$_socketId');
        _startActivityTimer();
        _resubscribeAll();
        return;

      case 'pusher:ping':
        _send({'event': 'pusher:pong', 'data': {}});
        return;

      case 'pusher:pong':
        return;

      case 'pusher:error':
        debugPrint('[Reverb] server error: $data');
        return;

      case 'pusher_internal:subscription_succeeded':
        if (channel != null) {
          _subscribedChannels.add(channel);
          debugPrint('[Reverb] subscribed to $channel');
          _completeSubscription(channel, true);
        }
        return;

      case 'pusher_internal:subscription_error':
        debugPrint('[Reverb] subscription failed for $channel: $data');
        if (channel != null) _completeSubscription(channel, false);
        return;
    }

    if (event.startsWith('pusher:') || event.startsWith('pusher_internal:')) {
      return;
    }

    if (channel == null) return;

    _events.add(ReverbEvent(channel: channel, event: event, data: data));
  }

  void _onError(Object error) {
    debugPrint('[Reverb] socket error: $error');
    _teardownSocket();
    _scheduleReconnect();
  }

  void _onDone() {
    debugPrint('[Reverb] socket closed');
    _teardownSocket();
    _scheduleReconnect();
  }

  void _teardownSocket() {
    _activityTimer?.cancel();
    _activityTimer = null;
    _subscription?.cancel();
    _subscription = null;
    _channel = null;
    _socketId = null;
    _subscribedChannels.clear();
  }

  void _scheduleReconnect() {
    if (_disposed || _wantedChannels.isEmpty) return;
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      debugPrint('[Reverb] giving up after $_reconnectAttempts attempts');
      return;
    }
    _reconnectTimer?.cancel();
    _reconnectAttempts++;
    _reconnectTimer = Timer(_reconnectDelay * _reconnectAttempts, connect);
  }

  void _startActivityTimer() {
    _activityTimer?.cancel();
    _activityTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _send({'event': 'pusher:ping', 'data': {}});
    });
  }

  void _send(Map<String, dynamic> frame) {
    try {
      _channel?.sink.add(jsonEncode(frame));
    } catch (e) {
      debugPrint('[Reverb] send failed: $e');
    }
  }

  // ------------------------------------------------------------------
  // Subscriptions
  // ------------------------------------------------------------------

  /// Subscribes to [channel]. Names starting with `private-` or `presence-`
  /// are authorized against `/broadcasting/auth` first.
  Future<void> subscribe(String channel) async {
    _wantedChannels.add(channel);

    if (_channel == null) {
      await connect();
      return; // _resubscribeAll runs once the handshake completes
    }
    if (_socketId == null) return; // still handshaking
    if (_subscribedChannels.contains(channel)) return;

    await _sendSubscribe(channel);
  }

  void _completeSubscription(String channel, bool ok) {
    final completer = _pendingSubscriptions.remove(channel);
    if (completer != null && !completer.isCompleted) completer.complete(ok);
  }

  /// Subscribes and waits until the server confirms the join.
  ///
  /// Reverb does not replay events published before a client joined, so a
  /// caller that triggers a broadcast (the code screen asking the backend to
  /// issue an OTP) has to be on the channel first or the event is lost. The
  /// timeout keeps that from ever blocking the UI: a caller that times out
  /// simply falls back to whatever non-realtime path it has.
  Future<bool> subscribeAndWait(
    String channel, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (_subscribedChannels.contains(channel)) return true;

    final completer =
        _pendingSubscriptions.putIfAbsent(channel, () => Completer<bool>());
    await subscribe(channel);

    try {
      return await completer.future.timeout(timeout);
    } on TimeoutException {
      debugPrint('[Reverb] timed out waiting to join $channel');
      _pendingSubscriptions.remove(channel);
      return false;
    }
  }

  Future<void> _sendSubscribe(String channel) async {
    final needsAuth =
        channel.startsWith('private-') || channel.startsWith('presence-');

    if (!needsAuth) {
      _send({
        'event': 'pusher:subscribe',
        'data': {'channel': channel},
      });
      return;
    }

    final auth = await _authorize(channel);
    if (auth == null) {
      debugPrint('[Reverb] no auth signature for $channel — skipping');
      _completeSubscription(channel, false);
      return;
    }

    _send({
      'event': 'pusher:subscribe',
      'data': {'channel': channel, 'auth': auth},
    });
  }

  /// Exchanges `socket_id` + channel for a signature.
  ///
  /// Uses the *current* token, which during login is the pending one — the
  /// student is not verified yet but must still receive their OTP, exactly as
  /// the web authorizer does with `sessionStorage.pending_auth_token`.
  Future<String?> _authorize(String channel) async {
    final socketId = _socketId;
    if (socketId == null) return null;

    final token = await SessionManager().currentToken();
    if (token == null || token.isEmpty) return null;

    try {
      final response = await http
          .post(
            Uri.parse(ApiConstants.broadcastingAuth),
            headers: {
              'Content-Type': 'application/x-www-form-urlencoded',
              'Accept': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: {'socket_id': socketId, 'channel_name': channel},
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        debugPrint('[Reverb] auth returned ${response.statusCode}');
        return null;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['auth'] != null) {
        return decoded['auth'].toString();
      }
      return null;
    } catch (e) {
      debugPrint('[Reverb] auth request failed: $e');
      return null;
    }
  }

  Future<void> _resubscribeAll() async {
    for (final channel in _wantedChannels.toList()) {
      if (_subscribedChannels.contains(channel)) continue;
      await _sendSubscribe(channel);
    }
  }

  void unsubscribe(String channel) {
    _wantedChannels.remove(channel);
    _subscribedChannels.remove(channel);
    _send({
      'event': 'pusher:unsubscribe',
      'data': {'channel': channel},
    });
  }

  /// Drops every subscription and closes the socket. Called on logout.
  Future<void> disconnect() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _wantedChannels.clear();
    _teardownSocket();
    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;
  }

  Future<void> dispose() async {
    _disposed = true;
    await disconnect();
    await _events.close();
  }
}

/// One broadcast frame.
class ReverbEvent {
  const ReverbEvent({
    required this.channel,
    required this.event,
    required this.data,
  });

  final String channel;

  /// Raw wire name, e.g. `App\Events\SendOtpEvent`.
  final String event;

  final dynamic data;

  /// Last segment of the event name, so `App\Events\SendOtpEvent` and a
  /// `broadcastAs`-shortened `SendOtpEvent` both match.
  ///
  /// Laravel Echo formats `listen('SendOtpEvent')` into
  /// `App\Events\SendOtpEvent` on the wire, which is why matching on the
  /// short name alone is not enough.
  String get shortName {
    final parts = event.split(RegExp(r'[\\.]'));
    return parts.isEmpty ? event : parts.last;
  }

  bool matches(String name) => event == name || shortName == name;

  Map<String, dynamic>? get dataMap =>
      data is Map ? Map<String, dynamic>.from(data as Map) : null;
}
