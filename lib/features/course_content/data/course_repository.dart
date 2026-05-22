import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../core/network/api_constants.dart';
import '../../../core/offline/offline_first_repository.dart';
import '../../../core/local/hive_boxes.dart';

/// Repository for course data with offline-first support
/// Combines API calls with local caching for seamless offline experience
class CourseRepository with OfflineFirstRepository {
  final _storage = const FlutterSecureStorage();

  Future<String?> getToken() async {
    return await _storage.read(key: 'auth_token');
  }

  /// Get all courses with offline-first support
  /// Returns cached data if offline or API fails
  Future<Map<String, dynamic>> getCourses({int? categoryId, String? include}) async {
    final token = await getToken();
    if (token == null) return {'success': false, 'message': 'No token found'};

    final cacheKey = categoryId != null ? 'courses_category_$categoryId' : 'courses_all';

    return offlineFirstFetch(
      apiFetcher: () async {
        var url = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.courses}');
        final queryParams = <String, String>{};

        // Add category_id query parameter if provided
        if (categoryId != null) {
          queryParams['category_id'] = categoryId.toString();
        }

        // Add include query parameter if provided
        if (include != null && include.isNotEmpty) {
          queryParams['include'] = include;
        }

        if (queryParams.isNotEmpty) {
          url = url.replace(queryParameters: queryParams);
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
            'message': data['message'] ?? 'Failed to fetch courses',
          };
        }
      },
      boxName: HiveBoxes.courses,
      cacheKey: cacheKey,
      maxCacheAge: const Duration(hours: 24),
    );
  }

  /// Get activated (enrolled) courses for the current student
  /// Uses the activated=1 query parameter to filter courses
  Future<Map<String, dynamic>> getActivatedCourses() async {
    final token = await getToken();
    if (token == null) return {'success': false, 'message': 'No token found'};

    return offlineFirstFetch(
      apiFetcher: () async {
        final url = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.courses}')
            .replace(queryParameters: {'activated': '1'});

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
            'message': data['message'] ?? 'Failed to fetch activated courses',
          };
        }
      },
      boxName: HiveBoxes.courses,
      cacheKey: 'courses_activated',
      maxCacheAge: const Duration(hours: 24),
    );
  }

  /// Get course by ID with offline-first support
  /// Returns cached course data if offline or API fails
  Future<Map<String, dynamic>> getCourseById(String courseId) async {
    final token = await getToken();
    if (token == null) return {'success': false, 'message': 'No token found'};

    return offlineFirstFetch(
      apiFetcher: () async {
        final url = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.courses}/$courseId');
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
            'message': data['message'] ?? 'Failed to fetch course details',
          };
        }
      },
      boxName: HiveBoxes.courses,
      cacheKey: 'course_$courseId',
      maxCacheAge: const Duration(hours: 24),
    );
  }

  /// Get cached courses for a specific category
  List<dynamic> getCachedCourses({int? categoryId}) {
    final allCourses = getAllCached(HiveBoxes.courses);
    if (categoryId == null) return allCourses;

    // Filter by category_id if needed
    return allCourses.where((course) {
      final data = _extractCourseData(course);
      return data?['category_id'] == categoryId;
    }).toList();
  }

  /// Get single cached course by ID
  dynamic getCachedCourseById(String courseId) {
    return getCached(HiveBoxes.courses, 'course_$courseId');
  }

  /// Check if we have cached courses
  bool hasCachedCourses() {
    final stats = getCacheStats(HiveBoxes.courses);
    return stats['valid'] > 0;
  }

  /// Extract course data from cached entry (handles both raw and timestamp-wrapped data)
  Map<String, dynamic>? _extractCourseData(dynamic course) {
    if (course is Map<String, dynamic>) {
      // Check if it's wrapped with timestamp
      if (course.containsKey('data')) {
        return course['data'] as Map<String, dynamic>?;
      }
      return course;
    }
    return null;
  }
}
