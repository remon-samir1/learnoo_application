import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../../../core/network/api_constants.dart';

class SearchRepository {
  final _storage = const FlutterSecureStorage();

  Future<String?> getToken() async {
    return await _storage.read(key: 'auth_token');
  }

  Future<Map<String, dynamic>> search({
    required String query,
    String? type,
    int limit = 10,
  }) async {
    try {
      final token = await getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      // Build query parameters
      final queryParams = <String, String>{
        'q': query,
        'limit': limit.toString(),
      };

      if (type != null && type.isNotEmpty) {
        queryParams['type'] = type;
      }

      final uri = Uri.parse('${ApiConstants.baseUrl}/v1/search')
          .replace(queryParameters: queryParams);

      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'success': true,
          'data': data['data'] ?? [],
          'meta': data['meta'] ?? {},
        };
      } else if (response.statusCode == 401) {
        return {'success': false, 'message': 'Unauthorized'};
      } else {
        return {'success': false, 'message': 'Search failed'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }
}
