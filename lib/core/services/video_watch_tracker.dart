import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:better_player_plus/better_player_plus.dart';

/// Tracks actual watch time for video view counting.
/// Calls onThresholdReached when view_by_minute threshold is met.
/// Designed for: POST /chapter/{chapter_id}/view after required minutes.
///
/// APPROACH: Uses wall-clock time (DateTime.now()) as the source of truth
/// rather than VideoPlayerController.value.position diffs, because BetterPlayer's
/// underlying VideoPlayerController.value.position does NOT update reliably
/// every 1-second tick — it may stay the same across multiple ticks, causing
/// the position-diff method to never accumulate watch time.
///
/// The wall-clock timer runs only while video is confirmed to be playing
/// (checked each tick via BetterPlayer events). Pauses/seeks stop accumulation.
class VideoWatchTracker extends ChangeNotifier {
  final String chapterId;
  final int viewByMinute;
  final VoidCallback? onThresholdReached;

  BetterPlayerController? _betterPlayerController;
  Timer? _trackingTimer;

  // Tracking state
  int _watchedSeconds = 0;
  bool _viewCounted = false;
  bool _isTracking = false;

  // Wall-clock tracking (the real source of truth)
  DateTime? _trackingStartedAt;
  int _accumulatedMs = 0;

  // Lifecycle state
  bool _isInForeground = true;
  bool _isDisposed = false;
  bool _isPaused = false;

  VideoWatchTracker({
    required this.chapterId,
    required this.viewByMinute,
    this.onThresholdReached,
  });

  /// `view_by_minute <= 0` means "count the view as soon as playback starts",
  /// which is how the web reads it (`useChapterViewRecording.ts`). The old
  /// 10-second grace period here meant a student who opened and closed a
  /// chapter within ten seconds was never charged a view the web would charge.
  bool get _countsImmediately => viewByMinute <= 0;

  int get watchedSeconds => _watchedSeconds;
  int get requiredSeconds => _countsImmediately ? 0 : viewByMinute * 60;
  int get remainingSeconds =>
      (requiredSeconds - _watchedSeconds).clamp(0, requiredSeconds);
  bool get viewCounted => _viewCounted;
  bool get isTracking => _isTracking;
  double get progress =>
      (requiredSeconds > 0) ? (_watchedSeconds / requiredSeconds).clamp(0.0, 1.0) : 1.0;

  // ─────────────────────────── Attach / Detach ────────────────────────────

  /// Attach to a [BetterPlayerController].
  void attach(BetterPlayerController controller) {
    if (_isDisposed) return;

    detach(); // clean up any previous controller

    _betterPlayerController = controller;
    controller.addEventsListener(_onBetterPlayerEvent);

    // If video is already playing when we attach, start tracking immediately.
    final vc = controller.videoPlayerController;
    final isPlaying = vc?.value.isPlaying ?? false;
    debugPrint(
      '[VideoWatchTracker] attach() - vc=$vc, isPlaying=$isPlaying, '
      '_isInForeground=$_isInForeground, _isPaused=$_isPaused, _viewCounted=$_viewCounted',
    );
    if (isPlaying && _isInForeground && !_isPaused && !_viewCounted) {
      _startTracking();
    }

    debugPrint(
      '[VideoWatchTracker] Attached to controller for chapter $chapterId',
    );
  }

  /// Detach from the current controller and stop tracking.
  void detach() {
    _betterPlayerController?.removeEventsListener(_onBetterPlayerEvent);
    _pauseTracking();
    _betterPlayerController = null;
    debugPrint('[VideoWatchTracker] Detached from controller');
  }

  // ───────────────────────── BetterPlayer events ──────────────────────────

  void _onBetterPlayerEvent(BetterPlayerEvent event) {
    if (_isDisposed || _betterPlayerController == null) return;

    switch (event.betterPlayerEventType) {
      case BetterPlayerEventType.play:
        debugPrint(
          '[VideoWatchTracker] PLAY event - _isInForeground=$_isInForeground, '
          '_isPaused=$_isPaused, _viewCounted=$_viewCounted',
        );
        if (_isInForeground && !_isPaused && !_viewCounted) {
          _startTracking();
        }
        break;

      case BetterPlayerEventType.pause:
      case BetterPlayerEventType.finished:
        _pauseTracking();
        break;

      case BetterPlayerEventType.seekTo:
        // On seek, flush any accumulated wall-clock time and reset baseline.
        _flushWallClockTime();
        debugPrint('[VideoWatchTracker] Seek detected → wall-clock reset');
        break;

      default:
        break;
    }
  }

