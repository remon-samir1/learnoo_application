import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:better_player_plus/better_player_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

/// Captures the video frame a student is asking about.
///
/// Port of the web's `src/lib/discussion-screenshot.ts`, which snapshots the
/// player when the student taps "ask about this moment" and attaches the image
/// to the discussion so the instructor sees exactly what was on screen.
class VideoFrameCaptureService {
  VideoFrameCaptureService._internal();
  static final VideoFrameCaptureService _instance =
      VideoFrameCaptureService._internal();
  factory VideoFrameCaptureService() => _instance;

  static const int _maxWidth = 1280;
  static const int _jpegQuality = 80;
  static const Duration _nativeTimeout = Duration(seconds: 8);

  /// Captures the frame at [positionSeconds].
  ///
  /// [videoUrl] is the source currently playing (a network URL or a local
  /// file path); [headers] are the auth headers the player was given, needed
  /// for the API's protected streams. [boundaryKey] is the key on the
  /// `RepaintBoundary` wrapping the player, used by level 2.
  ///
  /// Returns a JPEG in the temp directory, or `null` when every layer failed.
  Future<File?> capture({
    required String videoUrl,
    required int positionSeconds,
    required String chapterId,
    BetterPlayerController? betterPlayerController,
    Map<String, String>? headers,
    GlobalKey? boundaryKey,
    String? chapterTitle,
  }) async {
    final positionMs = math.max(0, positionSeconds) * 1000;

    // LEVEL 0 — direct native snapshot from player controller (PixelCopy / AVAssetImageGenerator)
    if (betterPlayerController != null) {
      try {
        final playerShot = await betterPlayerController.takeSnapshot();
        if (playerShot != null && playerShot.isNotEmpty) {
          debugPrint('[FrameCapture] level 0 (player controller snapshot) succeeded');
          return _writeBytes(playerShot, chapterId, positionSeconds);
        }
      } catch (e) {
        debugPrint('[FrameCapture] level 0 snapshot failed: $e');
      }
    }

    // LEVEL 1 — native frame extraction at the exact position via video_thumbnail
    final native = await _captureNativeFrame(
      videoUrl: videoUrl,
      positionMs: positionMs,
      headers: headers,
    );
    if (native != null) {
      debugPrint('[FrameCapture] level 1 (native) succeeded');
      return _writeBytes(native, chapterId, positionSeconds);
    }

    // LEVEL 2 — whatever the Flutter layer can rasterise.
    if (boundaryKey != null) {
      final widgetShot = await _captureBoundary(boundaryKey);
      if (widgetShot != null) {
        debugPrint('[FrameCapture] level 2 (repaint boundary) succeeded');
        return _writeBytes(widgetShot, chapterId, positionSeconds);
      }
    }

    debugPrint('[FrameCapture] all levels failed — posting without an image');
    return null;
  }

  // ------------------------------------------------------------------
  // LEVEL 1 — native frame extraction
  // ------------------------------------------------------------------

  Future<Uint8List?> _captureNativeFrame({
    required String videoUrl,
    required int positionMs,
    Map<String, String>? headers,
  }) async {
    final source = videoUrl.trim();
    if (source.isEmpty || source == 'offline') return null;

    try {
      // Headers are only meaningful for network sources; passing them for a
      // local path makes some platform implementations bail out.
      final isNetwork =
          source.startsWith('http://') || source.startsWith('https://');

      final bytes = await VideoThumbnail.thumbnailData(
        video: source,
        headers: isNetwork ? headers : null,
        imageFormat: ImageFormat.JPEG,
        maxWidth: _maxWidth,
        timeMs: positionMs,
        quality: _jpegQuality,
      ).timeout(_nativeTimeout);

      if (bytes == null || bytes.isEmpty) return null;
      if (await _looksBlank(bytes)) {
        debugPrint('[FrameCapture] native frame was blank — falling through');
        return null;
      }
      return bytes;
    } on TimeoutException {
      debugPrint('[FrameCapture] native extraction timed out');
      return null;
    } catch (e) {
      debugPrint('[FrameCapture] native extraction failed: $e');
      return null;
    }
  }

  // ------------------------------------------------------------------
  // LEVEL 2 — rasterise the player box
  // ------------------------------------------------------------------

  Future<Uint8List?> _captureBoundary(GlobalKey boundaryKey) async {
    try {
      final context = boundaryKey.currentContext;
      if (context == null) return null;

      final boundary = context.findRenderObject();
      if (boundary is! RenderRepaintBoundary) return null;

      // Wait a frame only if boundary needs paint.
      if (boundary.debugNeedsPaint) {
        await WidgetsBinding.instance.endOfFrame;
      }

      final image = await boundary.toImage(pixelRatio: 1.5);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();

      final bytes = byteData?.buffer.asUint8List();
      if (bytes == null || bytes.isEmpty) return null;
      return bytes;
    } catch (e) {
      debugPrint('[FrameCapture] boundary capture failed: $e');
      return null;
    }
  }

  // ------------------------------------------------------------------
  // LEVEL 3 — synthetic card
  // ------------------------------------------------------------------

