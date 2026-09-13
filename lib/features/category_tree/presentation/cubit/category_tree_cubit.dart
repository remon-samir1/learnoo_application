import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/models/category_tree_model.dart';
import '../../data/repositories/category_tree_repository.dart';
import 'category_tree_state.dart';

class CategoryTreeCubit extends Cubit<CategoryTreeState> {
  final CategoryTreeRepository _repository;

  CategoryTreeCubit({CategoryTreeRepository? repository})
      : _repository = repository ?? CategoryTreeRepository(),
        super(const CategoryTreeState());

  /// Load initial tree data.
  /// [initialFacultyId]: optional override for user's facultyId
  /// [initialSelectedId]: optional initial selected category ID for deep linking
  Future<void> loadTree({
    String? initialFacultyId,
    String? initialSelectedId,
  }) async {
    emit(state.copyWith(
      status: CategoryTreeStatus.loading,
      clearErrorMessage: true,
    ));

    try {
      // 1. Determine facultyId
      String? facultyId = initialFacultyId ?? state.facultyId;
      if (facultyId == null || facultyId.isEmpty) {
        facultyId = await _repository.getFacultyId();
      }

      // 2. Fetch categories
      final rawCategories = await _repository.getCategories();

      // 3. Build Category Map for O(1) lookup
      final categoryMap = buildCategoryMap(rawCategories);
      final allCategories = categoryMap.values.toList();

      // 4. Determine Root Categories
      final rootCategories = determineRootCategories(
        facultyId: facultyId,
        categories: allCategories,
        categoryMap: categoryMap,
      );

      // 5. Resolve Current View
      final selectedId = initialSelectedId ?? state.selectedId;
      _resolveAndEmitView(
        selectedId: selectedId,
        allCategories: allCategories,
        categoryMap: categoryMap,
        rootCategories: rootCategories,
        facultyId: facultyId,
        historyStack: state.historyStack,
      );
    } catch (e) {
      debugPrint('[CategoryTreeCubit] Error loading tree: $e');
      emit(state.copyWith(
        status: CategoryTreeStatus.error,
        errorMessage: e.toString(),
      ));
    }
  }

  /// Create a map `Map<String, Category> categoryMap` indexed by `id` for O(1) lookup.
  /// Traverses all categories and nested childrens recursively so that sub-categories
  /// and their courses are completely indexed.
  static Map<String, Category> buildCategoryMap(List<Category> categories) {
    final map = <String, Category>{};
    void addRecursively(Category cat) {
      if (cat.id.isNotEmpty) {
        final existing = map[cat.id];
        if (existing == null) {
          map[cat.id] = cat;
        } else {
          map[cat.id] = existing.copyWith(
            courses: existing.courses.isNotEmpty ? existing.courses : cat.courses,
            childrens: existing.childrens.isNotEmpty ? existing.childrens : cat.childrens,
            parentId: existing.parentId ?? cat.parentId,
          );
        }
      }
      for (final child in cat.childrens) {
        addRecursively(child);
      }
    }

    for (final cat in categories) {
      addRecursively(cat);
    }
    return map;
  }

  /// Root Categories Determination:
  /// - If facultyId != null: Filter categories where item.parent_id.toString() == facultyId.toString().
  /// - If matches are found, use them as the Root Categories.
  /// - If no match or facultyId == null: Filter categories where item.parent_id == null OR !categoryMap.containsKey(item.parent_id.toString()).
  static List<Category> determineRootCategories({
    required String? facultyId,
    required List<Category> categories,
    required Map<String, Category> categoryMap,
  }) {
    if (facultyId != null && facultyId.isNotEmpty) {
      final matches = categories.where((item) {
        if (item.parentId == null) return false;
        return item.parentId.toString() == facultyId.toString();
      }).toList();

      if (matches.isNotEmpty) {
        return matches;
      }
    }

    // Fallback: categories with no parent or whose parent is not in the categories map
    return categories.where((item) {
      if (item.parentId == null || item.parentId!.isEmpty) return true;
      return !categoryMap.containsKey(item.parentId.toString());
    }).toList();
  }

