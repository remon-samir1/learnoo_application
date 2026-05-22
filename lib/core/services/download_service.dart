import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/material.dart';

/// Download status enum for tracking file download state
enum DownloadStatus {
  idle,
  downloading,
  completed,
  failed,
  cancelled,
}

/// Model for tracking download progress
class DownloadProgress {
  final String url;
  final String fileName;
  final DownloadStatus status;
  final double progress;
  final String? localPath;
  final String? errorMessage;
  final int receivedBytes;
  final int totalBytes;

  DownloadProgress({
    required this.url,
    required this.fileName,
    this.status = DownloadStatus.idle,
    this.progress = 0.0,
    this.localPath,
    this.errorMessage,
    this.receivedBytes = 0,
    this.totalBytes = 0,
  });

  DownloadProgress copyWith({
    DownloadStatus? status,
    double? progress,
    String? localPath,
    String? errorMessage,
    int? receivedBytes,
    int? totalBytes,
  }) {
    return DownloadProgress(
      url: url,
      fileName: fileName,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      localPath: localPath ?? this.localPath,
      errorMessage: errorMessage ?? this.errorMessage,
      receivedBytes: receivedBytes ?? this.receivedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
    );
  }

  String get formattedProgress {
    if (totalBytes <= 0) return '0%';
    return '${(progress * 100).toStringAsFixed(0)}%';
  }

  String get formattedSize {
    final received = _formatBytes(receivedBytes);
    final total = _formatBytes(totalBytes);
    return '$received / $total';
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB'];
    var i = 0;
    double size = bytes.toDouble();
    while (size >= 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(1)} ${suffixes[i]}';
  }
}

/// Singleton service for managing file downloads
class DownloadService {
  static final DownloadService _instance = DownloadService._internal();
  factory DownloadService() => _instance;
  DownloadService._internal();

  final Dio _dio = Dio();
  final Map<String, CancelToken> _cancelTokens = {};
  final Map<String, DownloadProgress> _downloads = {};

  /// Stream controller for download progress updates
  final Map<String, ValueNotifier<DownloadProgress>> _progressNotifiers = {};

  /// Get or create progress notifier for a URL
  ValueNotifier<DownloadProgress> getProgressNotifier(String url, String fileName) {
    if (!_progressNotifiers.containsKey(url)) {
      _progressNotifiers[url] = ValueNotifier(
        DownloadProgress(url: url, fileName: fileName),
      );
    }
    return _progressNotifiers[url]!;
  }

  /// Download a file with progress tracking
  Future<DownloadProgress> downloadFile({
    required String url,
    required String fileName,
    String? subDirectory,
    bool saveToPublic = false,
  }) async {
    final cancelToken = CancelToken();
    _cancelTokens[url] = cancelToken;

    try {
      // Determine save path
      final directory = await _getSaveDirectory(subDirectory: subDirectory);
      final filePath = '${directory.path}/$fileName';

      // Update status to downloading
      _updateProgress(url, fileName, DownloadStatus.downloading, 0.0);

      // Download file
      await _dio.download(
        url,
        filePath,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            final progress = received / total;
            _updateProgress(
              url,
              fileName,
              DownloadStatus.downloading,
              progress,
              receivedBytes: received,
              totalBytes: total,
            );
          }
        },
      );

      // Check if cancelled
      if (cancelToken.isCancelled) {
        final progress = DownloadProgress(
          url: url,
          fileName: fileName,
          status: DownloadStatus.cancelled,
        );
        _downloads[url] = progress;
        return progress;
      }

      // Completed successfully
      final completedProgress = DownloadProgress(
        url: url,
        fileName: fileName,
        status: DownloadStatus.completed,
        progress: 1.0,
        localPath: filePath,
        receivedBytes: File(filePath).lengthSync(),
        totalBytes: File(filePath).lengthSync(),
      );
      _downloads[url] = completedProgress;
      _updateNotifier(url, completedProgress);

