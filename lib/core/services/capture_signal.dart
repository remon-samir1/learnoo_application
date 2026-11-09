/// Combines the screen-capture signals the platform gives the app into one
/// answer, and lets a stale one be corrected.
///
/// Two independent sources report capture: the app's own native channel
/// (`recording_started` / `recording_stopped`) and the `screen_capture_event`
/// plugin. Both are *edge* signals — they say "capture started" and rely on a
/// later event to say it stopped.
///
/// On iOS that is not enough. `UIScreen.main.isCaptured` is already true at
/// launch for AirPlay, display mirroring and a recording that was started
/// before the app was opened, and both sources report that straight away. If
/// no `UIScreen.capturedDidChangeNotification` ever follows — because nothing
/// changed, or because the notification was missed while the app was
/// suspended — the "started" edge is never cancelled and the app believes it
/// is being recorded for the rest of the session. Every lecture then paused
/// and muted itself a moment after the student pressed play.
///
/// [verify] exists for that: the platform is asked for the current truth and
/// the answer replaces both edges, so a latched signal clears itself.
class CaptureSignal {
  bool _native = false;
  bool _plugin = false;

  /// Whether the screen is believed to be captured right now.
  bool get isCapturing => _native || _plugin;

  /// Last value reported by the app's own native channel.
  bool get nativeReported => _native;

  /// Last value reported by the `screen_capture_event` plugin.
  bool get pluginReported => _plugin;

  /// Reports the app's native channel. Returns true when [isCapturing] moved.
  bool setNative(bool capturing) => _set(native: capturing, plugin: _plugin);

  /// Reports the plugin. Returns true when [isCapturing] moved.
  bool setPlugin(bool capturing) => _set(native: _native, plugin: capturing);

  /// Replaces both edges with the platform's current answer, so a signal that
  /// was never cancelled cannot keep playback muted forever. Returns true when
  /// [isCapturing] moved.
  bool verify(bool capturing) => _set(native: capturing, plugin: capturing);

  bool _set({required bool native, required bool plugin}) {
    final before = isCapturing;
    _native = native;
    _plugin = plugin;
    return isCapturing != before;
  }
}