  /// Current View Resolution:
  /// - If selectedId == null: display Root Categories.
  /// - If selectedId != null:
  ///   - Fetch selectedCategory = categoryMap[selectedId].
  ///   - Sub-categories detection:
  ///     - If selectedCategory.childrens is not empty: map each child ID through categoryMap[child.id] ?? child.
  ///     - Otherwise: filter global list for categories where item.parent_id.toString() == selectedCategory.id.toString().
  ///   - Courses detection:
  ///     - selectedCategory.courses filtered by active courses (status == 1 || status == "active" || status == true || status == null).
  void _resolveAndEmitView({
    required String? selectedId,
    required List<Category> allCategories,
    required Map<String, Category> categoryMap,
    required List<Category> rootCategories,
    required String? facultyId,
    required List<String?> historyStack,
  }) {
    if (selectedId == null) {
      emit(state.copyWith(
        status: CategoryTreeStatus.loaded,
        allCategories: allCategories,
        categoryMap: categoryMap,
        rootCategories: rootCategories,
        facultyId: facultyId,
        selectedId: null,
        clearSelectedId: true,
        historyStack: historyStack,
        currentCategories: rootCategories,
        currentCourses: const [],
        selectedCategory: null,
        clearSelectedCategory: true,
        breadcrumbPath: const [],
        clearErrorMessage: true,
      ));
      return;
    }

    final selectedCategory = categoryMap[selectedId];

    if (selectedCategory == null) {
      // Category not found; render empty
      emit(state.copyWith(
        status: CategoryTreeStatus.loaded,
        allCategories: allCategories,
        categoryMap: categoryMap,
        rootCategories: rootCategories,
        facultyId: facultyId,
        selectedId: selectedId,
        historyStack: historyStack,
        currentCategories: const [],
        currentCourses: const [],
        selectedCategory: null,
        clearSelectedCategory: true,
        breadcrumbPath: const [],
      ));
      return;
    }

    // 1. Sub-categories detection
    List<Category> subCategories = [];
    if (selectedCategory.childrens.isNotEmpty) {
      subCategories = selectedCategory.childrens.map((child) {
        return categoryMap[child.id] ?? child;
      }).toList();
    } else {
      subCategories = allCategories.where((item) {
        if (item.parentId == null) return false;
        return item.parentId.toString() == selectedCategory.id.toString();
      }).toList();
    }

    // 2. Courses detection: filter active courses only
    final List<CourseItem> activeCourses = selectedCategory.courses
        .where((course) => course.isActive)
        .toList();

    // 3. Compute breadcrumb trail from root to current selected category
    final breadcrumbs = _computeBreadcrumbTrail(selectedCategory, categoryMap);

    emit(state.copyWith(
      status: CategoryTreeStatus.loaded,
      allCategories: allCategories,
      categoryMap: categoryMap,
      rootCategories: rootCategories,
      facultyId: facultyId,
      selectedId: selectedId,
      historyStack: historyStack,
      currentCategories: subCategories,
      currentCourses: activeCourses,
      selectedCategory: selectedCategory,
      breadcrumbPath: breadcrumbs,
      clearErrorMessage: true,
    ));
  }

  /// Traces path backwards from current category to build breadcrumbs
  static List<Category> _computeBreadcrumbTrail(
    Category current,
    Map<String, Category> map,
  ) {
    final trail = <Category>[];
    final visited = <String>{};
    Category? pointer = current;

    while (pointer != null && visited.add(pointer.id)) {
      trail.insert(0, pointer);
      if (pointer.parentId != null && map.containsKey(pointer.parentId)) {
        pointer = map[pointer.parentId];
      } else {
        break;
      }
    }
    return trail;
  }

  /// User clicked a category card:
  /// Push current selectedId to navigationHistory and set selectedId = category.id.
  void selectCategory(String categoryId) {
    final newHistory = List<String?>.from(state.historyStack)
      ..add(state.selectedId);

    _resolveAndEmitView(
      selectedId: categoryId,
      allCategories: state.allCategories,
      categoryMap: state.categoryMap,
      rootCategories: state.rootCategories,
      facultyId: state.facultyId,
      historyStack: newHistory,
    );
  }

  /// Step back in navigation history:
  /// Pops the last ID from history and sets selectedId = previousId.
  /// Returns `true` if handled within the tree, or `false` if at the root.
  bool popHistory() {
    if (state.historyStack.isNotEmpty) {
      final newHistory = List<String?>.from(state.historyStack);
      final previousId = newHistory.removeLast();

      _resolveAndEmitView(
        selectedId: previousId,
        allCategories: state.allCategories,
        categoryMap: state.categoryMap,
        rootCategories: state.rootCategories,
        facultyId: state.facultyId,
        historyStack: newHistory,
      );
      return true;
    } else if (state.selectedId != null) {
      // Return to root if history stack was empty but an item was selected
      _resolveAndEmitView(
        selectedId: null,
        allCategories: state.allCategories,
        categoryMap: state.categoryMap,
        rootCategories: state.rootCategories,
        facultyId: state.facultyId,
        historyStack: const [],
      );
      return true;
    }

    return false; // Already at root; allow Flutter route pop
  }

