import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../core/network/api_constants.dart';
import '../../../core/offline/offline_first_repository.dart';
import '../../../core/local/hive_boxes.dart';

class LectureRepository with OfflineFirstRepository {
  final _storage = const FlutterSecureStorage();

  Future<String?> getToken() async {
    return await _storage.read(key: 'auth_token');
  }

  /// Get lectures with offline-first support
  Future<Map<String, dynamic>> getLectures({int? courseId}) async {
    final token = await getToken();
    if (token == null) return {'success': false, 'message': 'No token found'};

    final cacheKey = courseId != null ? 'lectures_course_$courseId' : 'lectures_all';

    return offlineFirstFetch(
      apiFetcher: () async {
        var url = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.lectures}');

        // Add course_id query parameter if provided
        if (courseId != null) {
          url = url.replace(queryParameters: {
            ...url.queryParameters,
            'course_id': courseId.toString(),
          });
        }

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
          return {'success': true, 'data': data['data']};
        } else {
          return {
            'success': false,
            'message': data['message'] ?? 'Failed to fetch lectures',
          };
        }
      },
      boxName: HiveBoxes.lectures,
      cacheKey: cacheKey,
      maxCacheAge: const Duration(hours: 24),
    );
  }

  /// Get lecture by ID with offline-first support
  Future<Map<String, dynamic>> getLectureById(String lectureId) async {
    final token = await getToken();
    if (token == null) return {'success': false, 'message': 'No token found'};

    return offlineFirstFetch(
      apiFetcher: () async {
        final url = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.lectures}/$lectureId');
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
          return {'success': true, 'data': data['data']};
        } else {
          return {
            'success': false,
            'message': data['message'] ?? 'Failed to fetch lecture details',
          };
        }
      },
      boxName: HiveBoxes.lectures,
      cacheKey: 'lecture_$lectureId',
      maxCacheAge: const Duration(hours: 24),
    );
  }

  /// Get cached lectures for a course
  List<dynamic> getCachedLectures({int? courseId}) {
    if (courseId != null) {
      final allLectures = getAllCached(HiveBoxes.lectures);
      // Filter by course_id if needed
      return allLectures.where((lecture) {
        final data = _extractLectureData(lecture);
        return data?['course_id'] == courseId;
      }).toList();
    }
    return getAllCached(HiveBoxes.lectures);
  }

  /// Get single cached lecture by ID
  dynamic getCachedLectureById(String lectureId) {
    return getCached(HiveBoxes.lectures, 'lecture_$lectureId');
  }

  /// Check if we have cached lectures
  bool hasCachedLectures() {
    final stats = getCacheStats(HiveBoxes.lectures);
    return stats['valid'] > 0;
  }

  /// Extract lecture data from cached entry (handles both raw and timestamp-wrapped data)
  Map<String, dynamic>? _extractLectureData(dynamic lecture) {
    if (lecture is Map<String, dynamic>) {
      // Check if it's wrapped with timestamp
      if (lecture.containsKey('data')) {
        return lecture['data'] as Map<String, dynamic>?;
      }
      return lecture;
    }
    return null;
  }
}
