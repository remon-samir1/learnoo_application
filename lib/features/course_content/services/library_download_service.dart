import 'dart:io';

import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/services/device_downloads.dart';
import '../../../core/services/feature_manager.dart';
import '../../../core/services/library_pdf_watermark.dart';
import '../../../core/services/notification_service.dart';
import '../../../features/auth/data/auth_repository.dart';
import '../domain/library_material.dart';

/// Why a library download did not produce a file.
enum LibraryDownloadFailure {
  /// The material is still behind an activation code.
  locked,

  /// The admin switched "Downloadable" off for this file.
  notDownloadable,

  /// The attachment has no file path.
  missingFile,

  /// The network request failed.
  network,

  /// The watermark could not be applied. The unwatermarked original is never
  /// handed out in its place.
  watermark,

  /// Android 9 and below: the storage permission was refused.
  storagePermission,

  /// The file could not be written to the device's Downloads.
  save,
}

class LibraryDownloadResult {
  const LibraryDownloadResult.success(this.saved, {required this.watermarked})
      : failure = null;

  const LibraryDownloadResult.failed(this.failure)
      : saved = null,
        watermarked = false;

  /// Where the file landed on the device.
  final SavedDownload? saved;
  final bool watermarked;
  final LibraryDownloadFailure? failure;

  bool get isSuccess => saved != null;
}

/// Downloads an electronic-library attachment the way the website does.
///
/// The website sends every download through `/api/pdf-proxy`, which stamps the
/// `library` watermark into the PDF before the browser saves it, and only
/// shows the button when the material is unlocked and the attachment is
/// `downloadable`. Both rules are enforced here as well, so the button is not
/// the only thing standing between a student and an unwatermarked file.
///
/// Like a browser download, the finished file is written to the device's
/// public Downloads (Files app on iOS) and tracked in the notification bar.
class LibraryDownloadService {
  LibraryDownloadService({
    Dio? dio,
    FeatureManager? featureManager,
    AuthRepository? authRepository,
    LibraryPdfWatermarker watermarker = const LibraryPdfWatermarker(),
    DeviceDownloads deviceDownloads = const DeviceDownloads(),
    NotificationService? notifications,
  })  : _dio = dio ?? Dio(),
        _featureManager = featureManager ?? FeatureManager(),
        _authRepository = authRepository ?? AuthRepository(),
        _watermarker = watermarker,
        _deviceDownloads = deviceDownloads,
        _notifications = notifications ?? NotificationService();

  final Dio _dio;
  final FeatureManager _featureManager;
  final AuthRepository _authRepository;
  final LibraryPdfWatermarker _watermarker;
  final DeviceDownloads _deviceDownloads;
  final NotificationService _notifications;

  /// The website parses the `library` bucket alone for downloads — no fallback
  /// to other buckets — so this does the same.
  bool get isWatermarkEnabled =>
      _featureManager.getWatermarkConfig('library').enabled;

  /// Whether [attachment] of [material] may be downloaded at all.
  static bool canDownload(
    dynamic material,
    Map<String, dynamic>? attachment,
  ) {
    if (attachment == null) return false;
    if (libraryIsLocked(material)) return false;
    if (attachmentPath(attachment).isEmpty) return false;
    return attachmentIsDownloadable(attachment);
  }