  /// Navigate directly to a specific breadcrumb level.
  void navigateToBreadcrumb(String? categoryId) {
    if (categoryId == state.selectedId) return;

    if (categoryId == null) {
      // Go to root
      _resolveAndEmitView(
        selectedId: null,
        allCategories: state.allCategories,
        categoryMap: state.categoryMap,
        rootCategories: state.rootCategories,
        facultyId: state.facultyId,
        historyStack: const [],
      );
      return;
    }

    // Truncate history up to this ID if present in history
    final newHistory = <String?>[];
    for (final id in state.historyStack) {
      if (id == categoryId) break;
      newHistory.add(id);
    }

    _resolveAndEmitView(
      selectedId: categoryId,
      allCategories: state.allCategories,
      categoryMap: state.categoryMap,
      rootCategories: state.rootCategories,
      facultyId: state.facultyId,
      historyStack: newHistory,
    );
  }

  /// Activate a locked course using code:
  /// `POST /v1/student/courses/activate` with `code` & `course_id`.
  Future<bool> activateCourse({
    required String courseId,
    required String code,
  }) async {
    emit(state.copyWith(
      isActivating: true,
      clearActivationMessage: true,
      isActivationSuccess: null,
    ));

    final result = await _repository.activateCourse(
      courseId: courseId,
      code: code,
    );

    final isSuccess = result['success'] == true;
    final message = result['message']?.toString() ??
        (isSuccess ? 'Course activated successfully!' : 'Activation failed');

    if (isSuccess) {
      // Update the activated course in state
      _updateCourseLockStatus(courseId, isLocked: false);

      emit(state.copyWith(
        isActivating: false,
        isActivationSuccess: true,
        activationMessage: message,
      ));
      return true;
    } else {
      emit(state.copyWith(
        isActivating: false,
        isActivationSuccess: false,
        activationMessage: message,
      ));
      return false;
    }
  }

  /// Updates the `isLocked` flag of a course across category structures in memory.
  void _updateCourseLockStatus(String courseId, {required bool isLocked}) {
    // 1. Update in currentCourses
    final updatedCurrentCourses = state.currentCourses.map((c) {
      if (c.id == courseId) {
        return c.copyWith(isLocked: isLocked);
      }
      return c;
    }).toList();

    // 2. Update in selectedCategory
    Category? updatedSelectedCategory = state.selectedCategory;
    if (updatedSelectedCategory != null) {
      final updatedCourses = updatedSelectedCategory.courses.map((c) {
        if (c.id == courseId) {
          return c.copyWith(isLocked: isLocked);
        }
        return c;
      }).toList();
      updatedSelectedCategory = updatedSelectedCategory.copyWith(
        courses: updatedCourses,
      );
    }

    // 3. Update in allCategories & categoryMap
    final updatedCategoryMap = Map<String, Category>.from(state.categoryMap);
    final updatedAllCategories = state.allCategories.map((category) {
      final updatedCourses = category.courses.map((c) {
        if (c.id == courseId) {
          return c.copyWith(isLocked: isLocked);
        }
        return c;
      }).toList();
      final updatedCategory = category.copyWith(courses: updatedCourses);
      updatedCategoryMap[category.id] = updatedCategory;
      return updatedCategory;
    }).toList();

    emit(state.copyWith(
      currentCourses: updatedCurrentCourses,
      selectedCategory: updatedSelectedCategory,
      categoryMap: updatedCategoryMap,
      allCategories: updatedAllCategories,
    ));
  }

  /// Refresh current data while preserving position
  Future<void> refresh() async {
    try {
      final categories = await _repository.getCategories();
      final categoryMap = buildCategoryMap(categories);
      final rootCategories = determineRootCategories(
        facultyId: state.facultyId,
        categories: categories,
        categoryMap: categoryMap,
      );

      _resolveAndEmitView(
        selectedId: state.selectedId,
        allCategories: categories,
        categoryMap: categoryMap,
        rootCategories: rootCategories,
        facultyId: state.facultyId,
        historyStack: state.historyStack,
      );
    } catch (e) {
      debugPrint('[CategoryTreeCubit] Error refreshing: $e');
    }
  }
}
