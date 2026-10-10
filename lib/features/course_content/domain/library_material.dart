/// Reading electronic-library materials the way the student website does.
///
/// Ported from `components/student/library/*` and
/// `src/lib/student-library-utils.ts`. The app diverged in three ways that
/// changed what a student could do:
///
///  * it treated `is_locked` as the lock, while the website locks a material on
///    `code_activation` — the field the activation code actually clears;
///  * it ignored each attachment's `downloadable` flag, so a file the admin
///    marked view-only was offered for download;
///  * it opened the raw attachment URL, skipping the watermark the website
///    stamps into every downloaded PDF.
library;

import '../../../core/utils/coerce.dart';

/// Material types the website filters by, in its tab order.
const List<String> kLibraryMaterialTypes = ['booklet', 'reference', 'guide'];

Map<String, dynamic> libraryAttributes(dynamic material) {
  if (material is! Map) return const {};
  final attrs = material['attributes'];
  if (attrs is Map) return Map<String, dynamic>.from(attrs);
  return Map<String, dynamic>.from(material);
}

String? libraryId(dynamic material) =>
    material is Map ? coerceId(material['id']) : null;

/// `isStudentLibraryPublished`: only an explicit `false` hides a material.
bool libraryIsPublished(dynamic material) =>
    coerceFlagOrNull(libraryAttributes(material)['is_publish']) != false;

/// Results of GET /v1/library?course_id= are already scoped by the server.
/// Do not require a singular course_id: materials can belong to many courses
/// or omit the course relation from the scoped response.
List<dynamic> publishedCourseLibraryItems(Iterable<dynamic> items) => items
    .whereType<Map>()
    .where(libraryIsPublished)
    .toList();

/// Locked until an activation code is redeemed — the website's rule.
bool libraryIsLocked(dynamic material) =>
    coerceFlag(libraryAttributes(material)['code_activation']);

String libraryTitle(dynamic material) =>
    coerceString(libraryAttributes(material)['title']) ?? '';

String libraryDescription(dynamic material) =>
    coerceString(libraryAttributes(material)['description'])?.trim() ?? '';

String libraryCover(dynamic material) =>
    coerceString(libraryAttributes(material)['cover_image'])?.trim() ?? '';

String libraryMaterialType(dynamic material) =>
    coerceString(libraryAttributes(material)['material_type']) ?? '';

/// Course ids joined the way the website's "Course #{id}" label shows them.
String libraryCourseIdsLabel(dynamic material) {
  final raw = libraryAttributes(material)['course_ids'];
  if (raw is List) {
    return raw.map((e) => e.toString()).where((e) => e.isNotEmpty).join(', ');
  }
  final single = coerceId(libraryAttributes(material)['course_id']);
  return single ?? '';
}

/// Course names from embedded relations, with resolved names for ID-only APIs.
String libraryCourseNamesLabel(dynamic material, {Map<String, String> resolvedNames = const {}}) {
  final attrs = libraryAttributes(material);
  final names = <String>{};
  final embedded = <String, String>{};
  void addCourse(dynamic course) {
    if (course is! Map) return;
    final data = course['data'] is Map ? course['data'] as Map : course;
    final details = data['attributes'] is Map ? data['attributes'] as Map : data;
    final title = coerceString(details['title'])?.trim();
    if (title == null || title.isEmpty) return;
    final id = coerceId(data['id']);
    if (id != null) embedded[id] = title;
    names.add(title);
  }
  final raw = attrs['courses'];
  final courses = raw is List ? raw : (raw is Map ? raw['data'] : null);
  if (courses is List) courses.forEach(addCourse);
  addCourse(attrs['course']);
  for (final id in libraryCourseIds(material)) {
    final title = embedded[id] ?? resolvedNames[id];
    if (title != null && title.trim().isNotEmpty) names.add(title.trim());
  }
  return names.join('، ');
}

/// Every course a material is attached to.
///
/// Admins attach a material to several courses at once, so the list endpoint
/// carries `course_ids` (the website's library card prints exactly this
/// field). The single `course_id` and a `courses` relation are read too for
/// older rows. The app used to scope by `course_id` alone, which is absent on
/// multi-course materials — the home preview came out empty and the full
/// library was never scoped at all.
List<String> libraryCourseIds(dynamic material) {
  final attrs = libraryAttributes(material);
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
      : (courses is Map && courses['data'] is List ? courses['data'] as List : null);
  courseList?.forEach(addId);

  addId(attrs['course_id']);
  final course = attrs['course'];
  if (course is Map) addId(course);

  if (material is Map && material['course_id'] != null) {
    addId(material['course_id']);
  }

  return ids.toList();
}

/// Price with two decimals, or the raw value when it is not numeric.
String libraryPriceLabel(dynamic material) {
  final raw = libraryAttributes(material)['price'];
  final parsed = double.tryParse(raw?.toString() ?? '0');
  if (parsed == null) return raw?.toString() ?? '—';
  return parsed.toStringAsFixed(2);
}

/// Attachments, unwrapped from either envelope the API uses.
List<Map<String, dynamic>> libraryAttachments(dynamic material) {
  final raw = libraryAttributes(material)['attachments'];
  final list = raw is List
      ? raw
      : raw is Map && raw['data'] is List
          ? raw['data'] as List
          : const [];
  return list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
}

Map<String, dynamic> attachmentAttributes(Map<String, dynamic> attachment) {
  final attrs = attachment['attributes'];
  return attrs is Map ? Map<String, dynamic>.from(attrs) : attachment;
}

String attachmentPath(Map<String, dynamic> attachment) =>
    coerceString(attachmentAttributes(attachment)['path'])?.trim() ?? '';

String attachmentName(Map<String, dynamic> attachment) =>
    coerceString(attachmentAttributes(attachment)['name']) ?? '';

String attachmentExtension(Map<String, dynamic> attachment) {
  final explicit =
      coerceString(attachmentAttributes(attachment)['extension'])?.trim();
  if (explicit != null && explicit.isNotEmpty) return explicit.toLowerCase();
  final path = attachmentPath(attachment).toLowerCase();
  final dot = path.lastIndexOf('.');
  return dot == -1 ? '' : path.substring(dot + 1);
}

bool attachmentIsPdf(Map<String, dynamic> attachment) =>
    attachmentExtension(attachment) == 'pdf';

/// The admin's "Downloadable" switch. Only an explicit true allows a download,
/// matching `downloadable === true` on the website.
bool attachmentIsDownloadable(Map<String, dynamic> attachment) =>
    coerceFlagOrNull(attachmentAttributes(attachment)['downloadable']) == true;

/// `formatLibraryAttachmentSize`: bytes to B / KB / MB, or an em dash.
String formatLibraryAttachmentSize(dynamic sizeRaw) {
  final n = int.tryParse(sizeRaw?.toString() ?? '');
  if (n == null || n < 0) return '—';
  if (n < 1024) return '$n B';
  if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} KB';
  return '${(n / 1024 / 1024).toStringAsFixed(1)} MB';
}

/// `librarySearchHaystack`: title, description, course ids and type.
bool libraryMatchesSearch(dynamic material, String query) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return true;
  final haystack = [
    libraryTitle(material),
    libraryDescription(material),
    libraryCourseIdsLabel(material),
    libraryMaterialType(material),
  ].join(' ').toLowerCase();
  return haystack.contains(needle);
}
