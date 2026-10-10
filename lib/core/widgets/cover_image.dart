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
    this.fallback = CoverFallback.gradient,
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

  /// What to draw when there is no image or it fails to load.
  final CoverFallback fallback;

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
    if (fallback == CoverFallback.logo) {
      // The website's `thumbnail || "/logo.svg"` in an `object-cover` box on
      // `bg-slate-100`.
      return const ColoredBox(
        color: Color(0xFFF1F5F9),
        child: CustomPaint(
          painter: _LearnooLogoPainter(),
          size: Size.infinite,
        ),
      );
    }
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

enum CoverFallback {
  /// Gradient from the title, like the website's category / subject cards.
  gradient,

  /// The Learnoo mark, like the website's course cards and course hero.
  logo,
}

/// Paints the mark from the website's `public/logo.svg` (viewBox 80×77),
/// scaled like `object-cover` so it fills the box the same way.
class _LearnooLogoPainter extends CustomPainter {
  const _LearnooLogoPainter();

  static final Path _mark = Path()
    ..moveTo(26.4179, 30.7214)
    ..lineTo(14.5596, 40.596)
    ..cubicTo(26.178, 45.3543, 32.3101, 49.6582, 36.4964, 59.4254)
    ..cubicTo(39.1871, 53.3477, 42.4686, 49.2848, 48.5983, 43.8895)
    ..cubicTo(54.5776, 38.6277, 60.5557, 35.4428, 65.4404, 35.1112)
    ..lineTo(49.9818, 16.5752)
    ..cubicTo(45.3096, 18.1808, 40.6016, 21.9753, 39.193, 31.7783)
    ..cubicTo(38.675, 35.3843, 38.2763, 40.0389, 37.7176, 42.9089)
    ..lineTo(37.6961, 43.0938)
    ..cubicTo(37.424, 45.1539, 36.5836, 46.5233, 36.5478, 46.5818)
    ..lineTo(36.1157, 46.3122)
    ..cubicTo(36.1228, 46.2991, 36.9405, 44.9643, 37.1936, 43.0056)
    ..cubicTo(37.2497, 42.5797, 37.2747, 42.1562, 37.2712, 41.7411)
    ..cubicTo(36.2458, 36.1895, 32.0881, 30.7047, 26.4203, 30.7214)
    ..close();

  static const double _viewWidth = 80;
  static const double _viewHeight = 77;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final scale = size.width / _viewWidth > size.height / _viewHeight
        ? size.width / _viewWidth
        : size.height / _viewHeight;
    canvas
      ..save()
      ..translate(
        (size.width - _viewWidth * scale) / 2,
        (size.height - _viewHeight * scale) / 2,
      )
      ..scale(scale);
    canvas.drawPath(_mark, Paint()..color = const Color(0xFF2137D6));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
