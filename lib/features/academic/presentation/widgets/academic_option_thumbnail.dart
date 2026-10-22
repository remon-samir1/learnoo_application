import 'package:flutter/material.dart';

import '../../../../core/widgets/cover_image.dart';

/// Leading thumbnail of an academic option (university / centre / faculty).
///
/// The web's `AcademicOptions` draws `option.image` in a 48px box beside the
/// name, so the onboarding rows and the profile pickers do the same. When the
/// record has no picture the icon the screens used before is drawn instead, and
/// an image that fails to load falls back to [CoverImage]'s gradient.
class AcademicOptionThumbnail extends StatelessWidget {
  const AcademicOptionThumbnail({
    super.key,
    required this.imageUrl,
    required this.label,
    required this.icon,
    required this.backgroundColor,
    required this.iconColor,
    this.size = 48,
    this.radius = 12,
  });

  /// Resolved by `entityImageUrl`; `null` when the record has no picture.
  final String? imageUrl;
  final String label;
  final IconData icon;
  final Color backgroundColor;
  final Color iconColor;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);

    if (imageUrl == null) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: borderRadius,
        ),
        child: Icon(icon, color: iconColor, size: size / 2),
      );
    }

    return CoverImage(
      url: imageUrl,
      title: label,
      width: size,
      height: size,
      icon: icon,
      borderRadius: borderRadius,
      showTitle: false,
      // University and faculty marks are logos: fit them in, as the
      // website does with object-contain, instead of cropping.
      fit: BoxFit.contain,
      cacheWidth: size.round(),
    );
  }
}
