import 'package:better_player_plus/better_player_plus.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/video_quality.dart';

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
    this.selectedTrack,
    this.selectedQualityId,
    this.onQualityOptionSelected,
    this.onQualitySelected,
  });

  final double currentSpeed;

  /// Minutes remaining on the sleep timer, or 0 when it is off.
  final int sleepTimerMinutes;

  final ValueChanged<double> onSpeedChanged;
  final ValueChanged<int> onSleepTimerChanged;

  /// Variants the stream advertises. Even if empty (e.g. progressive MP4 or
  /// offline video), default fake qualities are always provided.
  final List<BetterPlayerAsmsTrack> qualityTracks;

  /// Track the player is on now; `null` / the default track means Auto.
  final BetterPlayerAsmsTrack? selectedTrack;

  /// Explicitly chosen quality id (e.g. '1080p', 'auto', or null).
  final String? selectedQualityId;

  /// Called with the chosen quality option, or null for Auto.
  final ValueChanged<VideoQualityOption?>? onQualityOptionSelected;

  /// Called with the chosen rendition, or with
  /// [BetterPlayerAsmsTrack.defaultTrack] for Auto.
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
            if (_qualityOptions.isNotEmpty &&
                (onQualityOptionSelected != null || onQualitySelected != null)) ...[
              const SizedBox(height: 24),
              _heading(Icons.high_quality_outlined, 'course.quality'.tr()),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  // Auto first, like the web's quality submenu.
                  _chip(
                    label: autoQualityLabel(
                      _qualityOptions,
                      'course.quality_auto'.tr(),
                    ),
                    selected: _selectedQuality == null,
                    onTap: () {
                      if (onQualityOptionSelected != null) {
                        onQualityOptionSelected!(null);
                      } else if (onQualitySelected != null) {
                        onQualitySelected!(BetterPlayerAsmsTrack.defaultTrack());
                      }
                      Navigator.pop(context);
                    },
                  ),
                  ..._qualityOptions.map(
                    (option) => _chip(
                      label: option.label,
                      selected: option.id == _selectedQuality?.id,
                      onTap: () {
                        if (onQualityOptionSelected != null) {
                          onQualityOptionSelected!(option);
                        } else if (onQualitySelected != null && option.track != null) {
                          onQualitySelected!(option.track!);
                        }
                        Navigator.pop(context);
                      },
                    ),
                  ),
                ],
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

  /// Renditions available for selection, guaranteed to include standard heights up to 1080p.
  List<VideoQualityOption> get _qualityOptions =>
      videoQualityOptions(qualityTracks);

  VideoQualityOption? get _selectedQuality {
    if (selectedQualityId != null) {
      if (selectedQualityId == 'auto') return null;
      for (final option in _qualityOptions) {
        if (option.id == selectedQualityId) return option;
      }
    }
    return selectedQualityOption(_qualityOptions, selectedTrack);
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
