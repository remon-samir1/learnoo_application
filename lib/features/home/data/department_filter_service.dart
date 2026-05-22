import 'models/department_node.dart';

/// Service for filtering user departments based on hierarchy validation
class DepartmentFilterService {

  /// Main function: Get departments for the logged-in user
  /// Validates full hierarchy before returning departments
  static List<DepartmentNode> getUserDepartments({
    required Map<String, dynamic> meResponse,
    required List<dynamic> centers,
    required List<dynamic> faculties,
    required List<dynamic> departments,
  }) {
    // Step 1: Extract user data from me response
    final userData = _extractUserData(meResponse);
    if (userData == null) return [];

    final universityId = userData['universityId'];
    final facultyId = userData['facultyId'];
    final centerIds = userData['centerIds'] as List<String>;

    if (universityId == null || facultyId == null || centerIds.isEmpty) {
      return [];
    }

    // Step 2: Validate centers - find valid centers that belong to user's university
    final validCenterIds = _getValidCenterIds(
      centers: centers,
      universityId: universityId,
      userCenterIds: centerIds,
    );

    if (validCenterIds.isEmpty) return [];

    // Step 3: Validate faculty - find faculty that belongs to valid centers
    final isFacultyValid = _isFacultyValid(
      faculties: faculties,
      facultyId: facultyId,
      validCenterIds: validCenterIds,
    );

    if (!isFacultyValid) return [];

    // Step 4: Get root departments (where parent_id == facultyId AND parent_type == faculty)
    final rootDepartments = _getRootDepartments(
      departments: departments,
      facultyId: facultyId,
    );

    // Step 5: Build recursive department tree
    return _buildDepartmentTree(
      allDepartments: departments,
      rootDepartments: rootDepartments,
    );
  }

  /// Extract user data from me API response
  static Map<String, dynamic>? _extractUserData(Map<String, dynamic> meResponse) {
    try {
      final data = meResponse['data'] as Map<String, dynamic>?;
      if (data == null) return null;

      final attributes = data['attributes'] as Map<String, dynamic>?;
      if (attributes == null) return null;

      // Extract university
      final university = attributes['university']?['data'];
      final universityId = university?['id']?.toString();

      // Extract faculty
      final faculty = attributes['faculty']?['data'];
      final facultyId = faculty?['id']?.toString();

      // Extract centers (array)
      final centersData = attributes['centers'] as List<dynamic>? ?? [];
      final centerIds = centersData
          .map((c) => c['id']?.toString())
          .where((id) => id != null)
          .cast<String>()
          .toList();

      return {
        'universityId': universityId,
        'facultyId': facultyId,
        'centerIds': centerIds,
      };
    } catch (e) {
      return null;
    }
  }

  /// Validate centers - return center IDs that belong to user's university
  static List<String> _getValidCenterIds({
    required List<dynamic> centers,
    required String universityId,
    required List<String> userCenterIds,
  }) {
    final validIds = <String>[];

    for (final center in centers) {
      final centerId = center['id']?.toString();
      final attributes = center['attributes'] as Map<String, dynamic>?;
      final parentId = attributes?['parent_id']?.toString();

      // Center must be in user's centers AND belong to user's university
      if (centerId != null &&
          userCenterIds.contains(centerId) &&
          parentId == universityId) {
        validIds.add(centerId);
      }
    }

    return validIds;
  }

  /// Validate faculty belongs to one of the valid centers
  static bool _isFacultyValid({
    required List<dynamic> faculties,
    required String facultyId,
    required List<String> validCenterIds,
  }) {
    for (final faculty in faculties) {
      final id = faculty['id']?.toString();
      if (id != facultyId) continue;

      final attributes = faculty['attributes'] as Map<String, dynamic>?;
      final parentId = attributes?['parent_id']?.toString();

      // Faculty must belong to one of the valid centers
      return validCenterIds.contains(parentId);
    }

    return false;
  }

