import '../network/api_constants.dart';

/// Turns an API media value into a URL an image widget can load.
///
/// Course `thumbnail` and department `image` arrive as absolute URLs on
/// `api.learnoo.app` most of the time, but some records carry a
/// server-relative path (`/storage/...`), a `{url|path}` object, or the
/// literal string "null". Handed to an image widget as-is those never load,
/// which left cards blank where the website shows the picture.
///
/// Returns `null` when there is no usable value.
String? resolveMediaUrl(dynamic raw) {
  dynamic value = raw;
  if (value is Map) {
    value = value['url'] ?? value['original_url'] ?? value['path'] ?? value['src'];
  }
  if (value is List) {
    for (final item in value) {
      final resolved = resolveMediaUrl(item);
      if (resolved != null) return resolved;
    }
    return null;
  }
  if (value == null) return null;

  final u = value.toString().trim().replaceAll('\\', '/');
  if (u.isEmpty || u == 'null' || u == 'undefined') return null;
  if (RegExp(r'^https?://', caseSensitive: false).hasMatch(u)) return u;
  if (u.startsWith('//')) return 'https:$u';

  final base = ApiConstants.baseUrl.replaceAll(RegExp(r'/+$'), '');
  return u.startsWith('/') ? '$base$u' : '$base/$u';
}

/// First usable media URL among [keys] of [attributes].
String? readMediaUrl(dynamic attributes, List<String> keys) {
  if (attributes is! Map) return null;
  for (final key in keys) {
    final resolved = resolveMediaUrl(attributes[key]);
    if (resolved != null) return resolved;
  }
  return null;
}