      return completedProgress;
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        final progress = DownloadProgress(
          url: url,
          fileName: fileName,
          status: DownloadStatus.cancelled,
        );
        _downloads[url] = progress;
        return progress;
      }

      final failedProgress = DownloadProgress(
        url: url,
        fileName: fileName,
        status: DownloadStatus.failed,
        errorMessage: 'Download failed: ${e.message}',
      );
      _downloads[url] = failedProgress;
      _updateNotifier(url, failedProgress);
      return failedProgress;
    } catch (e) {
      final failedProgress = DownloadProgress(
        url: url,
        fileName: fileName,
        status: DownloadStatus.failed,
        errorMessage: 'Download failed: $e',
      );
      _downloads[url] = failedProgress;
      _updateNotifier(url, failedProgress);
      return failedProgress;
    } finally {
      _cancelTokens.remove(url);
    }
  }

  /// Cancel an ongoing download
  void cancelDownload(String url) {
    final cancelToken = _cancelTokens[url];
    if (cancelToken != null && !cancelToken.isCancelled) {
      cancelToken.cancel('Download cancelled by user');
    }
  }

  /// Share a downloaded file
  Future<void> shareFile(String filePath, {String? subject}) async {
    await Share.shareUri(Uri.parse(filePath));
  }

  /// Share URL with system dialog
  Future<void> shareUrl(String url, {String? subject, String? text}) async {
    await Share.shareUri(Uri.parse(url));
  }

  /// Copy URL to clipboard using Share
  Future<void> copyUrl(String url, {String? text}) async {
    await Share.shareUri(Uri.parse(url));
  }

  /// Get download directory
  Future<Directory> _getSaveDirectory({String? subDirectory}) async {
    final appDir = await getApplicationDocumentsDirectory();
    final downloadDir = Directory('${appDir.path}/downloads${subDirectory != null ? '/$subDirectory' : ''}');
    if (!await downloadDir.exists()) {
      await downloadDir.create(recursive: true);
    }
    return downloadDir;
  }

  /// Update progress and notify listeners
  void _updateProgress(
    String url,
    String fileName,
    DownloadStatus status,
    double progress, {
    String? localPath,
    String? errorMessage,
    int receivedBytes = 0,
    int totalBytes = 0,
  }) {
    final downloadProgress = DownloadProgress(
      url: url,
      fileName: fileName,
      status: status,
      progress: progress,
      localPath: localPath,
      errorMessage: errorMessage,
      receivedBytes: receivedBytes,
      totalBytes: totalBytes,
    );
    _downloads[url] = downloadProgress;
    _updateNotifier(url, downloadProgress);
  }

  void _updateNotifier(String url, DownloadProgress progress) {
    final notifier = _progressNotifiers[url];
    if (notifier != null) {
      notifier.value = progress;
    }
  }

  /// Get saved download progress
  DownloadProgress? getDownloadProgress(String url) {
    return _downloads[url];
  }

  /// Check if file is downloaded
  bool isDownloaded(String url) {
    final progress = _downloads[url];
    return progress?.status == DownloadStatus.completed && progress?.localPath != null;
  }

  /// Delete a downloaded file
  Future<bool> deleteDownload(String url) async {
    final progress = _downloads[url];
    if (progress?.localPath != null) {
      try {
        final file = File(progress!.localPath!);
        if (await file.exists()) {
          await file.delete();
        }
        _downloads.remove(url);
        return true;
      } catch (e) {
        return false;
      }
    }
    return false;
  }

  /// Get all downloads
  List<DownloadProgress> getAllDownloads() {
    return _downloads.values.toList();
  }

  /// Get completed downloads
  List<DownloadProgress> getCompletedDownloads() {
    return _downloads.values.where((d) => d.status == DownloadStatus.completed).toList();
  }

  /// Dispose notifier for a URL
  void disposeNotifier(String url) {
    _progressNotifiers.remove(url);
  }
}
