import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../core/network/api_constants.dart';

class LibraryRepository {
  final _storage = const FlutterSecureStorage();

  Future<String?> getToken() async {
    return await _storage.read(key: 'auth_token');
  }

  /// `GET /v1/library`, optionally scoped to one course.
  ///
  /// [courseId] mirrors `getCourseLibrary` on the web, which the course
  /// details page's Library tab calls with `?course_id=`.
  Future<Map<String, dynamic>> getLibraries({int? courseId}) async {
    final token = await getToken();
    if (token == null) return {'success': false, 'message': 'No token found'};

    final url = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.libraries}')
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
        return {'success': true, 'data': data['data'] ?? []};
      } else {
        return {
          'success': false,
          'message': data['message'] ?? 'Failed to fetch libraries',
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  /// `GET /v1/library/{id}` — the detail page's source, like `useLibrary` on
  /// the website. Returns the material itself so its lock and attachment
  /// flags are current rather than whatever the list happened to cache.
  Future<Map<String, dynamic>> getLibraryById(String id) async {
    final token = await getToken();
    if (token == null) return {'success': false, 'message': 'No token found'};

    final url = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.libraries}/$id');
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
      if (response.statusCode == 200 && data is Map) {
        return {'success': true, 'data': data['data']};
      }
      return {
        'success': false,
        'message': data is Map ? data['message'] : null,
        'statusCode': response.statusCode,
      };
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  Future<Map<String, dynamic>> activateCode({
    required String code,
    required int itemId,
    required String itemType,
  }) async {
    final token = await getToken();
    if (token == null) return {'success': false, 'message': 'No token found'};

    final url = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.codeActivate}');
    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'code': code,
          'item_id': itemId,
          'item_type': itemType,
        }),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {'success': true, 'data': data['data']};
      } else {
        return {
          'success': false,
          'message': data['message'] ?? 'Invalid activation code',
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }
}
