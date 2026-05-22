// lib/core/widgets/protected_screen.dart

import 'package:flutter/material.dart';
import 'secure_wrapper.dart';

@Deprecated('Use SecureWrapper instead for maximum security.')
enum ProtectionMode {
  standard,
  strict,
  debug,
}

/// Legacy wrapper for backward compatibility.
/// Under the new "extreme security" architecture, this simply forwards
/// to `SecureWrapper`, dropping the old iOS-specific blur events.
@Deprecated('Use SecureWrapper instead for maximum security.')
class ProtectedScreen extends StatelessWidget {
  final Widget child;
  final ProtectionMode mode;
  final VoidCallback? onScreenshotAttempt;
  final VoidCallback? onRecordingStarted;
  final VoidCallback? onRecordingStopped;
  final String? protectionMessage;
  final Color overlayColor;
  final Duration animationDuration;
  final bool showDebugIndicator;

  const ProtectedScreen({
    super.key,
    required this.child,
    this.mode = ProtectionMode.standard,
    this.onScreenshotAttempt,
    this.onRecordingStarted,
    this.onRecordingStopped,
    this.protectionMessage,
    this.overlayColor = const Color(0xFF1A1A2E),
    this.animationDuration = const Duration(milliseconds: 250),
    this.showDebugIndicator = false,
  });

  @override
  Widget build(BuildContext context) {
    // Forward the protection message to the new extreme SecureWrapper
    return SecureWrapper(
      protectionMessage: protectionMessage ?? "Content Protected",
      child: child,
    );
  }
}

/// Legacy Mixin for backward compatibility.
/// The new architecture handles state globally and natively, so imperative
/// calls from mixins are largely deprecated. Wrap your top-level widget 
/// in SecureWrapper instead.
@Deprecated('Mixins are no longer supported. Wrap your widget in SecureWrapper.')
mixin ScreenProtectionMixin<T extends StatefulWidget> on State<T> {
  void enableScreenProtection() {
    debugPrint("ScreenProtectionMixin: Use SecureWrapper instead.");
  }
  void disableScreenProtection() {
     debugPrint("ScreenProtectionMixin: Use SecureWrapper instead.");
  }
  void listenToProtectionEvents(Function onEvent) {
     debugPrint("ScreenProtectionMixin: Direct event listeners are deprecated.");
  }
  void cancelProtectionEventSubscription() {}
}
