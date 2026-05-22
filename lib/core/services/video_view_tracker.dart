import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

/// Tracks video watch time and triggers view count API when threshold is reached.
///
/// FIXES applied:
/// 1. Removed seconds==0 fallback that caused counting during buffering.
/// 2. onViewCounted callback is now actually called when threshold is reached.
/// 3. attach() now uses a listener instead of starting the timer unconditionally.
/// 4. Backward seek is handled — _lastPosition always updates after every tick.
/// 5. Async SharedPreferences load is guarded so attach() waits for it.
class VideoViewTracker extends ChangeNotifier {
  final String chapterId;
  final int viewByMinute;

  /// Called once when the watch-time threshold is reached.
  /// Receives the total watched minutes so the caller can hit the API.
  final Function(int watchedMinutes) onViewCounted;

  VideoPlayerController? _controller;
  Timer? _trackingTimer;

  // Tracking state
  int _watchedSeconds = 0;
  bool _viewCounted = false;
  bool _isTracking = false;
  Duration _lastPosition = Duration.zero;

  // Lifecycle state
  bool _isInForeground = true;
  bool _isDisposed = false;

  // FIX: Guard so attach() never starts before SharedPreferences finishes loading.
  bool _prefsLoaded = false;

  // Persistence keys
  late final String _prefsKeyWatched;
  late final String _prefsKeyCounted;
  late final String _prefsKeyTimestamp;

  VideoViewTracker({
    required this.chapterId,
    required this.viewByMinute,
    required this.onViewCounted,
  }) {
    _prefsKeyWatched = 'video_watch_$chapterId';
    _prefsKeyCounted = 'video_counted_$chapterId';
    _prefsKeyTimestamp = 'video_timestamp_$chapterId';
    _loadPersistedProgress();
  }

  int get watchedSeconds => _watchedSeconds;
  int get requiredSeconds => viewByMinute > 0 ? viewByMinute * 60 : 10;
  int get remainingSeconds =>
      (requiredSeconds - _watchedSeconds).clamp(0, requiredSeconds);
  bool get viewCounted => _viewCounted;
  double get progress =>
      (requiredSeconds > 0) ? (_watchedSeconds / requiredSeconds).clamp(0.0, 1.0) : 1.0;

  // ─────────────────────────── Attach / Detach ────────────────────────────

  /// FIX: Uses a listener instead of starting the timer unconditionally.
  /// The timer only starts when the video actually begins playing.
  void attach(VideoPlayerController controller) {
    if (_isDisposed) return;

    detach(); // remove any previous listener

    _controller = controller;
    controller.addListener(_onControllerUpdate);

    // In case the video is already playing when we attach.
    _onControllerUpdate();

    debugPrint('[VideoViewTracker] Attached for chapter $chapterId');
  }

  void detach() {
    _controller?.removeListener(_onControllerUpdate);
    _pauseTracking();
    _controller = null;
    debugPrint('[VideoViewTracker] Detached');
  }

  /// Reacts to VideoPlayerController state changes.
  void _onControllerUpdate() {
    if (_isDisposed || !_prefsLoaded) return;

    final isPlaying = _controller?.value.isPlaying ?? false;

    if (isPlaying && !_isTracking && _isInForeground && !_viewCounted) {
      _startTracking();
    } else if (!isPlaying && _isTracking) {
      _pauseTracking();
    }
  }

  // ───────────────────────── App lifecycle support ─────────────────────────

