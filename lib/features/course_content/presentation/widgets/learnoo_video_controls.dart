import 'dart:async';
import 'dart:ui' as ui;

import 'package:better_player_plus/better_player_plus.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'video_settings_sheet.dart';

/// Custom playback controls, replacing the packaged control bar.
///
/// Laid out like the website's `HlsVideoCustomControls`: a seek bar showing
/// both the buffered and the played range with a draggable playhead, then a row
/// with play/pause, skip, mute, the `current / duration` clock on the left, and
/// settings plus fullscreen on the right.
///
/// Two deliberate departures from the web control set:
///
///  * there is no captions button — the data source is built with
///    `enableSubtitles: false` and no subtitle track is served, so the button
///    would do nothing;
///  * prev/next *chapter* is replaced by ±10s seek, because this screen shows
///    one chapter and has no sibling list to move through, whereas seeking is
///    backed by the real controller.
///
/// The widget only renders chrome. Playback, watermarking and the moment
/// capture stay where they are, so the HLS pipeline and the iOS frame-capture
/// path are untouched.
class LearnooVideoControls extends StatefulWidget {
  const LearnooVideoControls({
    super.key,
    required this.controller,
    required this.visible,
    required this.onInteraction,
    this.isFullScreen = false,
    this.onToggleFullScreen,
    this.isBuffering = false,
    this.errorMessage,
    this.onRetry,
    this.leadingAction,
    this.trailingAction,
  });

  final BetterPlayerController controller;

  /// Whether the chrome is currently shown. The host owns the auto-hide timer.
  final bool visible;

  /// Called whenever the student touches a control, so the host can restart
  /// its auto-hide timer.
  final VoidCallback onInteraction;

  final bool isFullScreen;
  final VoidCallback? onToggleFullScreen;

  final bool isBuffering;

  /// Non-null puts the layer into its error state.
  final String? errorMessage;
  final VoidCallback? onRetry;

  /// Extra affordance on the bottom-left, e.g. "ask about this moment".
  final Widget? leadingAction;

  /// Extra affordance on the bottom-right, e.g. the download button.
  final Widget? trailingAction;

  @override
  State<LearnooVideoControls> createState() => _LearnooVideoControlsState();
}

class _LearnooVideoControlsState extends State<LearnooVideoControls> {
  static const Duration _skipStep = Duration(seconds: 10);

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _buffered = Duration.zero;
  bool _isPlaying = false;
  bool _muted = false;
  double _speed = 1.0;

  /// Non-null while the student is dragging the playhead; the bar follows the
  /// finger instead of the player until the drag ends.
  double? _dragValue;

  int _sleepTimerMinutes = 0;
  Timer? _sleepTimer;

  VoidCallback? _valueListener;

  @override
  void initState() {
    super.initState();
    _attach();
  }

