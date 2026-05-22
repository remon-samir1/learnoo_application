import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/feature_manager.dart';
import '../models/watermark_config.dart';
import 'watermark_widget.dart';

/// Watermark type enumeration
enum WatermarkType {
  videos,
  chapters,
  library,
  exams,
  files,
  liveStreams,
}

/// Watermark extension to get string key
extension WatermarkTypeExtension on WatermarkType {
  String get key {
    switch (this) {
      case WatermarkType.videos:
        return 'videos';
      case WatermarkType.chapters:
        return 'chapters';
      case WatermarkType.library:
        return 'library';
      case WatermarkType.exams:
        return 'exams';
      case WatermarkType.files:
        return 'files';
      case WatermarkType.liveStreams:
        return 'liveStreams';
    }
  }
}

/// Reusable Watermark Wrapper Widget
/// Applies a configurable watermark overlay to any child widget
class WatermarkWrapper extends StatefulWidget {
  final Widget child;
  final WatermarkType type;
  final String? studentCode;
  final FeatureManager? featureManager;

  const WatermarkWrapper({
    super.key,
    required this.child,
    required this.type,
    this.studentCode,
    this.featureManager,
  });

  @override
  State<WatermarkWrapper> createState() => _WatermarkWrapperState();
}

class _WatermarkWrapperState extends State<WatermarkWrapper> {
  late FeatureManager _manager;

  @override
  void initState() {
    super.initState();
    _manager = widget.featureManager ?? FeatureManager();
    _manager.addListener(_onFeatureManagerUpdate);
  }

