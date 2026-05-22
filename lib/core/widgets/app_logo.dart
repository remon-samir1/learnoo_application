import 'package:flutter/material.dart';

class AppLogo extends StatelessWidget {
  final double size;
  final bool isLarge;
  final bool showText;
  final Color iconColor;
  final Color textColor;

  const AppLogo({
    super.key,
    this.size = 100,
    this.isLarge = false,
    this.showText = true,
    this.iconColor = Colors.white,
    this.textColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    final double effectiveSize = isLarge ? size * 1.5 : size;

    return Container(
      width: effectiveSize,
      height: effectiveSize,
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(51), // Approximately 20% opacity
        borderRadius: BorderRadius.circular(20), // Matched to design
        border: Border.all(
          color: Colors.white.withAlpha(30),
          width: 1.5,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Image.asset(
          'assets/images/Logo.png',
          width: effectiveSize,
          height: effectiveSize,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}
