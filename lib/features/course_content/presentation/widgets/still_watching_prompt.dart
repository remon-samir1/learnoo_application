import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// The "are you still watching?" notice drawn over the lecture player when the
/// dashboard's sleep interval ends.
///
/// It reads [secondsLeft] — `null` hides it, a number shows the notice with
/// that many seconds left before the video stops — and calls [onStillWatching]
/// when the student presses the button. The countdown itself lives in
/// `ScreenAwakeController`; this widget only draws it, so the inline and the
/// fullscreen player show the same notice from the same clock.
///
/// Only the card takes touches: the dimmed backdrop lets taps through, so the
/// player's own controls (pause included) keep working while it is up.
class StillWatchingPrompt extends StatelessWidget {
  const StillWatchingPrompt({
    super.key,
    required this.secondsLeft,
    required this.total,
    required this.onStillWatching,
  });

  final ValueListenable<int?> secondsLeft;

  /// Length of the whole notice, for the countdown ring.
  final Duration total;

  final VoidCallback onStillWatching;

  static const Key cardKey = Key('still-watching-prompt');
  static const Key buttonKey = Key('still-watching-button');

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int?>(
      valueListenable: secondsLeft,
      builder: (context, seconds, _) {
        if (seconds == null) return const SizedBox.shrink();
        final totalSeconds = total.inSeconds <= 0 ? 1 : total.inSeconds;
        return Stack(
          fit: StackFit.expand,
          children: [
            const IgnorePointer(child: ColoredBox(color: Colors.black54)),
            Center(
              child: Padding(
                padding: const EdgeInsets.all(12),
                // The inline player is only 220pt tall; scaling down keeps the
                // whole card, button included, inside it.
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: _Card(
                    seconds: seconds,
                    fraction: (seconds / totalSeconds).clamp(0.0, 1.0),
                    onStillWatching: onStillWatching,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.seconds,
    required this.fraction,
    required this.onStillWatching,
  });

  final int seconds;
  final double fraction;
  final VoidCallback onStillWatching;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        key: StillWatchingPrompt.cardKey,
        constraints: const BoxConstraints(maxWidth: 320),
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
        decoration: BoxDecoration(
          color: const Color(0xEE1B1F2A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 40,
                  height: 40,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: fraction,
                        strokeWidth: 3,
                        color: const Color(0xFF3451E5),
                        backgroundColor: Colors.white24,
                      ),
                      Text(
                        '$seconds',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'course.still_watching_title'.tr(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'course.still_watching_countdown'.tr(
                          args: ['$seconds'],
                        ),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 40,
              child: ElevatedButton.icon(
                key: StillWatchingPrompt.buttonKey,
                onPressed: onStillWatching,
                icon: const Icon(Icons.check_rounded, size: 18),
                label: Text('course.still_watching_button'.tr()),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3451E5),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
