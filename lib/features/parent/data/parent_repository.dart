import '../../../core/network/api_client.dart';
import '../../../core/network/api_constants.dart';
import '../../../core/network/api_exception.dart';

/// Parent-side API surface.
///
/// One-to-one with `parentApi` in `src/lib/api.ts`: linking children by their
/// student code, then reading the per-child dashboard, activity and alerts.
class ParentRepository {
  ParentRepository({ApiClient? api}) : _api = api ?? ApiClient();

  final ApiClient _api;

  /// `POST /v1/parent/students` with a single student code.
  Future<Map<String, dynamic>> linkStudent(String studentCode) async {
    try {
      final payload = await _api.post(
        ApiConstants.parentStudents,
        body: {'student_code': studentCode},
        fallback: 'Failed to link the student',
      );
      return {
        'success': true,
        'message': _message(payload, 'Student linked successfully'),
        'data': payload is Map ? payload['data'] : null,
      };
    } catch (e) {
      return _fail(e, 'Failed to link the student');
    }
  }

  /// `POST /v1/parent/students` with a list of codes, the shape the web's
  /// link-student page sends.
  Future<Map<String, dynamic>> linkStudents(List<String> codes) async {
    try {
      final payload = await _api.post(
        ApiConstants.parentStudents,
        body: {'codes': codes},
        fallback: 'Failed to link the students',
      );
      return {
        'success': true,
        'message': _message(payload, 'Students linked successfully'),
        'data': payload is Map ? payload['data'] : null,
      };
    } catch (e) {
      return _fail(e, 'Failed to link the students');
    }
  }

  /// `GET /v1/parent/students` — the children on this parent account.
  Future<Map<String, dynamic>> linkedStudents() =>
      _list(ApiConstants.parentStudents, 'Failed to load linked students');

  Future<Map<String, dynamic>> studentDashboard(Object id) =>
      _object(ApiConstants.parentStudentDashboard(id), 'Failed to load the dashboard');

  Future<Map<String, dynamic>> studentProgress(Object id) =>
      _object(ApiConstants.parentStudentProgress(id), 'Failed to load progress');

  Future<Map<String, dynamic>> studentWeeklyStats(Object id) => _object(
        ApiConstants.parentStudentWeeklyStats(id),
        'Failed to load weekly stats',
      );

  Future<Map<String, dynamic>> studentAlerts(Object id) =>
      _list(ApiConstants.parentStudentAlerts(id), 'Failed to load alerts');

  Future<Map<String, dynamic>> studentFeedback(Object id) =>
      _list(ApiConstants.parentStudentFeedback(id), 'Failed to load feedback');

  Future<Map<String, dynamic>> studentActivity(Object id) =>
      _list(ApiConstants.parentStudentActivity(id), 'Failed to load activity');

  // ------------------------------------------------------------------

  Future<Map<String, dynamic>> _object(String path, String fallback) async {
    try {
      final payload = await _api.get(path, fallback: fallback);
      // The dashboard endpoint answers with the payload at the top level;
      // the others wrap it in `data`. The web accepts both, so this does too.
      final map = payload is Map ? Map<String, dynamic>.from(payload) : <String, dynamic>{};
      final inner = map['data'];
      return {
        'success': true,
        'data': inner is Map ? Map<String, dynamic>.from(inner) : map,
      };
    } catch (e) {
      return _fail(e, fallback);
    }
  }

  Future<Map<String, dynamic>> _list(String path, String fallback) async {
    try {
      final payload = await _api.get(path, fallback: fallback);
      return {'success': true, 'data': _extractList(payload)};
    } catch (e) {
      return _fail(e, fallback);
    }
  }

  /// Pulls the rows out of whichever envelope the endpoint used:
  /// a bare list, `{data: []}`, `{alerts: []}`, `{activities: []}` or
  /// `{feedback: []}` — the same fallback chain the web dashboard walks.
  static List<dynamic> _extractList(dynamic payload) {
    if (payload is List) return payload;
    if (payload is! Map) return const [];
    for (final key in const ['data', 'alerts', 'activities', 'feedback', 'items']) {
      final value = payload[key];
      if (value is List) return value;
    }
    return const [];
  }

  static String _message(dynamic payload, String fallback) {
    if (payload is Map && payload['message'] != null) {
      return payload['message'].toString();
    }
    return fallback;
  }

  static Map<String, dynamic> _fail(Object error, String fallback) {
    if (error is ApiException) {
      return {
        'success': false,
        'message': error.display(fallback),
        'errors': error.errors,
        'statusCode': error.status,
      };
    }
    return {'success': false, 'message': fallback, 'statusCode': 0};
  }
}
