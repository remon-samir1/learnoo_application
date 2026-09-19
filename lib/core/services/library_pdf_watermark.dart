import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../models/watermark_config.dart';

/// Watermark text for a downloaded PDF, exactly as the website builds it in
/// `src/lib/server-pdf-watermark.ts`:
///
///  * the student code when `use_student_code` is on, the phone when
///    `use_phone_number` is on, joined with " · ";
///  * the admin's static text when neither produced anything;
///  * the student code appended for traceability if it is not already there.
///
/// This differs slightly from the on-screen overlay rule, and the downloaded
/// file has to match the website's downloaded file, so it is kept separate.
String buildDownloadWatermarkText({
  required WatermarkConfig config,
  String? studentCode,
  String? phone,
}) {
  final code = studentCode?.trim() ?? '';
  final phoneNumber = phone?.trim() ?? '';

  final parts = <String>[
    if (config.useStudentCode && code.isNotEmpty) code,
    if (config.usePhoneNumber && phoneNumber.isNotEmpty) phoneNumber,
  ];

  var text = parts.isNotEmpty ? parts.join(' · ') : config.text.trim();

  if (code.isNotEmpty && !text.contains(code)) {
    text = text.isEmpty ? code : '$text · $code';
  }
  return text;
}

/// Stamps the website's download watermark into a PDF.
///
/// Mirrors `addGridWatermarks`: a 3 × 4 grid of 24pt bold text on every page,
/// rotated 25° counter-clockwise, with padding and gaps proportional to the
/// page so the layout is the same on A4 and on phone-sized scans. Opacity and
/// colour come from the `library` watermark settings.
class LibraryPdfWatermarker {
  const LibraryPdfWatermarker();

  static const int _columns = 3;
  static const int _rows = 4;
  static const double _fontSize = 24;
  static const double _rotationDegrees = -25;

  /// Refuse to load absurdly large files into the PDF engine.
  static const int _maxBytes = 80 * 1024 * 1024;

  /// Writes a watermarked copy of [source] to [destination].
  ///
  /// Throws when the file cannot be read as a PDF. The caller treats that as a
  /// failed download rather than handing out the unwatermarked original.
  Future<void> apply({
    required File source,
    required File destination,
    required String text,
    required WatermarkConfig config,
  }) async {
    final length = await source.length();
    if (length > _maxBytes) {
      throw const FileSystemException('PDF too large to watermark');
    }

    final bytes = await source.readAsBytes();
    final document = PdfDocument(inputBytes: bytes);

    try {
      // The standard PDF fonts only cover Latin text. Admin-entered text in
      // another script would render as nothing, so the traceable part — digits
      // and Latin characters — is what gets drawn in that case.
      final drawable = _latinOnly(text);

      final font = PdfStandardFont(
        PdfFontFamily.helvetica,
        _fontSize,
        style: PdfFontStyle.bold,
      );
      final color = config.color ?? const Color(0xFF000000);
      final brush = PdfSolidBrush(
        PdfColor(
          (color.r * 255).round().clamp(0, 255),
          (color.g * 255).round().clamp(0, 255),
          (color.b * 255).round().clamp(0, 255),
        ),
      );
      final textSize = font.measureString(drawable);

      for (var p = 0; p < document.pages.count; p++) {
        final page = document.pages[p];
        final graphics = page.graphics;
        final size = page.getClientSize();

        // Same proportions as the website's grid.
        final padX = size.width * 0.055;
        final padY = size.height * 0.048;
        final gapX = size.width * 0.088;
        final gapY = size.height * 0.063;
        final cellW = (size.width - padX * 2 - gapX * (_columns - 1)) / _columns;
        final cellH = (size.height - padY * 2 - gapY * (_rows - 1)) / _rows;

        for (var row = 0; row < _rows; row++) {
          for (var col = 0; col < _columns; col++) {
            final cx = padX + col * (cellW + gapX) + cellW / 2;
            final cy = padY + row * (cellH + gapY) + cellH / 2;

            graphics.save();
            graphics.setTransparency(config.opacity.clamp(0.0, 1.0));
            graphics.translateTransform(cx, cy);
            graphics.rotateTransform(_rotationDegrees);
            graphics.drawString(
              drawable,
              font,
              brush: brush,
              bounds: Rect.fromLTWH(
                -textSize.width / 2,
                -textSize.height / 2,
                textSize.width,
                textSize.height,
              ),
            );
            graphics.restore();
          }
        }
      }

      final saved = await document.save();
      await destination.writeAsBytes(saved, flush: true);
    } finally {
      document.dispose();
    }
  }

  static String _latinOnly(String text) {
    final kept = text.runes
        .where((r) => r >= 0x20 && r < 0x250)
        .map(String.fromCharCode)
        .join()
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .replaceAll(RegExp(r'^[\s·]+|[\s·]+$'), '')
        .trim();
    if (kept.isEmpty) {
      debugPrint('[LibraryPdfWatermarker] watermark text has no drawable glyphs');
      return 'Learnoo';
    }
    return kept;
  }
}
