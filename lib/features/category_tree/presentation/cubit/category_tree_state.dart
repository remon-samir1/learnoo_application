import 'package:equatable/equatable.dart';
import '../../data/models/category_tree_model.dart';

enum CategoryTreeStatus { initial, loading, loaded, error }

class CategoryTreeState extends Equatable {
  final CategoryTreeStatus status;
  final List<Category> allCategories;
  final Map<String, Category> categoryMap;
  final String? facultyId;
  final List<Category> rootCategories;
  final String? selectedId;
  final List<String?> historyStack;
  final List<Category> currentCategories;
  final List<CourseItem> currentCourses;
  final Category? selectedCategory;
  final List<Category> breadcrumbPath;
  final String? errorMessage;
  final bool isActivating;
  final String? activationMessage;
  final bool? isActivationSuccess;

  const CategoryTreeState({
    this.status = CategoryTreeStatus.initial,
    this.allCategories = const [],
    this.categoryMap = const {},
    this.facultyId,
    this.rootCategories = const [],
    this.selectedId,
    this.historyStack = const [],
    this.currentCategories = const [],
    this.currentCourses = const [],
    this.selectedCategory,
    this.breadcrumbPath = const [],
    this.errorMessage,
    this.isActivating = false,
    this.activationMessage,
    this.isActivationSuccess,
  });

  /// Whether current view is showing categories
  bool get showCategories => currentCategories.isNotEmpty;

  /// Whether current view is showing courses (priority: categories first, then courses)
  bool get showCourses => !showCategories && currentCourses.isNotEmpty;

  /// Whether current view is empty
  bool get showEmptyState => currentCategories.isEmpty && currentCourses.isEmpty;

  /// Whether back navigation is available in the tree
  bool get canGoBack => historyStack.isNotEmpty || selectedId != null;

  /// Title of current view
  String get currentTitle => selectedCategory?.name ?? '';

  CategoryTreeState copyWith({
    CategoryTreeStatus? status,
    List<Category>? allCategories,
    Map<String, Category>? categoryMap,
    String? facultyId,
    bool clearFacultyId = false,
    List<Category>? rootCategories,
    String? selectedId,
    bool clearSelectedId = false,
    List<String?>? historyStack,
    List<Category>? currentCategories,
    List<CourseItem>? currentCourses,
    Category? selectedCategory,
    bool clearSelectedCategory = false,
    List<Category>? breadcrumbPath,
    String? errorMessage,
    bool clearErrorMessage = false,
    bool? isActivating,
    String? activationMessage,
    bool clearActivationMessage = false,
    bool? isActivationSuccess,
  }) {
    return CategoryTreeState(
      status: status ?? this.status,
      allCategories: allCategories ?? this.allCategories,
      categoryMap: categoryMap ?? this.categoryMap,
      facultyId: clearFacultyId ? null : (facultyId ?? this.facultyId),
      rootCategories: rootCategories ?? this.rootCategories,
      selectedId: clearSelectedId ? null : (selectedId ?? this.selectedId),
      historyStack: historyStack ?? this.historyStack,
      currentCategories: currentCategories ?? this.currentCategories,
      currentCourses: currentCourses ?? this.currentCourses,
      selectedCategory: clearSelectedCategory
          ? null
          : (selectedCategory ?? this.selectedCategory),
      breadcrumbPath: breadcrumbPath ?? this.breadcrumbPath,
      errorMessage: clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
      isActivating: isActivating ?? this.isActivating,
      activationMessage: clearActivationMessage
          ? null
          : (activationMessage ?? this.activationMessage),
      isActivationSuccess: isActivationSuccess ?? this.isActivationSuccess,
    );
  }

  @override
  List<Object?> get props => [
        status,
        allCategories,
        categoryMap,
        facultyId,
        rootCategories,
        selectedId,
        historyStack,
        currentCategories,
        currentCourses,
        selectedCategory,
        breadcrumbPath,
        errorMessage,
        isActivating,
        activationMessage,
        isActivationSuccess,
      ];
}
