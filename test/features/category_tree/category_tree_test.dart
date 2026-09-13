import 'package:flutter_test/flutter_test.dart';
import 'package:learnoo/features/category_tree/data/models/category_tree_model.dart';
import 'package:learnoo/features/category_tree/presentation/cubit/category_tree_cubit.dart';
import 'package:learnoo/features/category_tree/presentation/cubit/category_tree_state.dart';

void main() {
  group('CategoryTreeModel Tests', () {
    test('Category.fromJson handles both int and String IDs safely', () {
      final json1 = {
        'id': 101,
        'attributes': {
          'name': 'Faculty of Engineering',
          'parent_id': 50,
          'stats': {'courses': 12, 'students': 250},
        }
      };

      final cat1 = Category.fromJson(json1);
      expect(cat1.id, '101');
      expect(cat1.name, 'Faculty of Engineering');
      expect(cat1.parentId, '50');
      expect(cat1.stats.coursesCount, 12);
      expect(cat1.stats.studentsCount, 250);

      // String IDs and nested parent.data.id
      final json2 = {
        'id': '202',
        'attributes': {
          'name': 'Department of Computer Science',
          'parent': {
            'data': {'id': 101, 'type': 'faculty'}
          },
        }
      };

      final cat2 = Category.fromJson(json2);
      expect(cat2.id, '202');
      expect(cat2.name, 'Department of Computer Science');
      expect(cat2.parentId, '101');
    });

    test('CourseItem.fromJson correctly detects isActive for different status values', () {
      final courseActiveInt = CourseItem.fromJson({
        'id': 1,
        'attributes': {'title': 'Algorithms', 'status': 1, 'is_locked': false}
      });
      expect(courseActiveInt.isActive, isTrue);
      expect(courseActiveInt.isLocked, isFalse);

      final courseActiveString = CourseItem.fromJson({
        'id': 2,
        'attributes': {'title': 'Networks', 'status': 'active', 'is_locked': 1}
      });
      expect(courseActiveString.isActive, isTrue);
      expect(courseActiveString.isLocked, isTrue);

      final courseActiveBool = CourseItem.fromJson({
        'id': 3,
        'attributes': {'title': 'Databases', 'status': true, 'is_locked': 'true'}
      });
      expect(courseActiveBool.isActive, isTrue);
      expect(courseActiveBool.isLocked, isTrue);

      final courseActiveNull = CourseItem.fromJson({
        'id': 4,
        'attributes': {'title': 'Security', 'status': null}
      });
      expect(courseActiveNull.isActive, isTrue);

      final courseInactive = CourseItem.fromJson({
        'id': 5,
        'attributes': {'title': 'Archived Math', 'status': 0}
      });
      expect(courseInactive.isActive, isFalse);
    });
  });

  group('CategoryTree Traversal & Filtering Algorithm Tests', () {
    late List<Category> sampleCategories;
    late Map<String, Category> sampleCategoryMap;

    setUp(() {
      // Structure:
      // Faculty (ID: '50')
      //   ├── Year 1 (ID: '101', parent_id: '50')
      //   │     └── Term 1 (ID: '201', parent_id: '101') -> Courses: [C1, C2]
      //   └── Year 2 (ID: '102', parent_id: '50')
      //         └── Term 1 (ID: '202', parent_id: '102') -> Courses: [C3]
      // Unrelated faculty (ID: '999', parent_id: '60')

      sampleCategories = [
        Category.fromJson({
          'id': '101',
          'attributes': {
            'name': 'Year 1',
            'parent_id': '50',
            'childrens': [
              {'id': '201', 'attributes': {'name': 'Term 1'}}
            ],
          },
        }),
        Category.fromJson({
          'id': '102',
          'attributes': {
            'name': 'Year 2',
            'parent_id': '50',
            'childrens': [
              {'id': '202', 'attributes': {'name': 'Term 1'}}
            ],
          },
        }),
        Category.fromJson({
          'id': '201',
          'attributes': {
            'name': 'Term 1 (Year 1)',
            'parent_id': '101',
            'courses': [
              {
                'id': 'c1',
                'attributes': {'title': 'Physics 101', 'status': 1, 'is_locked': false}
              },
              {
                'id': 'c2',
                'attributes': {'title': 'Calculus 1', 'status': 'active', 'is_locked': true}
              },
              {
                'id': 'c_inactive',
                'attributes': {'title': 'Old Syllabus', 'status': 0}
              },
            ],
          },
        }),
        Category.fromJson({
          'id': '202',
          'attributes': {
            'name': 'Term 1 (Year 2)',
            'parent_id': '102',
            'courses': [
              {
                'id': 'c3',
                'attributes': {'title': 'Data Structures', 'status': true}
              },
            ],
          },
        }),
        Category.fromJson({
          'id': '999',
          'attributes': {
            'name': 'Other Faculty Level',
            'parent_id': '60',
          },
        }),
      ];

      sampleCategoryMap = CategoryTreeCubit.buildCategoryMap(sampleCategories);
    });

    test('1. Category Map indexes all items by id for O(1) lookup', () {
      expect(sampleCategoryMap.containsKey('101'), isTrue);
      expect(sampleCategoryMap.containsKey('102'), isTrue);
      expect(sampleCategoryMap.containsKey('201'), isTrue);
      expect(sampleCategoryMap.containsKey('202'), isTrue);
      expect(sampleCategoryMap.containsKey('999'), isTrue);
      expect(sampleCategoryMap['101']?.name, 'Year 1');
    });

    test('2. Root Categories Determination matches facultyId when provided', () {
      final roots = CategoryTreeCubit.determineRootCategories(
        facultyId: '50',
        categories: sampleCategories,
        categoryMap: sampleCategoryMap,
      );

      expect(roots.length, 2);
      expect(roots.map((Category c) => c.id).toSet(), {'101', '102'});
    });

    test('2. Root Categories Determination falls back when facultyId is null or unmatched', () {
      // If facultyId is unknown (e.g. '99999'), fallback to items with no parent or parent not in map
      final roots = CategoryTreeCubit.determineRootCategories(
        facultyId: '99999',
        categories: sampleCategories,
        categoryMap: sampleCategoryMap,
      );

      // '50' and '60' are not in sampleCategoryMap, so all those nodes qualify as root entries
      expect(roots.isNotEmpty, isTrue);
    });

    test('3. Current View Resolution: Sub-categories detection & Courses detection', () {
      // Create cubit with custom initial state
      final cubit = CategoryTreeCubit();

      final roots = CategoryTreeCubit.determineRootCategories(
        facultyId: '50',
        categories: sampleCategories,
        categoryMap: sampleCategoryMap,
      );

      // Initial state is at root
      cubit.emit(CategoryTreeState(
        status: CategoryTreeStatus.loaded,
        allCategories: sampleCategories,
        categoryMap: sampleCategoryMap,
        rootCategories: roots,
        facultyId: '50',
        selectedId: null,
        currentCategories: roots,
        currentCourses: const [],
      ));

      expect(cubit.state.showCategories, isTrue);
      expect(cubit.state.showCourses, isFalse);
      expect(cubit.state.currentCategories.length, 2);

      // Drill down into 'Year 1' (ID: '101')
      cubit.selectCategory('101');

      expect(cubit.state.selectedId, '101');
      expect(cubit.state.historyStack, [null]);
      expect(cubit.state.showCategories, isTrue);
      expect(cubit.state.showCourses, isFalse);
      expect(cubit.state.currentCategories.length, 1);
      expect(cubit.state.currentCategories.first.id, '201');

      // Drill down into 'Term 1' (ID: '201') -> has courses, no child categories
      cubit.selectCategory('201');

      expect(cubit.state.selectedId, '201');
      expect(cubit.state.historyStack, [null, '101']);
      expect(cubit.state.showCategories, isFalse);
      expect(cubit.state.showCourses, isTrue);
      // c1 and c2 are active, c_inactive should be filtered out
      expect(cubit.state.currentCourses.length, 2);
      expect(cubit.state.currentCourses.map((c) => c.id).toList(), ['c1', 'c2']);

      // 4. Back Navigation
      final handledBack1 = cubit.popHistory();
      expect(handledBack1, isTrue);
      expect(cubit.state.selectedId, '101');
      expect(cubit.state.showCategories, isTrue);
      expect(cubit.state.currentCategories.first.id, '201');

      final handledBack2 = cubit.popHistory();
      expect(handledBack2, isTrue);
      expect(cubit.state.selectedId, isNull);
      expect(cubit.state.currentCategories.length, 2);

      // At root, popHistory returns false
      final handledBack3 = cubit.popHistory();
      expect(handledBack3, isFalse);

      cubit.close();
    });

    test('4. Rendering Priority: Category > Course > Empty State', () {
      const stateWithCategories = CategoryTreeState(
        currentCategories: [Category(id: '1', name: 'Cat 1')],
        currentCourses: [CourseItem(id: 'c1', title: 'Course 1')],
      );
      // If both are present, priority is Categories
      expect(stateWithCategories.showCategories, isTrue);
      expect(stateWithCategories.showCourses, isFalse);
      expect(stateWithCategories.showEmptyState, isFalse);

      const stateWithCoursesOnly = CategoryTreeState(
        currentCategories: [],
        currentCourses: [CourseItem(id: 'c1', title: 'Course 1')],
      );
      expect(stateWithCoursesOnly.showCategories, isFalse);
      expect(stateWithCoursesOnly.showCourses, isTrue);
      expect(stateWithCoursesOnly.showEmptyState, isFalse);

      const stateEmpty = CategoryTreeState(
        currentCategories: [],
        currentCourses: [],
      );
      expect(stateEmpty.showCategories, isFalse);
      expect(stateEmpty.showCourses, isFalse);
      expect(stateEmpty.showEmptyState, isTrue);
    });

    test('5. navigateToBreadcrumb navigates up and truncates history stack correctly', () {
      final cubit = CategoryTreeCubit();
      final roots = CategoryTreeCubit.determineRootCategories(
        facultyId: '50',
        categories: sampleCategories,
        categoryMap: sampleCategoryMap,
      );

      cubit.emit(CategoryTreeState(
        status: CategoryTreeStatus.loaded,
        allCategories: sampleCategories,
        categoryMap: sampleCategoryMap,
        rootCategories: roots,
        facultyId: '50',
        selectedId: null,
        currentCategories: roots,
      ));

      // Navigate Root -> 101 -> 201
      cubit.selectCategory('101');
      cubit.selectCategory('201');

      expect(cubit.state.selectedId, '201');
      expect(cubit.state.historyStack, [null, '101']);

      // Jump directly to root via breadcrumb
      cubit.navigateToBreadcrumb(null);
      expect(cubit.state.selectedId, isNull);
      expect(cubit.state.historyStack, isEmpty);
      expect(cubit.state.showCategories, isTrue);

      cubit.close();
    });
  });
}
