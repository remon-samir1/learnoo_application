import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../../../core/theme/app_colors.dart';
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

  // Curated gradient pairs for categories without images
  static const List<List<Color>> _gradientPairs = [
    [Color(0xFF3451E5), Color(0xFF637EFF)],
    [Color(0xFF0D9488), Color(0xFF2DD4BF)],
    [Color(0xFF7C3AED), Color(0xFFA78BFA)],
    [Color(0xFFE11D48), Color(0xFFFB7185)],
    [Color(0xFFD97706), Color(0xFFFBBF24)],
    [Color(0xFF2563EB), Color(0xFF60A5FA)],
  ];

  List<Color> get _cardGradients {
    final pairIndex = (category.id.hashCode.abs() + index) % _gradientPairs.length;
    return _gradientPairs[pairIndex];
  }

  @override
  Widget build(BuildContext context) {
    final hasImage = category.image != null && category.image!.trim().isNotEmpty;
    final gradients = _cardGradients;

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
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Top row: Thumbnail image/icon + Chevron indicator
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: gradients,
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: gradients[0].withValues(alpha: 0.25),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: hasImage
                          ? CachedNetworkImage(
                              imageUrl: category.image!,
                              fit: BoxFit.cover,
                              placeholder: (context, url) => Center(
                                child: Text(
                                  _getInitials(category.name),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                  ),
                                ),
                              ),
                              errorWidget: (context, url, error) => Center(
                                child: Text(
                                  _getInitials(category.name),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                  ),
                                ),
                              ),
                            )
                          : Center(
                              child: Text(
                                _getInitials(category.name),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                            ),
                    ),
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF4F6FB),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 13,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                // Middle: Category Name
                Text(
                  category.name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1F2937),
                    height: 1.25,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),

                const SizedBox(height: 12),

                // Bottom row: Courses count & Students count badges
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

  String _getInitials(String name) {
    final words = name.trim().split(RegExp(r'\s+'));
    if (words.isEmpty || words[0].isEmpty) return '?';
    if (words.length == 1) {
      return words[0].substring(0, 1).toUpperCase();
    }
    return '${words[0][0]}${words[1][0]}'.toUpperCase();
  }
}
