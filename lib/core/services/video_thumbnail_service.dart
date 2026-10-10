import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:flutter/foundation.dart';

/// Generates and caches video preview frames from network URLs.
///
/// Frame extraction downloads part of the video, so it is the **fallback**
/// for chapters without an API picture — and it is rationed:
///  * at most [maxConcurrent] extractions run at once; the rest wait in a
///    queue, so a long list never floods the network;
///  * results are cached on disk (keyed by URL hash) and in memory;
///  * a URL that failed is not retried during the session;
///  * HLS playlists are skipped outright: the platform extractor cannot
///    decode them, and trying (three times, as before) is what kept the
///    shimmer spinning for so long.
class VideoThumbnailService {
  static VideoThumbnailService? _instance;
  static VideoThumbnailService get instance =>
      _instance ??= VideoThumbnailService._internal();

  VideoThumbnailService._internal();

  /// Extractions allowed to run in parallel.
  static const int maxConcurrent = 2;

  /// Upper bound for one extraction; a stalled download must not hold a slot.
  static const Duration extractionTimeout = Duration(seconds: 20);

  final Map<String, String> _thumbnailCache = {};
  final Map<String, Future<String?>> _inFlight = {};
  final Set<String> _failed = {};
  final Queue<Completer<void>> _waiting = Queue();
  int _running = 0;
  Directory? _dir;

  Future<Directory> _getThumbnailDirectory() async {
    final cached = _dir;
    if (cached != null) return cached;
    final tempDir = await getTemporaryDirectory();
    final thumbDir = Directory('${tempDir.path}/video_thumbnails');
    if (!await thumbDir.exists()) {
      await thumbDir.create(recursive: true);
    }
    return _dir = thumbDir;
  }

  String _generateCacheKey(String url) => md5.convert(url.codeUnits).toString();

  String _getThumbnailPath(String url, Directory thumbDir) =>
      '${thumbDir.path}/${_generateCacheKey(url)}.jpg';

  /// Whether frames can be extracted from [videoUrl] at all.
  static bool isExtractable(String videoUrl) {
    if (videoUrl.isEmpty) return false;
    final path = videoUrl.toLowerCase().split('?').first;
    return !path.endsWith('.m3u8');
  }

  /// Cached thumbnail path for [videoUrl], or `null` — never extracts.
  Future<String?> cachedThumbnail(String videoUrl) async {
    if (videoUrl.isEmpty) return null;
    final memory = _thumbnailCache[videoUrl];
    if (memory != null && await File(memory).exists()) return memory;
    final path = _getThumbnailPath(videoUrl, await _getThumbnailDirectory());
    if (await File(path).exists()) {
      _thumbnailCache[videoUrl] = path;
      return path;
    }
    return null;
  }

  /// Check if thumbnail exists in cache
  Future<bool> hasThumbnail(String videoUrl) async =>
      await cachedThumbnail(videoUrl) != null;

  /// Returns the thumbnail file for [videoUrl], extracting it when needed.
  ///
  /// [stillNeeded] is checked when the request reaches the front of the queue;
  /// returning `false` (the row scrolled away / was disposed) skips the work.
  Future<String?> generateThumbnail(
    String videoUrl, {
    bool Function()? stillNeeded,
  }) async {
    if (!isExtractable(videoUrl) || _failed.contains(videoUrl)) return null;

    final cached = await cachedThumbnail(videoUrl);
    if (cached != null) return cached;

    final pending = _inFlight[videoUrl];
    if (pending != null) return pending;

    final future = _extractQueued(videoUrl, stillNeeded);
    _inFlight[videoUrl] = future;
    try {
      return await future;
    } finally {
      _inFlight.remove(videoUrl);
    }
  }

  Future<String?> _extractQueued(
    String videoUrl,
    bool Function()? stillNeeded,
  ) async {
    if (_running >= maxConcurrent) {
      final slot = Completer<void>();
      _waiting.add(slot);
      await slot.future;
    } else {
      _running++;
    }

    try {
      if (stillNeeded != null && !stillNeeded()) return null;

      final path = _getThumbnailPath(videoUrl, await _getThumbnailDirectory());
      final bytes = await VideoThumbnail.thumbnailData(
        video: videoUrl,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 320,
        maxHeight: 240,
        quality: 75,
        timeMs: 1000,
      ).timeout(extractionTimeout);

      if (bytes == null || bytes.isEmpty) {
        _failed.add(videoUrl);
        return null;
      }
      await File(path).writeAsBytes(bytes, flush: true);
      _thumbnailCache[videoUrl] = path;
      return path;
    } catch (e) {
      _failed.add(videoUrl);
      debugPrint('[VideoThumbnailService] Frame extraction failed: $e');
      return null;
    } finally {
      // Hand the slot straight to the next waiter, or free it.
      if (_waiting.isNotEmpty) {
        _waiting.removeFirst().complete();
      } else {
        _running--;
      }
    }
  }

  /// Clear all cached thumbnails
  Future<void> clearCache() async {
    try {
      final thumbDir = await _getThumbnailDirectory();
      if (await thumbDir.exists()) {
        final files = await thumbDir.list().toList();
        for (final file in files) {
          if (file is File) {
            await file.delete();
          }
        }
      }
      _thumbnailCache.clear();
      _failed.clear();
    } catch (e) {
      debugPrint('[VideoThumbnailService] Error clearing cache: $e');
    }
  }

  /// Clear specific thumbnail from cache
  Future<void> removeThumbnail(String videoUrl) async {
    _thumbnailCache.remove(videoUrl);
    _failed.remove(videoUrl);
    final thumbDir = await _getThumbnailDirectory();
    final file = File(_getThumbnailPath(videoUrl, thumbDir));
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// Get cache size in bytes
  Future<int> getCacheSize() async {
    try {
      final thumbDir = await _getThumbnailDirectory();
      if (!await thumbDir.exists()) return 0;

      int size = 0;
      final files = await thumbDir.list().toList();
      for (final file in files) {
        if (file is File) {
          size += await file.length();
        }
      }
      return size;
    } catch (e) {
      return 0;
    }
  }
}