  Future<LibraryDownloadResult> download({
    required dynamic material,
    required Map<String, dynamic> attachment,
    void Function(double progress)? onProgress,
  }) async {
    if (libraryIsLocked(material)) {
      return const LibraryDownloadResult.failed(LibraryDownloadFailure.locked);
    }
    if (!attachmentIsDownloadable(attachment)) {
      return const LibraryDownloadResult.failed(
        LibraryDownloadFailure.notDownloadable,
      );
    }
    final url = attachmentPath(attachment);
    if (url.isEmpty) {
      return const LibraryDownloadResult.failed(
        LibraryDownloadFailure.missingFile,
      );
    }

    final fileName = fileNameFor(material, attachment);
    final key = 'library:${libraryId(material) ?? ''}:$url';
    final title = 'library.notification_downloading'.tr();

    await _notify(() => _notifications.showDownloadStarted(
          url: key,
          title: title,
          body: fileName,
        ));

    final tempDir = await getTemporaryDirectory();
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final raw = File('${tempDir.path}/library_raw_$stamp');
    final prepared = File('${tempDir.path}/library_ready_$stamp');

    Future<LibraryDownloadResult> fail(LibraryDownloadFailure failure) async {
      await _notify(() => _notifications.showDownloadFailed(
            url: key,
            title: 'library.notification_failed'.tr(),
            body: fileName,
          ));
      return LibraryDownloadResult.failed(failure);
    }

    try {
      var lastNotified = DateTime.fromMillisecondsSinceEpoch(0);
      try {
        await _dio.download(
          url,
          raw.path,
          onReceiveProgress: (received, total) {
            if (total > 0) onProgress?.call(received / total);
            final now = DateTime.now();
            // The notification bar is rate limited; twice a second is plenty.
            if (now.difference(lastNotified).inMilliseconds < 500) return;
            lastNotified = now;
            _notify(() => _notifications.showDownloadProgress(
                  url: key,
                  title: title,
                  body: fileName,
                  progress: total > 0 ? received / total : 0,
                  receivedBytes: received,
                  totalBytes: total > 0 ? total : received,
                  indeterminate: total <= 0,
                ));
          },
        );
      } catch (_) {
        return fail(LibraryDownloadFailure.network);
      }

      final config = _featureManager.getWatermarkConfig('library');
      final shouldWatermark = config.enabled && attachmentIsPdf(attachment);

      if (shouldWatermark) {
        await _notify(() => _notifications.showDownloadStarted(
              url: key,
              title: 'library.notification_watermarking'.tr(),
              body: fileName,
            ));
        try {
          final identity = await _studentIdentity();
          final text = buildDownloadWatermarkText(
            config: config,
            studentCode: identity.studentCode,
            phone: identity.phone,
          );
          await _watermarker.apply(
            source: raw,
            destination: prepared,
            text: text,
            config: config,
          );
        } catch (_) {
          debugPrint('[LibraryDownload] watermarking failed');
          return fail(LibraryDownloadFailure.watermark);
        }
      }

      final SavedDownload saved;
      try {
        saved = await _deviceDownloads.save(
          source: shouldWatermark ? prepared : raw,
          fileName: fileName,
          mimeType:
              DeviceDownloads.mimeTypeFor(attachmentExtension(attachment)),
        );
      } on DeviceDownloadPermissionDenied {
        return fail(LibraryDownloadFailure.storagePermission);
      } catch (_) {
        debugPrint('[LibraryDownload] saving to device failed');
        return fail(LibraryDownloadFailure.save);
      }

      await _notify(() => _notifications.showDownloadCompleted(
            url: key,
            title: 'library.notification_done'.tr(),
            body: saved.fileName,
            payload: NotificationService.openDownloadPayload(saved),
          ));
      return LibraryDownloadResult.success(saved, watermarked: shouldWatermark);
    } finally {
      await _deleteQuietly(raw);
      await _deleteQuietly(prepared);
    }
  }

  /// Opens a saved download in the device's viewer.
  Future<bool> open(SavedDownload saved) =>
      _deviceDownloads.open(uri: saved.uri, mimeType: saved.mimeType);

  /// Notifications are a courtesy: failing to post one must never fail the
  /// download itself.
  static Future<void> _notify(Future<void> Function() post) async {
    try {
      await post();
    } catch (_) {}
  }

  /// Student code and phone for the watermark: the live profile when
  /// reachable, the cached copy otherwise.
  Future<({String? studentCode, String? phone})> _studentIdentity() async {
    try {
      final result = await _authRepository.getProfile();
      final data = result['data'];
      final attrs = data is Map ? data['attributes'] : null;
      if (result['success'] == true && attrs is Map) {
        return (
          studentCode: attrs['student_code']?.toString(),
          phone: attrs['phone']?.toString(),
        );
      }
    } catch (_) {
      // Fall through to the cache.
    }
    final cached = _authRepository.getCachedWatermarkData();
    return (studentCode: cached['student_code'], phone: cached['phone']);
  }

  /// File name the download is saved under on the device.
  @visibleForTesting
  static String fileNameFor(
    dynamic material,
    Map<String, dynamic> attachment,
  ) {
    final extension = attachmentExtension(attachment);
    var base = attachmentName(attachment).trim();
    if (base.isEmpty) base = libraryTitle(material).trim();
    if (base.isEmpty) base = 'material_${libraryId(material) ?? 'file'}';

    // Keep Arabic and Latin letters, digits, dash and underscore.
    base = base
        .replaceAll(RegExp(r'\.[A-Za-z0-9]{1,5}$'), '')
        .replaceAll(RegExp(r'[^\p{L}\p{N}_\- ]', unicode: true), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '_');
    if (base.isEmpty) base = 'material';

    final suffix = extension.isEmpty ? '' : '.$extension';
    return '$base$suffix';
  }

  static Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
