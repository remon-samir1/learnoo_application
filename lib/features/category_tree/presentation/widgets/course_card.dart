import 'package:flutter/material.dart';

import '../../../../core/utils/media_url.dart';
import '../../../../core/widgets/cover_image.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../data/models/category_tree_model.dart';

class CourseCard extends StatelessWidget {
  final CourseItem course;
  final String? categoryName;
  final VoidCallback onTap;
  final VoidCallback onActivate;

  const CourseCard({
    super.key,
    required this.course,
    this.categoryName,
    required this.onTap,
    required this.onActivate,
  });

  @override
  Widget build(BuildContext context) {
    final isLocked = course.isLocked;
    final hasThumbnail = resolveMediaUrl(course.thumbnail) != null;
    final displayCategory = categoryName ?? course.subTitle ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
        border: Border.all(
          color: const Color(0xFFF1F3F9),
          width: 1.2,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Banner: Gradient or Thumbnail with Header Badges + Center Lock/Play icon
          Stack(
            children: [
              Container(
                height: 155,
                width: double.infinity,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color(0xFF5A45FF),
                      Color(0xFF7E64FF),
                      Color(0xFF9373FF),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: CoverImage(
                  url: course.thumbnail,
                  title: course.title,
                  height: 155,
                  showTitle: false,
                  darken: hasThumbnail ? 0.25 : 0,
                  cacheWidth: 220,
                ),
              ),

              // Decorative subtle circle pattern in background
              Positioned(
                right: -20,
                top: -20,
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                ),
              ),

              // Top-left: Graduation Cap icon badge
              Positioned(
                top: 14,
                left: 14,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: FaIcon(
                      FontAwesomeIcons.graduationCap,
                      color: Colors.white,
                      size: 15,
                    ),
                  ),
                ),
              ),

              // Top-right: Category name badge (e.g. "فرقة تجربة")
              if (displayCategory.isNotEmpty)
                Positioned(
                  top: 14,
                  right: 14,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      displayCategory,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),

              // Center: Lock icon inside white rounded rectangle (or Play badge)
              Positioned.fill(
                child: Center(
                  child: GestureDetector(
                    onTap: isLocked ? onActivate : onTap,
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.95),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Center(
                        child: FaIcon(
                          isLocked ? FontAwesomeIcons.lock : FontAwesomeIcons.play,
                          color: const Color(0xFF4A68F6),
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // Bottom-left inside banner: Course title overlay
              Positioned(
                bottom: 12,
                left: 16,
                right: 16,
                child: Text(
                  course.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    shadows: [
                      Shadow(
                        color: Colors.black38,
                        blurRadius: 4,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),

          // Bottom Content
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Course Title
                Text(
                  course.title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF111827),
                    height: 1.3,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),

                const SizedBox(height: 10),

                // Stats row: Notes & Lectures count
                Row(
                  children: [
                    _buildStatItem(
                      FontAwesomeIcons.bookOpen,
                      '${course.stats.notesCount} Notes',
                    ),
                    const SizedBox(width: 18),
                    _buildStatItem(
                      FontAwesomeIcons.video,
                      '${course.stats.lecturesCount} Lectures',
                    ),
                    if (course.stats.studentsCount > 0) ...[
                      const SizedBox(width: 18),
                      _buildStatItem(
                        FontAwesomeIcons.users,
                        '${course.stats.studentsCount} Students',
                      ),
                    ],
                  ],
                ),

                const SizedBox(height: 18),

                // Action Buttons: Course Details (Main) + Activation Button (if locked)
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: onTap,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: const Text(
                          'Course Details',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),

                    if (isLocked) ...[
                      const SizedBox(width: 10),
                      InkWell(
                        onTap: onActivate,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 13,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEEF2FF),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: const Color(0xFFC7D2FE),
                            ),
                          ),
                          child: const Row(
                            children: [
                              FaIcon(
                                FontAwesomeIcons.key,
                                size: 14,
                                color: Color(0xFF2563EB),
                              ),
                              SizedBox(width: 6),
                              Text(
                                'Unlock',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF2563EB),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(dynamic icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FaIcon(
          icon as dynamic,
          size: 13,
          color: const Color(0xFF6B7280),
        ),
        const SizedBox(width: 6),
        Text(
          text,
          style: const TextStyle(
            fontSize: 13,
            color: Color(0xFF4B5563),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
