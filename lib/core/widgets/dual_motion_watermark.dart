import 'package:flutter/material.dart';

import '../models/watermark_config.dart';

/// Two smoothly moving watermark instances, the way the website draws them.
///
/// Port of `components/student/watermark/DualMotionWatermark.tsx`. The web
/// renders exactly two copies that glide along two fixed five-point paths in
/// linear time, tilted in opposite directions. Everything here — the paths, the
/// loop duration, the text sizes, the tilt — matches that component so a
/// recording of the app is watermarked identically to a recording of the site.
class DualMotionWatermark extends StatefulWidget {
  const DualMotionWatermark({
    super.key,
    required this.text,
    required this.config,
  });

  final String text;
  final WatermarkConfig config;

  /// The two paths, as fractions of the frame. Same numbers as
  /// `DUAL_WATERMARK_MOTION_PATTERNS`, converted from percentages.
  static const List<List<Offset>> motionPaths = [
    [
      Offset(0.05, 0.08),
      Offset(0.85, 0.78),
      Offset(0.42, 0.32),
      Offset(0.12, 0.68),
      Offset(0.75, 0.18),
    ],
    [
      Offset(0.82, 0.18),
      Offset(0.08, 0.72),
      Offset(0.48, 0.28),
      Offset(0.72, 0.62),
      Offset(0.05, 0.10),
    ],
  ];

  /// Loop length when the admin has not set an interval.
  static const int defaultMovementDurationSeconds = 28;
  static const int _minLoopSeconds = 16;
  static const int _maxLoopSeconds = 120;

  /// Port of `resolveDualWatermarkDurationSeconds`.
  ///
  /// The admin's 1–5s "change interval" is scaled into a full path cycle rather
  /// than used one-to-one, then clamped.
  static int resolveDurationSeconds(WatermarkConfig config) {
    final interval = config.dynamicInterval;
    if (interval > 0) {
      final scale = config.dynamicPosition ? 10 : 8;
      final loop = interval * scale;
      return loop.clamp(_minLoopSeconds, _maxLoopSeconds);
    }
    return defaultMovementDurationSeconds;
  }

  /// Port of `dualWatermarkTextSizeClass`, in logical pixels.
  static double fontSizeFor(String size) {
    switch (size.toLowerCase()) {
      case 'small':
        return 12;
      case 'large':
        return 18;
      default:
        return 14;
    }
  }

  /// Port of `dualWatermarkTiltDegrees`: the first copy tilts one way, the
  /// second the other, both by the configured magnitude.
  static double tiltDegreesFor(int index, double rotationRadians) {
    final degrees = rotationRadians * 180 / 3.1415926535897932;
    final magnitude = degrees.abs() == 0 ? 20.0 : degrees.abs();
    return index == 0 ? -magnitude : magnitude;
  }

  @override
  State<DualMotionWatermark> createState() => _DualMotionWatermarkState();
}

class _DualMotionWatermarkState extends State<DualMotionWatermark>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(
        seconds: DualMotionWatermark.resolveDurationSeconds(widget.config),
      ),
    )..repeat();
  }

  @override
  void didUpdateWidget(DualMotionWatermark oldWidget) {
    super.didUpdateWidget(oldWidget);
    final duration = Duration(
      seconds: DualMotionWatermark.resolveDurationSeconds(widget.config),
    );
    if (_controller.duration != duration) {
      _controller
        ..duration = duration
        ..repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Position along [path] at progress `t` in [0, 1).
  ///
  /// The web animates through the five keyframes and loops back to the first,
  /// so the interpolation wraps rather than stopping at the last point.
  Offset _pointAt(List<Offset> path, double t) {
    final segments = path.length;
    final scaled = t * segments;
    final index = scaled.floor() % segments;
    final next = (index + 1) % segments;
    return Offset.lerp(path[index], path[next], scaled - scaled.floor())!;
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.text.trim();
    if (text.isEmpty) return const SizedBox.shrink();

    final config = widget.config;
    final fontSize = DualMotionWatermark.fontSizeFor(config.size);
    // `config.opacity` is already the 0–1 fraction the feature parser produced.
    final opacity = config.opacity.clamp(0.0, 1.0);
    final color = config.color ?? const Color(0xFF666666);

    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return ClipRect(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                return Stack(
                  children: List.generate(
                    DualMotionWatermark.motionPaths.length,
                    (index) {
                      final point = _pointAt(
                        DualMotionWatermark.motionPaths[index],
                        _controller.value,
                      );
                      final tilt = DualMotionWatermark.tiltDegreesFor(
                        index,
                        config.rotation,
                      );

                      return Positioned(
                        left: point.dx * constraints.maxWidth,
                        top: point.dy * constraints.maxHeight,
                        child: Transform.rotate(
                          angle: tilt * 3.1415926535897932 / 180,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: constraints.maxWidth * 0.88,
                            ),
                            child: Text(
                              text,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              softWrap: false,
                              style: TextStyle(
                                fontSize: fontSize,
                                fontWeight: FontWeight.w900,
                                color: color.withValues(alpha: opacity),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
