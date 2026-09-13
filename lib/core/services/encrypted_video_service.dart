import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cryptography/cryptography.dart' hide Hmac;
import 'notification_service.dart';
import 'offline_video_cipher.dart';

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
  /// Key material for the superseded schemes only. Version 2 keeps no key in
  /// the metadata: it is derived from the keystore secret at read time.
  final String encryptionKey;

  /// Nonce for the superseded version-1 keystream. Unused from version 2 on,
  /// where the nonce lives in the container header.
  final String encryptionNonce;

  /// Which encryption scheme wrote this file.
  ///
  /// `0` — the original XOR pad. `1` — the HMAC counter-mode keystream.
  /// Neither is authenticated, so both are treated as legacy and are never
  /// mistaken for a version-2 container. [OfflineVideoCipher.kFormatVersion]
  /// is what new downloads record.
  final int encryptionVersion;

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
    this.encryptionNonce = '',
    this.encryptionVersion = 0,
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
      'encryptionNonce': encryptionNonce,
      'encryptionVersion': encryptionVersion,
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
      encryptionNonce: json['encryptionNonce'] ?? '',
      // Entries written before versioning are version 0 or 1; the nonce tells
      // them apart and neither is authenticated.
      encryptionVersion: json['encryptionVersion'] is int
          ? json['encryptionVersion'] as int
          : ((json['encryptionNonce'] ?? '').toString().isEmpty ? 0 : 1),
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

  /// Key base for the superseded XOR scheme. Kept only so videos downloaded
  /// before the change still play; nothing new is encrypted with it.
  static const String _legacyEncryptionKeyBase = 'learnoo_video_key_v1';

  final OfflineVideoCipher _cipher = OfflineVideoCipher();

  /// Get or create progress notifier for a URL
  ValueNotifier<EncryptedDownloadProgress> getProgressNotifier(String url, String fileName) {
    if (!_progressNotifiers.containsKey(url)) {
      _progressNotifiers[url] = ValueNotifier(
        EncryptedDownloadProgress(url: url, fileName: fileName),
      );
    }
    return _progressNotifiers[url]!;
  }

  /// Legacy key derivation, for files downloaded before the cipher change.
  String _legacyEncryptionKey(String videoId) {
    final keyData = '$_legacyEncryptionKeyBase:$videoId';
    final hash = sha256.convert(utf8.encode(keyData));
    return base64.encode(hash.bytes);
  }

  /// The superseded repeating-pad XOR. Decrypt-only.
  Uint8List _legacyXor(Uint8List data, String key) {
    final keyBytes = base64.decode(key);
    final out = Uint8List(data.length);
    for (var i = 0; i < data.length; i++) {
      out[i] = data[i] ^ keyBytes[i % keyBytes.length];
    }
    return out;
  }

  /// The superseded version-1 HMAC counter-mode keystream. Decrypt-only.
  Uint8List _legacyKeystream(Uint8List data, String key, String nonce) {
    const blockSize = 32;
    final keyBytes = base64.decode(key);
    final nonceBytes = base64.decode(nonce);
    final out = Uint8List(data.length);

    Uint8List blockAt(int index) {
      final input = Uint8List(nonceBytes.length + 8);
      input.setRange(0, nonceBytes.length, nonceBytes);
      for (var i = 0; i < 8; i++) {
        input[nonceBytes.length + 7 - i] = (index >> (8 * i)) & 0xFF;
      }
      return Uint8List.fromList(Hmac(sha256, keyBytes).convert(input).bytes);
    }

    var blockIndex = 0;
    var block = blockAt(0);
    var posInBlock = 0;
    for (var i = 0; i < data.length; i++) {
      if (posInBlock == blockSize) {
        blockIndex++;
        block = blockAt(blockIndex);
        posInBlock = 0;
      }
      out[i] = data[i] ^ block[posInBlock];
      posInBlock++;
    }
    return out;
  }

  /// Decrypts a download written by a superseded scheme.
  ///
  /// Neither scheme is authenticated, so a tampered legacy file cannot be
  /// detected. They are kept only so a student does not lose material they
  /// already downloaded; every new download uses the version-2 container.
  Future<String?> _decryptLegacy({
    required DownloadedVideo video,
    required String videoId,
    required File encryptedFile,
    required File destination,
  }) async {
    final encryptedData = await encryptedFile.readAsBytes();

    final Uint8List plain;
    if (video.encryptionVersion == 1 && video.encryptionNonce.isNotEmpty) {
      plain = _legacyKeystream(
        encryptedData,
        video.encryptionKey,
        video.encryptionNonce,
      );
    } else {
      final key = video.encryptionKey.isEmpty
          ? _legacyEncryptionKey(videoId)
          : video.encryptionKey;
      plain = _legacyXor(encryptedData, key);
    }

    await destination.writeAsBytes(plain);
    return destination.path;
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

  bool _isHlsUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('.m3u8') ||
        lower.contains('/hls/') ||
        lower.endsWith('/playlist') ||
        lower.contains('/playlist?');
  }

  Future<int> _downloadHlsToTempFile({
    required String playlistUrl,
    required String tempFilePath,
    required String url,
    required String fileName,
    required String lectureTitle,
    required CancelToken cancelToken,
    Map<String, String>? headers,
  }) async {
    final dioHeaders = <String, String>{
      if (headers != null) ...headers,
    };

    // 1. Fetch playlist
    final playlistResp = await _dio.get<String>(
      playlistUrl,
      options: Options(
        headers: dioHeaders.isNotEmpty ? dioHeaders : null,
        responseType: ResponseType.plain,
        receiveTimeout: const Duration(seconds: 30),
      ),
      cancelToken: cancelToken,
    );

    String playlistData = playlistResp.data ?? '';
    Uri currentUri = Uri.parse(playlistUrl);
    debugPrint('[HLS_DEBUG] playlistData:\n$playlistData');

    // 2. Handle master playlist variants
    if (playlistData.contains('#EXT-X-STREAM-INF')) {
      final lines = playlistData.split('\n');
      String? variantPath;
      for (int i = 0; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.startsWith('#EXT-X-STREAM-INF')) {
          for (int j = i + 1; j < lines.length; j++) {
            final nextLine = lines[j].trim();
            if (nextLine.isNotEmpty && !nextLine.startsWith('#')) {
              variantPath = nextLine;
              break;
            }
          }
          if (variantPath != null) break;
        }
      }

      if (variantPath != null) {
        currentUri = currentUri.resolve(variantPath);
        final mediaResp = await _dio.get<String>(
          currentUri.toString(),
          options: Options(
            headers: dioHeaders.isNotEmpty ? dioHeaders : null,
            responseType: ResponseType.plain,
            receiveTimeout: const Duration(seconds: 30),
          ),
          cancelToken: cancelToken,
        );
        playlistData = mediaResp.data ?? '';
        debugPrint('[HLS_DEBUG] variant playlistData:\n$playlistData');
      }
    }

    // 3. Parse segments, tracking active key and IV per segment
    final lines = playlistData.split('\n');
    final segments = <_HlsSegment>[];
    String? currentKeyUriStr;
    Uint8List? currentIv;
    int mediaSeq = 0;

    final seqMatch = RegExp(r'#EXT-X-MEDIA-SEQUENCE:(\d+)').firstMatch(playlistData);
    if (seqMatch != null) {
      mediaSeq = int.tryParse(seqMatch.group(1)!) ?? 0;
    }

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.startsWith('#EXT-X-KEY')) {
        if (line.contains('METHOD=NONE')) {
          currentKeyUriStr = null;
          currentIv = null;
        } else if (line.contains('METHOD=AES-128')) {
          final uriMatch = RegExp(r'URI="([^"]+)"').firstMatch(line);
          if (uriMatch != null) {
            currentKeyUriStr = currentUri.resolve(uriMatch.group(1)!).toString();
          }
          final ivMatch = RegExp(r'IV=0x([0-9a-fA-F]+)').firstMatch(line);
          if (ivMatch != null) {
            final hex = ivMatch.group(1)!.padLeft(32, '0');
            currentIv = Uint8List.fromList([
              for (int h = 0; h < 32; h += 2) int.parse(hex.substring(h, h + 2), radix: 16)
            ]);
          } else {
            currentIv = null;
          }
        }
      } else if (line.isNotEmpty && !line.startsWith('#')) {
        final segUri = currentUri.resolve(line);
        final segIndex = segments.length;
        Uint8List iv;
        if (currentIv != null) {
          iv = currentIv;
        } else {
          final seq = mediaSeq + segIndex;
          iv = Uint8List(16);
          for (int b = 0; b < 8; b++) {
            iv[15 - b] = (seq >> (8 * b)) & 0xFF;
          }
        }
        segments.add(_HlsSegment(
          url: segUri.toString(),
          keyUri: currentKeyUriStr,
          iv: iv,
        ));
      }
    }

    if (segments.isEmpty) {
      throw Exception('No video segments found in HLS playlist');
    }

    // 4. Pre-fetch and cache all required encryption keys
    final keyCache = <String, Uint8List>{};
    for (final seg in segments) {
      if (seg.keyUri != null && !keyCache.containsKey(seg.keyUri!)) {
        final keyResp = await _dio.get<List<int>>(
          seg.keyUri!,
          options: Options(
            headers: dioHeaders.isNotEmpty ? dioHeaders : null,
            responseType: ResponseType.bytes,
            receiveTimeout: const Duration(seconds: 30),
          ),
          cancelToken: cancelToken,
        );
        if (keyResp.data != null && keyResp.data!.isNotEmpty) {
          keyCache[seg.keyUri!] = Uint8List.fromList(keyResp.data!);
        }
      }
    }

    // 5. Download and assemble segments
    final tempFile = File(tempFilePath);
    final raf = tempFile.openSync(mode: FileMode.write);
    int downloadedBytes = 0;
    DateTime lastNotificationTime = DateTime.fromMillisecondsSinceEpoch(0);
    final aesCbc = AesCbc.with128bits(macAlgorithm: MacAlgorithm.empty);

    try {
      for (int s = 0; s < segments.length; s++) {
        if (cancelToken.isCancelled) {
          break;
        }

        final seg = segments[s];
        List<int>? segData;
        for (int retry = 0; retry < 3; retry++) {
          try {
            final segResp = await _dio.get<List<int>>(
              seg.url,
              options: Options(
                headers: dioHeaders.isNotEmpty ? dioHeaders : null,
                responseType: ResponseType.bytes,
                receiveTimeout: const Duration(seconds: 30),
              ),
              cancelToken: cancelToken,
            );
            segData = segResp.data;
            break;
          } catch (e) {
            if ((e is DioException && CancelToken.isCancel(e)) || cancelToken.isCancelled) rethrow;
            if (retry == 2) rethrow;
            await Future.delayed(Duration(milliseconds: 600 * (retry + 1)));
          }
        }

        if (segData != null && segData.isNotEmpty) {
          List<int> chunk = segData;
          if (seg.keyUri != null && keyCache.containsKey(seg.keyUri!)) {
            final keyBytes = keyCache[seg.keyUri!]!;
            final secretKey = SecretKey(keyBytes);
            final box = SecretBox(chunk, nonce: seg.iv, mac: Mac.empty);
            chunk = await aesCbc.decrypt(box, secretKey: secretKey);
          }
          raf.writeFromSync(chunk);
          downloadedBytes += chunk.length;
        }

        final progress = ((s + 1) / segments.length) * 0.8;
        _updateProgress(
          url,
          fileName,
          EncryptedDownloadStatus.downloading,
          progress,
          receivedBytes: s + 1,
          totalBytes: segments.length,
        );

        final now = DateTime.now();
        if (now.difference(lastNotificationTime).inSeconds >= 1) {
          lastNotificationTime = now;
          await _notificationService.showDownloadProgress(
            url: url,
            title: 'Downloading Video',
            body: lectureTitle,
            progress: progress,
            receivedBytes: s + 1,
            totalBytes: segments.length,
          );
        }
      }
    } finally {
      raf.closeSync();
    }

    return downloadedBytes;
  }

  Future<int> _downloadDirectToTempFile({
    required String url,
    required String tempFilePath,
    required String fileName,
    required String lectureTitle,
    required CancelToken cancelToken,
    Map<String, String>? headers,
  }) async {
    final tempFile = File(tempFilePath);
    int downloadedBytes = 0;
    if (await tempFile.exists()) {
      downloadedBytes = await tempFile.length();
    }

    int totalFileSize = 0;
    DateTime lastNotificationTime = DateTime.fromMillisecondsSinceEpoch(0);

    for (int i = 0; i < 5; i++) {
      try {
        final requestHeaders = <String, String>{
          if (headers != null) ...headers,
          if (downloadedBytes > 0) 'Range': 'bytes=$downloadedBytes-',
        };

        final response = await _dio.get(
          url,
          options: Options(
            responseType: ResponseType.stream,
            headers: requestHeaders.isNotEmpty ? requestHeaders : null,
            receiveTimeout: const Duration(seconds: 30),
          ),
          cancelToken: cancelToken,
        );

        bool isRangeSupported = response.statusCode == 206;
        if (downloadedBytes > 0 && !isRangeSupported) {
          downloadedBytes = 0;
        }

        final contentLengthStr =
            response.headers.value(HttpHeaders.contentLengthHeader) ?? '-1';
        int contentLength = int.tryParse(contentLengthStr) ?? -1;

        if (contentLength > 0) {
          totalFileSize = isRangeSupported
              ? downloadedBytes + contentLength
              : contentLength;
        }

        final raf = tempFile.openSync(
          mode: isRangeSupported && downloadedBytes > 0
              ? FileMode.append
              : FileMode.write,
        );

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
                progress * 0.8,
                receivedBytes: downloadedBytes,
                totalBytes: totalFileSize,
              );

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
          return downloadedBytes;
        }

        return downloadedBytes;
      } on DioException catch (e) {
        if (CancelToken.isCancel(e)) return downloadedBytes;
        if (i == 4) rethrow;
        await Future.delayed(Duration(seconds: 2 * (i + 1)));
      } catch (e) {
        if (i == 4) rethrow;
        await Future.delayed(Duration(seconds: 2 * (i + 1)));
      }
    }

    return downloadedBytes;
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
    Map<String, String>? headers,
  }) async {
    final videoId = '${courseId}_$chapterId';
    final fileName = 'video_$videoId.enc';

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
      if (!await tempDir.exists()) {
        await tempDir.create(recursive: true);
      }
      final tempFilePath = '${tempDir.path}/temp_$fileName';

      int totalFileSize = 0;
      if (_isHlsUrl(url)) {
        totalFileSize = await _downloadHlsToTempFile(
          playlistUrl: url,
          tempFilePath: tempFilePath,
          url: url,
          fileName: fileName,
          lectureTitle: lectureTitle,
          cancelToken: cancelToken,
          headers: headers,
        );
      } else {
        totalFileSize = await _downloadDirectToTempFile(
          url: url,
          tempFilePath: tempFilePath,
          fileName: fileName,
          lectureTitle: lectureTitle,
          cancelToken: cancelToken,
          headers: headers,
        );
      }

      if (cancelToken.isCancelled) {
        return _handleCancellation(url, fileName);
      }

      // Encrypt the file
      _updateProgress(url, fileName, EncryptedDownloadStatus.encrypting, 0.8, totalBytes: totalFileSize);

      // Show encrypting notification
      await _notificationService.showDownloadProgress(
        url: url,
        title: 'Encrypting Video',
        body: lectureTitle,
        progress: 0.9,
        receivedBytes: totalFileSize,
        totalBytes: totalFileSize,
        indeterminate: true,
      );

      final tempFile = File(tempFilePath);
      final encryptedFile = File(filePath);

      // AES-256-GCM, one authenticated frame per megabyte, written to a .part
      // file and renamed only when the final frame lands — so an interrupted
      // encryption never leaves something that looks complete.
      await _cipher.encryptFile(
        source: tempFile,
        destination: encryptedFile,
        videoId: videoId,
      );

      final encryptedSize = await encryptedFile.length();

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
        fileSize: encryptedSize,
        duration: duration,
        downloadDate: DateTime.now(),
        // Version 2 derives its key from the keystore; nothing secret is kept
        // in the metadata file.
        encryptionKey: '',
        encryptionNonce: '',
        encryptionVersion: OfflineVideoCipher.kFormatVersion,
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
        totalBytes: encryptedSize,
        receivedBytes: encryptedSize,
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
          body: lectureTitle,
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

      final tempDir = await getTemporaryDirectory();
      final tempFilePath = '${tempDir.path}/temp_playback_$videoId.mp4';
      final tempFile = File(tempFilePath);

      // The magic decides, not the metadata: a legacy file can never take the
      // authenticated path, and a version-2 container can never take the
      // unauthenticated one.
      if (await _cipher.isSecureContainer(encryptedFile)) {
        await _cipher.decryptFile(
          source: encryptedFile,
          destination: tempFile,
          videoId: videoId,
        );
        return tempFilePath;
      }

      if (video.encryptionVersion >= OfflineVideoCipher.kFormatVersion) {
        // Metadata claims the secure format but the file is not one — it was
        // swapped or truncated. Refuse rather than fall back.
        throw const OfflineCipherException(
          'metadata claims an authenticated container but the file is not one',
        );
      }

      // Downloaded under a superseded scheme. These are unauthenticated, so
      // they are decrypted only to let a student finish material they already
      // have; nothing new is written this way.
      return _decryptLegacy(
        video: video,
        videoId: videoId,
        encryptedFile: encryptedFile,
        destination: tempFile,
      );
    } on OfflineCipherException catch (error) {
      // The file failed authentication: altered on disk, truncated, or copied
      // from another installation. It can never become playable, so it is
      // dropped and the student can download it again. The reason is logged;
      // no key material or file path is.
      debugPrint('[EncryptedVideo] rejected download: ${error.reason}');
      await deleteDownloadedVideo(videoId);
      return null;
    } catch (_) {
      debugPrint('[EncryptedVideo] could not decrypt download');
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
        encryptionNonce: video.encryptionNonce,
        encryptionVersion: video.encryptionVersion,
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

class _HlsSegment {
  final String url;
  final String? keyUri;
  final Uint8List iv;

  _HlsSegment({
    required this.url,
    required this.keyUri,
    required this.iv,
  });
}

