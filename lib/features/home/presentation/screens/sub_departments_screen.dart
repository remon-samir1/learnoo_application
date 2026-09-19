import 'package:flutter/material.dart';
import '../../../../core/widgets/cover_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:learnoo/features/category_tree/presentation/screens/category_tree_screen.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_bottom_navigation_bar.dart';
import 'department_options_screen.dart';

class SubDepartmentsScreen extends StatelessWidget {
  final String parentId;
  final String parentTitle;
  final String? parentImage;
  final List<dynamic> allDepartments;
  final List<dynamic>? children;

  const SubDepartmentsScreen({
    super.key,
    required this.parentId,
    required this.parentTitle,
    this.parentImage,
    required this.allDepartments,
    this.children,
  });

  List<dynamic> get subDepartments {
    // Use provided children if available
    if (children != null && children!.isNotEmpty) {
      return children!;
    }
    // Fallback: filter from all departments
    return allDepartments.where((dept) {
      final parent = dept['attributes']?['parent'];
      if (parent == null) return false;
      final parentData = parent['data'];
      if (parentData == null) return false;
      return parentData['id']?.toString() == parentId;
    }).toList();
  }

  void _navigateToDetail(BuildContext context, dynamic department) {
    final deptId = department['id']?.toString() ?? '';

    // Find the FULL department data from allDepartments (has complete childrens info)
    final fullDepartment = allDepartments.firstWhere(
      (dept) => dept['id']?.toString() == deptId,
      orElse: () => department,
    );

    final fullAttributes = fullDepartment['attributes'] ?? {};
    final name = fullAttributes['name']?.toString() ?? '';
    final image = fullAttributes['image']?.toString() ?? '';

    // Check if this department has children from the FULL department's childrens array
    final childrenList = fullAttributes['childrens'] as List<dynamic>?;
    bool hasChildren = childrenList != null && childrenList.isNotEmpty;

    // If no childrens array, check from allDepartments
    List<dynamic>? childrenToPass;
    if (hasChildren) {
      childrenToPass = childrenList;
    } else {
      // Find children from allDepartments
      childrenToPass = allDepartments.where((dept) {
        final parent = dept['attributes']?['parent'];
        if (parent == null) return false;
        final parentData = parent['data'];
        if (parentData == null) return false;
        return parentData['id']?.toString() == deptId;
      }).toList();
      hasChildren = childrenToPass.isNotEmpty;
    }

    // Check if this department has courses
    final stats = fullAttributes['stats'] as Map<String, dynamic>?;
    final coursesCount = stats?['courses'] as int? ?? 0;
    final hasCourses = coursesCount > 0;

    if (hasChildren && hasCourses) {
      // Department has both courses and children - show options screen
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => DepartmentOptionsScreen(
            departmentId: deptId,
            departmentTitle: name,
            departmentImage: image,
            allDepartments: allDepartments,
            children: childrenToPass,
            coursesCount: coursesCount,
          ),
        ),
      );
    } else if (hasChildren) {
      // Navigate to another sub-departments screen
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => SubDepartmentsScreen(
            parentId: deptId,
            parentTitle: name,
            parentImage: image,
            allDepartments: allDepartments,
            children: childrenToPass,
          ),
        ),
      );
    } else {
      // Navigate to CategoryTreeScreen to show courses matching web
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CategoryTreeScreen(
            initialSelectedId: deptId,
          ),
        ),
      );
    }
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
                              parentTitle,
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

                    // Sub-departments Grid
                    Expanded(
                      child: subDepartments.isEmpty
                          ? _buildEmptyState()
                          : _buildSubDepartmentsGrid(),
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

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const FaIcon(
            FontAwesomeIcons.folder,
            color: Color(0xFFD1D1D1),
            size: 64,
          ),
          const SizedBox(height: 16),
          Text(
            'home.no_sub_departments'.tr(),
            style: const TextStyle(
              color: Color(0xFF9CA3AF),
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubDepartmentsGrid() {
    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 0.72,
      ),
      itemCount: subDepartments.length,
      itemBuilder: (context, index) {
        final department = subDepartments[index];
        final attributes = department['attributes'] ?? {};
        final name = attributes['name']?.toString() ?? '';
        final image = attributes['image']?.toString() ?? '';
        final stats = attributes['stats'] ?? {};
        final coursesCount = stats['courses'] ?? 0;

        // Get color based on index
        final colorIndex = index % AppColors.subjectColors.length;
        final colors = AppColors.subjectColors[colorIndex];

        return _buildDepartmentCard(
          context,
          department,
          name,
          image,
          coursesCount,
          colors['bg']!,
          colors['text']!,
        );
      },
    );
  }

  Widget _buildDepartmentCard(
    BuildContext context,
    dynamic department,
    String title,
    String imageUrl,
    int coursesCount,
    Color bgColor,
    Color iconColor,
  ) {

    // Check if this department has children
    final deptId = department['id']?.toString() ?? '';

    // Find the FULL department data from allDepartments
    final fullDepartment = allDepartments.firstWhere(
      (dept) => dept['id']?.toString() == deptId,
      orElse: () => department,
    );

    final fullAttributes = fullDepartment['attributes'] as Map<String, dynamic>?;
    final childrenList = fullAttributes?['childrens'] as List<dynamic>?;

    // First check childrens array from full department, then check allDepartments
    bool hasChildren = childrenList != null && childrenList.isNotEmpty;
    if (!hasChildren) {
      hasChildren = allDepartments.any((dept) {
        final parent = dept['attributes']?['parent'];
        if (parent == null) return false;
        final parentData = parent['data'];
        if (parentData == null) return false;
        return parentData['id']?.toString() == deptId;
      });
    }

    return GestureDetector(
      onTap: () => _navigateToDetail(context, department),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image — prominent cover, like the web's card
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              child: CoverImage(
                url: imageUrl,
                title: title,
                height: 120,
                icon: Icons.menu_book_rounded,
                cacheWidth: 240,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: iconColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (hasChildren) ...[
                        Icon(
                          Icons.folder_open_outlined,
                          color: iconColor.withValues(alpha: 0.6),
                          size: 13,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'home.sub_departments'.tr(),
                          style: TextStyle(
                            color: iconColor.withValues(alpha: 0.6),
                            fontSize: 11,
                          ),
                        ),
                      ] else ...[
                        Icon(
                          Icons.menu_book_outlined,
                          color: iconColor.withValues(alpha: 0.6),
                          size: 13,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$coursesCount ${"home.courses".tr()}',
                          style: TextStyle(
                            color: iconColor.withValues(alpha: 0.6),
                            fontSize: 11,
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
      ),
    );
  }

}