  // ───────────────────────────── Timer tick ───────────────────────────────

  /// Uses wall-clock elapsed time as source of truth.
  /// Each tick verifies the video is still playing, then calculates
  /// elapsed real seconds since tracking started.
  void _onTick() {
    if (_isDisposed || !_isInForeground || _viewCounted || !_isTracking) {
      _trackingTimer?.cancel();
      return;
    }

    final vc = _betterPlayerController?.videoPlayerController;
    if (vc == null) return;

    final value = vc.value;

    if (!value.isPlaying) {
      // Video stopped/buffering mid-tick — flush and pause.
      _flushWallClockTime();
      _pauseTracking();
      return;
    }

    // Calculate wall-clock seconds elapsed since we started tracking.
    if (_trackingStartedAt == null) {
      _trackingStartedAt = DateTime.now();
      return;
    }

    final now = DateTime.now();
    final elapsedMs = now.difference(_trackingStartedAt!).inMilliseconds;
    _trackingStartedAt = now; // reset baseline for next tick

    // The timer fires every 1s. On each tick, we accumulate the milliseconds
    // (since we already verified the video is playing). We cap the elapsedMs
    // to 2000ms to detect large gaps (e.g., device sleep) safely.
    final msToAdd = elapsedMs.clamp(0, 2000);

    if (msToAdd > 0) {
      _accumulatedMs += msToAdd;
      
      final newWatchedSeconds = _accumulatedMs ~/ 1000;
      if (newWatchedSeconds > _watchedSeconds) {
        final secondsToAdd = newWatchedSeconds - _watchedSeconds;
        _watchedSeconds = newWatchedSeconds;

        debugPrint(
          '[VideoWatchTracker] _onTick() +${secondsToAdd}s, total=$_watchedSeconds/${requiredSeconds}s',
        );
        _checkThreshold();

        if (_watchedSeconds % 10 == 0) {
          debugPrint(
            '[VideoWatchTracker] Progress: $_watchedSeconds / ${requiredSeconds}s '
            '(${(progress * 100).toStringAsFixed(0)}%)',
          );
        }
      }
    }

    notifyListeners();
  }

  /// Flush wall-clock time accumulated since _trackingStartedAt.
  /// Called on seek/pause to ensure elapsed time is credited before resetting.
  void _flushWallClockTime() {
    if (_trackingStartedAt == null) return;
    final now = DateTime.now();
    final elapsedMs = now.difference(_trackingStartedAt!).inMilliseconds;
    final msToAdd = elapsedMs.clamp(0, 2000);
    if (msToAdd > 0) {
      _accumulatedMs += msToAdd;
      final newWatchedSeconds = _accumulatedMs ~/ 1000;
      if (newWatchedSeconds > _watchedSeconds) {
        final secondsToAdd = newWatchedSeconds - _watchedSeconds;
        _watchedSeconds = newWatchedSeconds;
        debugPrint(
          '[VideoWatchTracker] _flushWallClockTime() +${secondsToAdd}s, total=$_watchedSeconds/${requiredSeconds}s',
        );
        _checkThreshold();
      }
    }
    _trackingStartedAt = null;
  }

  // ─────────────────────── Start / Pause tracking ─────────────────────────

