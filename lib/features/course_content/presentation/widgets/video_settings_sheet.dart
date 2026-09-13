import 'package:better_player_plus/better_player_plus.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Playback speeds offered, matching `SPEED_OPTIONS` in the web player.
const List<double> kVideoSpeedOptions = [
  0.25,
  0.5,
  0.75,
  1,
  1.25,
  1.5,
  1.75,
  2,
];

/// Sleep-timer choices in minutes, matching `SLEEP_TIMER_OPTIONS` on the web.
/// `0` means off.
const List<int> kSleepTimerOptions = [0, 5, 10, 15, 30, 45, 60];

/// The player's settings menu.
///
/// The app previously cycled through a short speed list with a tap on a chip,
/// so a student could not pick a speed directly and had no sleep timer at all.
/// This is the app's version of the website's settings panel.
class VideoSettingsSheet extends StatelessWidget {
  const VideoSettingsSheet({
    super.key,
    required this.currentSpeed,
    required this.sleepTimerMinutes,
    required this.onSpeedChanged,
    required this.onSleepTimerChanged,
    this.qualityTracks = const [],
    this.onQualitySelected,
  });

  final double currentSpeed;

  /// Minutes remaining on the sleep timer, or 0 when it is off.
  final int sleepTimerMinutes;

  final ValueChanged<double> onSpeedChanged;
  final ValueChanged<int> onSleepTimerChanged;

  /// Variants the stream advertises. Empty for a progressive file, in which
  /// case no quality section is shown — the web hides its quality submenu the
  /// same way rather than offering a choice the player cannot honour.
  final List<BetterPlayerAsmsTrack> qualityTracks;

  final ValueChanged<BetterPlayerAsmsTrack>? onQualitySelected;

  static String formatSpeed(double speed) =>
      speed == speed.truncateToDouble() ? '${speed.toInt()}x' : '${speed}x';

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE5E7EB),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            _heading(Icons.speed, 'course.playback_speed'.tr()),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: kVideoSpeedOptions
                  .map(
                    (speed) => _chip(
                      label: formatSpeed(speed),
                      selected: speed == currentSpeed,
                      onTap: () {
                        onSpeedChanged(speed);
                        Navigator.pop(context);
                      },
                    ),
                  )
                  .toList(),
            ),
            if (_selectableTracks.isNotEmpty &&
                onQualitySelected != null) ...[
              const SizedBox(height: 24),
              _heading(Icons.high_quality_outlined, 'course.quality'.tr()),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _selectableTracks
                    .map(
                      (track) => _chip(
                        label: _qualityLabel(track),
                        selected: false,
                        onTap: () {
                          onQualitySelected!(track);
                          Navigator.pop(context);
                        },
                      ),
                    )
                    .toList(),
              ),
            ],
            const SizedBox(height: 24),
            _heading(Icons.bedtime_outlined, 'course.sleep_timer'.tr()),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: kSleepTimerOptions
                  .map(
                    (minutes) => _chip(
                      label: minutes == 0
                          ? 'course.sleep_timer_off'.tr()
                          : 'course.minutes_short'.tr(args: ['$minutes']),
                      selected: minutes == sleepTimerMinutes,
                      onTap: () {
                        onSleepTimerChanged(minutes);
                        Navigator.pop(context);
                      },
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  /// Tracks worth offering: anything that reports a height, plus the
  /// player's own "auto" entry when the stream provides one.
  List<BetterPlayerAsmsTrack> get _selectableTracks =>
      qualityTracks.where((t) => (t.height ?? 0) > 0).toList();

  /// `720p` style label, falling back to the bitrate when the variant does not
  /// report a resolution.
  static String _qualityLabel(BetterPlayerAsmsTrack track) {
    final height = track.height ?? 0;
    if (height > 0) return '${height}p';
    final bitrate = track.bitrate ?? 0;
    if (bitrate > 0) return '${(bitrate / 1000).round()} kbps';
    return 'course.quality_auto'.tr();
  }

  Widget _heading(IconData icon, String label) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.primaryBlue),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1F2937),
          ),
        ),
      ],
    );
  }

  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryBlue : const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : const Color(0xFF374151),
          ),
        ),
      ),
    );
  }
}
