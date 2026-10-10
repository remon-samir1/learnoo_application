import 'package:easy_localization/easy_localization.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../core/network/api_client.dart';
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
    if (token == null) return {'success': false, 'message': 'errors.no_token'.tr()};

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
            'message': data['message'] ?? 'errors.failed_fetch_courses'.tr(),
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
    if (token == null) return {'success': false, 'message': 'errors.no_token'.tr()};

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
          final activated = data['data'];
          if (activated is! List || activated.isEmpty) {
            return {'success': true, 'data': activated};
          }
          final catalogue = await _fetchCatalogue(token);
          return {
            'success': true,
            'data': mergeActivatedWithCatalogue(activated, catalogue),
          };
        } else {
          return {
            'success': false,
            'message': data['message'] ?? 'errors.failed_fetch_activated_courses'.tr(),
          };
        }
      },
      boxName: HiveBoxes.courses,
      // v2: rows cached before the catalogue merge have no cover image.
      cacheKey: 'courses_activated_v2',
      maxCacheAge: const Duration(hours: 24),
    );
  }

  /// `GET /v1/course?per_page=500` — the list the website's student course
  /// pages render from (`STUDENT_COURSES_LIST_PARAMS`). Empty on failure, so
  /// the activated rows are still shown as they are.
  Future<List<dynamic>> _fetchCatalogue(String token) async {
    try {
      final url = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.courses}')
          .replace(queryParameters: {'per_page': '500'});
      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      if (response.statusCode != 200) return const [];
      final data = jsonDecode(response.body);
      final rows = data is Map ? data['data'] : null;
      return rows is List ? rows : const [];
    } catch (_) {
      return const [];
    }
  }

  /// Fields the website reads the course cover from.
  static const _imageKeys = ['thumbnail', 'image', 'cover_image'];

  /// Fills each activated course with the catalogue row of the same id.
  ///
  /// `?activated=1` decides *which* courses the student has, but its rows can
  /// come back without the cover (the website stopped rendering from it for
  /// that reason). The catalogue row supplies the cover and any other field
  /// the activated row leaves empty; the activated row's own values win
  /// otherwise, so enrolment state is unchanged.
  static List<dynamic> mergeActivatedWithCatalogue(
    List<dynamic> activated,
    List<dynamic> catalogue,
  ) {
    if (catalogue.isEmpty) return activated;

    final byId = <String, Map>{};
    for (final row in catalogue) {
      if (row is Map && row['id'] != null) byId[row['id'].toString()] = row;
    }

    bool isEmpty(dynamic v) =>
        v == null || (v is String && (v.trim().isEmpty || v.trim() == 'null'));

    return activated.map((row) {
      if (row is! Map) return row;
      final match = byId[row['id']?.toString()];
      if (match == null) return row;

      final own = row['attributes'] is Map
          ? Map<String, dynamic>.from(row['attributes'] as Map)
          : <String, dynamic>{};
      final other = match['attributes'] is Map
          ? Map<String, dynamic>.from(match['attributes'] as Map)
          : <String, dynamic>{};

      final merged = Map<String, dynamic>.from(own);
      other.forEach((key, value) {
        final preferCatalogue = _imageKeys.contains(key) && !isEmpty(value);
        if (preferCatalogue || isEmpty(merged[key])) merged[key] = value;
      });

      return {...Map<String, dynamic>.from(row), 'attributes': merged};
    }).toList();
  }

  /// Get course by ID with offline-first support
  /// Returns cached course data if offline or API fails
  Future<Map<String, dynamic>> getCourseById(String courseId) async {
    final token = await getToken();
    if (token == null) return {'success': false, 'message': 'errors.no_token'.tr()};

    return offlineFirstFetch(
      apiFetcher: () async {
        final url = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.courses}/$courseId');
        final response = await http.get(
          url,
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'Authorization': 'Bearer $token',
            'lang': ApiClient.locale,
          },
        ).timeout(const Duration(seconds: 15));

        final data = jsonDecode(response.body);
        if (response.statusCode == 200) {
          return {'success': true, 'data': data['data']};
        } else {
          return {
            'success': false,
            'message': data['message'] ?? 'errors.failed_fetch_course_details'.tr(),
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
