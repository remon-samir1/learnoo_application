import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:flutter/foundation.dart';

/// Service for generating and caching video thumbnails from network URLs
class VideoThumbnailService {
  static VideoThumbnailService? _instance;
  static VideoThumbnailService get instance => _instance ??= VideoThumbnailService._internal();

  VideoThumbnailService._internal();

  // Cache for storing generated thumbnail paths to avoid regeneration
  final Map<String, String> _thumbnailCache = {};
  final Set<String> _generatingThumbnails = {};

  /// Get the thumbnail directory path
  Future<Directory> _getThumbnailDirectory() async {
    final tempDir = await getTemporaryDirectory();
    final thumbDir = Directory('${tempDir.path}/video_thumbnails');
    if (!await thumbDir.exists()) {
      await thumbDir.create(recursive: true);
    }
    return thumbDir;
  }

  /// Generate MD5 hash of URL for consistent cache key
  String _generateCacheKey(String url) {
    final bytes = url.codeUnits;
    final digest = md5.convert(bytes);
    return digest.toString();
  }

  /// Get thumbnail file path from URL
  String _getThumbnailPath(String url, Directory thumbDir) {
    final cacheKey = _generateCacheKey(url);
    return '${thumbDir.path}/$cacheKey.jpg';
  }

  /// Check if thumbnail exists in cache
  Future<bool> hasThumbnail(String videoUrl) async {
    if (_thumbnailCache.containsKey(videoUrl)) {
      final file = File(_thumbnailCache[videoUrl]!);
      return await file.exists();
    }
    
    final thumbDir = await _getThumbnailDirectory();
    final path = _getThumbnailPath(videoUrl, thumbDir);
    final file = File(path);
    
    if (await file.exists()) {
      _thumbnailCache[videoUrl] = path;
      return true;
    }
    return false;
  }

  /// Generate thumbnail from video URL
  /// Returns the file path of the generated thumbnail
  Future<String?> generateThumbnail(String videoUrl, {int maxAttempts = 3}) async {
    if (videoUrl.isEmpty) return null;

    // Check memory cache first
    if (_thumbnailCache.containsKey(videoUrl)) {
      final cachedPath = _thumbnailCache[videoUrl]!;
      if (await File(cachedPath).exists()) {
        return cachedPath;
      }
    }

    // Check file cache
    final thumbDir = await _getThumbnailDirectory();
    final path = _getThumbnailPath(videoUrl, thumbDir);
    
    if (await File(path).exists()) {
      _thumbnailCache[videoUrl] = path;
      return path;
    }

    // Prevent concurrent generation of same thumbnail
    if (_generatingThumbnails.contains(videoUrl)) {
      // Wait for generation to complete
      for (var i = 0; i < 50; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
        if (!_generatingThumbnails.contains(videoUrl)) {
          if (_thumbnailCache.containsKey(videoUrl)) {
            return _thumbnailCache[videoUrl];
          }
          break;
        }
      }
    }

    _generatingThumbnails.add(videoUrl);

    try {
      // Try to generate thumbnail with retries
      Uint8List? thumbnailBytes;
      int attempt = 0;

      while (thumbnailBytes == null && attempt < maxAttempts) {
        try {
          thumbnailBytes = await VideoThumbnail.thumbnailData(
            video: videoUrl,
            imageFormat: ImageFormat.JPEG,
            maxWidth: 320,
            maxHeight: 240,
            quality: 85,
            timeMs: 1000, // Get frame at 1 second mark
          );
        } catch (e) {
          attempt++;
          if (attempt >= maxAttempts) break;
          await Future.delayed(const Duration(milliseconds: 200));
        }
      }

      if (thumbnailBytes != null) {
        final file = File(path);
        await file.writeAsBytes(thumbnailBytes);
        _thumbnailCache[videoUrl] = path;
        return path;
      }
    } catch (e) {
      debugPrint('[VideoThumbnailService] Error generating thumbnail: $e');
    } finally {
      _generatingThumbnails.remove(videoUrl);
    }

    return null;
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
    } catch (e) {
      debugPrint('[VideoThumbnailService] Error clearing cache: $e');
    }
  }

  /// Clear specific thumbnail from cache
  Future<void> removeThumbnail(String videoUrl) async {
    _thumbnailCache.remove(videoUrl);
    final thumbDir = await _getThumbnailDirectory();
    final path = _getThumbnailPath(videoUrl, thumbDir);
    final file = File(path);
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
