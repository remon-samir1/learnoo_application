import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'notification_service.dart';

/// Status for encrypted video download
enum EncryptedDownloadStatus {
  idle,
  downloading,
  encrypting,
  completed,
  failed,
  cancelled,
}

/// Model for downloaded video metadata
class DownloadedVideo {
  final String id;
  final String chapterId;
  final String chapterTitle;
  final String lectureTitle;
  final String courseId;
  final String originalUrl;
  final String encryptedFilePath;
  final String thumbnailUrl;
  final int fileSize;
  final String duration;
  final DateTime downloadDate;
  final String encryptionKey;
  final int currentViews;
  final int maxViews;

  DownloadedVideo({
    required this.id,
    required this.chapterId,
    required this.chapterTitle,
    required this.lectureTitle,
    required this.courseId,
    required this.originalUrl,
    required this.encryptedFilePath,
    required this.thumbnailUrl,
    required this.fileSize,
    required this.duration,
    required this.downloadDate,
    required this.encryptionKey,
    this.currentViews = 0,
    this.maxViews = 5,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'chapterId': chapterId,
      'chapterTitle': chapterTitle,
      'lectureTitle': lectureTitle,
      'courseId': courseId,
      'originalUrl': originalUrl,
      'encryptedFilePath': encryptedFilePath,
      'thumbnailUrl': thumbnailUrl,
      'fileSize': fileSize,
      'duration': duration,
      'downloadDate': downloadDate.toIso8601String(),
      'encryptionKey': encryptionKey,
      'currentViews': currentViews,
      'maxViews': maxViews,
    };
  }

  factory DownloadedVideo.fromJson(Map<String, dynamic> json) {
    return DownloadedVideo(
      id: json['id'] ?? '',
      chapterId: json['chapterId'] ?? '',
      chapterTitle: json['chapterTitle'] ?? '',
      lectureTitle: json['lectureTitle'] ?? '',
      courseId: json['courseId'] ?? '',
      originalUrl: json['originalUrl'] ?? '',
      encryptedFilePath: json['encryptedFilePath'] ?? '',
      thumbnailUrl: json['thumbnailUrl'] ?? '',
      fileSize: json['fileSize'] ?? 0,
      duration: json['duration'] ?? '',
      downloadDate: DateTime.parse(json['downloadDate'] ?? DateTime.now().toIso8601String()),
      encryptionKey: json['encryptionKey'] ?? '',
      currentViews: json['currentViews'] ?? 0,
      maxViews: json['maxViews'] ?? 5,
    );
  }

  String get formattedSize {
    if (fileSize <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB'];
    var i = 0;
    double size = fileSize.toDouble();
    while (size >= 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(1)} ${suffixes[i]}';
  }
}

/// Progress tracking for encrypted downloads
class EncryptedDownloadProgress {
  final String url;
  final String fileName;
  final EncryptedDownloadStatus status;
  final double progress;
  final String? errorMessage;
  final int receivedBytes;
  final int totalBytes;
  final DownloadedVideo? downloadedVideo;

  EncryptedDownloadProgress({
    required this.url,
    required this.fileName,
    this.status = EncryptedDownloadStatus.idle,
    this.progress = 0.0,
    this.errorMessage,
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.downloadedVideo,
  });

  EncryptedDownloadProgress copyWith({
    EncryptedDownloadStatus? status,
    double? progress,
    String? errorMessage,
    int? receivedBytes,
    int? totalBytes,
    DownloadedVideo? downloadedVideo,
  }) {
    return EncryptedDownloadProgress(
      url: url,
      fileName: fileName,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      errorMessage: errorMessage ?? this.errorMessage,
      receivedBytes: receivedBytes ?? this.receivedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      downloadedVideo: downloadedVideo ?? this.downloadedVideo,
    );
  }

  String get formattedProgress {
    if (totalBytes <= 0) return '0%';
    return '${(progress * 100).toStringAsFixed(0)}%';
  }
}

/// Service for managing encrypted video downloads
class EncryptedVideoService {
  static final EncryptedVideoService _instance = EncryptedVideoService._internal();
  factory EncryptedVideoService() => _instance;
  EncryptedVideoService._internal();

