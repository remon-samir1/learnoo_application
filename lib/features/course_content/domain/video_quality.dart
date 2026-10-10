/// Quality menu for the chapter player.
///
/// Merges real renditions from the HLS master playlist with standard fake qualities
/// (1080p, 720p, 480p, 360p) so that at least four qualities up to 1080p are always
/// offered. Real renditions switch playback, while synthetic placeholders remain
/// visible and selectable without interfering with playback.
library;

import 'package:better_player_plus/better_player_plus.dart';

/// Standard quality heights up to 1080p, ensuring at least four qualities are always available.
const List<int> kDefaultQualityHeights = [1080, 720, 480, 360];

/// One selectable entry of the quality menu.
class VideoQualityOption {
  const VideoQualityOption({
    required this.id,
    required this.label,
    this.track,
    this.height,
    this.bitrate,
    this.isReal = true,
  });

  /// Stable id, like the web's (`720p`, or `level-N` without a height).
  final String id;

  /// `1080p` / `720p`, or `850 kbps` when the variant has no resolution.
  final String label;

  /// Vertical resolution, when the playlist reports one.
  final int? height;

  /// Peak bitrate in bits per second, when reported.
  final int? bitrate;

  /// Track to hand to `BetterPlayerController.setTrack`. Null if fake.
  final BetterPlayerAsmsTrack? track;

  /// Whether this variant exists in the stream or is a synthetic placeholder.
  final bool isReal;
}

/// Whether [track] is the player's adaptive ("Auto") track.
bool isAutoQualityTrack(BetterPlayerAsmsTrack? track) {
  if (track == null) return true;
  return (track.width ?? 0) == 0 &&
      (track.height ?? 0) == 0 &&
      (track.bitrate ?? 0) == 0;
}

/// Renditions from the master playlist merged with standard fake qualities (at least 4 up to 1080p).
///
/// Drops the player's synthetic default track (Auto is offered separately)
/// and collapses variants of the same height to the highest-bitrate one.
/// Ensures standard heights up to 1080p are always available.
List<VideoQualityOption> videoQualityOptions(
  List<BetterPlayerAsmsTrack> tracks, {
  List<int> defaultHeights = kDefaultQualityHeights,
}) {
  final byHeight = <int, BetterPlayerAsmsTrack>{};
  final byBitrate = <int, BetterPlayerAsmsTrack>{};

  for (final track in tracks) {
    if (isAutoQualityTrack(track)) continue;
    final height = track.height ?? 0;
    final bitrate = track.bitrate ?? 0;
    if (height > 0) {
      final existing = byHeight[height];
      if (existing == null || (existing.bitrate ?? 0) < bitrate) {
        byHeight[height] = track;
      }
    } else if (bitrate > 0) {
      byBitrate.putIfAbsent(bitrate, () => track);
    }
  }

  // Combine real heights and fake heights so there are always at least four
  // qualities up to 1080p (e.g. 1080p, 720p, 480p, 360p).
  final allHeights = <int>{...byHeight.keys, ...defaultHeights};

  final options = <VideoQualityOption>[
    for (final height in allHeights)
      VideoQualityOption(
        id: '${height}p',
        label: '${height}p',
        height: height,
        bitrate: byHeight[height]?.bitrate,
        track: byHeight[height],
        isReal: byHeight.containsKey(height),
      ),
    for (final entry in byBitrate.entries)
      VideoQualityOption(
        id: 'bitrate-${entry.key}',
        label: '${(entry.key / 1000).round()} kbps',
        bitrate: entry.key,
        track: entry.value,
        isReal: true,
      ),
  ];

  // Same order as the web: highest resolution first, then highest bitrate.
  options.sort((a, b) {
    final byH = (b.height ?? 0).compareTo(a.height ?? 0);
    if (byH != 0) return byH;
    return (b.bitrate ?? 0).compareTo(a.bitrate ?? 0);
  });
  return options;
}

/// The web's Auto label: `Auto (1080p)` with the best available height, or
/// just [autoWord] when no rendition reports one.
String autoQualityLabel(List<VideoQualityOption> options, String autoWord) {
  var maxHeight = 0;
  for (final option in options) {
    final h = option.height ?? 0;
    if (h > maxHeight) maxHeight = h;
  }
  return maxHeight > 0 ? '$autoWord (${maxHeight}p)' : autoWord;
}

/// The option matching the player's current [track], or `null` for Auto.
VideoQualityOption? selectedQualityOption(
  List<VideoQualityOption> options,
  BetterPlayerAsmsTrack? track,
) {
  if (isAutoQualityTrack(track)) return null;
  for (final option in options) {
    final t = option.track;
    if (t != null &&
        t.height == track!.height &&
        t.width == track.width &&
        t.bitrate == track.bitrate) {
      return option;
    }
  }
  for (final option in options) {
    if ((option.height ?? 0) > 0 && option.height == track!.height) {
      return option;
    }
  }
  return null;
}
