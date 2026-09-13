/// Navigating the University → Centre → Faculty → Department tree.
///
/// Ported from `src/lib/faculty-university.ts` and
/// `src/lib/student-faculty-departments.ts`. Two rules the app was missing:
///
///  * a faculty belongs to a centre through **either** `parent_id` **or**
///    `parent.data.id`, and ids must be compared as strings because the API
///    mixes `12` and `"12"`;
///  * departments are not a separate endpoint — they arrive nested on the
///    faculty as `attributes.childrens` (note the spelling) and are what the
///    web's fourth onboarding step lists.
library;

import '../../../core/utils/coerce.dart';

/// Loose id equality: `12`, `"12"` and `12.0` all match.
bool idsMatch(dynamic a, dynamic b) {
  final left = coerceId(a);
  final right = coerceId(b);
  if (left == null || right == null) return false;
  return left == right;
}

/// `attributes.name`, falling back to a flat `name` (the centre endpoint is
/// flat while university/faculty are JSON:API).
String entityName(dynamic item) {
  if (item is! Map) return '';
  final attrs = item['attributes'];
  if (attrs is Map) {
    final name = coerceString(attrs['name']);
    if (name != null) return name;
  }
  return coerceString(item['name']) ?? '';
}

String? entityId(dynamic item) {
  if (item is! Map) return null;
  return coerceId(item['id']);
}

Map<String, dynamic>? _attributesOf(dynamic item) {
  if (item is! Map) return null;
  final attrs = item['attributes'];
  return attrs is Map ? Map<String, dynamic>.from(attrs) : null;
}

/// Parent id of a node, from `parent_id` then `parent.data.id`.
String? parentIdOf(dynamic item) {
  final attrs = _attributesOf(item);
  if (attrs != null) {
    final direct = coerceId(attrs['parent_id']);
    if (direct != null) return direct;

    final parent = attrs['parent'];
    if (parent is Map && parent['data'] is Map) {
      final nested = coerceId((parent['data'] as Map)['id']);
      if (nested != null) return nested;
    }
  }

  if (item is Map) {
    final flat = coerceId(item['parent_id']);
    if (flat != null) return flat;

    final parent = item['parent'];
    if (parent is Map && parent['data'] is Map) {
      return coerceId((parent['data'] as Map)['id']);
    }
  }

  return null;
}

/// Centres under [universityId].
List<dynamic> centersForUniversity(
  List<dynamic> centers,
  dynamic universityId,
) {
  if (universityId == null) return const [];
  return centers.where((c) => idsMatch(parentIdOf(c), universityId)).toList();
}

/// Faculties under [centerId].
bool facultyBelongsToCenter(dynamic faculty, dynamic centerId) {
  return idsMatch(parentIdOf(faculty), centerId);
}

List<dynamic> facultiesForCenter(List<dynamic> faculties, dynamic centerId) {
  if (centerId == null) return const [];
  return faculties.where((f) => facultyBelongsToCenter(f, centerId)).toList();
}

/// Departments nested on a faculty.
///
/// The API spells the key `childrens`; some payloads use `children`, so both
/// are accepted.
List<dynamic> facultyDepartments(dynamic faculty) {
  final attrs = _attributesOf(faculty);
  if (attrs == null) return const [];

  final raw = attrs['childrens'] ?? attrs['children'];
  if (raw is List) return raw;
  return const [];
}

/// Finds a faculty by id in a flat list.
dynamic findFacultyById(List<dynamic> faculties, dynamic facultyId) {
  if (facultyId == null) return null;
  for (final faculty in faculties) {
    if (idsMatch(entityId(faculty), facultyId)) return faculty;
  }
  return null;
}

