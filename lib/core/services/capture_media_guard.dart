import 'package:better_player_plus/better_player_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

import 'screen_protection_service.dart';

/// Pauses and mutes video players while the screen is being recorded.
///
/// Screen protection already blacks out the picture (FLAG_SECURE on Android,
/// a black overlay window on iOS), but a recorder still picked up the sound.
/// On Android 10+ the manifest's `allowAudioPlaybackCapture="false"` and the
/// player's capture policy stop that at the OS level; iOS has no equivalent,
/// so while [ScreenProtectionService.mediaCaptureActive] is true every
/// attached player is paused and kept at volume 0. When capture stops the
/// previous volume is restored but playback does not resume by itself — the
/// student presses play.
///
/// Follows the dashboard switch `feature_block_screenshots`: when the
/// dashboard allows capture, [ScreenProtectionService.mediaCaptureActive]
/// never turns on and players are left alone.
///
/// Usage: [attachBetterPlayer]/[attachVideoPlayer] right after creating the
/// controller and [detach] before disposing it.
class CaptureMediaGuard {
  CaptureMediaGuard._();

  static final Map<Object, _GuardedPlayer> _players = {};
  static bool _listening = false;

  static ValueListenable<bool> get _capture =>
      ScreenProtectionService().mediaCaptureActive;

  static bool get isCaptureActive => _capture.value;

  static void attachBetterPlayer(BetterPlayerController controller) {
    _attach(controller, _BetterPlayerGuard(controller));
  }

  static void attachVideoPlayer(VideoPlayerController controller) {
    _attach(controller, _VideoPlayerGuard(controller));
  }

  static void detach(Object controller) {
    _players.remove(controller)?.dispose();
  }

  static void _attach(Object key, _GuardedPlayer player) {
    _players.remove(key)?.dispose();
    _players[key] = player;
    if (!_listening) {
      _listening = true;
      _capture.addListener(_onCaptureChanged);
    }
    player.init();
    if (isCaptureActive) player.silence();
  }

  static void _onCaptureChanged() {
    final active = isCaptureActive;
    for (final player in List<_GuardedPlayer>.of(_players.values)) {
      if (active) {
        player.silence();
      } else {
        player.restore();
      }
    }
  }
}

abstract class _GuardedPlayer {
  /// Volume before capture started; null while not silenced.
  double? _savedVolume;
  bool _enforcing = false;

  void init();
  void dispose();
  double get volume;
  bool get isPlaying;
  Future<void> pause();
  Future<void> setVolume(double volume);

  void silence() {
    _savedVolume ??= volume;
    enforce();
  }

  void restore() {
    final saved = _savedVolume;
    _savedVolume = null;
    if (saved != null) _safely(() => setVolume(saved));
  }

  /// Called on any player change: while capture is on, a student pressing
  /// play or unmute gets a silent player.
  void enforce() {
    if (!CaptureMediaGuard.isCaptureActive || _enforcing) return;
    _savedVolume ??= volume;
    _enforcing = true;
    _safely(() async {
      try {
        if (volume > 0) await setVolume(0);
        if (isPlaying) await pause();
      } finally {
        _enforcing = false;
      }
    });
  }

  static void _safely(Future<void> Function() action) {
    try {
      action().catchError((Object e) {
        debugPrint('[CaptureMediaGuard] ${e.runtimeType}');
      });
    } catch (e) {
      // Player not initialized yet / already disposed.
      debugPrint('[CaptureMediaGuard] ${e.runtimeType}');
    }
  }
}

class _BetterPlayerGuard extends _GuardedPlayer {
  _BetterPlayerGuard(this.controller);

  final BetterPlayerController controller;

  void _onEvent(BetterPlayerEvent event) {
    switch (event.betterPlayerEventType) {
      case BetterPlayerEventType.initialized:
        if (CaptureMediaGuard.isCaptureActive) silence();
        break;
      case BetterPlayerEventType.play:
      case BetterPlayerEventType.setVolume:
        enforce();
        break;
      default:
        break;
    }
  }

  @override
  void init() => controller.addEventsListener(_onEvent);

  @override
  void dispose() => controller.removeEventsListener(_onEvent);

  @override
  double get volume => controller.videoPlayerController?.value.volume ?? 1.0;

  @override
  bool get isPlaying => controller.videoPlayerController?.value.isPlaying ?? false;

  @override
  Future<void> pause() async {
    if (controller.videoPlayerController == null) return;
    await controller.pause();
  }

  @override
  Future<void> setVolume(double volume) async {
    if (controller.videoPlayerController == null) return;
    await controller.setVolume(volume);
  }
}

class _VideoPlayerGuard extends _GuardedPlayer {
  _VideoPlayerGuard(this.controller);

  final VideoPlayerController controller;

  void _onValue() {
    if (controller.value.isPlaying || controller.value.volume > 0) enforce();
  }

  @override
  void init() => controller.addListener(_onValue);

  @override
  void dispose() => controller.removeListener(_onValue);

  @override
  double get volume => controller.value.volume;

  @override
  bool get isPlaying => controller.value.isPlaying;

  @override
  Future<void> pause() => controller.pause();

  @override
  Future<void> setVolume(double volume) => controller.setVolume(volume);
}