  /// Get root departments (direct children of the faculty)
  static List<DepartmentNode> _getRootDepartments({
    required List<dynamic> departments,
    required String facultyId,
  }) {
    final rootDepartments = <DepartmentNode>[];

    for (final dept in departments) {
      final node = DepartmentNode.fromJson(dept as Map<String, dynamic>);

      // Root department: parent_id matches faculty AND parent_type is "faculty"
      if (node.parentId == facultyId &&
          (node.parentType == 'faculty' || node.parentType == null)) {
        rootDepartments.add(node);
      }
    }

    return rootDepartments;
  }

  /// Build recursive department tree with infinite nesting support
  static List<DepartmentNode> _buildDepartmentTree({
    required List<dynamic> allDepartments,
    required List<DepartmentNode> rootDepartments,
  }) {
    // Build lookup map for O(1) access
    final departmentMap = <String, DepartmentNode>{};
    final childrenByParent = <String, List<DepartmentNode>>{};

    // First pass: parse all departments and group children by parent
    for (final deptJson in allDepartments) {
      final dept = DepartmentNode.fromJson(deptJson as Map<String, dynamic>);
      departmentMap[dept.id] = dept;

      // If this department has a parent that is another department (not faculty)
      if (dept.parentId != null &&
          dept.parentType == 'department') {
        childrenByParent
            .putIfAbsent(dept.parentId!, () => [])
            .add(dept);
      }
    }

    // Recursive function to build subtree
    DepartmentNode buildSubtree(DepartmentNode node) {
      final children = childrenByParent[node.id] ?? [];
      final childrenWithSubtree = children.map(buildSubtree).toList();
      return node.copyWith(children: childrenWithSubtree);
    }

    // Build tree for all root departments
    return rootDepartments.map(buildSubtree).toList();
  }

  /// Alternative: Build tree from specific parent ID (for recursive calls)
  static List<DepartmentNode> buildDepartmentTreeFromParent({
    required List<dynamic> departments,
    required String parentId,
  }) {
    // Build lookup maps
    final childrenByParent = <String, List<DepartmentNode>>{};

    for (final deptJson in departments) {
      final dept = DepartmentNode.fromJson(deptJson as Map<String, dynamic>);
      if (dept.parentId != null) {
        childrenByParent
            .putIfAbsent(dept.parentId!, () => [])
            .add(dept);
      }
    }

    // Get direct children of parent
    final directChildren = childrenByParent[parentId] ?? [];

    // Recursive builder
    DepartmentNode buildSubtree(DepartmentNode node) {
      final children = childrenByParent[node.id] ?? [];
      final childrenWithSubtree = children.map(buildSubtree).toList();
      return node.copyWith(children: childrenWithSubtree);
    }

    return directChildren.map(buildSubtree).toList();
  }

