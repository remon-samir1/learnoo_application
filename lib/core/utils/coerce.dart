/// Loose-value coercion helpers.
///
/// The API returns booleans inconsistently — `true`, `1`, `"1"`, `"true"`,
/// `"yes"` all mean the same thing. Flutter's `as bool?` cast silently yields
/// `null` (and therefore `false`) for every non-`bool` form, which is why
/// free-preview chapters used to appear locked. These mirror
/// `coercePreviewFlag` / `coerceCanWatchExplicitTrue` in
/// `src/lib/student-chapter-access.ts`.
library;

/// Permissive boolean read: accepts `true`, `1`, `"1"`, `"true"`, `"yes"`, `"on"`.
bool coerceFlag(dynamic value) {
  if (value == null) return false;
  if (value is bool) return value;
  if (value is num) return value == 1;
  if (value is String) {
    final s = value.trim().toLowerCase();
    if (s.isEmpty) return false;
    return s == 'true' || s == '1' || s == 'yes' || s == 'on';
  }
  return false;
}

/// Tri-state boolean read — `null` when the field is absent or unparseable.
bool? coerceFlagOrNull(dynamic value) {
  if (value == null) return null;
  if (value is bool) return value;
  if (value is num) {
    if (value == 1) return true;
    if (value == 0) return false;
    return null;
  }
  if (value is String) {
    final s = value.trim().toLowerCase();
    if (s.isEmpty) return null;
    if (s == 'true' || s == '1' || s == 'yes' || s == 'on') return true;
    if (s == 'false' || s == '0' || s == 'no' || s == 'off') return false;
  }
  return null;
}

/// Strict read used for `can_watch`: only an explicit truthy value unlocks.
///
/// The backend sends `can_watch: false` when views are exhausted, and omits it
/// in some payloads — an omission must never be read as permission.
bool coerceCanWatchExplicitTrue(dynamic value) {
  if (value == true) return true;
  if (value is num && value == 1) return true;
  if (value is String) {
    final s = value.trim().toLowerCase();
    return s == 'true' || s == '1';
  }
  return false;
}

/// Positive integer or `null`. Accepts numeric strings.
int? coercePositiveInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value > 0 ? value : null;
  if (value is num) {
    final n = value.toInt();
    return n > 0 ? n : null;
  }
  if (value is String) {
    final n = int.tryParse(value.trim());
    return (n != null && n > 0) ? n : null;
  }
  return null;
}

/// Non-negative integer or `null`. Accepts numeric strings.
int? coerceNonNegativeInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value >= 0 ? value : null;
  if (value is num) {
    final n = value.toInt();
    return n >= 0 ? n : null;
  }
  if (value is String) {
    final n = int.tryParse(value.trim());
    return (n != null && n >= 0) ? n : null;
  }
  return null;
}

/// Integer with a default, for fields the UI must always render.
int coerceInt(dynamic value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim()) ?? fallback;
  return fallback;
}

/// Stringified id, `null` for absent/blank. Trims and drops decimal noise.
String? coerceId(dynamic value) {
  if (value == null) return null;
  if (value is int) return value.toString();
  if (value is num) return value.toInt().toString();
  final s = value.toString().trim();
  return s.isEmpty ? null : s;
}

/// Trimmed string, `null` when blank.
String? coerceString(dynamic value) {
  if (value == null) return null;
  final s = value.toString().trim();
  return s.isEmpty ? null : s;
}
