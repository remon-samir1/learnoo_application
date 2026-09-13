import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shimmer/shimmer.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../course_content/presentation/screens/course_detail_screen.dart';
import '../../data/models/category_tree_model.dart';
import '../cubit/category_tree_cubit.dart';
import '../cubit/category_tree_state.dart';
import '../widgets/category_card.dart';
import '../widgets/category_tree_header.dart';
import '../widgets/course_activation_dialog.dart';
import '../widgets/course_card.dart';

class CategoryTreeScreen extends StatefulWidget {
  final String? initialFacultyId;
  final String? initialSelectedId;

  const CategoryTreeScreen({
    super.key,
    this.initialFacultyId,
    this.initialSelectedId,
  });

  @override
  State<CategoryTreeScreen> createState() => _CategoryTreeScreenState();
}

class _CategoryTreeScreenState extends State<CategoryTreeScreen> {
  late final CategoryTreeCubit _cubit;

  @override
  void initState() {
    super.initState();
    _cubit = CategoryTreeCubit();
    _cubit.loadTree(
      initialFacultyId: widget.initialFacultyId,
      initialSelectedId: widget.initialSelectedId,
    );
  }

  @override
  void dispose() {
    _cubit.close();
    super.dispose();
  }

  void _handleBack(BuildContext context, CategoryTreeState state) {
    if (state.canGoBack) {
      _cubit.popHistory();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  void _navigateToCourse(BuildContext context, CourseItem course) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CourseDetailScreen(
          courseId: course.id,
          title: course.title,
          thumbnail: course.thumbnail ?? '',
          price: course.price ?? '0',
          description: course.description ?? '',
        ),
      ),
    );
  }

  void _openActivationDialog(BuildContext context, CourseItem course) {
    CourseActivationDialog.show(
      context: context,
      courseId: course.id,
      courseTitle: course.title,
      cubit: _cubit,
      onSuccess: () {
        // Optional refresh after activation
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _cubit,
      child: BlocBuilder<CategoryTreeCubit, CategoryTreeState>(
        builder: (context, state) {
          return PopScope(
            canPop: !state.canGoBack,
            onPopInvokedWithResult: (didPop, result) {
              if (didPop) return;
              _handleBack(context, state);
            },
            child: Scaffold(
              backgroundColor: const Color(0xFFFAFBFF),
              body: Column(
                children: [
                  CategoryTreeHeader(
                    state: state,
                    cubit: _cubit,
                    onBack: () => _handleBack(context, state),
                  ),
                  Expanded(
                    child: _buildBody(context, state),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBody(BuildContext context, CategoryTreeState state) {
    if (state.status == CategoryTreeStatus.loading) {
      return _buildSkeletonLoading(context);
    }

    if (state.status == CategoryTreeStatus.error) {
      return _buildErrorState(context, state.errorMessage);
    }

    return RefreshIndicator(
      onRefresh: () => _cubit.refresh(),
      color: AppColors.primaryBlue,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isTablet = constraints.maxWidth >= 600;
          final isWide = constraints.maxWidth >= 900;

          // 1. Rendering Priority: Category Grid
          if (state.showCategories) {
            final crossAxisCount = isWide ? 4 : (isTablet ? 3 : 2);
            return GridView.builder(
              padding: const EdgeInsets.all(20),
              physics: const AlwaysScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
                childAspectRatio: isTablet ? 0.95 : 0.88,
              ),
              itemCount: state.currentCategories.length,
              itemBuilder: (context, index) {
                final category = state.currentCategories[index];
                return CategoryCard(
                  category: category,
                  index: index,
                  onTap: () => _cubit.selectCategory(category.id),
                );
              },
            );
          }

          // 2. Rendering Priority: Courses Grid/List
          if (state.showCourses) {
            if (isTablet) {
              // 2 columns on tablet
              return GridView.builder(
                padding: const EdgeInsets.all(20),
                physics: const AlwaysScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  mainAxisExtent: 310,
                ),
                itemCount: state.currentCourses.length,
                itemBuilder: (context, index) {
                  final course = state.currentCourses[index];
                  return CourseCard(
                    course: course,
                    categoryName: state.selectedCategory?.name,
                    onTap: () => _navigateToCourse(context, course),
                    onActivate: () => _openActivationDialog(context, course),
                  );
                },
              );
            } else {
              // Single column list on mobile
              return ListView.builder(
                padding: const EdgeInsets.all(20),
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: state.currentCourses.length,
                itemBuilder: (context, index) {
                  final course = state.currentCourses[index];
                  return CourseCard(
                    course: course,
                    categoryName: state.selectedCategory?.name,
                    onTap: () => _navigateToCourse(context, course),
                    onActivate: () => _openActivationDialog(context, course),
                  );
                },
              );
            }
          }

          // 3. Rendering Priority: Empty State
          return _buildEmptyState(context);
        },
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.15),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.folder_off_outlined,
                      size: 42,
                      color: Color(0xFF9CA3AF),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'No subjects or courses found',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1F2937),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'There are currently no items available in this category level.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Color(0xFF6B7280),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                if (_cubit.state.canGoBack)
                  OutlinedButton.icon(
                    onPressed: () => _cubit.popHistory(),
                    icon: const Icon(Icons.arrow_back_rounded, size: 16),
                    label: const Text('Go Back'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primaryBlue,
                      side: const BorderSide(color: AppColors.primaryBlue),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorState(BuildContext context, String? message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: const BoxDecoration(
                color: Color(0xFFFEE2E2),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: Icon(
                  Icons.wifi_off_rounded,
                  size: 38,
                  color: Color(0xFFEF4444),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Failed to load categories',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1F2937),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message ?? 'Please check your internet connection and try again.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF6B7280),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _cubit.loadTree(
                initialFacultyId: widget.initialFacultyId,
                initialSelectedId: widget.initialSelectedId,
              ),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Try Again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSkeletonLoading(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.grey[200]!,
      highlightColor: Colors.grey[100]!,
      child: GridView.builder(
        padding: const EdgeInsets.all(20),
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 14,
          mainAxisSpacing: 14,
          childAspectRatio: 0.88,
        ),
        itemCount: 6,
        itemBuilder: (context, index) {
          return Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  height: 16,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  width: 80,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Container(
                      width: 60,
                      height: 18,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
