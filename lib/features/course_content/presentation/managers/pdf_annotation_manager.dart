import 'dart:io';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../models/pdf_annotation.dart';

class PdfAnnotationManager {
  // Store annotations per page (key = page number, 1-indexed)
  final Map<int, List<InkStroke>> pageAnnotations = {};
  
  // Undo stack per page
  final Map<int, List<List<InkStroke>>> undoStacks = {};
  
  // Current annotation settings
  Color currentColor = Colors.red;
  double currentStrokeWidth = 3.0;
  bool isHighlighterMode = false;
  
  // Track if there are unsaved changes
  bool hasUnsavedChanges = false;

  /// Add a stroke to a specific page
  void addStroke(int pageNumber, InkStroke stroke) {
    if (!pageAnnotations.containsKey(pageNumber)) {
      pageAnnotations[pageNumber] = [];
      undoStacks[pageNumber] = [];
    }
    
    // Save current state to undo stack before adding
    undoStacks[pageNumber]!.add(List.from(pageAnnotations[pageNumber]!));
    
    // Add the new stroke
    pageAnnotations[pageNumber]!.add(stroke);
    hasUnsavedChanges = true;
  }

  /// Undo last stroke on a specific page
  void undo(int pageNumber) {
    if (!undoStacks.containsKey(pageNumber) || undoStacks[pageNumber]!.isEmpty) {
      return;
    }
    
    // Restore previous state
    pageAnnotations[pageNumber] = undoStacks[pageNumber]!.removeLast();
    
    // Check if there are any annotations left
    if (pageAnnotations[pageNumber]!.isEmpty && undoStacks[pageNumber]!.isEmpty) {
      hasUnsavedChanges = false;
    }
  }

  /// Check if undo is available for a page
  bool canUndo(int pageNumber) {
    return undoStacks.containsKey(pageNumber) && undoStacks[pageNumber]!.isNotEmpty;
  }

  /// Clear all annotations on a specific page
  void clearPage(int pageNumber) {
    if (pageAnnotations.containsKey(pageNumber) && pageAnnotations[pageNumber]!.isNotEmpty) {
      undoStacks[pageNumber] = [List.from(pageAnnotations[pageNumber]!)];
      pageAnnotations[pageNumber]!.clear();
      hasUnsavedChanges = true;
    }
  }

  /// Discard all annotations and reset
  void discardAll() {
    pageAnnotations.clear();
    undoStacks.clear();
    hasUnsavedChanges = false;
  }

  /// Get annotations for a specific page
  List<InkStroke> getAnnotationsForPage(int pageNumber) {
    return pageAnnotations[pageNumber] ?? [];
  }

  /// Check if a page has annotations
  bool pageHasAnnotations(int pageNumber) {
    return pageAnnotations.containsKey(pageNumber) && pageAnnotations[pageNumber]!.isNotEmpty;
  }

  /// Save all annotations to the PDF file
  Future<bool> saveToPdf(String filePath) async {
    try {
      final File file = File(filePath);
      final bytes = await file.readAsBytes();
      final document = PdfDocument(inputBytes: bytes);

      // Process each page with annotations
      for (final entry in pageAnnotations.entries) {
        final pageNumber = entry.key; // 1-indexed
        final strokes = entry.value;
        
        if (strokes.isEmpty) continue;

        // Get the PDF page (0-indexed)
        if (pageNumber <= 0 || pageNumber > document.pages.count) continue;
        final page = document.pages[pageNumber - 1];

        // Draw each stroke
        for (final stroke in strokes) {
          if (stroke.points.length < 2) continue;

          final pen = PdfPen(
            PdfColor(
              (stroke.color.r * 255).round(),
              (stroke.color.g * 255).round(),
              (stroke.color.b * 255).round(),
            ),
          );
          pen.width = stroke.strokeWidth;
          pen.lineCap = PdfLineCap.round;
          pen.lineJoin = PdfLineJoin.round;

          // If highlighter, use transparency
          if (stroke.isHighlighter) {
            pen.color = PdfColor(
              (stroke.color.r * 255).round(),
              (stroke.color.g * 255).round(),
              (stroke.color.b * 255).round(),
              100, // Alpha for transparency
            );
          }

          // Draw the stroke
          for (int i = 0; i < stroke.points.length - 1; i++) {
            final point = stroke.points[i];
            final nextPoint = stroke.points[i + 1];
            
            page.graphics.drawLine(
              pen,
              point.offset,
              nextPoint.offset,
            );
          }
        }
      }

      // Save the modified document
      final savedBytes = await document.save();
      await file.writeAsBytes(savedBytes);
      document.dispose();

      // Clear unsaved changes flag
      hasUnsavedChanges = false;
      
      return true;
    } catch (e) {
      debugPrint('Error saving annotations to PDF: $e');
      return false;
    }
  }

  /// Transform screen coordinates to PDF page coordinates
  /// This needs to be called with the current zoom level and scroll offset
  Offset screenToPdfCoordinates(
    Offset screenOffset,
    double zoomLevel,
    Offset scrollOffset,
    Size pageSize,
  ) {
    return Offset(
      (screenOffset.dx + scrollOffset.dx) / zoomLevel,
      (screenOffset.dy + scrollOffset.dy) / zoomLevel,
    );
  }

  /// Transform PDF coordinates to screen coordinates
  Offset pdfToScreenCoordinates(
    Offset pdfOffset,
    double zoomLevel,
    Offset scrollOffset,
  ) {
    return Offset(
      pdfOffset.dx * zoomLevel - scrollOffset.dx,
      pdfOffset.dy * zoomLevel - scrollOffset.dy,
    );
  }

  /// Group points into strokes based on distance
  static List<List<AnnotationPoint>> groupPointsIntoStrokes(
    List<AnnotationPoint> points,
    double distanceThreshold,
  ) {
    final List<List<AnnotationPoint>> strokes = [];
    List<AnnotationPoint> currentStroke = [];

    for (int i = 0; i < points.length; i++) {
      final point = points[i];

      // Check if this is a new stroke (distance > threshold from previous)
      if (i > 0) {
        final prevPoint = points[i - 1];
        if ((point.offset - prevPoint.offset).distance > distanceThreshold) {
          if (currentStroke.isNotEmpty) {
            strokes.add(List.from(currentStroke));
            currentStroke.clear();
          }
        }
      }

      // Add point to current stroke
      currentStroke.add(point);
    }

    // Add final stroke
    if (currentStroke.isNotEmpty) {
      strokes.add(currentStroke);
    }

    return strokes;
  }
}
