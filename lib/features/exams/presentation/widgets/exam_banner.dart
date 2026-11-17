import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Width ÷ height of the exam banner: staff are asked for 1600 × 400 px, the
/// same 4:1 strip as a Google Forms header.
const double kExamBannerAspectRatio = 4;

/// The banner never takes more than this share of the screen height, so a
/// phone held sideways still has room for the question under it.
const double kExamBannerMaxScreenFraction = 0.2;

/// Height of the banner box for [width] on a screen [screenHeight] tall.
double examBannerHeight(double width, double screenHeight) {
  return math.min(
    width / kExamBannerAspectRatio,
    screenHeight * kExamBannerMaxScreenFraction,
  );
}

/// The exam's banner image, shown at the top of the exam. The whole image is
/// always visible (no cropping); if it fails to load the banner disappears and
/// the exam looks exactly as it does without one.
class ExamBanner extends StatelessWidget {
  final String url;

  const ExamBanner({super.key, required this.url});

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.sizeOf(context).height;

    return LayoutBuilder(
      builder: (context, constraints) {
        final height = examBannerHeight(constraints.maxWidth, screenHeight);
        // When the height cap applies (landscape) the strip keeps its 4:1
        // shape and sits in the middle instead of stretching with empty sides.
        Widget frame(Widget child) => Center(
          child: SizedBox(
            key: const ValueKey('exam-banner'),
            width: height * kExamBannerAspectRatio,
            height: height,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(15),
                child: child,
              ),
            ),
          ),
        );

        return CachedNetworkImage(
          imageUrl: url,
          imageBuilder: (context, image) => frame(
            Image(image: image, fit: BoxFit.contain, gaplessPlayback: true),
          ),
          placeholder: (context, _) => frame(const SizedBox.expand()),
          errorWidget: (context, _, _) => const SizedBox.shrink(),
        );
      },
    );
  }
}
