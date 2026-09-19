import '../../../core/network/api_constants.dart';

/// Resolves a quiz / answer media value to an absolute URL.
///
/// Mirrors `resolveStudentExamMediaUrl` in the website
/// (`src/lib/student-exam-media.ts`): the API returns question images, answer
/// images and `reason_image` either as absolute URLs or as server-relative
/// paths (`/storage/...`). A relative path handed straight to
/// `CachedNetworkImage` has no host and never loads, which is why review
/// images stayed blank. Relative paths are prefixed with the API origin.
///
/// Returns `null` when there is no usable value.
String? resolveExamMediaUrl(dynamic raw) {
  dynamic value = raw;
  if (value is Map) {
    value = value['url'] ?? value['path'] ?? value['src'];
  }
  if (value == null) return null;
  final u = value.toString().trim().replaceAll('\\', '/');
  if (u.isEmpty || u == 'null') return null;
  if (RegExp(r'^https?://', caseSensitive: false).hasMatch(u)) return u;
  if (u.startsWith('//')) return 'https:$u';
  final base = ApiConstants.baseUrl.replaceAll(RegExp(r'/+$'), '');
  return u.startsWith('/') ? '$base$u' : '$base/$u';
}

/// First non-empty media URL among [keys] in [attributes].
String? readExamMediaUrl(Map attributes, List<String> keys) {
  for (final key in keys) {
    final resolved = resolveExamMediaUrl(attributes[key]);
    if (resolved != null) return resolved;
  }
  return null;
}
