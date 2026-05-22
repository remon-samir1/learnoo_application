import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class LectureHeader extends StatelessWidget {
  final String lectureTitle;
  final String chapterTitle;
  final int currentViews;
  final int maxViews;
  final String duration;
  final bool isLocked;
  final bool isActivated;

  const LectureHeader({
    super.key,
    required this.lectureTitle,
    required this.chapterTitle,
    required this.currentViews,
    required this.maxViews,
    required this.duration,
    required this.isLocked,
    required this.isActivated,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F2FF),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                lectureTitle,
                style: const TextStyle(
                  color: Color(0xFF3451E5),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: currentViews >= maxViews
                    ? const Color(0xFFFFF0F0)
                    : const Color(0xFFE8F9F0),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'course.views_used'.tr(
                  args: [currentViews.toString(), maxViews.toString()],
                ),
                style: TextStyle(
                  color: currentViews >= maxViews
                      ? const Color(0xFFFF4B4B)
                      : const Color(0xFF2DBC77),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          chapterTitle,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1F2937),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            FaIcon(FontAwesomeIcons.clock, size: 14, color: Colors.grey[400]),
            const SizedBox(width: 6),
            Text(
              'course.duration_label'.tr(args: [duration]),
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            if (isLocked)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF0F0),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(
                  children: [
                    FaIcon(
                      FontAwesomeIcons.lock,
                      size: 12,
                      color: Color(0xFFFF4B4B),
                    ),
                    SizedBox(width: 4),
                    Text(
                      'Locked',
                      style: TextStyle(
                        color: Color(0xFFFF4B4B),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            if (isActivated)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F9F0),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(
                  children: [
                    FaIcon(
                      FontAwesomeIcons.check,
                      size: 12,
                      color: Color(0xFF2DBC77),
                    ),
                    SizedBox(width: 4),
                    Text(
                      'Activated',
                      style: TextStyle(
                        color: Color(0xFF2DBC77),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}
