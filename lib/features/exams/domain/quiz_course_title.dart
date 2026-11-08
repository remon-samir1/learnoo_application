/// The name of the course an exam belongs to.
library;

/// Reads the course title out of a quiz's `attributes`.
///
/// The API attaches the course in several shapes depending on the endpoint:
/// a `course` relation (flat, or JSON:API `{data: {attributes: {title}}}`), a
/// `courses` list for exams shared by more than one course, a flat
/// `course_title`, or — for a chapter exam — only through the chapter's own
/// course. The start page shows the first one it finds.
String? quizCourseTitle(Map<String, dynamic>? attributes) {
  if (attributes == null) return null;

  String? titleOf(dynamic node) {
    if (node is! Map) return null;

    final data = node['data'];
    if (data is Map) {
      final nested = titleOf(data);
      if (nested != null) return nested;
    }
    if (data is List) {
      for (final item in data) {
        final nested = titleOf(item);
        if (nested != null) return nested;
      }
    }

    final attrs = node['attributes'];
    final source = attrs is Map ? attrs : node;
    for (final key in const ['title', 'name']) {
      final value = source[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }

  for (final key in const ['course_title', 'course_name']) {
    final value = attributes[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
  }

  final direct = titleOf(attributes['course']);
  if (direct != null) return direct;

  final courses = attributes['courses'];
  if (courses is List) {
    for (final course in courses) {
      final title = titleOf(course);
      if (title != null) return title;
    }
  } else {
    final title = titleOf(courses);
    if (title != null) return title;
  }

  // A chapter exam names its course only under the chapter.
  final chapter = attributes['chapter'];
  final chapterNode = chapter is Map
      ? (chapter['data'] is Map ? chapter['data'] as Map : chapter)
      : null;
  final chapterAttrs = chapterNode?['attributes'];
  if (chapterAttrs is Map) {
    final fromChapter = titleOf(chapterAttrs['course']);
    if (fromChapter != null) return fromChapter;
    for (final key in const ['course_title', 'course_name']) {
      final value = chapterAttrs[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
  }

  return null;
}