/// Collects every course id reachable from the student's faculty, walking the
/// department tree breadth-first.
///
/// Mirrors `extractFacultyTreeCourses` — the home screen uses it to keep the
/// "My subjects" tree limited to the student's own faculty.
Set<String> facultyTreeCourseIds(
  List<dynamic> categories,
  dynamic facultyId,
) {
  final courseIds = <String>{};
  if (categories.isEmpty || facultyId == null) return courseIds;

  final byId = <String, dynamic>{};
  for (final item in categories) {
    final id = entityId(item);
    if (id != null) byId[id] = item;
  }

  final seen = <String>{};
  final queue = <dynamic>[];

  for (final category in categories) {
    if (idsMatch(parentIdOf(category), facultyId)) {
      final id = entityId(category);
      if (id != null && seen.add(id)) queue.add(category);
    }
  }

  while (queue.isNotEmpty) {
    final node = queue.removeAt(0);
    final attrs = _attributesOf(node);

    final courses = attrs?['courses'] ?? (node is Map ? node['courses'] : null);
    if (courses is List) {
      for (final course in courses) {
        final id = entityId(course);
        if (id != null) courseIds.add(id);
      }
    }

    final nodeId = entityId(node);
    if (nodeId == null) continue;

    for (final candidate in byId.values) {
      if (!idsMatch(parentIdOf(candidate), nodeId)) continue;
      final id = entityId(candidate);
      if (id != null && seen.add(id)) queue.add(candidate);
    }
  }

  return courseIds;
}

/// One entry of an academic dropdown: a stable id plus the label to render.
class AcademicOption {
  const AcademicOption({required this.id, required this.label});

  final String id;
  final String label;
}

/// Centre node hanging off a faculty as `attributes.parent.data`.
///
/// The web derives the centre list from the faculty list rather than from
/// `/v1/center`, which is why a centre with no faculties never appears in a
/// dropdown there. [centerOptionsForUniversity] reproduces that.
Map<String, dynamic>? facultyCenterNode(dynamic faculty) {
  final attrs = _attributesOf(faculty);
  final parent = attrs?['parent'];
  if (parent is Map && parent['data'] is Map) {
    return Map<String, dynamic>.from(parent['data'] as Map);
  }
  return null;
}

/// Centres under [universityId], derived from the faculty list.
///
/// Port of `buildUniversityCenterOptions`: value is `parent.data.id`, label is
/// `parent.data.attributes.name`, duplicates collapse and the list is sorted by
/// label.
List<AcademicOption> centerOptionsForUniversity(
  List<dynamic> faculties,
  dynamic universityId,
) {
  if (universityId == null || universityId.toString().isEmpty) {
    return const [];
  }

  final byId = <String, AcademicOption>{};

  for (final faculty in faculties) {
    final center = facultyCenterNode(faculty);
    if (center == null) continue;

    final centerAttrs = center['attributes'];
    final centerParentId =
        centerAttrs is Map ? centerAttrs['parent_id'] : center['parent_id'];
    if (!idsMatch(centerParentId, universityId)) continue;

    final label = entityName(center).trim();
    if (label.isEmpty) continue;

    final id = entityId(center);
    if (id == null) continue;

    byId.putIfAbsent(id, () => AcademicOption(id: id, label: label));
  }

  final options = byId.values.toList()
    ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
  return options;
}

/// Faculties under [centerId] as dropdown options. Port of
/// `buildCenterFacultyOptions`.
List<AcademicOption> facultyOptionsForCenter(
  List<dynamic> faculties,
  dynamic centerId,
) {
  if (centerId == null || centerId.toString().isEmpty) return const [];

  final options = <AcademicOption>[];
  for (final faculty in faculties) {
    if (!facultyBelongsToCenter(faculty, centerId)) continue;
    final label = entityName(faculty).trim();
    final id = entityId(faculty);
    if (label.isEmpty || id == null) continue;
    options.add(AcademicOption(id: id, label: label));
  }

  options.sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
  return options;
}

/// Departments of [facultyId] as dropdown options, read from
/// `attributes.childrens`. Port of `buildFacultyDepartmentOptions`.
List<AcademicOption> departmentOptionsForFaculty(
  List<dynamic> faculties,
  dynamic facultyId, [
  dynamic facultyDetail,
]) {
  final faculty = findFacultyById(faculties, facultyId);
  final source = facultyDepartments(faculty).isNotEmpty
      ? faculty
      : (facultyDetail ?? faculty);

  final options = <AcademicOption>[];
  for (final department in facultyDepartments(source)) {
    final id = entityId(department);
    final label = entityName(department).trim();
    if (id == null || label.isEmpty) continue;
    options.add(AcademicOption(id: id, label: label));
  }
  return options;
}
