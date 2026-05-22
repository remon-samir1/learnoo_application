import 'package:flutter/material.dart';

class AnnotationPoint {
  final Offset offset;
  final Color color;
  final double strokeWidth;
  final bool isHighlighter;

  AnnotationPoint({
    required this.offset,
    required this.color,
    required this.strokeWidth,
    this.isHighlighter = false,
  });
}

class InkStroke {
  final List<AnnotationPoint> points;
  final Color color;
  final double strokeWidth;
  final bool isHighlighter;
  final DateTime timestamp;

  InkStroke({
    required this.points,
    required this.color,
    required this.strokeWidth,
    this.isHighlighter = false,
  }) : timestamp = DateTime.now();

  InkStroke copyWith({
    List<AnnotationPoint>? points,
    Color? color,
    double? strokeWidth,
    bool? isHighlighter,
  }) {
    return InkStroke(
      points: points ?? this.points,
      color: color ?? this.color,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      isHighlighter: isHighlighter ?? this.isHighlighter,
    );
  }
}
