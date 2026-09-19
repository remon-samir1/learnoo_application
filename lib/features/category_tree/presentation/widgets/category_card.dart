import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/cover_image.dart';
import '../../data/models/category_tree_model.dart';

class CategoryCard extends StatelessWidget {
  final Category category;
  final VoidCallback onTap;
  final int index;

  const CategoryCard({
    super.key,
    required this.category,
    required this.onTap,
    this.index = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: const Color(0xFFF1F3F9),
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          splashColor: AppColors.primaryBlue.withValues(alpha: 0.08),
          highlightColor: AppColors.primaryBlue.withValues(alpha: 0.04),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: CoverImage(
                  url: category.image,
                  title: category.name,
                  icon: Icons.menu_book_rounded,
                  showTitle: false,
                  cacheWidth: 200,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            category.name,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1F2937),
                              height: 1.25,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                          color: Color(0xFF9CA3AF),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (category.stats.coursesCount > 0)
                          _buildStatChip(
                            icon: FontAwesomeIcons.bookOpen,
                            label: '${category.stats.coursesCount} Courses',
                            color: AppColors.primaryBlue,
                            bgColor: const Color(0xFFEEF2FF),
                          )
                        else if (category.childrens.isNotEmpty)
                          _buildStatChip(
                            icon: FontAwesomeIcons.folderTree,
                            label: '${category.childrens.length} Sub-levels',
                            color: const Color(0xFF7C3AED),
                            bgColor: const Color(0xFFF5F3FF),
                          ),
                        if (category.stats.studentsCount > 0)
                          _buildStatChip(
                            icon: FontAwesomeIcons.userGraduate,
                            label: '${category.stats.studentsCount}',
                            color: const Color(0xFF059669),
                            bgColor: const Color(0xFFECFDF5),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatChip({
    required dynamic icon,
    required String label,
    required Color color,
    required Color bgColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FaIcon(
            icon as dynamic,
            size: 10,
            color: color,
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

}
