import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../core/network/api_constants.dart';
import '../../../core/offline/offline_first_repository.dart';
import '../../../core/local/hive_boxes.dart';
import '../../../core/local/models/pending_action.dart';

class ChapterRepository with OfflineFirstRepository {
  final _storage = const FlutterSecureStorage();

  /// Stores auth error data when API returns 403/401
  /// This allows offlineFirstFetch to return real server error instead of stale cache
  Map<String, dynamic>? _authErrorData;

  Future<String?> getToken() async {
    return await _storage.read(key: 'auth_token');
  }

  /// Get all chapters with offline-first support
  Future<Map<String, dynamic>> getChapters({int? courseId}) async {
    final token = await getToken();
    if (token == null) return {'success': false, 'message': 'No token found'};

    final cacheKey = courseId != null
        ? 'chapters_course_$courseId'
        : 'chapters_all';

    return offlineFirstFetch(
      apiFetcher: () async {
        var url = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.chapters}');

        if (courseId != null) {
          url = url.replace(
            queryParameters: {
              ...url.queryParameters,
              'course_id': courseId.toString(),
            },
          );
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
          return {'success': true, 'data': data['data'] ?? []};
        } else {
          return {
            'success': false,
            'message': data['message'] ?? 'Failed to fetch chapters',
          };
        }
      },
      boxName: HiveBoxes.chapters,
      cacheKey: cacheKey,
      maxCacheAge: const Duration(hours: 24),
    );
  }

  /// Get chapter by ID with offline-first support
  Future<Map<String, dynamic>> getChapterById(String chapterId) async {
    final token = await getToken();
    if (token == null) return {'success': false, 'message': 'No token found'};

    // Clear any previous auth error data
    _authErrorData = null;

    final result = await offlineFirstFetch(
      apiFetcher: () async {
        final url = Uri.parse(
          '${ApiConstants.baseUrl}${ApiConstants.chapters}/$chapterId',
        );
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
        } else if (response.statusCode == 403 || response.statusCode == 401) {
          // Save error data and throw simple string to prevent cache fallback
          _authErrorData = {
            'statusCode': response.statusCode,
            'message': data['message'] ?? 'Access denied',
            'max_views': data['max_views'],
            'current_views': data['current_views'],
          };
          throw 'AUTH_ERROR';
        } else {
          return {
            'success': false,
            'message': data['message'] ?? 'Failed to fetch chapter details',
            'max_views': data['max_views'],
            'current_views': data['current_views'],
            'statusCode': response.statusCode,
          };
        }
      },
      boxName: HiveBoxes.chapters,
      cacheKey: 'chapter_$chapterId',
      maxCacheAge: const Duration(hours: 24),
    );

    // If auth error occurred, return the real server error data instead of cached result
    if (_authErrorData != null) {
      return {
        'success': false,
        'message': _authErrorData!['message'],
        'max_views': _authErrorData!['max_views'],
        'current_views': _authErrorData!['current_views'],
        'statusCode': _authErrorData!['statusCode'],
        'authorizationError': true,
        'fromCache': false,
        'offline': false,
      };
    }

    return result;
  }

  Future<Map<String, dynamic>> activateCode({
    required String code,
    required int itemId,
    required String itemType,
  }) async {
    final token = await getToken();
    if (token == null) return {'success': false, 'message': 'No token found'};

    final url = Uri.parse(
      '${ApiConstants.baseUrl}${ApiConstants.codeActivate}',
    );
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

  /// Get user progress with offline-first support
  Future<Map<String, dynamic>> getUserProgress() async {
    final token = await getToken();
    if (token == null) return {'success': false, 'message': 'No token found'};

    return offlineFirstFetch(
      apiFetcher: () async {
        final url = Uri.parse(
          '${ApiConstants.baseUrl}${ApiConstants.userProgress}',
        );
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
            'message': data['message'] ?? 'Failed to fetch user progress',
          };
        }
      },
      boxName: HiveBoxes.progress,
      cacheKey: 'user_progress',
      maxCacheAge: const Duration(hours: 1), // Progress changes frequently
    );
  }

  /// Update user progress with offline queue support
  /// When offline, the update is queued and synced when connection is restored
  Future<Map<String, dynamic>> updateUserProgress({
    required int chapterId,
    required int progressSeconds,
    required bool isCompleted,
  }) async {
    final token = await getToken();
    if (token == null) return {'success': false, 'message': 'No token found'};

    final payload = {
      'chapter_id': chapterId,
      'progress_seconds': progressSeconds,
      'is_completed': isCompleted,
    };

    // Try to queue the action
    final queueResult = await queueAction(
      actionType: PendingActionTypes.progress,
      payload: payload,
      optimisticId: 'progress_$chapterId',
      deduplicate: true, // Only keep latest progress for each chapter
    );

    // If not queued (we're online), execute immediately
    if (!queueResult['queued']) {
      try {
        final url = Uri.parse(
          '${ApiConstants.baseUrl}${ApiConstants.userProgress}',
        );
        final response = await http.post(
          url,
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode(payload),
        );

        final data = jsonDecode(response.body);
        if (response.statusCode == 200 || response.statusCode == 201) {
          return {
            'success': true,
            'data': data['data'],
            'offline': false,
            'queued': false,
          };
        } else {
          // API failed, queue for retry
          await queueAction(
            actionType: PendingActionTypes.progress,
            payload: payload,
            optimisticId: 'progress_$chapterId',
            deduplicate: true,
          );
          return {
            'success': true, // Optimistic success
            'offline': false,
            'queued': true,
            'message': 'Progress saved locally, will sync when online',
          };
        }
      } catch (e) {
        // Network error, queue for retry
        await queueAction(
          actionType: PendingActionTypes.progress,
          payload: payload,
          optimisticId: 'progress_$chapterId',
          deduplicate: true,
        );
        return {
          'success': true, // Optimistic success
          'offline': true,
          'queued': true,
          'message': 'Progress saved locally, will sync when online',
        };
      }
    }

    // Action was queued (offline mode)
    return {
      'success': true,
      'offline': true,
      'queued': true,
      'actionId': queueResult['actionId'],
      'message': 'Progress saved locally, will sync when online',
    };
  }

  /// Get cached chapters for a course
  List<dynamic> getCachedChapters() {
    return getAllCached(HiveBoxes.chapters);
  }

  /// Get cached user progress
  List<dynamic>? getCachedProgress() {
    final cached = getCached(HiveBoxes.progress, 'user_progress');
    return cached as List<dynamic>?;
  }

  /// Increment chapter view count when user watches for required minutes
  Future<Map<String, dynamic>> incrementViewCount({
    required int chapterId,
    required int watchedMinutes,
  }) async {
    final token = await getToken();
    if (token == null) return {'success': false, 'message': 'No token found'};

    try {
      final headers = {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      };

      final url =
          '${ApiConstants.baseUrl}${ApiConstants.chapters}/$chapterId/view';
      debugPrint('[ChapterRepository] incrementViewCount: POST $url');

      // No body, matching the web's `chaptersApi.recordView`: the server
      // derives the watched time from its own view record. The log used to
      // claim a `watched_minutes` payload that was never sent.
      final response = await http.post(Uri.parse(url), headers: headers);

      debugPrint('[ChapterRepository] Response Status: ${response.statusCode}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        return {
          'success': true,
          'current_views': data['current_views'] ?? data['views_count'],
          'message': data['message'],
        };
      } else {
        final data = jsonDecode(response.body);
        return {
          'success': false,
          'message': data['message'] ?? 'Failed to record view',
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }
}
