import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Back control for screens that draw their own header — a gradient
/// `Container` or a `Stack` — instead of an `AppBar`.
///
/// An `AppBar` adds its own leading back button on a route that can be popped;
/// a hand-rolled header does not, and iOS has no hardware back button, so such
/// a screen becomes a dead end there. This widget gives those headers the same
/// affordance in the shape the app already uses: a translucent rounded square
/// with a directional arrow.
///
/// The arrow is [Icons.arrow_back_rounded], a Material directional icon that
/// mirrors itself in RTL, and callers place it with directional insets
/// (`PositionedDirectional`, `AlignmentDirectional`, `Row` order) so it also
/// sits on the correct side in Arabic.
class HeaderBackButton extends StatelessWidget {
  const HeaderBackButton({
    super.key,
    this.onPressed,
    this.iconColor = Colors.white,
    this.backgroundColor,
    this.borderColor,
    this.iconSize = 20,
    this.padding = const EdgeInsets.all(10),
    this.borderRadius = 14,
  });

  /// Defaults to `Navigator.maybePop`, which goes through the route's
  /// `PopScope` exactly like the Android back button does.
  final VoidCallback? onPressed;

  final Color iconColor;
  final Color? backgroundColor;
  final Color? borderColor;
  final double iconSize;
  final EdgeInsetsGeometry padding;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);

    return Tooltip(
      message: 'common.back'.tr(),
      child: InkWell(
        onTap: onPressed ?? () => Navigator.of(context).maybePop(),
        borderRadius: radius,
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: backgroundColor ?? Colors.white.withValues(alpha: 0.2),
            borderRadius: radius,
            border: Border.all(
              color: borderColor ?? Colors.white.withValues(alpha: 0.25),
            ),
          ),
          child: Icon(
            Icons.arrow_back_rounded,
            color: iconColor,
            size: iconSize,
          ),
        ),
      ),
    );
  }
}