  void onAppLifecycleStateChanged(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _isInForeground = true;
        _onControllerUpdate(); // let the listener decide whether to resume
        break;

      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        _isInForeground = false;
        _pauseTracking();
        _persistProgress();
        break;

      case AppLifecycleState.detached:
        _disposeInternal();
        break;
    }
  }

  // ─────────────────────── Start / Pause tracking ──────────────────────────

  void _startTracking() {
    if (_isTracking || _viewCounted || _isDisposed || _controller == null) return;

    _isTracking = true;
    _lastPosition = _controller!.value.position;

    _trackingTimer?.cancel();
    _trackingTimer = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());

    debugPrint('[VideoViewTracker] Started tracking for chapter $chapterId');
    notifyListeners();
  }

  void _pauseTracking() {
    if (!_isTracking) return;

    _isTracking = false;
    _trackingTimer?.cancel();

    if (_controller != null) {
      _lastPosition = _controller!.value.position;
    }

    _persistProgress();
    debugPrint(
      '[VideoViewTracker] Paused tracking. Watched: $_watchedSeconds / ${requiredSeconds}s',
    );
    notifyListeners();
  }

  // ───────────────────────────── Timer tick ────────────────────────────────

  void _onTick() {
    if (_isDisposed || !_isInForeground || _viewCounted || !_isTracking) {
      _trackingTimer?.cancel();
      return;
    }

    if (_controller == null) return;

    final value = _controller!.value;

    if (!value.isPlaying) {
      // Stopped mid-tick (e.g. buffering). Save position and wait.
      _lastPosition = value.position;
      return;
    }

    final position = value.position;
    final diff = position - _lastPosition;
    final seconds = diff.inSeconds;

    // FIX: Count only when the playhead actually advanced by 1-2 s.
    // - seconds == 0 → buffering or position unchanged → do NOT count.
    // - seconds > 2  → seek jump → do NOT count.
    // - seconds < 0  → backward seek → do NOT count.
    // _lastPosition is always updated so the next tick has a correct baseline.
    if (seconds > 0 && seconds <= 2) {
      _watchedSeconds += seconds;
      _checkThreshold();

      if (_watchedSeconds % 10 == 0) {
        debugPrint(
          '[VideoViewTracker] Progress: $_watchedSeconds / ${requiredSeconds}s '
          '(${(progress * 100).toStringAsFixed(0)}%)',
        );
      }
    } else if (seconds != 0) {
      // Seek detected (forward or backward).
      debugPrint(
        '[VideoViewTracker] Seek detected ($seconds s) — position reset, not counting.',
      );
    }

    // FIX: Always update _lastPosition, even on seek or 0-diff.
    _lastPosition = position;
    notifyListeners();
  }

  // ──────────────────────────── Threshold ──────────────────────────────────

  void _checkThreshold() {
    if (_viewCounted) return;
    if (_watchedSeconds >= requiredSeconds) {
      _markAsViewed();
    }
  }

  Future<void> _markAsViewed() async {
    if (_viewCounted) return;

    _viewCounted = true;
    _isTracking = false;
    _trackingTimer?.cancel();

    await _persistProgress();

    final watchedMinutes = (_watchedSeconds / 60).ceil();

    debugPrint(
      '[VideoViewTracker] VIEW COUNTED for chapter $chapterId! '
      'Watched: $_watchedSeconds s (~$watchedMinutes min)',
    );

    // FIX: Actually call the callback so the API call happens.
    onViewCounted(watchedMinutes);

    notifyListeners();
  }

  // ───────────────────────── SharedPreferences ─────────────────────────────

  /// FIX: Sets _prefsLoaded = true when done, so attach() starts safely.
  Future<void> _loadPersistedProgress() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final wasCounted = prefs.getBool(_prefsKeyCounted) ?? false;
      if (wasCounted) {
        _viewCounted = true;
        _prefsLoaded = true;
        debugPrint(
          '[VideoViewTracker] View already counted for chapter $chapterId',
        );
        notifyListeners();
        return;
      }

      final savedSeconds = prefs.getInt(_prefsKeyWatched) ?? 0;
      final savedTimestamp = prefs.getInt(_prefsKeyTimestamp) ?? 0;

      if (savedSeconds > 0) {
        final savedDate =
            DateTime.fromMillisecondsSinceEpoch(savedTimestamp);
        final now = DateTime.now();
        final isSameDay = savedDate.year == now.year &&
            savedDate.month == now.month &&
            savedDate.day == now.day;

        if (isSameDay) {
          _watchedSeconds = savedSeconds;
          debugPrint(
            '[VideoViewTracker] Restored progress: $_watchedSeconds s',
          );
        } else {
          debugPrint('[VideoViewTracker] Progress expired, resetting');
          await _clearPersistedProgress();
        }
      }
    } catch (e) {
      debugPrint('[VideoViewTracker] Error loading progress: $e');
    } finally {
      _prefsLoaded = true;
      // If the controller was attached before prefs finished loading,
      // kick off the listener check now.
      _onControllerUpdate();
      notifyListeners();
    }
  }

  Future<void> _persistProgress() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefsKeyWatched, _watchedSeconds);
      await prefs.setBool(_prefsKeyCounted, _viewCounted);
      await prefs.setInt(
        _prefsKeyTimestamp,
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (e) {
      debugPrint('[VideoViewTracker] Error persisting progress: $e');
    }
  }

  Future<void> _clearPersistedProgress() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKeyWatched);
      await prefs.remove(_prefsKeyCounted);
      await prefs.remove(_prefsKeyTimestamp);
    } catch (e) {
      debugPrint('[VideoViewTracker] Error clearing progress: $e');
    }
  }

  // ──────────────────────────── Reset / Dispose ────────────────────────────

  Future<void> reset() async {
    _pauseTracking();
    _watchedSeconds = 0;
    _viewCounted = false;
    _lastPosition = Duration.zero;
    await _clearPersistedProgress();
    notifyListeners();
    debugPrint('[VideoViewTracker] Reset for chapter $chapterId');
  }

  void _disposeInternal() {
    if (_isDisposed) return;
    _isDisposed = true;
    detach();
    _trackingTimer?.cancel();
    _trackingTimer = null;
    debugPrint('[VideoViewTracker] Disposed for chapter $chapterId');
  }

  @override
  void dispose() {
    _disposeInternal();
    super.dispose();
  }
}