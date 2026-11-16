import 'package:easy_localization/easy_localization.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../core/network/api_constants.dart';
import '../../../core/offline/offline_first_repository.dart';
import '../../../core/local/hive_boxes.dart';
import '../../../core/local/hive_service.dart';
import '../../../core/local/models/pending_action.dart';
import '../../../core/services/offline_view_service.dart';

class ChapterRepository with OfflineFirstRepository {
  final _storage = const FlutterSecureStorage();

  /// Stores auth error data when API returns 403/401
  /// This allows offlineFirstFetch to return real server error instead of stale cache
  Map<String, dynamic>? _authErrorData;

  Future<String?> getToken() async {
    return await _storage.read(key: 'auth_token');
  }

  /// The chapter's `view_by_minute` as last loaded online. A downloaded copy
  /// is played without fetching the chapter, and must still wait this long
  /// before charging a view.
  int? cachedViewByMinute(String chapterId) {
    final data = HiveService().retrieveWithTimestamp(
      HiveBoxes.chapters,
      'chapter_$chapterId',
    )?['data'];
    final attributes = data is Map ? data['attributes'] : null;
    return attributes is Map
        ? int.tryParse('${attributes['view_by_minute']}')
        : null;
  }

  /// Get all chapters with offline-first support
  Future<Map<String, dynamic>> getChapters({int? courseId}) async {
    final token = await getToken();
    if (token == null) return {'success': false, 'message': 'errors.no_token'.tr()};

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
            'message': data['message'] ?? 'errors.failed_fetch_chapters'.tr(),
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
    if (token == null) return {'success': false, 'message': 'errors.no_token'.tr()};

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
            'message': data['message'] ?? 'errors.access_denied'.tr(),
            'max_views': data['max_views'],
            'current_views': data['current_views'],
            'watch_access_state': data['watch_access_state'],
          };
          throw 'AUTH_ERROR';
        } else {
          return {
            'success': false,
            'message': data['message'] ?? 'errors.failed_fetch_chapter_details'.tr(),
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
        'watch_access_state': _authErrorData!['watch_access_state'],
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
    if (token == null) return {'success': false, 'message': 'errors.no_token'.tr()};

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
        await _discardViewsResetBy(itemType, itemId);
        return {'success': true, 'data': data['data']};
      } else {
        return {
          'success': false,
          'message': data['message'] ?? 'library.invalid_activation_code'.tr(),
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'course.connection_error'.tr(args: ['$e'])};
    }
  }

  /// A code resets the server's view count for its lesson (or for every
  /// lesson of its course). Views this device still holds in the queue were
  /// spent before that reset: kept, they would lock the lesson here again and
  /// later be charged against the new code. Done here so every screen that
  /// redeems a code gets it, not only the lesson screen.
  Future<void> _discardViewsResetBy(String itemType, int itemId) async {
    final views = OfflineViewService();
    if (itemType == 'chapter') {
      await views.discardViewsAfterActivation('$itemId');
    } else if (itemType == 'course') {
      await views.discardViewsAfterCourseActivation('$itemId');
    }
  }

  /// Get user progress with offline-first support
  Future<Map<String, dynamic>> getUserProgress() async {
    final token = await getToken();
    if (token == null) return {'success': false, 'message': 'errors.no_token'.tr()};

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
            'message': data['message'] ?? 'errors.failed_fetch_user_progress'.tr(),
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
    if (token == null) return {'success': false, 'message': 'errors.no_token'.tr()};

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
            'message': 'errors.progress_saved_offline'.tr(),
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
          'message': 'errors.progress_saved_offline'.tr(),
        };
      }
    }

    // Action was queued (offline mode)
    return {
      'success': true,
      'offline': true,
      'queued': true,
      'actionId': queueResult['actionId'],
      'message': 'errors.progress_saved_offline'.tr(),
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

  /// Records one view of [chapterId] — `POST /v1/chapter/{id}/view`, as the
  /// website's `chaptersApi.recordView` does once the watch threshold is met.
  ///
  /// [viewKey] identifies this opening of the lesson; the server counts a key
  /// once, so re-sending the same opening cannot add a second view.
  ///
  /// `retryable` is true only when the server's answer is unknown (no
  /// response, a timeout) or it failed on its side (5xx); the view may then be
  /// queued and re-sent with the same key. Any other refusal (a 4xx such as
  /// `view_limit_reached`) is final, as on the website, and is not queued.
  Future<Map<String, dynamic>> incrementViewCount({
    required int chapterId,
    required String viewKey,
  }) async {
    final token = await getToken();
    if (token == null) {
      return {'success': false, 'retryable': false, 'message': 'errors.no_token'.tr()};
    }

    final url = '${ApiConstants.baseUrl}${ApiConstants.chapters}/$chapterId/view';
    debugPrint('[ChapterRepository] incrementViewCount: POST $url');

    final http.Response response;
    try {
      response = await http
          .post(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({'view_key': viewKey}),
          )
          .timeout(viewRequestTimeout);
    } catch (e) {
      return {
        'success': false,
        'retryable': true,
        'message': 'course.connection_error'.tr(args: ['$e']),
      };
    }

    debugPrint('[ChapterRepository] Response Status: ${response.statusCode}');
    Object? data;
    try {
      data = jsonDecode(response.body);
    } catch (_) {}

    if (response.statusCode == 200 || response.statusCode == 201) {
      // The server answers with the chapter resource; its view count is
      // `data.attributes.current_user_views`.
      Object? views;
      if (data is Map) {
        final resource = data['data'];
        final attributes = resource is Map ? resource['attributes'] : null;
        views = (attributes is Map ? attributes['current_user_views'] : null) ??
            data['current_views'] ??
            data['views_count'];
      }
      return {
        'success': true,
        'current_views': int.tryParse('${views ?? ''}'),
        'message': data is Map ? data['message'] : null,
      };
    }

    return {
      'success': false,
      'retryable': response.statusCode >= 500,
      'statusCode': response.statusCode,
      'watch_access_state': data is Map ? data['watch_access_state'] : null,
      'message': (data is Map ? data['message'] : null) ?? 'errors.failed_record_view'.tr(),
    };
  }

  /// How long a view request may take before its answer counts as unknown.
  static const Duration viewRequestTimeout = Duration(seconds: 20);
}
