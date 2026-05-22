import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A dynamic, moving watermark widget that displays user information.
/// Position changes periodically to prevent easy removal or AI cropping.
class WatermarkWidget extends StatefulWidget {
  final String userName;
  final String userId;
  final TextStyle? style;
  final double opacity;
  final double rotation;
  final int dynamicInterval;

  const WatermarkWidget({
    super.key,
    required this.userName,
    required this.userId,
    this.style,
    this.opacity = 0.15,
    this.rotation = -0.21,
    this.dynamicInterval = 8,
  });

  @override
  State<WatermarkWidget> createState() => _WatermarkWidgetState();
}

class _WatermarkWidgetState extends State<WatermarkWidget> {
  double _top = 100;
  double _left = 100;
  double _parentWidth = 0;
  double _parentHeight = 0;
  BoxConstraints _currentConstraints = const BoxConstraints();
  Timer? _timer;
  final math.Random _random = math.Random();
  final GlobalKey _watermarkKey = GlobalKey();

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _initializePosition(BoxConstraints constraints) {
    _currentConstraints = constraints;
    _parentWidth = constraints.maxWidth;
    _parentHeight = constraints.maxHeight;

    // Get watermark size if already rendered
    final watermarkSize = _getWatermarkSize();
    final watermarkWidth = watermarkSize?.width ?? 150;
    final watermarkHeight = watermarkSize?.height ?? 60;

    // Constrain position to stay within parent bounds
    final maxTop = math.max(0, _parentHeight - watermarkHeight - 20);
    final maxLeft = math.max(0, _parentWidth - watermarkWidth - 20);

    _top = maxTop > 20 ? _random.nextDouble() * maxTop + 10 : 10;
    _left = maxLeft > 20 ? _random.nextDouble() * maxLeft + 10 : 10;
  }

  Size? _getWatermarkSize() {
    final context = _watermarkKey.currentContext;
    if (context != null) {
      final renderBox = context.findRenderObject() as RenderBox?;
      return renderBox?.size;
    }
    return null;
  }

  void _startMoving(BoxConstraints constraints) {
    // Always restart timer with new constraints
    _timer?.cancel();
    _timer = null;

    final interval = widget.dynamicInterval > 0 ? widget.dynamicInterval : 8;
    _timer = Timer.periodic(Duration(seconds: interval), (timer) {
      if (!mounted) return;

      // Get current watermark size
      final watermarkSize = _getWatermarkSize();
      final watermarkWidth = watermarkSize?.width ?? 150;
      final watermarkHeight = watermarkSize?.height ?? 60;

      // Calculate safe bounds using stored current constraints
      final maxTop = math.max(0, _currentConstraints.maxHeight - watermarkHeight - 20);
      final maxLeft = math.max(0, _currentConstraints.maxWidth - watermarkWidth - 20);

      setState(() {
        // Keep watermark within parent bounds with margin
        _top = maxTop > 20 ? _random.nextDouble() * maxTop + 10 : 10;
        _left = maxLeft > 20 ? _random.nextDouble() * maxLeft + 10 : 10;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Initialize on first build or when constraints change significantly
        if (_parentWidth != constraints.maxWidth || _parentHeight != constraints.maxHeight) {
          _initializePosition(constraints);
          _startMoving(constraints);
        }
        
        return IgnorePointer(
          child: Stack(
            children: [
AnimatedPositioned(
                duration: const Duration(seconds: 2),
                curve: Curves.easeInOut,
                top: _top,
                left: _left,
                child: Transform.rotate(
                  angle: widget.rotation,
                  child: Container(
                    key: _watermarkKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.userName,
                          style: widget.style?.copyWith(
                                color: (widget.style?.color ?? Colors.black54).withOpacity(widget.opacity),
                              ) ??
                              TextStyle(
                                color: Colors.black54.withOpacity(widget.opacity),
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                shadows: const [
                                  Shadow(
                                    blurRadius: 3,
                                    color: Colors.white,
                                    offset: Offset(1, 1),
                                  ),
                                ],
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
