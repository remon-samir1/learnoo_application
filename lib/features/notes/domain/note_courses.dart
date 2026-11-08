import '../../../core/utils/coerce.dart';

/// Every course a note belongs to.
///
/// The web's home filters notes on the flat `course_id` alone, but the
/// dashboard also attaches a note through `course_ids`, an inlined `courses`
/// list or a `course` relation, and a note tied to a chapter carries the
/// course only under that chapter. Those rows were silently dropped from the
/// student's home, which is why a course's notes never showed up.
List<String> noteCourseIds(dynamic note) {
  final attrs = note is Map ? (note['attributes'] ?? note) : null;
  if (attrs is! Map) return const [];

  final ids = <String>{};

  void addId(dynamic raw) {
    if (raw is Map) {
      final data = raw['data'];
      addId(raw['id'] ?? (data is Map ? data['id'] : null));
      return;
    }
    final id = coerceId(raw);
    if (id != null && id != '0') ids.add(id);
  }

  final many = attrs['course_ids'];
  if (many is List) {
    many.forEach(addId);
  } else if (many is String) {
    for (final part in many.split(',')) {
      addId(part.trim());
    }
  }

  final courses = attrs['courses'];
  final courseList = courses is List
      ? courses
      : (courses is Map && courses['data'] is List
            ? courses['data'] as List
            : null);
  courseList?.forEach(addId);

  addId(attrs['course_id']);
  addId(attrs['course']);

  // A note hung off a chapter or a lecture names its course there.
  for (final key in const ['chapter', 'lecture']) {
    final owner = attrs[key];
    final ownerAttrs = owner is Map
        ? (owner['attributes'] ??
              (owner['data'] is Map
                  ? (owner['data'] as Map)['attributes']
                  : null))
        : null;
    if (ownerAttrs is Map) {
      addId(ownerAttrs['course_id']);
      addId(ownerAttrs['course']);
    }
  }

  if (note is Map) addId(note['course_id']);

  return ids.toList();
}