  @override
  void didUpdateWidget(WatermarkWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.featureManager != oldWidget.featureManager) {
      oldWidget.featureManager?.removeListener(_onFeatureManagerUpdate);
      _manager = widget.featureManager ?? FeatureManager();
      _manager.addListener(_onFeatureManagerUpdate);
    }
  }

  @override
  void dispose() {
    _manager.removeListener(_onFeatureManagerUpdate);
    super.dispose();
  }

  void _onFeatureManagerUpdate() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = _manager.getWatermarkConfig(widget.type.key);

    // If watermark is disabled, return child widget only
    if (!settings.enabled) {
      return widget.child;
    }

    // Determine watermark text
    final watermarkText = settings.useStudentCode && widget.studentCode != null
        ? widget.studentCode!
        : settings.text;

    // Support moving watermark if position is 'moving'
    if (settings.position.name.toLowerCase() == 'moving' ||
        settings.dynamicPosition) {
      return Stack(
        children: [
          widget.child,
          WatermarkWidget(
            userName: watermarkText,
            userId: widget.studentCode ?? '',
            opacity: settings.opacity,
            rotation: settings.rotation,
            dynamicInterval: settings.dynamicInterval,
            style: TextStyle(
              fontSize: settings.fontSize,
              fontWeight: FontWeight.bold,
              color: (settings.color ?? Colors.black).withOpacity(settings.opacity),
            ),
          ),
        ],
      );
    }

    return Stack(
      children: [
        // Original content
        widget.child,
        // Watermark overlay — sized to text only, never full screen
        _buildWatermarkOverlay(settings, watermarkText),
      ],
    );
  }

  Widget _buildWatermarkOverlay(WatermarkConfig settings, String text) {
    final position = settings.position.name;

    if (position == 'full') {
      return _buildFullWatermark(settings, text);
    } else {
      return _buildCornerWatermark(settings, text, position);
    }
  }

  // ─────────────────────────────────────────────
  // FULL: CustomPainter — no gray overlay, no shadows stacking
  // ─────────────────────────────────────────────
  Widget _buildFullWatermark(WatermarkConfig settings, String text) {
    return IgnorePointer(
      child: CustomPaint(
        // Size.zero → painter draws on the Stack's overlay layer
        // without consuming any layout space itself
        size: Size.zero,
        painter: _WatermarkPainter(
          text: text,
          fontSize: settings.fontSize,
          opacity: settings.opacity,
          rotation: settings.rotation,
          color: settings.color,
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // CORNER / CENTER: widget sized to text only
  // ─────────────────────────────────────────────
  Widget _buildCornerWatermark(
    WatermarkConfig settings,
    String text,
    String position,
  ) {
    // The actual text widget — no shadows, sized to its content
    // Use config color or dark gray for visibility on both light and dark PDF backgrounds
    final textColor = settings.color ?? Colors.black54;
    final textWidget = IgnorePointer(
      child: Transform.rotate(
        angle: settings.rotation * (math.pi / 180),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          color: Colors.transparent,
          child: Text(
            text,
            style: TextStyle(
              fontSize: settings.fontSize,
              fontWeight: FontWeight.bold,
              // Use config color or default dark gray visible on both light and dark backgrounds
              color: textColor.withOpacity(settings.opacity),
            ),
          ),
        ),
      ),
    );

    if (position == 'center') {
      return Center(child: textWidget);
    }

    double? left, top, right, bottom;

    switch (position) {
      case 'topLeft':
        left = 16;
        top = 16;
        break;
      case 'topRight':
        right = 16;
        top = 16;
        break;
      case 'bottomLeft':
        left = 16;
        bottom = 16;
        break;
      case 'bottomRight':
      default:
        right = 16;
        bottom = 16;
        break;
    }

    return Positioned(
      left: left,
      top: top,
      right: right,
      bottom: bottom,
      child: textWidget,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CustomPainter for 'full' mode
// Draws repeated text directly on the Canvas — transparent background,
// no Widget tree overhead, no shadow stacking.
// ─────────────────────────────────────────────────────────────────────────────
class _WatermarkPainter extends CustomPainter {
  final String text;
  final double fontSize;
  final double opacity;
  final double rotation;
  final Color? color;

  const _WatermarkPainter({
    required this.text,
    required this.fontSize,
    required this.opacity,
    required this.rotation,
    this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // We need the actual screen size from the Stack parent,
    // so we clip to the nearest ancestor's bounds instead of `size`
    // (size is zero — we rely on the Stack to clip naturally).
    final screenSize = PaintingBinding.instance.window.physicalSize /
        PaintingBinding.instance.window.devicePixelRatio;

    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          // Increase visual font size for the overlay as well
          fontSize: fontSize * 1.2,
          fontWeight: FontWeight.w600,
          // Use config color or default dark gray visible on both light and dark backgrounds
          color: (color ?? Colors.black54).withValues(alpha: opacity),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final double spacingX = fontSize * 8;
    final double spacingY = fontSize * 8;

    final int cols = (screenSize.width / spacingX).ceil() + 2;
    final int rows = (screenSize.height / spacingY).ceil() + 2;

    for (int row = 0; row < rows; row++) {
      for (int col = 0; col < cols; col++) {
        // Stagger every other row
        final double stagger = (row % 2) * (spacingX / 2);
        final double x = col * spacingX + stagger - (spacingX / 2); // Start slightly left for better coverage
        final double y = row * spacingY;

        canvas.save();
        canvas.translate(x, y);
        canvas.rotate(rotation * (math.pi / 180));
        textPainter.paint(canvas, Offset.zero);
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(_WatermarkPainter old) =>
      old.text != text ||
      old.opacity != opacity ||
      old.rotation != rotation ||
      old.fontSize != fontSize ||
      old.color != color;
}

// ─────────────────────────────────────────────────────────────────────────────
// Simplified watermark widget for specific use cases
// ─────────────────────────────────────────────────────────────────────────────
class SimpleWatermark extends StatelessWidget {
  final String text;
  final double opacity;
  final double rotation;
  final double fontSize;
  final Color? color;

  const SimpleWatermark({
    super.key,
    required this.text,
    this.opacity = 0.2,
    this.rotation = -12.0,
    this.fontSize = 18.0,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Transform.rotate(
        angle: rotation * (math.pi / 180),
        child: Text(
          text,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
            // Use config color or default dark gray visible on both light and dark backgrounds
            color: (color ?? Colors.black54).withValues(alpha: opacity),
          ),
        ),
      ),
    );
  }
}