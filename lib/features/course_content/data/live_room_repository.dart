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

  Future<Map<String, dynamic>> getLiveRooms({int? courseId}) async {
    final token = await getToken();
    if (token == null) return {'success': false, 'message': 'No token found'};

    var urlString = '${ApiConstants.baseUrl}${ApiConstants.liveRooms}';
    if (courseId != null) {
      urlString += '?course_id=$courseId';
    }

    final url = Uri.parse(urlString);

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
        final liveRooms = liveRoomsData.map((item) => LiveRoom.fromJson(item)).toList();
        return {'success': true, 'data': liveRooms};
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
