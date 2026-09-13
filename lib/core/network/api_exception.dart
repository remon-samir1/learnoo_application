/// Unified API error, mirroring `ApiError` in the Next.js dashboard
/// (`src/lib/api.ts`). Replaces the six copies of `_handleError` that used to
/// live in the repositories.
class ApiException implements Exception {
  ApiException(this.status, this.message, [this.errors]);

  /// HTTP status code, or 0 for transport/parse failures.
  final int status;

  final String message;

  /// Laravel validation bag: `{ field: [msg, ...] }`.
  final Map<String, dynamic>? errors;

  bool get isUnauthorized => status == 401;
  bool get isForbidden => status == 403;
  bool get isValidation => status == 422 || (errors?.isNotEmpty ?? false);
  bool get isNetwork => status == 0;

  /// Flattened, human-readable message.
  ///
  /// Mirrors `getApiErrorMessage`: validation messages win over the generic
  /// `message` field, joined with " | ".
  String display([String fallback = 'Request failed']) {
    final bag = errors;
    if (bag != null && bag.isNotEmpty) {
      final parts = <String>[];
      bag.forEach((field, value) {
        if (value is List) {
          for (final item in value) {
            final s = item?.toString().trim() ?? '';
            if (s.isNotEmpty) parts.add(s);
          }
        } else {
          final s = value?.toString().trim() ?? '';
          if (s.isNotEmpty) parts.add(s);
        }
      });
      if (parts.isNotEmpty) return parts.join(' | ');
    }
    final m = message.trim();
    return m.isNotEmpty ? m : fallback;
  }

  /// Builds an exception from a decoded JSON error body.
  factory ApiException.fromBody(
    int status,
    dynamic body, {
    String fallback = 'Request failed',
  }) {
    if (body is! Map) {
      return ApiException(status, fallback);
    }

    final rawErrors = body['errors'];
    final Map<String, dynamic>? bag =
        rawErrors is Map ? Map<String, dynamic>.from(rawErrors) : null;

    final message = body['message']?.toString().trim();

    return ApiException(
      status,
      (message != null && message.isNotEmpty) ? message : fallback,
      bag,
    );
  }

  @override
  String toString() => 'ApiException($status): ${display()}';
}
