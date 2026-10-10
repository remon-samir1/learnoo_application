import 'package:easy_localization/easy_localization.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../core/network/api_constants.dart';
import '../../auth/data/auth_repository.dart';

class NotesRepository {
  final _authRepository = AuthRepository();

  String _handleError(dynamic data, String defaultMessage) {
    if (data == null) return defaultMessage;

    if (data['message'] != null) {
      return data['message'].toString();
    }

    if (data['errors'] != null && data['errors'] is Map) {
      final errors = data['errors'] as Map<String, dynamic>;
      return errors.values
          .map((e) {
            if (e is List) return e.join(', ');
            return e.toString();
          })
          .join('\n');
    }

    return defaultMessage;
  }

  /// `GET /v1/note`, optionally scoped to one course.
  Future<Map<String, dynamic>> getNotes({int? courseId}) async {
    final token = await _authRepository.getToken();
    if (token == null) return {'success': false, 'message': 'errors.no_token'.tr()};

    final url = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.notes}')
        .replace(
      queryParameters:
          courseId == null ? null : {'course_id': courseId.toString()},
    );

    try {
      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {
          'success': true,
          'data': data['data'] ?? [],
        };
      } else {
        return {
          'success': false,
          'message': _handleError(data, 'errors.failed_fetch_notes'.tr()),
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'course.connection_error'.tr(args: ['$e'])};
    }
  }

  Future<Map<String, dynamic>> getNoteById(String id) async {
    final token = await _authRepository.getToken();
    if (token == null) return {'success': false, 'message': 'errors.no_token'.tr()};

    final url = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.notes}/$id');

    try {
      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {
          'success': true,
          'data': data['data'],
        };
      } else {
        return {
          'success': false,
          'message': _handleError(data, 'errors.failed_fetch_note_details'.tr()),
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'course.connection_error'.tr(args: ['$e'])};
    }
  }
}