  /// Build full 4-level hierarchy tree: University > Centers > Faculty > Departments
  /// Returns the complete tree structure for the user's hierarchy
  static Map<String, dynamic> buildFullHierarchyTree({
    required Map<String, dynamic> meResponse,
    required List<dynamic> centers,
    required List<dynamic> faculties,
    required List<dynamic> departments,
  }) {
    // Step 1: Extract user data
    final userData = _extractUserData(meResponse);
    if (userData == null) return {};

    final universityId = userData['universityId'];
    final facultyId = userData['facultyId'];
    final centerIds = userData['centerIds'] as List<String>;

    if (universityId == null || facultyId == null || centerIds.isEmpty) {
      return {};
    }

    // Step 2: Build hierarchy tree
    final tree = <String, dynamic>{
      'universityId': universityId,
      'centers': <Map<String, dynamic>>[],
    };

    // Group faculties by center
    final facultiesByCenter = <String, List<Map<String, dynamic>>>{};
    for (final faculty in faculties) {
      final fId = faculty['id']?.toString();
      final fAttributes = faculty['attributes'] as Map<String, dynamic>?;

      // Check parent_id (flat) or parent.data.id (nested)
      String? centerId = fAttributes?['parent_id']?.toString();
      if (centerId == null) {
        final parent = fAttributes?['parent'] as Map<String, dynamic>?;
        final parentData = parent?['data'] as Map<String, dynamic>?;
        centerId = parentData?['id']?.toString();
      }

      if (fId != null && centerId != null) {
        facultiesByCenter.putIfAbsent(centerId, () => []).add({
          'id': fId,
          'name': fAttributes?['name'] ?? '',
          'centerId': centerId,
          'departments': <DepartmentNode>[],
        });
      }
    }

    // Build department tree
    final deptChildrenByParent = <String, List<DepartmentNode>>{};
    for (final deptJson in departments) {
      final dept = DepartmentNode.fromJson(deptJson as Map<String, dynamic>);
      if (dept.parentId != null && dept.parentType == 'department') {
        deptChildrenByParent
            .putIfAbsent(dept.parentId!, () => [])
            .add(dept);
      }
    }

    DepartmentNode buildDeptSubtree(DepartmentNode node) {
      final children = deptChildrenByParent[node.id] ?? [];
      final childrenWithSubtree = children.map(buildDeptSubtree).toList();
      return node.copyWith(children: childrenWithSubtree);
    }

    // Build centers with their faculties and departments
    for (final center in centers) {
      final cId = center['id']?.toString();
      final cAttributes = center['attributes'] as Map<String, dynamic>?;

      // Check parent_id (flat) or parent.data.id (nested)
      String? cParentId = cAttributes?['parent_id']?.toString();
      if (cParentId == null) {
        final cParent = cAttributes?['parent'] as Map<String, dynamic>?;
        final cParentData = cParent?['data'] as Map<String, dynamic>?;
        cParentId = cParentData?['id']?.toString();
      }

      print('Center: $cId, parent: $cParentId, user centers: $centerIds');

      // Center must belong to user's university and be in user's centers
      if (cId != null &&
          centerIds.contains(cId) &&
          cParentId == universityId) {
        final centerFaculties = facultiesByCenter[cId] ?? [];

        // Add departments to each faculty
        for (final faculty in centerFaculties) {
          final fId = faculty['id'] as String;
          if (fId == facultyId) {
            // Get departments for this faculty
            final facultyDepts = <DepartmentNode>[];
            for (final deptJson in departments) {
              final dept = DepartmentNode.fromJson(deptJson as Map<String, dynamic>);
              if (dept.parentId == fId &&
                  (dept.parentType == 'faculty' || dept.parentType == null)) {
                facultyDepts.add(buildDeptSubtree(dept));
              }
            }
            faculty['departments'] = facultyDepts;
          }
        }

        // Only add center if it has the target faculty
        final validFaculties = centerFaculties.where((f) => f['id'] == facultyId).toList();
        if (validFaculties.isNotEmpty) {
          (tree['centers'] as List<Map<String, dynamic>>).add({
            'id': cId,
            'name': cAttributes?['name'] ?? '',
            'faculties': validFaculties,
          });
        }
      }
    }

    return tree;
  }

  /// Get all departments as a flat list from the hierarchy tree
  static List<DepartmentNode> getAllDepartmentsFromTree(
    Map<String, dynamic> tree,
  ) {
    final departments = <DepartmentNode>[];
    final centers = tree['centers'] as List<dynamic>? ?? [];

    for (final center in centers) {
      final centerMap = center as Map<String, dynamic>;
      final faculties = centerMap['faculties'] as List<dynamic>? ?? [];
      for (final faculty in faculties) {
        final facultyMap = faculty as Map<String, dynamic>;
        final depts = facultyMap['departments'];
        if (depts is List<DepartmentNode>) {
          departments.addAll(depts);
        } else if (depts is List<dynamic>) {
          departments.addAll(depts.whereType<DepartmentNode>());
        }
      }
    }

    return departments;
  }

  /// Debug helper: Print the hierarchy tree structure
  static void debugPrintTree(Map<String, dynamic> tree) {
    print('=== Hierarchy Tree ===');
    print('University ID: ${tree['universityId']}');
    final centers = tree['centers'] as List<dynamic>? ?? [];
    print('Centers count: ${centers.length}');
    for (final center in centers) {
      final c = center as Map<String, dynamic>;
      print('  Center: ${c['name']} (${c['id']})');
      final faculties = c['faculties'] as List<dynamic>? ?? [];
      for (final faculty in faculties) {
        final f = faculty as Map<String, dynamic>;
        final depts = f['departments'];
        final deptCount = depts is List ? depts.length : 0;
        print('    Faculty: ${f['name']} (${f['id']}) - $deptCount departments');
      }
    }
    print('====================');
  }
}