  @override
  void didUpdateWidget(LearnooVideoControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _detach(oldWidget.controller);
      _attach();
    }
  }

  void _attach() {
    final video = widget.controller.videoPlayerController;
    if (video == null) return;

    void listener() {
      if (!mounted) return;
      final value = video.value;
      final buffered = value.buffered.isEmpty
          ? Duration.zero
          : value.buffered.last.end;

      setState(() {
        _position = value.position;
        _duration = value.duration ?? Duration.zero;
        _buffered = buffered;
        _isPlaying = value.isPlaying;
        _muted = value.volume == 0;
      });
    }

    _valueListener = listener;
    video.addListener(listener);
    listener();
  }

  void _detach(BetterPlayerController controller) {
    final listener = _valueListener;
    if (listener != null) {
      controller.videoPlayerController?.removeListener(listener);
    }
    _valueListener = null;
  }

  @override
  void dispose() {
    _detach(widget.controller);
    _sleepTimer?.cancel();
    super.dispose();
  }

  // ------------------------------------------------------------------
  // Actions
  // ------------------------------------------------------------------

  void _touched() => widget.onInteraction();

  Future<void> _togglePlay() async {
    _touched();
    if (_isPlaying) {
      await widget.controller.pause();
    } else {
      await widget.controller.play();
    }
  }

  Future<void> _skip(Duration delta) async {
    _touched();
    final target = _position + delta;
    final clamped = target < Duration.zero
        ? Duration.zero
        : (_duration > Duration.zero && target > _duration ? _duration : target);
    await widget.controller.seekTo(clamped);
  }

  Future<void> _toggleMute() async {
    _touched();
    await widget.controller.setVolume(_muted ? 1.0 : 0.0);
  }

  Future<void> _setSpeed(double speed) async {
    setState(() => _speed = speed);
    await widget.controller.setSpeed(speed);
  }

  /// Pauses playback when the timer runs out, matching the web behaviour.
  void _setSleepTimer(int minutes) {
    _sleepTimer?.cancel();
    setState(() => _sleepTimerMinutes = minutes);
    if (minutes <= 0) return;

    _sleepTimer = Timer(Duration(minutes: minutes), () async {
      await widget.controller.pause();
      if (mounted) setState(() => _sleepTimerMinutes = 0);
    });
  }

  void _openSettings() {
    _touched();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => VideoSettingsSheet(
        currentSpeed: _speed,
        sleepTimerMinutes: _sleepTimerMinutes,
        onSpeedChanged: _setSpeed,
        onSleepTimerChanged: _setSleepTimer,
        // Only offered when the stream actually advertises variants, so the
        // menu never lists a quality the player cannot switch to.
        qualityTracks: widget.controller.betterPlayerAsmsTracks,
        onQualitySelected: (track) {
          widget.controller.setTrack(track);
        },
      ),
    );
  }

  // ------------------------------------------------------------------
  // Formatting
  // ------------------------------------------------------------------

  static String _clock(Duration value) {
    final total = value.inSeconds < 0 ? 0 : value.inSeconds;
    final hours = total ~/ 3600;
    final minutes = (total % 3600) ~/ 60;
    final seconds = total % 60;
    final mm = minutes.toString().padLeft(hours > 0 ? 2 : 1, '0');
    final ss = seconds.toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$mm:$ss' : '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.errorMessage != null) {
      return _buildErrorLayer();
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        if (widget.isBuffering)
          const Center(
            child: SizedBox(
              height: 40,
              width: 40,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 3,
              ),
            ),
          ),
        AnimatedOpacity(
          opacity: widget.visible ? 1 : 0,
          duration: const Duration(milliseconds: 200),
          child: IgnorePointer(
            ignoring: !widget.visible,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Scrim, so white chrome stays readable over a bright frame.
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0x66000000),
                        Color(0x00000000),
                        Color(0x99000000),
                      ],
                      stops: [0, 0.45, 1],
                    ),
                  ),
                ),
                if (!widget.isBuffering) _buildCentreCluster(),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _buildBottomBar(),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorLayer() {
    return ColoredBox(
      color: const Color(0xFF111827),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                color: Colors.white70,
                size: 40,
              ),
              const SizedBox(height: 12),
              Text(
                widget.errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
              if (widget.onRetry != null) ...[
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: widget.onRetry,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: Text('course.retry'.tr()),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF111827),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Big transport cluster: skip back, play/pause, skip forward.
  ///
  /// Laid out with [Directionality] forced to LTR so the skip arrows keep
  /// pointing the way time runs in Arabic too.
  Widget _buildCentreCluster() {
    return Center(
      child: Directionality(
        textDirection: ui.TextDirection.ltr,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _roundButton(
              icon: Icons.replay_10,
              size: 30,
              onPressed: () => _skip(-_skipStep),
              tooltip: 'course.skip_back'.tr(),
            ),
            const SizedBox(width: 24),
            _roundButton(
              icon: _isPlaying ? Icons.pause : Icons.play_arrow,
              size: 42,
              filled: true,
              onPressed: _togglePlay,
              tooltip: _isPlaying ? 'course.pause'.tr() : 'course.play'.tr(),
            ),
            const SizedBox(width: 24),
            _roundButton(
              icon: Icons.forward_10,
              size: 30,
              onPressed: () => _skip(_skipStep),
              tooltip: 'course.skip_forward'.tr(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    final durationMs = _duration.inMilliseconds;
    final positionMs = _position.inMilliseconds.clamp(0, durationMs).toDouble();
    final value = _dragValue ?? positionMs;

    return SafeArea(
      top: false,
      left: false,
      right: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The seek bar always runs left-to-right, like the web's, which
            // forces `direction: ltr` on its range input for the same reason.
            Directionality(
              textDirection: ui.TextDirection.ltr,
              child: _buildSeekBar(durationMs, value),
            ),
            Row(
              children: [
                _roundButton(
                  icon: _isPlaying ? Icons.pause : Icons.play_arrow,
                  size: 22,
                  onPressed: _togglePlay,
                  tooltip:
                      _isPlaying ? 'course.pause'.tr() : 'course.play'.tr(),
                ),
                _roundButton(
                  icon: _muted ? Icons.volume_off : Icons.volume_up,
                  size: 20,
                  onPressed: _toggleMute,
                  tooltip: _muted
                      ? 'course.unmute'.tr()
                      : 'course.mute'.tr(),
                ),
                const SizedBox(width: 4),
                // Digits stay LTR so a timestamp is not mirrored in Arabic.
                Directionality(
                  textDirection: ui.TextDirection.ltr,
                  child: Text(
                    '${_clock(_position)} / ${_clock(_duration)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const Spacer(),
                if (widget.leadingAction != null) widget.leadingAction!,
                if (widget.trailingAction != null) widget.trailingAction!,
                _roundButton(
                  icon: Icons.settings,
                  size: 20,
                  badge: _sleepTimerMinutes > 0 || _speed != 1.0,
                  onPressed: _openSettings,
                  tooltip: 'course.player_settings'.tr(),
                ),
                if (widget.onToggleFullScreen != null)
                  _roundButton(
                    icon: widget.isFullScreen
                        ? Icons.fullscreen_exit
                        : Icons.fullscreen,
                    size: 22,
                    onPressed: () {
                      _touched();
                      widget.onToggleFullScreen!();
                    },
                    tooltip: widget.isFullScreen
                        ? 'course.exit_fullscreen'.tr()
                        : 'course.fullscreen'.tr(),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSeekBar(int durationMs, double value) {
    final bufferedFraction = durationMs <= 0
        ? 0.0
        : (_buffered.inMilliseconds / durationMs).clamp(0.0, 1.0);

    return SizedBox(
      height: 24,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Track plus the buffered range behind the slider itself.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: SizedBox(
              height: 3,
              child: Row(
                children: [
                  Expanded(
                    flex: (bufferedFraction * 1000).round(),
                    child: const DecoratedBox(
                      decoration: BoxDecoration(color: Color(0x80FFFFFF)),
                    ),
                  ),
                  Expanded(
                    flex: 1000 - (bufferedFraction * 1000).round(),
                    child: const DecoratedBox(
                      decoration: BoxDecoration(color: Color(0x40FFFFFF)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              activeTrackColor: const Color(0xFFFF0033),
              inactiveTrackColor: Colors.transparent,
              thumbColor: const Color(0xFFFF0033),
              overlayColor: const Color(0x33FF0033),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
              min: 0,
              max: durationMs <= 0 ? 1 : durationMs.toDouble(),
              value: durationMs <= 0 ? 0 : value.clamp(0, durationMs).toDouble(),
              onChanged: durationMs <= 0
                  ? null
                  : (next) {
                      _touched();
                      setState(() => _dragValue = next);
                    },
              onChangeEnd: durationMs <= 0
                  ? null
                  : (next) async {
                      await widget.controller
                          .seekTo(Duration(milliseconds: next.round()));
                      if (mounted) setState(() => _dragValue = null);
                    },
            ),
          ),
        ],
      ),
    );
  }

  /// A control button sized to the 40dp minimum touch target regardless of the
  /// icon it draws.
  Widget _roundButton({
    required IconData icon,
    required double size,
    required VoidCallback onPressed,
    required String tooltip,
    bool filled = false,
    bool badge = false,
  }) {
    final button = Semantics(
      button: true,
      label: tooltip,
      child: InkResponse(
        onTap: onPressed,
        radius: 26,
        child: Container(
          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          alignment: Alignment.center,
          decoration: filled
              ? const BoxDecoration(
                  color: Color(0x59000000),
                  shape: BoxShape.circle,
                )
              : null,
          padding: filled ? const EdgeInsets.all(8) : EdgeInsets.zero,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(icon, color: Colors.white, size: size),
              if (badge)
                Positioned(
                  right: -1,
                  top: -1,
                  child: Container(
                    height: 7,
                    width: 7,
                    decoration: const BoxDecoration(
                      color: Color(0xFF3EA6FF),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    return Tooltip(message: tooltip, child: button);
  }
}
