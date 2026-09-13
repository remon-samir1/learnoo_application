import 'package:flutter/material.dart';

enum WatermarkPosition {
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
  center,
  full,
}

enum WatermarkAnimationStyle {
  slide,
  fade,
  scale,
  rotate,
  glide,
}

enum WatermarkEasingType {
  linear,
  easeIn,
  easeOut,
  easeInOut,
  bounce,
  elastic,
}

class WatermarkConfig {
  final bool enabled;
  final String text;
  final bool useStudentCode;
  final bool usePhoneNumber;
  final WatermarkPosition position;
  final double opacity;
  final double rotation;
  final String size;
  
  // Dynamic Movement properties
  final bool dynamicPosition;
  final int dynamicInterval;
  final bool randomCoordinates;
  
  // Animation System properties
  final WatermarkAnimationStyle animationStyle;
  final WatermarkEasingType easingType;
  
  // Voice properties
  final bool voiceEnabled;
  final int voiceInterval;

  /// `watermark_{type}_movement_pattern`. Only the admin preview varies with
  /// it on the web, but it is carried through so the two clients read the same
  /// settings and a future player can honour it.
  final String movementPattern;

  // Color property
  final Color? color;

  const WatermarkConfig({
    required this.enabled,
    required this.text,
    required this.useStudentCode,
    required this.usePhoneNumber,
    required this.position,
    required this.opacity,
    required this.rotation,
    required this.size,
    required this.dynamicPosition,
    required this.dynamicInterval,
    required this.randomCoordinates,
    required this.animationStyle,
    required this.easingType,
    required this.voiceEnabled,
    required this.voiceInterval,
    this.movementPattern = 'random',
    this.color,
  });

  /// Get parsed font size based on string size
  double get fontSize {
    switch (size.toLowerCase()) {
      case 'small':
        return 12.0;
      case 'large':
        return 24.0;
      case 'medium':
      default:
        return 18.0;
    }
  }

  /// Get actual Flutter Curve from EasingType
  Curve get curve {
    switch (easingType) {
      case WatermarkEasingType.easeIn:
        return Curves.easeIn;
      case WatermarkEasingType.easeOut:
        return Curves.easeOut;
      case WatermarkEasingType.easeInOut:
        return Curves.easeInOut;
      case WatermarkEasingType.bounce:
        return Curves.bounceOut;
      case WatermarkEasingType.elastic:
        return Curves.elasticOut;
      case WatermarkEasingType.linear:
      default:
        return Curves.linear;
    }
  }

  /// Helper to convert string to enum mapping
  static WatermarkPosition parsePosition(String val) {
    switch (val.toLowerCase()) {
      case 'topleft': return WatermarkPosition.topLeft;
      case 'topright': return WatermarkPosition.topRight;
      case 'bottomleft': return WatermarkPosition.bottomLeft;
      case 'bottomright': return WatermarkPosition.bottomRight;
      case 'center': return WatermarkPosition.center;
      case 'full': return WatermarkPosition.full;
      // The web's DEFAULT_WATERMARK_CONFIG.position is `full`.
      default: return WatermarkPosition.full;
    }
  }

  static WatermarkAnimationStyle parseAnimationStyle(String val) {
    switch (val.toLowerCase()) {
      case 'slide': return WatermarkAnimationStyle.slide;
      case 'fade': return WatermarkAnimationStyle.fade;
      case 'scale': return WatermarkAnimationStyle.scale;
      case 'rotate': return WatermarkAnimationStyle.rotate;
      case 'glide': return WatermarkAnimationStyle.glide;
      default: return WatermarkAnimationStyle.fade;
    }
  }

  static WatermarkEasingType parseEasingType(String val) {
    switch (val.toLowerCase()) {
      case 'easein': return WatermarkEasingType.easeIn;
      case 'easeout': return WatermarkEasingType.easeOut;
      case 'easeinout': return WatermarkEasingType.easeInOut;
      case 'bounce': return WatermarkEasingType.bounce;
      case 'elastic': return WatermarkEasingType.elastic;
      case 'linear': return WatermarkEasingType.linear;
      default: return WatermarkEasingType.linear;
    }
  }
}
