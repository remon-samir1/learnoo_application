import 'dart:async';

import 'package:flutter/foundation.dart';

import '../network/api_constants.dart';
import 'reverb_client.dart';

/// Listens for the login code on the student's private Reverb channel.
///
/// Mirrors `src/hooks/useEchoOTP.ts`: subscribe to `private-auto-otp.{userId}`,
/// wait for `SendOtpEvent`, and read `payload.user.otp`. The code screen uses
/// this to fill the boxes the moment the backend issues the code, before the
/// SMS lands.
///
/// The subscription happens while the student is still unverified, authorized
/// with the pending token — the same thing the web authorizer does.
class OtpListener {
  OtpListener();

  final ReverbClient _reverb = ReverbClient();

  StreamSubscription<ReverbEvent>? _subscription;
  String? _channel;

  final ValueNotifier<String?> otp = ValueNotifier<String?>(null);
  final ValueNotifier<bool> connected = ValueNotifier<bool>(false);

  Timer? _statusTimer;

  /// Starts listening for [userId]'s code. Safe to call more than once.
  Future<void> start(String userId) async {
    if (userId.trim().isEmpty) {
      debugPrint('[OTP] no user id — cannot subscribe');
      return;
    }

    final channel = ApiConstants.otpChannel(userId);
    if (_channel == channel && _subscription != null) return;

    await stop();
    _channel = channel;

    _subscription = _reverb.events.listen((event) {
      if (event.channel != channel) return;
      if (!event.matches(ApiConstants.otpEvent)) return;

      final code = _readCode(event.data);
      if (code != null) {
        debugPrint('[OTP] code received over websocket');
        otp.value = code;
      }
    });

    // Join before the caller asks the backend to issue a code — Reverb does
    // not replay a broadcast that happened before we were on the channel.
    await _reverb.subscribeAndWait(channel);

    _statusTimer?.cancel();
    _statusTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      connected.value = _reverb.isConnected;
    });
    connected.value = _reverb.isConnected;
  }

  /// Reads the code out of the broadcast payload.
  ///
  /// The HTTP sibling of this event returns the code under `code`, while the
  /// web types the broadcast as `{ user: { otp } }`. Accept every shape so a
  /// backend change on either side does not silently stop the auto-fill.
  String? _readCode(dynamic data) {
    if (data is! Map) return null;

    final nested = data['user'];
    for (final candidate in [
      data['code'],
      data['otp'],
      nested is Map ? nested['otp'] : null,
      nested is Map ? nested['code'] : null,
    ]) {
      final code = candidate?.toString().trim();
      if (code != null && code.isNotEmpty) return code;
    }
    return null;
  }

  void clear() => otp.value = null;

  Future<void> stop() async {
    _statusTimer?.cancel();
    _statusTimer = null;
    await _subscription?.cancel();
    _subscription = null;
    if (_channel != null) {
      _reverb.unsubscribe(_channel!);
      _channel = null;
    }
  }

  Future<void> dispose() async {
    await stop();
    otp.dispose();
    connected.dispose();
  }
}
