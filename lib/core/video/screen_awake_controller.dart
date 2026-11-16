import 'dart:async';

import 'package:flutter/foundation.dart';

/// Turns the platform wakelock on or off.
typedef ScreenAwakeSetter = void Function(bool enable);

/// Schedules [callback] after [duration]. Injected so the countdown can be
/// driven deterministically in tests without a real player or real clock.
typedef ScreenAwakeScheduler = Timer Function(
  Duration duration,
  void Function() callback,
);

/// Runs the dashboard's `sleep_per_minute` window during playback, asks the
/// student whether they are still watching when it ends, and pauses the
/// lecture if nobody answers.
///
/// The screen is kept awake from the moment a lecture starts playing. When the
/// window elapses the video keeps playing and [promptSecondsLeft] starts
/// counting down from [promptDuration] — the player shows "are you still
/// watching? the video stops in N seconds" with a "still watching" button, and
/// the screen stays awake for the whole notice. Pressing the button
/// ([stillWatching]) hides the notice and starts a fresh window with no
/// interruption. If the countdown reaches zero the lecture is paused through
/// [onExpired] and stays paused until the student presses play, which starts a
/// new window. Pausing, finishing or leaving the screen always hides the
/// notice and releases the wakelock, so it can never be left on.
///
/// Before the notice the window also restarts on other signs that the student
/// is there — a seek, or the player controls being brought up. Once the notice
/// is up only the button (or pausing / playing again) answers it, so a stray
/// tap cannot silently dismiss it.
///
/// [timeout] is read fresh each time the window starts, so a value edited in
/// the dashboard mid-session takes effect at the next restart. A `null` timeout
/// means "no limit": the screen stays awake for the whole of playback and the
/// notice never appears, the behaviour the app had before the setting existed
/// and the fallback when the value was never fetched.
class ScreenAwakeController {
  ScreenAwakeController({
    required ScreenAwakeSetter setAwake,
    required Duration? Function() timeout,
    void Function()? onExpired,
    ScreenAwakeScheduler scheduler = Timer.new,
    this.promptDuration = defaultPromptDuration,
  })  : _setAwake = setAwake,
        _timeout = timeout,
        _onExpired = onExpired,
        _scheduler = scheduler;

  /// How long the "still watching?" notice stays up before the video pauses.
  static const Duration defaultPromptDuration = Duration(seconds: 15);

  final Duration promptDuration;

  final ScreenAwakeSetter _setAwake;
  final Duration? Function() _timeout;

  /// Called when the notice runs out unanswered, so the player can pause.
  final void Function()? _onExpired;
  final ScreenAwakeScheduler _scheduler;

  /// Whole seconds left on the "still watching?" notice, or `null` while no
  /// notice is shown. The player listens to this to draw the notice.
  final ValueNotifier<int?> promptSecondsLeft = ValueNotifier<int?>(null);

  Timer? _timer;
  bool _awake = false;
  bool _playing = false;
  bool _disposed = false;

  /// Whether the wakelock is currently held.
  bool get isAwake => _awake;

  /// Whether a countdown (the window or the notice) is running.
  bool get hasPendingTimeout => _timer != null;

  /// Whether the "still watching?" notice is up.
  bool get isPrompting => promptSecondsLeft.value != null;

  /// Playback started or resumed: hold the screen and (re)start the window.
  void playbackStarted() {
    if (_disposed) return;
    _playing = true;
    _hold();
  }

  /// The student is demonstrably still watching — a seek, or the controls being
  /// shown. Restarts the window, and takes the screen back if it had already
  /// been released. Ignored while paused, so hidden controls on a paused video
  /// never switch the wakelock back on, and while the notice is up, which only
  /// its own button answers.
  void userActivity() {
    if (_disposed || !_playing || isPrompting) return;
    _hold();
  }

  /// The student pressed "still watching" on the notice: hide it and start a
  /// fresh window without touching playback.
  void stillWatching() {
    if (_disposed || !_playing || !isPrompting) return;
    _hold();
  }

  /// Playback stopped — paused, finished, or the player went away.
  void playbackStopped() {
    if (_disposed) return;
    _playing = false;
    _cancelTimer();
    _setPrompt(null);
    _apply(false);
  }

  /// Releases the wakelock and stops any countdown for good.
  void dispose() {
    if (_disposed) return;
    _playing = false;
    _cancelTimer();
    _setPrompt(null);
    _apply(false);
    _disposed = true;
    promptSecondsLeft.dispose();
  }

  void _hold() {
    _apply(true);
    _cancelTimer();
    _setPrompt(null);
    final limit = _timeout();
    if (limit == null || limit <= Duration.zero) return;
    _timer = _scheduler(limit, _onWindowElapsed);
  }

  void _onWindowElapsed() {
    _timer = null;
    if (_disposed || !_playing) return;
    // The video keeps playing and the screen stays on while the student is
    // asked; nothing stops until the notice itself runs out.
    final seconds = promptDuration.inSeconds;
    if (seconds <= 0) {
      _expire();
      return;
    }
    _setPrompt(seconds);
    _scheduleTick();
  }

  void _scheduleTick() {
    _timer = _scheduler(const Duration(seconds: 1), _onTick);
  }

  void _onTick() {
    _timer = null;
    if (_disposed || !_playing) return;
    final left = (promptSecondsLeft.value ?? 0) - 1;
    if (left <= 0) {
      _expire();
      return;
    }
    _setPrompt(left);
    _scheduleTick();
  }

  void _expire() {
    // Nobody answered: the lecture is paused and the screen handed back to the
    // phone's own display timeout until the student presses play again.
    _playing = false;
    _setPrompt(null);
    _apply(false);
    _onExpired?.call();
  }

  /// The configured window changed (it arrives from the dashboard after the
  /// app starts, so a lecture opened first would otherwise never get one).
  /// Starts the window against the new value when playback is under way; a
  /// notice already on screen is left to run.
  void timeoutChanged() {
    if (_disposed || !_playing || isPrompting) return;
    _hold();
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _setPrompt(int? seconds) {
    if (_disposed) return;
    promptSecondsLeft.value = seconds;
  }

  void _apply(bool value) {
    if (_awake == value) return;
    _awake = value;
    _setAwake(value);
  }
}
