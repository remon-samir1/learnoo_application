import '../../../core/utils/coerce.dart';

/// Reads the student's academic selection out of `GET /v1/auth/me`.
///
/// Ported one-to-one from `src/lib/student-profile-completeness.ts`. Each id can
/// arrive either as a flat field (`university_id`) or as a JSON:API relation
/// (`university.data.id`), and the centre can additionally be inferred from the
/// faculty's parent — the app used to read only some of those shapes, so a
/// student with a complete profile could still be pushed back into onboarding.
class StudentProfile {
  const StudentProfile._(this._attributes);

  final Map<String, dynamic> _attributes;

  /// Builds from the `attributes` object of `/v1/auth/me`.
  factory StudentProfile.fromAttributes(Map<String, dynamic>? attributes) {
    return StudentProfile._(attributes ?? const {});
  }

  /// Builds from the full `data` node, unwrapping `attributes` when present.
  factory StudentProfile.fromData(Map<String, dynamic>? data) {
    if (data == null) return const StudentProfile._({});
    final attrs = data['attributes'];
    if (attrs is Map) {
      return StudentProfile._(Map<String, dynamic>.from(attrs));
    }
    return StudentProfile._(Map<String, dynamic>.from(data));
  }

  Map<String, dynamic> get attributes => _attributes;

  // ------------------------------------------------------------------
  // Identity
  // ------------------------------------------------------------------

  String get firstName => coerceString(_attributes['first_name']) ?? '';
  String get lastName => coerceString(_attributes['last_name']) ?? '';

  String get fullName {
    final explicit = coerceString(_attributes['full_name']);
    if (explicit != null) return explicit;
    final joined = '$firstName $lastName'.trim();
    return joined;
  }

  String? get phone => coerceString(_attributes['phone']);
  String? get email => coerceString(_attributes['email']);
  String? get imageUrl => coerceString(_attributes['image']);
  String? get studentCode => coerceString(_attributes['student_code']);
  String? get role => coerceString(_attributes['role']);

  bool get isPhoneVerified => _attributes['phone_verified_at'] != null;
  bool get isEmailVerified => _attributes['email_verified_at'] != null;

  // ------------------------------------------------------------------
  // Academic ids
  // ------------------------------------------------------------------

  String? get universityId {
    final flat = coerceId(_attributes['university_id']);
    if (flat != null) return flat;
    return coerceId(_relationId('university'));
  }

  String? get facultyId {
    final flat = coerceId(_attributes['faculty_id']);
    if (flat != null) return flat;
    return coerceId(_relationId('faculty'));
  }

  /// Centre id, in the same priority order as the web:
  /// `centers[0]` (scalar or relation), then the faculty's `parent_id`, then
  /// the faculty's `parent.data.id`.
  String? get centerId {
    final centers = _attributes['centers'];
    if (centers is List && centers.isNotEmpty) {
      final first = centers.first;
      if (first is num || first is String) {
        final id = coerceId(first);
        if (id != null) return id;
      }
      if (first is Map) {
        final nested = first['data'];
        if (nested is Map) {
          final id = coerceId(nested['id']);
          if (id != null) return id;
        }
        final direct = coerceId(first['id']);
        if (direct != null) return direct;
      }
    }

    final facultyAttrs = _relationAttributes('faculty');
    if (facultyAttrs != null) {
      final parentId = coerceId(facultyAttrs['parent_id']);
      if (parentId != null) return parentId;

      final parent = facultyAttrs['parent'];
      if (parent is Map && parent['data'] is Map) {
        final id = coerceId((parent['data'] as Map)['id']);
        if (id != null) return id;
      }
    }

    return null;
  }

  String? get departmentId {
    final flat = coerceId(_attributes['department_id']);
    if (flat != null) return flat;
    return coerceId(_relationId('department'));
  }

  /// All centre ids the student belongs to.
  List<String> get centerIds {
    final centers = _attributes['centers'];
    if (centers is! List) return const [];

    final out = <String>[];
    for (final item in centers) {
      if (item is num || item is String) {
        final id = coerceId(item);
        if (id != null) out.add(id);
        continue;
      }
      if (item is Map) {
        final nested = item['data'];
        if (nested is Map) {
          final id = coerceId(nested['id']);
          if (id != null) {
            out.add(id);
            continue;
          }
        }
        final direct = coerceId(item['id']);
        if (direct != null) out.add(direct);
      }
    }
    return out;
  }

  // ------------------------------------------------------------------
  // Display names
  // ------------------------------------------------------------------

  String? get universityName => _relationName('university');
  String? get facultyName => _relationName('faculty');
  String? get departmentName => _relationName('department');

  List<String> get centerNames {
    final centers = _attributes['centers'];
    if (centers is! List) return const [];
    final out = <String>[];
    for (final item in centers) {
      if (item is! Map) continue;
      final attrs = item['attributes'];
      if (attrs is Map) {
        final name = coerceString(attrs['name']);
        if (name != null) out.add(name);
      }
    }
    return out;
  }

  // ------------------------------------------------------------------
  // Completeness
  // ------------------------------------------------------------------

  /// Dashboard guard: university, centre and faculty must all resolve.
  ///
  /// Department is intentionally *not* required — the web gate checks these
  /// three, and requiring a fourth would lock out students who signed up
  /// before departments existed.
  bool get isAcademicProfileComplete =>
      universityId != null && centerId != null && facultyId != null;

  // ------------------------------------------------------------------
  // Relation helpers
  // ------------------------------------------------------------------

  dynamic _relationId(String key) {
    final relation = _attributes[key];
    if (relation is Map && relation['data'] is Map) {
      return (relation['data'] as Map)['id'];
    }
    return null;
  }

  Map<String, dynamic>? _relationAttributes(String key) {
    final relation = _attributes[key];
    if (relation is Map && relation['data'] is Map) {
      final attrs = (relation['data'] as Map)['attributes'];
      if (attrs is Map) return Map<String, dynamic>.from(attrs);
    }
    return null;
  }

  String? _relationName(String key) {
    final attrs = _relationAttributes(key);
    if (attrs == null) return null;
    return coerceString(attrs['name']);
  }
}