  final Dio _dio = Dio();
  final Map<String, CancelToken> _cancelTokens = {};
  final Map<String, ValueNotifier<EncryptedDownloadProgress>> _progressNotifiers = {};
  final Map<String, DownloadedVideo> _downloadedVideos = {};
  final NotificationService _notificationService = NotificationService();

  static const String _storageKey = 'learnoo_downloaded_videos';
  static const String _encryptionKeyBase = 'learnoo_video_key_v1';

  /// Get or create progress notifier for a URL
  ValueNotifier<EncryptedDownloadProgress> getProgressNotifier(String url, String fileName) {
    if (!_progressNotifiers.containsKey(url)) {
      _progressNotifiers[url] = ValueNotifier(
        EncryptedDownloadProgress(url: url, fileName: fileName),
      );
    }
    return _progressNotifiers[url]!;
  }

  /// Generate encryption key for a video
  String _generateEncryptionKey(String videoId) {
    final keyData = '$_encryptionKeyBase:$videoId';
    final hash = sha256.convert(utf8.encode(keyData));
    return base64.encode(hash.bytes);
  }

  /// Encrypt data using XOR with key
  Uint8List _encryptData(Uint8List data, String key) {
    final keyBytes = base64.decode(key);
    final encrypted = Uint8List(data.length);
    for (var i = 0; i < data.length; i++) {
      encrypted[i] = data[i] ^ keyBytes[i % keyBytes.length];
    }
    return encrypted;
  }

  /// Decrypt data using XOR with key
  Uint8List _decryptData(Uint8List data, String key) {
    // XOR is symmetric, so encryption and decryption are the same
    return _encryptData(data, key);
  }

  /// Get app-private video directory (hidden from gallery)
  Future<Directory> _getVideoDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final videoDir = Directory('${appDir.path}/.learnoo_videos');
    if (!await videoDir.exists()) {
      await videoDir.create(recursive: true);
    }
    // Create .nomedia file to hide from gallery
    final nomediaFile = File('${videoDir.path}/.nomedia');
    if (!await nomediaFile.exists()) {
      await nomediaFile.writeAsString('');
    }
    return videoDir;
  }

