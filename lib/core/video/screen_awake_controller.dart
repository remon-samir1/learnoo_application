import 'dart:async';

/// Turns the platform wakelock on or off.
typedef ScreenAwakeSetter = void Function(bool enable);

/// Schedules [callback] after [duration]. Injected so the countdown can be
/// driven deterministically in tests without a real player or real clock.
typedef ScreenAwakeScheduler = Timer Function(
  Duration duration,
  void Function() callback,
);

/// Decides when the phone's display timeout is held off during playback.
///
/// The screen is kept awake from the moment a lecture starts playing until the
/// dashboard's `sleep_per_minute` window elapses; after that the wakelock is
/// released and the phone may blank as usual, even if the video is still
/// running. The window restarts on every sign that the student is still there:
/// playback resuming after a pause, a seek, or the player controls being
/// brought up. Pausing, finishing or leaving the screen always releases the
/// wakelock, so it can never be left on.
///
/// [timeout] is read fresh each time the countdown starts, so a value edited in
/// the dashboard mid-session takes effect at the next restart. A `null` timeout
/// means "no limit": the screen stays awake for the whole of playback, which is
/// the behaviour the app had before the setting existed and the fallback when
/// the value was never fetched.
class ScreenAwakeController {
  ScreenAwakeController({
    required ScreenAwakeSetter setAwake,
    required Duration? Function() timeout,
    void Function()? onExpired,
    ScreenAwakeScheduler scheduler = Timer.new,
  })  : _setAwake = setAwake,
        _timeout = timeout,
        _onExpired = onExpired,
        _scheduler = scheduler;

  final ScreenAwakeSetter _setAwake;
  final Duration? Function() _timeout;

  /// Called once the window elapses, so the player can stop playback. The
  /// screen going dark with a lecture still running would otherwise keep
  /// burning data and, on iOS, be suspended by the system anyway.
  final void Function()? _onExpired;
  final ScreenAwakeScheduler _scheduler;

  Timer? _timer;
  bool _awake = false;
  bool _playing = false;
  bool _disposed = false;

  /// Whether the wakelock is currently held.
  bool get isAwake => _awake;

  /// Whether a countdown to releasing the wakelock is running.
  bool get hasPendingTimeout => _timer != null;

  /// Playback started or resumed: hold the screen and (re)start the countdown.
  void playbackStarted() {
    if (_disposed) return;
    _playing = true;
    _hold();
  }

  /// The student is demonstrably still watching — a seek, or the controls being
  /// shown. Restarts the countdown, and takes the screen back if it had already
  /// been released. Ignored while paused, so hidden controls on a paused video
  /// never switch the wakelock back on.
  void userActivity() {
    if (_disposed || !_playing) return;
    _hold();
  }

  /// Playback stopped — paused, finished, or the player went away.
  void playbackStopped() {
    if (_disposed) return;
    _playing = false;
    _cancelTimer();
    _apply(false);
  }

  /// Releases the wakelock and stops any countdown for good.
  void dispose() {
    if (_disposed) return;
    _playing = false;
    _cancelTimer();
    _apply(false);
    _disposed = true;
  }

  void _hold() {
    _apply(true);
    _cancelTimer();
    final limit = _timeout();
    if (limit == null || limit <= Duration.zero) return;
    _timer = _scheduler(limit, _onTimeout);
  }

  void _onTimeout() {
    _timer = null;
    if (_disposed) return;
    // The screen is handed back to the phone's own display timeout and the
    // lecture is stopped, so a student who walked away does not keep playing
    // to a dark screen.
    _playing = false;
    _apply(false);
    _onExpired?.call();
  }

  /// The configured window changed (it arrives from the dashboard after the
  /// app starts, so a lecture opened first would otherwise never get one).
  /// Starts the countdown against the new value when playback is under way.
  void timeoutChanged() {
    if (_disposed || !_playing) return;
    _hold();
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _apply(bool value) {
    if (_awake == value) return;
    _awake = value;
    _setAwake(value);
  }
}
