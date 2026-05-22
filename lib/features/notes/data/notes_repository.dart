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

  Future<Map<String, dynamic>> getNotes() async {
    final token = await _authRepository.getToken();
    if (token == null) return {'success': false, 'message': 'No token found'};

    final url = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.notes}');

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
          'message': _handleError(data, 'Failed to fetch notes'),
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  Future<Map<String, dynamic>> getNoteById(String id) async {
    final token = await _authRepository.getToken();
    if (token == null) return {'success': false, 'message': 'No token found'};

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
          'message': _handleError(data, 'Failed to fetch note details'),
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }
}
