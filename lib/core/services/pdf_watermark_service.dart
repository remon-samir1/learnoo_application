import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:path/path.dart' as path;
import '../models/watermark_config.dart';

/// Service to embed watermarks directly into PDF files.
class PdfWatermarkService {
  /// Embeds a watermark into each page of a PDF file.
  /// Returns the path to the watermarked PDF.
  Future<String> embedWatermark({
    required String sourcePdfPath,
    required String watermarkText,
    double opacity = 0.2,
    double fontSize = 18,
    double rotationDeg = -45,
    WatermarkPosition position = WatermarkPosition.full,
    Color? color,
  }) async {
    try {
      final File sourceFile = File(sourcePdfPath);
      if (!await sourceFile.exists()) {
        throw Exception('Source PDF file not found: $sourcePdfPath');
      }

      // Check file size to prevent OOM - limit to 50MB
      const int maxFileSize = 50 * 1024 * 1024; // 50MB
      final int fileLength = await sourceFile.length();
      if (fileLength > maxFileSize) {
        throw Exception('PDF file too large (${(fileLength / 1024 / 1024).toStringAsFixed(1)}MB). Maximum allowed: 50MB');
      }

      // Read file bytes
      final Uint8List bytes = await sourceFile.readAsBytes();
      PdfDocument? document;
      try {
        document = PdfDocument(inputBytes: bytes);

      // Create a font for the watermark
      // Make the font size moderately larger for PDFs
      final double effectiveFontSize = fontSize * 3.2; 
      final PdfFont font = PdfStandardFont(PdfFontFamily.helvetica, effectiveFontSize, style: PdfFontStyle.bold);

      // Resolve color - default to gray if null
      final displayColor = color ?? Colors.grey;
      
      // Create an opaque brush (transparency is handled via graphics state)
      final PdfBrush brush = PdfSolidBrush(PdfColor(
        (displayColor.r * 255.0).round().clamp(0, 255),
        (displayColor.g * 255.0).round().clamp(0, 255),
        (displayColor.b * 255.0).round().clamp(0, 255),
        255, // Full alpha here, applied in setTransparency
      ));

      // Calculate spacing for vertical stacking in center
      final double textWidthEstimate = watermarkText.length * effectiveFontSize * 0.6;
      final double spacingY = effectiveFontSize * 2.5;  // Vertical spacing between watermarks
      
      // Use the requested position (center)
      final WatermarkPosition effectivePosition = position;

      // Process each page
      for (int i = 0; i < document.pages.count; i++) {
        final PdfPage page = document.pages[i];
        final PdfGraphics graphics = page.graphics;
        final Size pageSize = page.getClientSize();

        // Save graphics state
        graphics.save();
        
        // Set transparency and blend mode to blend into the background (appear under content)
        graphics.setTransparency(opacity, mode: PdfBlendMode.multiply);

        // CENTERED VERTICAL STACK - draw multiple watermarks stacked vertically in center
        final int count = 5; // Number of watermarks to stack
        final double totalHeight = count * spacingY;
        final double startY = (pageSize.height - totalHeight) / 2; // Center vertically
        final double centerX = pageSize.width / 2;

        for (int i = 0; i < count; i++) {
          final double y = startY + (i * spacingY);
          
          // Calculate text width for centering
          final textLines = watermarkText.split(' | ');
          final double lineHeight = effectiveFontSize * 1.2;
          final double textBlockHeight = textLines.length * lineHeight;
          final double textWidth = textLines.fold<double>(0, (max, line) {
            final lineWidth = line.length * effectiveFontSize * 0.6;
            return lineWidth > max ? lineWidth : max;
          });
          
          // Center the text block
          final double x = centerX - (textWidth / 2);
          final double adjustedY = y - (textBlockHeight / 2);

          graphics.save();
          graphics.translateTransform(x, adjustedY);
          graphics.rotateTransform(rotationDeg);

          for (int lineIdx = 0; lineIdx < textLines.length; lineIdx++) {
            final double lineY = lineIdx * lineHeight;
            graphics.drawString(textLines[lineIdx], font, brush: brush, bounds: Rect.fromLTWH(0, lineY, textWidth, lineHeight));
          }

          graphics.restore();
        }

        // Restore graphics state
        graphics.restore();
      }
      

        // Save the modified document
        final List<int> savedBytes = await document.save();

        // Create a new file path for the watermarked PDF
        final String directory = path.dirname(sourcePdfPath);
        final String extension = path.extension(sourcePdfPath);
        final String fileName = path.basenameWithoutExtension(sourcePdfPath);
        final String targetPath = path.join(directory, '${fileName}_wm$extension');

        final File targetFile = File(targetPath);
        await targetFile.writeAsBytes(savedBytes);

        debugPrint('[PdfWatermarkService] Watermark embedded successfully at $position: $targetPath');
        return targetPath;
      } finally {
        document?.dispose();
      }
    } catch (e) {
      debugPrint('[PdfWatermarkService] Error embedding watermark: $e');
      rethrow;
    }
  }
}