  Future<Uint8List?> _renderSyntheticCard({
    required String chapterTitle,
    required int positionSeconds,
  }) async {
    try {
      const width = 960.0;
      const height = 540.0;

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(
        recorder,
        const Rect.fromLTWH(0, 0, width, height),
      );

      // Brand gradient background (matches AppColors.mainGradient).
      final backgroundPaint = Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2137D6), Color(0xFF4A68F6)],
        ).createShader(const Rect.fromLTWH(0, 0, width, height));
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, width, height),
        backgroundPaint,
      );

      _drawText(
        canvas,
        text: _formatTimestamp(positionSeconds),
        offset: const Offset(64, 190),
        fontSize: 76,
        fontWeight: FontWeight.bold,
        maxWidth: width - 128,
      );

      _drawText(
        canvas,
        text: 'Asked at this moment',
        offset: const Offset(64, 300),
        fontSize: 26,
        color: const Color(0xCCFFFFFF),
        maxWidth: width - 128,
      );

      if (chapterTitle.trim().isNotEmpty) {
        _drawText(
          canvas,
          text: chapterTitle.trim(),
          offset: const Offset(64, 348),
          fontSize: 22,
          color: const Color(0x99FFFFFF),
          maxWidth: width - 128,
          maxLines: 2,
        );
      }

      final picture = recorder.endRecording();
      final image = await picture.toImage(width.toInt(), height.toInt());
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      picture.dispose();

      return byteData?.buffer.asUint8List();
    } catch (e) {
      debugPrint('[FrameCapture] synthetic card failed: $e');
      return null;
    }
  }

  void _drawText(
    Canvas canvas, {
    required String text,
    required Offset offset,
    required double fontSize,
    required double maxWidth,
    Color color = const Color(0xFFFFFFFF),
    FontWeight fontWeight = FontWeight.normal,
    int maxLines = 1,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: fontWeight,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: maxLines,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);

    painter.paint(canvas, offset);
    painter.dispose();
  }

  String _formatTimestamp(int seconds) {
    final s = math.max(0, seconds);
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    final mm = m.toString().padLeft(2, '0');
    final ss = sec.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

  // ------------------------------------------------------------------
  // Validation & output
  // ------------------------------------------------------------------

  /// Rejects a capture that is a single flat colour.
  ///
  /// A black texture and a transparent bitmap both come back as valid image
  /// bytes; only sampling pixels tells them apart from a real frame.
  Future<bool> _looksBlank(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: 32,
        targetHeight: 32,
      );
      final frame = await codec.getNextFrame();
      final data =
          await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
      frame.image.dispose();
      codec.dispose();

      if (data == null) return true;

      final pixels = data.buffer.asUint8List();
      if (pixels.length < 16) return true;

      var opaqueCount = 0;
      int? firstR, firstG, firstB;
      var varied = false;

      for (var i = 0; i + 3 < pixels.length; i += 4) {
        final r = pixels[i];
        final g = pixels[i + 1];
        final b = pixels[i + 2];
        final a = pixels[i + 3];

        if (a < 16) continue;
        opaqueCount++;

        if (firstR == null) {
          firstR = r;
          firstG = g;
          firstB = b;
          continue;
        }

        // A frame with any real content varies by more than a few levels.
        if ((r - firstR).abs() > 8 ||
            (g - firstG!).abs() > 8 ||
            (b - firstB!).abs() > 8) {
          varied = true;
          break;
        }
      }

      // Fully transparent, or one flat colour edge to edge.
      if (opaqueCount < pixels.length ~/ 16) return true;
      return !varied;
    } catch (e) {
      debugPrint('[FrameCapture] blank check failed: $e');
      // If we cannot inspect it, let it through rather than dropping a
      // possibly-good frame.
      return false;
    }
  }

  Future<File?> _writeBytes(
    Uint8List bytes,
    String chapterId,
    int positionSeconds,
  ) async {
    try {
      final dir = await getTemporaryDirectory();
      final captureDir = Directory('${dir.path}/moment_captures');
      if (!await captureDir.exists()) {
        await captureDir.create(recursive: true);
      }

      final file = File(
        '${captureDir.path}/moment_${chapterId}_${positionSeconds}_'
        '${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await file.writeAsBytes(bytes, flush: true);
      return file;
    } catch (e) {
      debugPrint('[FrameCapture] could not write capture: $e');
      return null;
    }
  }

  /// Deletes captures left behind by earlier sessions.
  Future<void> clearOldCaptures() async {
    try {
      final dir = await getTemporaryDirectory();
      final captureDir = Directory('${dir.path}/moment_captures');
      if (!await captureDir.exists()) return;

      final cutoff = DateTime.now().subtract(const Duration(days: 1));
      await for (final entity in captureDir.list()) {
        if (entity is! File) continue;
        final stat = await entity.stat();
        if (stat.modified.isBefore(cutoff)) {
          await entity.delete();
        }
      }
    } catch (_) {
      // Housekeeping only.
    }
  }
}
