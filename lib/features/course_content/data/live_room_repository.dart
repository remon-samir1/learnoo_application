import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../core/network/api_constants.dart';
import 'models/live_room.dart';

class LiveRoomRepository {
  final _storage = const FlutterSecureStorage();

  Future<String?> getToken() async {
    return await _storage.read(key: 'auth_token');
  }

  Future<Map<String, dynamic>> getLiveRooms({
    int page = 1,
    int perPage = 500,
    String? search,
    int? courseId,
  }) async {
    final token = await getToken();
    if (token == null) return {'success': false, 'message': 'No token found'};

    final queryParams = <String, String>{
      'page': page.toString(),
      'per_page': perPage.toString(),
      if (courseId != null) 'course_id': courseId.toString(),
      if (search != null && search.trim().isNotEmpty) ...{
        'title': search.trim(),
        'search': search.trim(),
      },
    };

    final url = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.liveRooms}')
        .replace(queryParameters: queryParams);

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
        final List<dynamic> liveRoomsData = data['data'] ?? [];
        final liveRooms =
            liveRoomsData.map((item) => LiveRoom.fromJson(item)).toList();
        final meta =
            data['meta'] is Map ? Map<String, dynamic>.from(data['meta']) : null;
        final links =
            data['links'] is Map ? Map<String, dynamic>.from(data['links']) : null;
        final hasNextPage = (links != null && links['next'] != null) ||
            (meta != null &&
                (meta['current_page'] ?? 1) < (meta['last_page'] ?? 1)) ||
            (perPage < 500 && liveRooms.length >= perPage);

        return {
          'success': true,
          'data': liveRooms,
          'meta': meta,
          'hasNextPage': hasNextPage,
        };
      } else {
        return {
          'success': false,
          'message': data['message'] ?? 'Failed to fetch live rooms',
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  Future<Map<String, dynamic>> getLiveRoomById(String roomId) async {
    final token = await getToken();
    if (token == null) return {'success': false, 'message': 'No token found'};

    final url = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.liveRooms}/$roomId');

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
        final liveRoom = LiveRoom.fromJson(data['data'] ?? {});
        return {'success': true, 'data': liveRoom};
      } else {
        return {
          'success': false,
          'message': data['message'] ?? 'Failed to fetch live room details',
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }
}
