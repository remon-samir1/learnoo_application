import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../utils/media_url.dart';

/// Course / department cover, rendered the way the website's
/// `CourseCardThumbnail` and `CategoryCardThumbnail` do: the API image when
/// there is one and it loads, otherwise a gradient picked from the title with
/// an icon and the title on it.
class CoverImage extends StatelessWidget {
  const CoverImage({
    super.key,
    required this.url,
    required this.title,
    this.width = double.infinity,
    this.height,
    this.icon = Icons.school_rounded,
    this.borderRadius = BorderRadius.zero,
    this.showTitle = true,
    this.cacheWidth,
    this.darken = 0,
  });

  /// Raw API value; resolved with [resolveMediaUrl].
  final dynamic url;
  final String title;
  final double width;
  final double? height;
  final IconData icon;
  final BorderRadius borderRadius;

  /// Draw the title on the gradient fallback. Off for small thumbnails.
  final bool showTitle;

  /// Decode width in logical pixels, to keep memory low in long lists.
  final int? cacheWidth;

  /// 0..1 black overlay on a loaded image, for text drawn on top.
  final double darken;

  /// The website's `GRADIENTS` list, in the same order.
  static const List<List<Color>> gradients = [
    [Color(0xFF1D4ED8), Color(0xFF3B82F6), Color(0xFF60A5FA)],
    [Color(0xFF047857), Color(0xFF0D9488), Color(0xFF14B8A6)],
    [Color(0xFF4338CA), Color(0xFF6366F1), Color(0xFF8B5CF6)],
    [Color(0xFFBE185D), Color(0xFFEC4899), Color(0xFFF472B6)],
    [Color(0xFF0369A1), Color(0xFF0284C7), Color(0xFF38BDF8)],
    [Color(0xFFC2410C), Color(0xFFEA580C), Color(0xFFF97316)],
    [Color(0xFF6D28D9), Color(0xFF9333EA), Color(0xFFC084FC)],
  ];

  /// Same hash as the website's `getGradientStyle`, so a course gets the same
  /// colours in the app and in the browser.
  static List<Color> gradientFor(String seed) {
    var hash = 0;
    for (final unit in seed.codeUnits) {
      hash = ((hash << 5) - hash + unit).toSigned(32);
    }
    return gradients[hash.abs() % gradients.length];
  }

  @override
  Widget build(BuildContext context) {
    final resolved = resolveMediaUrl(url);
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2;
    final memWidth = cacheWidth == null ? null : (cacheWidth! * dpr).round();

    return ClipRRect(
      borderRadius: borderRadius,
      child: SizedBox(
        width: width,
        height: height,
        child: resolved == null
            ? _fallback()
            : CachedNetworkImage(
                imageUrl: resolved,
                width: width,
                height: height,
                fit: BoxFit.cover,
                memCacheWidth: memWidth,
                color: darken > 0
                    ? Colors.black.withValues(alpha: darken)
                    : null,
                colorBlendMode: darken > 0 ? BlendMode.darken : null,
                fadeInDuration: const Duration(milliseconds: 150),
                placeholder: (_, _) => _fallback(),
                errorWidget: (_, _, _) => _fallback(),
              ),
      ),
    );
  }

  Widget _fallback() {
    final colors = gradientFor(title);
    return LayoutBuilder(
      builder: (context, constraints) {
        final small = constraints.maxHeight < 90 || constraints.maxWidth < 110;
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: colors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          padding: EdgeInsets.all(small ? 6 : 14),
          child: small || !showTitle
              ? Center(
                  child: Icon(icon, color: Colors.white, size: small ? 22 : 30),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon, color: Colors.white, size: 20),
                    ),
                    const Spacer(),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }
}
