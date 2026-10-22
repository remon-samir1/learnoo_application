import 'package:easy_localization/easy_localization.dart';

/// Unified API error, mirroring `ApiError` in the Next.js dashboard
/// (`src/lib/api.ts`). Replaces the six copies of `_handleError` that used to
/// live in the repositories.
class ApiException implements Exception {
  ApiException(
    this.status,
    this.message, [
    this.errors,
    this.code,
    this.transferToken,
  ]);

  /// HTTP status code, or 0 for transport/parse failures.
  final int status;

  final String message;

  /// Laravel validation bag: `{ field: [msg, ...] }`.
  final Map<String, dynamic>? errors;

  /// Machine-readable error key the backend sends alongside `message`, e.g.
  /// `device_transfer_required` when this device is not the approved one, or
  /// `device_session_revoked` on a 401 after staff moved the account to
  /// another device. Mirrors `ApiError.code` in `src/lib/api.ts`.
  final String? code;

  /// One-shot token from a `device_transfer_required` body (`transfer_token`),
  /// replayed to `POST /v1/auth/device-transfer` to ask staff for approval.
  final String? transferToken;

  bool get isUnauthorized => status == 401;
  bool get isForbidden => status == 403;
  bool get isValidation => status == 422 || (errors?.isNotEmpty ?? false);
  bool get isNetwork => status == 0;

  /// Flattened, human-readable message.
  ///
  /// Mirrors `getApiErrorMessage`: validation messages win over the generic
  /// `message` field, joined with " | ".
  String display([String? fallback]) {
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
    return m.isNotEmpty ? m : (fallback ?? 'errors.request_failed'.tr());
  }

  /// Builds an exception from a decoded JSON error body.
  factory ApiException.fromBody(
    int status,
    dynamic body, {
    String? fallback,
  }) {
    final fallbackMessage = fallback ?? 'errors.request_failed'.tr();
    if (body is! Map) {
      return ApiException(status, fallbackMessage);
    }

    final rawErrors = body['errors'];
    final Map<String, dynamic>? bag =
        rawErrors is Map ? Map<String, dynamic>.from(rawErrors) : null;

    final message = body['message']?.toString().trim();
    final code = body['code']?.toString().trim();
    final transferToken = body['transfer_token']?.toString().trim();

    return ApiException(
      status,
      (message != null && message.isNotEmpty) ? message : fallbackMessage,
      bag,
      (code != null && code.isNotEmpty) ? code : null,
      (transferToken != null && transferToken.isNotEmpty)
          ? transferToken
          : null,
    );
  }

  @override
  String toString() => 'ApiException($status): ${display()}';
}
