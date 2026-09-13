import 'package:flutter/material.dart';
import '../cubit/category_tree_cubit.dart';
import '../cubit/category_tree_state.dart';

class CategoryTreeHeader extends StatelessWidget {
  final CategoryTreeState state;
  final CategoryTreeCubit cubit;
  final VoidCallback onBack;

  const CategoryTreeHeader({
    super.key,
    required this.state,
    required this.cubit,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final canGoBack = state.canGoBack;
    final title = state.selectedCategory != null
        ? state.selectedCategory!.name
        : 'Educational Programs';

    final subtitle = state.showCategories
        ? '${state.currentCategories.length} categories available'
        : (state.showCourses
            ? '${state.currentCourses.length} courses available'
            : 'Explore courses & departments');

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF2137D6),
            Color(0xFF4A68F6),
            Color(0xFF7A92F8),
          ],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x332137D6),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Bar: Back button + Title / Level indicator
              Row(
                children: [
                  if (canGoBack) ...[
                    InkWell(
                      onTap: onBack,
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.25),
                            width: 1,
                          ),
                        ),
                        child: const Icon(
                          Icons.arrow_back_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: -0.3,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white.withValues(alpha: 0.85),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Level / Mode badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          state.showCourses
                              ? Icons.play_lesson_rounded
                              : Icons.account_tree_rounded,
                          color: Colors.white,
                          size: 14,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          state.showCourses ? 'Courses' : 'Levels',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // Breadcrumbs Trail (if deeper than root)
              if (state.breadcrumbPath.isNotEmpty) ...[
                const SizedBox(height: 16),
                _buildBreadcrumbs(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBreadcrumbs() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // Home / Root item
            InkWell(
              onTap: () => cubit.navigateToBreadcrumb(null),
              child: const Row(
                children: [
                  Icon(Icons.home_rounded, color: Colors.white, size: 15),
                  SizedBox(width: 4),
                  Text(
                    'Root',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            ...state.breadcrumbPath.asMap().entries.map((entry) {
              final isLast = entry.key == state.breadcrumbPath.length - 1;
              final category = entry.value;

              return Row(
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(
                      Icons.chevron_right_rounded,
                      color: Colors.white60,
                      size: 16,
                    ),
                  ),
                  InkWell(
                    onTap: isLast
                        ? null
                        : () => cubit.navigateToBreadcrumb(category.id),
                    child: Text(
                      category.name,
                      style: TextStyle(
                        color: isLast ? Colors.white : Colors.white70,
                        fontSize: 12,
                        fontWeight: isLast ? FontWeight.bold : FontWeight.w500,
                        decoration: isLast ? null : TextDecoration.underline,
                        decorationColor: Colors.white54,
                      ),
                    ),
                  ),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }
}
