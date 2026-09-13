/// Choosing what to feed the video player for a chapter.
///
/// Ported from `src/lib/chapter-playback-urls.ts` and
/// `src/lib/video-stream-detect.ts`. Two things the app was getting wrong:
///
///  * it only ever looked at `attributes.video`, so chapters whose stream lives
///    at `video_hls_url` / `playlist` played nothing;
///  * its HLS check was a substring test for `.m3u8`, which misses the API's
///    own extension-less playlists at `/hls/chapter/{id}/playlist`.
library;

import '../../../core/network/api_constants.dart';
import '../../../core/utils/coerce.dart';

/// Playable sources for one chapter.
class ChapterStreams {
  const ChapterStreams({required this.primaryUrl, required this.mp4Fallback});

  /// Preferred source — HLS whenever one exists.
  final String primaryUrl;

  /// Progressive MP4 to fall back to when HLS fails on a device.
  final String mp4Fallback;

  bool get hasVideo => primaryUrl.isNotEmpty || mp4Fallback.isNotEmpty;

  /// The URL to hand the player first.
  String get bestUrl => primaryUrl.isNotEmpty ? primaryUrl : mp4Fallback;

  bool get isHls => isHlsStreamUrl(bestUrl);
}

/// HLS master or media playlist.
///
/// Accepts extension-less playlists: anything under `/hls/` and anything whose
/// path ends in `/playlist` counts, not just `.m3u8`.
bool isHlsStreamUrl(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) return false;
  if (trimmed.toLowerCase().contains('.m3u8')) return true;

  try {
    final path = Uri.parse(trimmed).path.toLowerCase();
    if (path.contains('/hls/')) return true;
    if (path.endsWith('/playlist') || path.endsWith('/playlist.m3u8')) {
      return true;
    }
  } catch (_) {
    return false;
  }
  return false;
}

/// Progressive file the player can stream directly.
bool isMp4StreamUrl(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty || trimmed.startsWith('data:')) return false;
  if (RegExp(r'\.(mp4|m4v|mov|webm|m4a|mkv)($|\?|#)', caseSensitive: false)
      .hasMatch(trimmed)) {
    return true;
  }

  try {
    final path = Uri.parse(trimmed).path.toLowerCase();
    if ((path.contains('/storage/') || path.contains('/uploads/')) &&
        !path.contains('/hls/') &&
        !path.endsWith('.m3u8') &&
        !path.endsWith('/playlist')) {
      return true;
    }
  } catch (_) {
    return false;
  }
  return false;
}

/// Turns a relative path from the API into an absolute URL.
String absoluteMediaUrl(String raw) {
  var url = raw.trim().replaceAll(r'\', '/');
  if (url.isEmpty) return '';
  if (url.startsWith('http://') || url.startsWith('https://')) return url;
  if (!url.startsWith('/')) url = '/$url';
  return '${ApiConstants.baseUrl}$url';
}

/// Picks the primary source and MP4 fallback for a chapter.
///
/// Priority mirrors `pickChapterStreams`: an explicit HLS field, then the
/// generic `video` field when it looks like HLS, then the API's per-chapter
/// playlist endpoint. MP4 is kept aside as a fallback rather than used as the
/// primary whenever HLS is available.
ChapterStreams pickChapterStreams({
  required Object? chapterId,
  required Map<String, dynamic> attributes,
}) {
  final explicitHls = absoluteMediaUrl(
    coerceString(attributes['video_hls_url']) ??
        coerceString(attributes['playlist']) ??
        '',
  );
  final explicitMp4 = absoluteMediaUrl(
    coerceString(attributes['main_video']) ??
        coerceString(attributes['video_mp4_url']) ??
        '',
  );
  final video = absoluteMediaUrl(coerceString(attributes['video']) ?? '');

  final hlsFromVideo = isHlsStreamUrl(video) ? video : '';
  final mp4FromVideo = isMp4StreamUrl(video) ? video : '';

  var primary = '';
  if (explicitHls.isNotEmpty) {
    primary = explicitHls;
  } else if (hlsFromVideo.isNotEmpty) {
    primary = hlsFromVideo;
  }

  final id = coercePositiveInt(chapterId);
  if (primary.isEmpty && id != null) {
    // The API serves an encrypted playlist per chapter even when no explicit
    // HLS field is present.
    primary = ApiConstants.chapterHlsPlaylist(id);
  }

  final fallback = explicitMp4.isNotEmpty ? explicitMp4 : mp4FromVideo;

  // Nothing HLS-shaped and no id to build one: play the progressive file.
  if (primary.isEmpty) {
    return ChapterStreams(primaryUrl: fallback, mp4Fallback: '');
  }

  return ChapterStreams(primaryUrl: primary, mp4Fallback: fallback);
}
