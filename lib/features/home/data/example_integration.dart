import 'department_filter_service.dart';
import 'models/department_node.dart';

/// Example integration for Home Screen
class HomeScreenIntegration {

  /// Example: Load and display user departments in Home Screen
  static void exampleHomeScreenUsage() {
    // 1. Get me response (user data)
    final meResponse = {
      "data": {
        "id": "123",
        "attributes": {
          "first_name": "John",
          "last_name": "Doe",
          "university": {
            "data": {
              "id": "1",
              "type": "university",
              "attributes": {"name": "Cairo University"}
            }
          },
          "faculty": {
            "data": {
              "id": "100",
              "type": "faculty",
              "attributes": {"name": "Commerce"}
            }
          },
          "centers": [
            {
              "id": "10",
              "type": "center",
              "attributes": {"name": "Main Center"}
            }
          ]
        }
      }
    };

    // 2. Centers API response
    final centers = [
      {
        "id": "10",
        "type": "center",
        "attributes": {
          "name": "Main Center",
          "parent_id": "1", // university_id
          "order": 1
        }
      },
      {
        "id": "11",
        "type": "center",
        "attributes": {
          "name": "Other Center",
          "parent_id": "2", // different university
          "order": 2
        }
      }
    ];

    // 3. Faculties API response
    final faculties = [
      {
        "id": "100",
        "type": "faculty",
        "attributes": {
          "name": "Commerce",
          "parent_id": "10", // center_id
          "order": 1
        }
      },
      {
        "id": "101",
        "type": "faculty",
        "attributes": {
          "name": "Other Faculty",
          "parent_id": "11", // different center
          "order": 2
        }
      }
    ];

    // 4. Departments API response (with nesting)
    final departments = [
      {
        "id": "179",
        "type": "department",
        "attributes": {
          "name": "Term 1",
          "image": null,
          "order": 1,
          "parent_id": "100",
          "parent": {
            "data": {"id": "100", "type": "faculty"}
          },
          "stats": {"courses": 5},
          "courses": []
        }
      },
      {
        "id": "180",
        "type": "department",
        "attributes": {
          "name": "Term 2",
          "image": "https://example.com/dept.jpg",
          "order": 2,
          "parent_id": "100",
          "parent": {
            "data": {"id": "100", "type": "faculty"}
          },
          "stats": {"courses": 3},
          "courses": [],
          "childrens": []
        }
      },
      {
        "id": "182",
        "type": "department",
        "attributes": {
          "name": "Regular Section",
          "image": null,
          "order": 1,
          "parent_id": "180",
          "parent": {
            "data": {"id": "180", "type": "department"}
          },
          "stats": {},
          "courses": [],
          "childrens": []
        }
      },
      {
        "id": "183",
        "type": "department",
        "attributes": {
          "name": "Other Department",
          "image": null,
          "order": 1,
          "parent_id": "101", // different faculty
          "parent": {
            "data": {"id": "101", "type": "faculty"}
          },
          "stats": {},
          "courses": []
        }
      }
    ];

    // 5. Get user departments with full hierarchy validation
    final userDepartments = DepartmentFilterService.getUserDepartments(
      meResponse: meResponse,
      centers: centers,
      faculties: faculties,
      departments: departments,
    );

    // Output: Only Term 1 and Term 2 (with Regular Section as child)
    // Department 183 is excluded (different faculty)
    print('User Departments:');
    for (final dept in userDepartments) {
      _printDepartment(dept, 0);
    }
  }

  static void _printDepartment(DepartmentNode dept, int level) {
    final indent = '  ' * level;
    print('$indent- ${dept.name} (${dept.children.length} children)');
    for (final child in dept.children) {
      _printDepartment(child, level + 1);
    }
  }

  /// Example: Using in a controller/provider
  static void exampleControllerPattern() {
    // In your controller or provider:
    /*
    class HomeController {
      List<DepartmentNode> _userDepartments = [];
      List<DepartmentNode> get userDepartments => _userDepartments;

      Future<void> loadUserData() async {
        // Fetch all APIs
        final me = await api.getMe();
        final centers = await api.getCenters();
        final faculties = await api.getFaculties();
        final departments = await api.getDepartments();

        // Get filtered departments
        _userDepartments = DepartmentFilterService.getUserDepartments(
          meResponse: me,
          centers: centers['data'],
          faculties: faculties['data'],
          departments: departments['data'],
        );

        notifyListeners();
      }
    }
    */
  }

  /// Example: Build tree from specific parent (for sub-departments screen)
  static void exampleSubDepartments() {
    final departments = [
      {
        "id": "182",
        "type": "department",
        "attributes": {
          "name": "Regular",
          "parent_id": "180",
          "parent": {"data": {"id": "180", "type": "department"}}
        }
      },
      {
        "id": "184",
        "type": "department",
        "attributes": {
          "name": "First Year",
          "parent_id": "182",
          "parent": {"data": {"id": "182", "type": "department"}}
        }
      }
    ];

    // Get children of department 180
    final children = DepartmentFilterService.buildDepartmentTreeFromParent(
      departments: departments,
      parentId: '180',
    );

    print('Children of department 180:');
    for (final child in children) {
      print('- ${child.name}');
      for (final grandChild in child.children) {
        print('  - ${grandChild.name}');
      }
    }
  }
}