  /// Load downloaded videos from storage
  Future<void> loadDownloadedVideos() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_storageKey);
      if (jsonString != null) {
        final List<dynamic> jsonList = json.decode(jsonString);
        _downloadedVideos.clear();
        for (var jsonItem in jsonList) {
          final video = DownloadedVideo.fromJson(jsonItem);
          _downloadedVideos[video.id] = video;
        }
      }
    } catch (e) {
      debugPrint('Error loading downloaded videos: $e');
    }
  }

  /// Save downloaded videos to storage
  Future<void> _saveDownloadedVideos() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = _downloadedVideos.values.map((v) => v.toJson()).toList();
      await prefs.setString(_storageKey, json.encode(jsonList));
    } catch (e) {
      debugPrint('Error saving downloaded videos: $e');
    }
  }

  /// Download and encrypt a video
  Future<EncryptedDownloadProgress> downloadVideo({
    required String url,
    required String chapterId,
    required String chapterTitle,
    required String lectureTitle,
    required String courseId,
    required String duration,
    String thumbnailUrl = '',
    int currentViews = 0,
    int maxViews = 5,
  }) async {
    final videoId = '${courseId}_${chapterId}';
    final fileName = 'video_${videoId}.enc';
    final encryptionKey = _generateEncryptionKey(videoId);

    final cancelToken = CancelToken();
    _cancelTokens[url] = cancelToken;

    try {
      final videoDir = await _getVideoDirectory();
      final filePath = '${videoDir.path}/$fileName';

      // Check if already downloaded
      if (_downloadedVideos.containsKey(videoId)) {
        final existingVideo = _downloadedVideos[videoId]!;
        final file = File(existingVideo.encryptedFilePath);
        if (await file.exists()) {
          final completedProgress = EncryptedDownloadProgress(
            url: url,
            fileName: fileName,
            status: EncryptedDownloadStatus.completed,
            progress: 1.0,
            totalBytes: existingVideo.fileSize,
            receivedBytes: existingVideo.fileSize,
            downloadedVideo: existingVideo,
          );
          _updateNotifier(url, completedProgress);
          return completedProgress;
        }
      }

      // Start download
      _updateProgress(url, fileName, EncryptedDownloadStatus.downloading, 0.0);

      // Show download started notification
      await _notificationService.showDownloadStarted(
        url: url,
        title: 'Downloading Video',
        body: '$lectureTitle - $chapterTitle',
      );

      // Download to temp file first
      final tempDir = await getTemporaryDirectory();
      // Ensure temp directory exists
      if (!await tempDir.exists()) {
        await tempDir.create(recursive: true);
      }
      final tempFilePath = '${tempDir.path}/temp_$fileName';

      int totalFileSize = 0;
      int downloadedBytes = 0;
      DateTime lastNotificationTime = DateTime.fromMillisecondsSinceEpoch(0);
      bool success = false;

      // Retry mechanism for reliable downloads
      for (int i = 0; i < 5; i++) {
        try {
          final tempFile = File(tempFilePath);
          if (await tempFile.exists()) {
            downloadedBytes = await tempFile.length();
          }

          final response = await _dio.get(
            url,
            options: Options(
              responseType: ResponseType.stream,
              headers: downloadedBytes > 0 ? {'Range': 'bytes=$downloadedBytes-'} : null,
              receiveTimeout: const Duration(seconds: 30),
            ),
            cancelToken: cancelToken,
          );

          bool isRangeSupported = response.statusCode == 206;
          if (downloadedBytes > 0 && !isRangeSupported) {
            downloadedBytes = 0; // Server doesn't support resume, start over
          }

          final contentLengthStr = response.headers.value(HttpHeaders.contentLengthHeader) ?? '-1';
          int contentLength = int.tryParse(contentLengthStr) ?? -1;
          
          if (contentLength > 0) {
            totalFileSize = isRangeSupported ? downloadedBytes + contentLength : contentLength;
          }

          final raf = tempFile.openSync(mode: isRangeSupported && downloadedBytes > 0 ? FileMode.append : FileMode.write);

          try {
            await for (var chunk in response.data.stream) {
              if (cancelToken.isCancelled) {
                break;
              }
              raf.writeFromSync(chunk);
              downloadedBytes += chunk.length as int;

              if (totalFileSize > 0) {
                final progress = downloadedBytes / totalFileSize;
                
                _updateProgress(
                  url,
                  fileName,
                  EncryptedDownloadStatus.downloading,
                  progress * 0.8, // Download is 80% of total progress
                  receivedBytes: downloadedBytes,
                  totalBytes: totalFileSize,
                );

                // Throttle notifications to every 1 second
                final now = DateTime.now();
                if (now.difference(lastNotificationTime).inSeconds >= 1) {
                  lastNotificationTime = now;
                  await _notificationService.showDownloadProgress(
                    url: url,
                    title: 'Downloading Video',
                    body: lectureTitle,
                    progress: progress * 0.8,
                    receivedBytes: downloadedBytes,
                    totalBytes: totalFileSize,
                  );
                }
              }
            }
          } finally {
            raf.closeSync();
          }

          if (cancelToken.isCancelled) {
            return _handleCancellation(url, fileName);
          }
          
          success = true;
          break; // Exit retry loop on success
        } on DioException catch (e) {
          if (CancelToken.isCancel(e)) {
            return _handleCancellation(url, fileName);
          }
          if (i == 4) throw e; // Last retry failed, rethrow
          await Future.delayed(Duration(seconds: 2 * (i + 1))); // Backoff
        } catch (e) {
          if (i == 4) throw e;
          await Future.delayed(Duration(seconds: 2 * (i + 1)));
        }
      }

      if (!success && cancelToken.isCancelled) {
        return _handleCancellation(url, fileName);
      }

      // Encrypt the file
      _updateProgress(url, fileName, EncryptedDownloadStatus.encrypting, 0.8, totalBytes: totalFileSize);

      // Show encrypting notification
      await _notificationService.showDownloadProgress(
        url: url,
        title: 'Encrypting Video',
        body: '$lectureTitle',
        progress: 0.9,
        receivedBytes: totalFileSize,
        totalBytes: totalFileSize,
        indeterminate: true,
      );

      final tempFile = File(tempFilePath);
      final fileData = await tempFile.readAsBytes();
      final encryptedData = _encryptData(fileData, encryptionKey);

      // Write encrypted file
      final encryptedFile = File(filePath);
      await encryptedFile.writeAsBytes(encryptedData);

      // Delete temp file
      await tempFile.delete();

      // Create metadata
      final downloadedVideo = DownloadedVideo(
        id: videoId,
        chapterId: chapterId,
        chapterTitle: chapterTitle,
        lectureTitle: lectureTitle,
        courseId: courseId,
        originalUrl: url,
        encryptedFilePath: filePath,
        thumbnailUrl: thumbnailUrl,
        fileSize: encryptedData.length,
        duration: duration,
        downloadDate: DateTime.now(),
        encryptionKey: encryptionKey,
        currentViews: currentViews,
        maxViews: maxViews,
      );

      // Save to storage
      _downloadedVideos[videoId] = downloadedVideo;
      await _saveDownloadedVideos();

      // Complete
      final completedProgress = EncryptedDownloadProgress(
        url: url,
        fileName: fileName,
        status: EncryptedDownloadStatus.completed,
        progress: 1.0,
        totalBytes: encryptedData.length,
        receivedBytes: encryptedData.length,
        downloadedVideo: downloadedVideo,
      );
      _updateNotifier(url, completedProgress);

      // Show completed notification
      await _notificationService.showDownloadCompleted(
        url: url,
        title: 'Download Complete',
        body: '$lectureTitle - Ready to watch offline',
      );

      return completedProgress;
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        await _notificationService.showDownloadCancelled(
          url: url,
          title: 'Download Cancelled',
          body: '$lectureTitle',
        );
        return _handleCancellation(url, fileName);
      }
      await _notificationService.showDownloadFailed(
        url: url,
        title: 'Download Failed',
        body: '$lectureTitle - ${e.message}',
      );
      return _handleError(url, fileName, 'Download failed: ${e.message}');
    } catch (e) {
      await _notificationService.showDownloadFailed(
        url: url,
        title: 'Download Failed',
        body: '$lectureTitle - ${e.toString()}',
      );
      return _handleError(url, fileName, 'Download failed: $e');
    } finally {
      _cancelTokens.remove(url);
    }
  }

  EncryptedDownloadProgress _handleCancellation(String url, String fileName) {
    final progress = EncryptedDownloadProgress(
      url: url,
      fileName: fileName,
      status: EncryptedDownloadStatus.cancelled,
    );
    _updateNotifier(url, progress);
    return progress;
  }

  EncryptedDownloadProgress _handleError(String url, String fileName, String error) {
    final progress = EncryptedDownloadProgress(
      url: url,
      fileName: fileName,
      status: EncryptedDownloadStatus.failed,
      errorMessage: error,
    );
    _updateNotifier(url, progress);
    return progress;
  }

  void _updateProgress(
    String url,
    String fileName,
    EncryptedDownloadStatus status,
    double progress, {
    int receivedBytes = 0,
    int totalBytes = 0,
  }) {
    final downloadProgress = EncryptedDownloadProgress(
      url: url,
      fileName: fileName,
      status: status,
      progress: progress,
      receivedBytes: receivedBytes,
      totalBytes: totalBytes,
    );
    _updateNotifier(url, downloadProgress);
  }

  void _updateNotifier(String url, EncryptedDownloadProgress progress) {
    final notifier = _progressNotifiers[url];
    if (notifier != null) {
      notifier.value = progress;
    }
  }

  /// Cancel an ongoing download
  void cancelDownload(String url) {
    final cancelToken = _cancelTokens[url];
    if (cancelToken != null && !cancelToken.isCancelled) {
      cancelToken.cancel('Download cancelled by user');
    }
  }

  /// Decrypt and get temp file path for playback
  Future<String?> getDecryptedVideoPath(String videoId) async {
    try {
      final video = _downloadedVideos[videoId];
      if (video == null) return null;

      final encryptedFile = File(video.encryptedFilePath);
      if (!await encryptedFile.exists()) return null;

      // Read encrypted data
      final encryptedData = await encryptedFile.readAsBytes();

      // Decrypt data
      final decryptedData = _decryptData(encryptedData, video.encryptionKey);

      // Write to temp file for playback
      final tempDir = await getTemporaryDirectory();
      final tempFilePath = '${tempDir.path}/temp_playback_$videoId.mp4';
      final tempFile = File(tempFilePath);
      await tempFile.writeAsBytes(decryptedData);

      return tempFilePath;
    } catch (e) {
      debugPrint('Error decrypting video: $e');
      return null;
    }
  }

  /// Check if video is downloaded
  bool isVideoDownloaded(String videoId) {
    return _downloadedVideos.containsKey(videoId);
  }

  /// Get downloaded video
  DownloadedVideo? getDownloadedVideo(String videoId) {
    return _downloadedVideos[videoId];
  }

  /// Get all downloaded videos
  List<DownloadedVideo> getAllDownloadedVideos() {
    return _downloadedVideos.values.toList()
      ..sort((a, b) => b.downloadDate.compareTo(a.downloadDate));
  }

  /// Delete a downloaded video
  Future<bool> deleteDownloadedVideo(String videoId) async {
    try {
      final video = _downloadedVideos[videoId];
      if (video == null) return false;

      // Delete encrypted file
      final file = File(video.encryptedFilePath);
      if (await file.exists()) {
        await file.delete();
      }

      // Remove from storage
      _downloadedVideos.remove(videoId);
      await _saveDownloadedVideos();

      return true;
    } catch (e) {
      debugPrint('Error deleting video: $e');
      return false;
    }
  }

  /// Delete all downloaded videos
  Future<bool> deleteAllVideos() async {
    try {
      for (final video in _downloadedVideos.values) {
        final file = File(video.encryptedFilePath);
        if (await file.exists()) {
          await file.delete();
        }
      }

      _downloadedVideos.clear();
      await _saveDownloadedVideos();

      return true;
    } catch (e) {
      debugPrint('Error deleting all videos: $e');
      return false;
    }
  }

  /// Get total storage used by downloaded videos
  int getTotalStorageUsed() {
    return _downloadedVideos.values.fold(0, (sum, video) => sum + video.fileSize);
  }

  /// Increment view count for a downloaded video
  /// Returns the updated view count or -1 if video not found
  Future<int> incrementViewCount(String videoId) async {
    try {
      final video = _downloadedVideos[videoId];
      if (video == null) return -1;

      final newViewCount = video.currentViews + 1;
      final updatedVideo = DownloadedVideo(
        id: video.id,
        chapterId: video.chapterId,
        chapterTitle: video.chapterTitle,
        lectureTitle: video.lectureTitle,
        courseId: video.courseId,
        originalUrl: video.originalUrl,
        encryptedFilePath: video.encryptedFilePath,
        thumbnailUrl: video.thumbnailUrl,
        fileSize: video.fileSize,
        duration: video.duration,
        downloadDate: video.downloadDate,
        encryptionKey: video.encryptionKey,
        currentViews: newViewCount,
        maxViews: video.maxViews,
      );

      _downloadedVideos[videoId] = updatedVideo;
      await _saveDownloadedVideos();

      return newViewCount;
    } catch (e) {
      debugPrint('Error incrementing view count: $e');
      return -1;
    }
  }

  /// Check if video has exhausted its views
  bool hasExhaustedViews(String videoId) {
    final video = _downloadedVideos[videoId];
    if (video == null) return true;
    return video.currentViews >= video.maxViews;
  }

  /// Delete video if views are exhausted
  Future<bool> deleteIfViewsExhausted(String videoId) async {
    if (hasExhaustedViews(videoId)) {
      return await deleteDownloadedVideo(videoId);
    }
    return false;
  }

  /// Dispose notifier for a URL
  void disposeNotifier(String url) {
    _progressNotifiers.remove(url);
  }
}
