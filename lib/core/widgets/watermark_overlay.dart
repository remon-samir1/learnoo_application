import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

/// Enhanced watermark overlay with multiple display modes and opacity control
class WatermarkOverlay extends StatefulWidget {
  final String userName;
  final String userId;
  final double opacity;
  final WatermarkMode mode;
  final double fontSize;
  final Color color;
  final bool animated;

  const WatermarkOverlay({
    super.key,
    required this.userName,
    required this.userId,
    this.opacity = 0.15,
    this.mode = WatermarkMode.diagonal,
    this.fontSize = 14,
    this.color = Colors.grey,
    this.animated = true,
  });

  @override
  State<WatermarkOverlay> createState() => _WatermarkOverlayState();
}

class _WatermarkOverlayState extends State<WatermarkOverlay> {
  late Timer _timer;
  double _position = 0.0;
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    if (widget.animated && widget.mode == WatermarkMode.moving) {
      _startAnimation();
    }
  }

  void _startAnimation() {
    _timer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) {
        setState(() {
          _position = _random.nextDouble();
        });
      }
    });
  }

  @override
  void dispose() {
    if (widget.animated && widget.mode == WatermarkMode.moving) {
      _timer.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 300),
        opacity: widget.opacity,
        child: _buildWatermarkContent(),
      ),
    );
  }

  Widget _buildWatermarkContent() {
    switch (widget.mode) {
      case WatermarkMode.single:
        return _buildSingleWatermark();
      case WatermarkMode.diagonal:
        return _buildDiagonalWatermark();
      case WatermarkMode.grid:
        return _buildGridWatermark();
      case WatermarkMode.moving:
        return _buildMovingWatermark();
    }
  }

  Widget _buildSingleWatermark() {
    return Positioned(
      bottom: 20,
      right: 20,
      child: _buildWatermarkText(),
    );
  }

  Widget _buildDiagonalWatermark() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            for (int i = 0; i < 5; i++)
              Positioned(
                top: constraints.maxHeight * (i * 0.2) + 50,
                left: constraints.maxWidth * (i * 0.15) + 20,
                child: Transform.rotate(
                  angle: -0.3,
                  child: _buildWatermarkText(),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildGridWatermark() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            for (int row = 0; row < 3; row++)
              for (int col = 0; col < 3; col++)
                Positioned(
                  top: constraints.maxHeight * (row * 0.33 + 0.1),
                  left: constraints.maxWidth * (col * 0.33 + 0.05),
                  child: Transform.rotate(
                    angle: -0.2,
                    child: _buildWatermarkText(),
                  ),
                ),
          ],
        );
      },
    );
  }

  Widget _buildMovingWatermark() {
    return AnimatedPositioned(
      duration: const Duration(seconds: 5),
      curve: Curves.easeInOut,
      top: MediaQuery.of(context).size.height * _position,
      left: MediaQuery.of(context).size.width * (1 - _position),
      child: Transform.rotate(
        angle: -0.3,
        child: _buildWatermarkText(),
      ),
    );
  }

  Widget _buildWatermarkText() {
    final textStyle = TextStyle(
      color: widget.color,
      fontSize: widget.fontSize,
      fontWeight: FontWeight.bold,
      shadows: [
        Shadow(
          blurRadius: 2,
          color: widget.color.withValues(alpha: 0.3),
          offset: const Offset(1, 1),
        ),
      ],
    );

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        color: Colors.transparent,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.userName,
            style: textStyle,
          ),
          Text(
            'ID: ${widget.userId}',
            style: textStyle.copyWith(fontSize: widget.fontSize * 0.85),
          ),
          Text(
            DateTime.now().toString().split('.')[0],
            style: textStyle.copyWith(fontSize: widget.fontSize * 0.7),
          ),
        ],
      ),
    );
  }
}

/// Enum for different watermark display modes
enum WatermarkMode {
  single,
  diagonal,
  grid,
  moving,
}

/// Widget that wraps content with a watermark overlay
class WatermarkedContent extends StatelessWidget {
  final Widget child;
  final String userName;
  final String userId;
  final double opacity;
  final WatermarkMode mode;
  final bool enableWatermark;

  const WatermarkedContent({
    super.key,
    required this.child,
    required this.userName,
    required this.userId,
    this.opacity = 0.15,
    this.mode = WatermarkMode.diagonal,
    this.enableWatermark = true,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        if (enableWatermark)
          Positioned.fill(
            child: WatermarkOverlay(
              userName: userName,
              userId: userId,
              opacity: opacity,
              mode: mode,
            ),
          ),
      ],
    );
  }
}

/// Specialized watermark for exam screens with anti-cheat measures
class ExamWatermarkOverlay extends StatelessWidget {
  final String userName;
  final String userId;
  final double opacity;

  const ExamWatermarkOverlay({
    super.key,
    required this.userName,
    required this.userId,
    this.opacity = 0.1,
  });

  @override
  Widget build(BuildContext context) {
    return WatermarkOverlay(
      userName: userName,
      userId: userId,
      opacity: opacity,
      mode: WatermarkMode.grid,
      fontSize: 12,
      animated: false,
    );
  }
}

/// Watermark with opacity slider control
class AdjustableWatermark extends StatefulWidget {
  final String userName;
  final String userId;
  final Widget child;

  const AdjustableWatermark({
    super.key,
    required this.userName,
    required this.userId,
    required this.child,
  });

  @override
  State<AdjustableWatermark> createState() => _AdjustableWatermarkState();
}

class _AdjustableWatermarkState extends State<AdjustableWatermark> {
  double _opacity = 0.15;
  bool _showControls = false;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: WatermarkOverlay(
            userName: widget.userName,
            userId: widget.userId,
            opacity: _opacity,
          ),
        ),
        // Toggle controls button
        Positioned(
          top: 8,
          right: 8,
          child: GestureDetector(
            onTap: () => setState(() => _showControls = !_showControls),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.water_drop,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        ),
        // Opacity controls
        if (_showControls)
          Positioned(
            top: 50,
            right: 8,
            child: Container(
              width: 200,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Watermark Opacity',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Slider(
                    value: _opacity,
                    min: 0,
                    max: 0.5,
                    divisions: 10,
                    label: '${(_opacity * 100).toStringAsFixed(0)}%',
                    onChanged: (value) => setState(() => _opacity = value),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('0%', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                      Text('50%', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
