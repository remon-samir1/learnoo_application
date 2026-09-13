import 'package:flutter/material.dart';

import '../models/watermark_config.dart';
import '../services/feature_manager.dart';
import '../utils/watermark_text.dart';
import 'dual_motion_watermark.dart';

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

/// Overlays the platform watermark on protected content.
///
/// Matches the website's `VideoWatermark`, which is what every student surface
/// there uses: resolve the first enabled bucket for this content type, build the
/// line with [buildWatermarkText], and draw it with [DualMotionWatermark]. The
/// app used to pick between several static and moving renderings of its own, so
/// the same platform settings produced a visibly different watermark on each
/// client.
class WatermarkWrapper extends StatefulWidget {
  const WatermarkWrapper({
    super.key,
    required this.child,
    required this.type,
    this.studentCode,
    this.phone,
    this.featureManager,
  });

  final Widget child;
  final WatermarkType type;

  /// The student's own code, not a pre-formatted line — the text is assembled
  /// here so every surface formats it the same way.
  final String? studentCode;

  final String? phone;

  final FeatureManager? featureManager;

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
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // Bucket fallback (chapters → videos → exams), like the web.
    final WatermarkConfig settings =
        _manager.resolveWatermarkConfig(widget.type.key);

    if (!settings.enabled) return widget.child;

    final text = buildWatermarkText(
      config: settings,
      studentCode: widget.studentCode,
      phone: widget.phone,
    );

    if (text.trim().isEmpty) return widget.child;

    return Stack(
      fit: StackFit.passthrough,
      children: [
        widget.child,
        Positioned.fill(
          child: DualMotionWatermark(text: text, config: settings),
        ),
      ],
    );
  }
}