  void _startTracking() {
    debugPrint('[VideoWatchTracker] _startTracking() called');
    if (_isTracking || _viewCounted || _isDisposed) {
      debugPrint(
        '[VideoWatchTracker] _startTracking() early return: _isTracking=$_isTracking, _viewCounted=$_viewCounted, _isDisposed=$_isDisposed',
      );
      return;
    }

    // Ensure video is actually playing before starting timer.
    final vc = _betterPlayerController?.videoPlayerController;
    final isPlaying = vc?.value.isPlaying ?? false;
    if (vc == null || !isPlaying) {
      debugPrint(
        '[VideoWatchTracker] _startTracking() early return: vc=$vc, isPlaying=$isPlaying',
      );
      return;
    }

    // No minimum watch time: the view is registered on the first play.
    if (_countsImmediately) {
      debugPrint(
        '[VideoWatchTracker] view_by_minute<=0 → counting view on first play',
      );
      _markAsViewed();
      return;
    }

    _isTracking = true;
    _trackingStartedAt = DateTime.now();

    _trackingTimer?.cancel();
    _trackingTimer = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());

    debugPrint('[VideoWatchTracker] Started wall-clock tracking for chapter $chapterId');
    notifyListeners();
  }

  void _pauseTracking() {
    if (!_isTracking) return;

    _flushWallClockTime();

    _isTracking = false;
    _trackingTimer?.cancel();
    _trackingStartedAt = null;

    debugPrint(
      '[VideoWatchTracker] Paused tracking. '
      'Watched: $_watchedSeconds / ${requiredSeconds}s',
    );
    notifyListeners();
  }

  // ─────────────────────────── Public controls ────────────────────────────

  /// Call when the user explicitly pauses playback.
  void userPaused() {
    _isPaused = true;
    _pauseTracking();
  }

  /// Call when the user explicitly resumes playback.
  void userResumed() {
    _isPaused = false;
    final vc = _betterPlayerController?.videoPlayerController;
    if (_isInForeground && vc?.value.isPlaying == true && !_viewCounted) {
      _startTracking();
    }
  }

  /// Call if you know a seek happened outside of BetterPlayer events.
  void onSeek(Duration newPosition) {
    _flushWallClockTime();
    debugPrint('[VideoWatchTracker] Manual seek → wall-clock reset');
  }

  // ──────────────────────── App lifecycle support ──────────────────────────

  void onAppLifecycleStateChanged(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _isInForeground = true;
        final vc = _betterPlayerController?.videoPlayerController;
        if (vc?.value.isPlaying == true && !_viewCounted && !_isPaused) {
          _startTracking();
        }
        break;

      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        _isInForeground = false;
        _pauseTracking();
        break;

      case AppLifecycleState.detached:
        _disposeInternal();
        break;
    }
  }

  // ──────────────────────────── Threshold ─────────────────────────────────

  void _checkThreshold() {
    debugPrint(
      '[VideoWatchTracker] _checkThreshold() - _viewCounted=$_viewCounted, _watchedSeconds=$_watchedSeconds, requiredSeconds=$requiredSeconds',
    );
    if (_viewCounted) return;
    if (_watchedSeconds >= requiredSeconds) {
      _markAsViewed();
    }
  }

  void _markAsViewed() {
    debugPrint('[VideoWatchTracker] _markAsViewed() called');
    if (_viewCounted) {
      debugPrint('[VideoWatchTracker] _markAsViewed() already counted, returning');
      return;
    }

    _viewCounted = true;
    _isTracking = false;
    _trackingTimer?.cancel();
    _trackingStartedAt = null;

    debugPrint(
      '[VideoWatchTracker] VIEW COUNTED for chapter $chapterId! '
      'Total watched: $_watchedSeconds s, calling onThresholdReached...',
    );

    onThresholdReached?.call();
    debugPrint('[VideoWatchTracker] onThresholdReached callback completed');
    notifyListeners();
  }

  // ──────────────────────────── Reset / Dispose ───────────────────────────

  /// Reset the tracker so the user can re-watch and trigger another view.
  void reset() {
    _pauseTracking();
    _watchedSeconds = 0;
    _accumulatedMs = 0;
    _viewCounted = false;
    _trackingStartedAt = null;
    notifyListeners();
    debugPrint('[VideoWatchTracker] Reset for chapter $chapterId');
  }

  void _disposeInternal() {
    if (_isDisposed) return;
    _isDisposed = true;
    detach();
    _trackingTimer?.cancel();
    _trackingTimer = null;
    _trackingStartedAt = null;
    debugPrint('[VideoWatchTracker] Disposed for chapter $chapterId');
  }

  @override
  void dispose() {
    _disposeInternal();
    super.dispose();
  }
}