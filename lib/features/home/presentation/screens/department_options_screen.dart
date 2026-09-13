import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_bottom_navigation_bar.dart';
import 'package:learnoo/features/category_tree/presentation/screens/category_tree_screen.dart';
import 'sub_departments_screen.dart';

class DepartmentOptionsScreen extends StatelessWidget {
  final String departmentId;
  final String departmentTitle;
  final String? departmentImage;
  final List<dynamic> allDepartments;
  final List<dynamic>? children;
  final int coursesCount;

  const DepartmentOptionsScreen({
    super.key,
    required this.departmentId,
    required this.departmentTitle,
    this.departmentImage,
    required this.allDepartments,
    this.children,
    required this.coursesCount,
  });

  void _navigateToCourses(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CategoryTreeScreen(
          initialSelectedId: departmentId,
        ),
      ),
    );
  }

  void _navigateToSubDepartments(BuildContext context) {
    // Get children if not provided
    List<dynamic>? childrenToPass = children;
    if (childrenToPass == null || childrenToPass.isEmpty) {
      childrenToPass = allDepartments.where((dept) {
        final parent = dept['attributes']?['parent'];
        if (parent == null) return false;
        final parentData = parent['data'];
        if (parentData == null) return false;
        return parentData['id']?.toString() == departmentId;
      }).toList();
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SubDepartmentsScreen(
          parentId: departmentId,
          parentTitle: departmentTitle,
          parentImage: departmentImage,
          allDepartments: allDepartments,
          children: childrenToPass,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
          // Background Gradients
          Positioned(
            top: -100,
            left: -50,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFFFFE4E1).withValues(alpha: 0.4),
                    const Color(0xFFFFE4E1).withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: -50,
            right: -100,
            child: Container(
              width: 400,
              height: 400,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFFE6E6FA).withValues(alpha: 0.4),
                    const Color(0xFFE6E6FA).withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),

              SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: Container(
                              height: 44,
                              width: 44,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.05),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: const Center(
                                child: FaIcon(
                                  FontAwesomeIcons.chevronLeft,
                                  color: Color(0xFF5A75FF),
                                  size: 18,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              departmentTitle,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textDark,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 40),

                    // Title
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        'home.select_option'.tr(),
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textDark,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        'home.select_option_subtitle'.tr(),
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.textDark.withValues(alpha: 0.6),
                        ),
                      ),
                    ),

                    const SizedBox(height: 40),

                    // Options
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          children: [
                            // View Courses Option
                            _buildOptionCard(
                              context,
                              icon: FontAwesomeIcons.bookOpen,
                              title: 'home.view_courses'.tr(),
                              subtitle: 'home.view_courses_subtitle'
                                  .tr(args: [coursesCount.toString()]),
                              color: const Color(0xFF5A75FF),
                              onTap: () => _navigateToCourses(context),
                            ),

                            const SizedBox(height: 20),

                            // View Sub-Departments Option
                            _buildOptionCard(
                              context,
                              icon: FontAwesomeIcons.folderTree,
                              title: 'home.view_sub_departments'.tr(),
                              subtitle: 'home.view_sub_departments_subtitle'.tr(),
                              color: const Color(0xFF10B981),
                              onTap: () => _navigateToSubDepartments(context),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          ),
          const AppBottomNavigationBar(),
        ],
      ),
    );
  }

  Widget _buildOptionCard(
    BuildContext context, {
    required FaIconData? icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: color.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: FaIcon(
                  icon,
                  color: color,
                  size: 28,
                ),
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textDark.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
            FaIcon(
              FontAwesomeIcons.chevronRight,
              color: color.withValues(alpha: 0.6),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
