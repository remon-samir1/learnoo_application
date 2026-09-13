import 'dart:io';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_constants.dart';
import '../../../core/network/api_exception.dart';

/// Support tickets — `POST /v1/issues`.
///
/// The web has a support form at `/student/support` (`IssuesForm.tsx`); the app
/// had no equivalent, so a student on mobile had no in-app way to report a
/// problem.
class IssueRepository {
  final ApiClient _api = ApiClient();

  Map<String, dynamic> _fail(Object error, String fallback) {
    if (error is ApiException) {
      return {
        'success': false,
        'message': error.display(fallback),
        'errors': error.errors,
      };
    }
    return {'success': false, 'message': fallback};
  }

  /// Files a support ticket. [attachment] is optional (a screenshot of the
  /// problem), and switches the request to multipart when present.
  Future<Map<String, dynamic>> createIssue({
    required String title,
    required String description,
    String? type,
    File? attachment,
  }) async {
    try {
      final dynamic payload;

      if (attachment != null) {
        payload = await _api.multipart(
          ApiConstants.issues,
          fields: {
            'title': title,
            'description': description,
            if (type != null && type.isNotEmpty) 'type': type,
          },
          files: {'image': attachment.path},
          fallback: 'Failed to submit your report',
        );
      } else {
        payload = await _api.post(
          ApiConstants.issues,
          body: {
            'title': title,
            'description': description,
            if (type != null && type.isNotEmpty) 'type': type,
          },
          fallback: 'Failed to submit your report',
        );
      }

      return {
        'success': true,
        'data': payload is Map ? payload['data'] : null,
        'message': payload is Map ? payload['message'] : null,
      };
    } catch (e) {
      return _fail(e, 'Failed to submit your report');
    }
  }

  /// The student's own tickets.
  Future<Map<String, dynamic>> getIssues() async {
    try {
      final payload = await _api.get(
        ApiConstants.issues,
        fallback: 'Failed to load your reports',
      );
      return {'success': true, 'data': unwrapList(payload)};
    } catch (e) {
      return _fail(e, 'Failed to load your reports');
    }
  }
}
