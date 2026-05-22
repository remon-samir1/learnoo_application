import 'package:flutter/material.dart';
import '../models/watermark_config.dart';
import '../controllers/watermark_controller.dart';

class DynamicWatermarkWidget extends StatefulWidget {
  final WatermarkController controller;
  
  const DynamicWatermarkWidget({super.key, required this.controller});

  @override
  State<DynamicWatermarkWidget> createState() => _DynamicWatermarkWidgetState();
}

class _DynamicWatermarkWidgetState extends State<DynamicWatermarkWidget> with SingleTickerProviderStateMixin {
  late AnimationController _fxController;

  @override
  void initState() {
    super.initState();
    _fxController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    if (widget.controller.config.animationStyle == WatermarkAnimationStyle.scale || 
        widget.controller.config.animationStyle == WatermarkAnimationStyle.fade) {
      _fxController.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _fxController.dispose();
    // NOTE: controller is NOT disposed here - the parent widget that created it owns disposal
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([widget.controller, _fxController]),
      builder: (context, child) {
        if (!widget.controller.config.enabled || !widget.controller.isInitialized) {
          return const SizedBox.shrink();
        }

        // Calculate opacity - use color alpha instead of Opacity widget to avoid gray overlay on real devices
        double currentOpacity = widget.controller.config.opacity;
        if (widget.controller.config.animationStyle == WatermarkAnimationStyle.fade) {
          final fadeValue = Tween(begin: currentOpacity, end: 0.0).animate(
             CurvedAnimation(parent: _fxController, curve: Curves.easeInOut)
          );
          currentOpacity = fadeValue.value;
        }

        // Split display text by separator to show multiple lines
        final displayParts = widget.controller.displayText.split(' | ');
        
        Widget watermark = Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ...displayParts.map((part) => Text(
                part,
                style: TextStyle(
                  color: Colors.white.withOpacity(currentOpacity),
                  fontSize: widget.controller.config.fontSize,
                  fontWeight: FontWeight.bold,
                  shadows: const [
                    Shadow(
                      offset: Offset(1, 1),
                      blurRadius: 2.0,
                      color: Colors.black54,
                    )
                  ]
                ),
              )),
              Text(
                DateTime.now().toString().split('.')[0],
                style: TextStyle(
                  color: Colors.white.withOpacity(currentOpacity * 0.7),
                  fontSize: widget.controller.config.fontSize * 0.7,
                  shadows: const [
                    Shadow(offset: Offset(1, 1), blurRadius: 2.0, color: Colors.black54)
                  ]
                ),
              ),
            ],
          ),
        );

        // Apply rotation
        if (widget.controller.config.animationStyle == WatermarkAnimationStyle.rotate) {
          watermark = RotationTransition(
            turns: Tween(begin: 0.0, end: 1.0).animate(_fxController),
            child: watermark,
          );
        } else if (widget.controller.config.rotation != 0) {
          watermark = Transform.rotate(
            angle: widget.controller.config.rotation,
            child: watermark,
          );
        }

        // Apply scale pulse
        if (widget.controller.config.animationStyle == WatermarkAnimationStyle.scale) {
          watermark = ScaleTransition(
            scale: Tween(begin: 0.8, end: 1.2).animate(
              CurvedAnimation(parent: _fxController, curve: Curves.easeInOut)
            ),
            child: watermark,
          );
        }

        // Map X,Y to Alignment (-1.0 to 1.0)
        final alignX = (widget.controller.positionX * 2) - 1.0;
        final alignY = (widget.controller.positionY * 2) - 1.0;

        // Always animate position changes when dynamicPosition is enabled
        return AnimatedAlign(
          duration: Duration(seconds: widget.controller.config.dynamicInterval),
          curve: widget.controller.config.curve,
          alignment: Alignment(alignX, alignY),
          child: watermark,
        );
      },
    );
  }
}
