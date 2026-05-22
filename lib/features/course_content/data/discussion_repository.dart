import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart';
import '../../../core/network/api_constants.dart';
import '../../../core/offline/offline_first_repository.dart';
import '../../../core/local/hive_boxes.dart';
import '../../../core/local/models/pending_action.dart';
import '../../../core/sync/offline_queue_service.dart';
import '../../../core/services/connectivity_service.dart';

/// Repository for discussion/comment data with offline-first support
/// GET requests are cached locally, POST requests are queued when offline
class DiscussionRepository with OfflineFirstRepository {
  final _storage = const FlutterSecureStorage();
  final OfflineQueueService _queue = OfflineQueueService();

  Future<String?> _getToken() async {
    return await _storage.read(key: 'auth_token');
  }

  /// Get discussions with offline-first support
  /// Returns cached discussions if offline or API fails
  Future<Map<String, dynamic>> getDiscussions({int? chapterId}) async {
    final token = await _getToken();
    if (token == null) return {'success': false, 'message': 'No token found'};

    final cacheKey = chapterId != null ? 'discussions_chapter_$chapterId' : 'discussions_all';

    return offlineFirstFetch(
      apiFetcher: () async {
        final queryParams = chapterId != null ? '?chapter_id=$chapterId' : '';
        final url = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.discussion}$queryParams');

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
            'message': data['message'] ?? 'Failed to fetch discussions',
          };
        }
      },
      boxName: HiveBoxes.comments,
      cacheKey: cacheKey,
      maxCacheAge: const Duration(minutes: 30), // Comments change frequently
    );
  }

  /// Post a discussion with offline queue support
  /// When offline, the comment is queued and synced when connection is restored
  /// Supports optimistic UI updates - returns immediately with pending status
  Future<Map<String, dynamic>> postDiscussion({
    required int chapterId,
    required String type,
    required String content,
    required int moment,
    int? parentId,
    File? voiceFile,
  }) async {
    final token = await _getToken();
    if (token == null) return {'success': false, 'message': 'No token found'};

    // For voice files, we need to handle offline differently since
    // we can't easily queue multipart file uploads
    if (type == 'voice' && voiceFile != null) {
      return _postVoiceDiscussion(
        chapterId: chapterId,
        voiceFile: voiceFile,
        moment: moment,
        parentId: parentId,
      );
    }

    // Build payload for text comments
    final payload = {
      'chapter_id': chapterId,
      'type': type,
      'content': content,
      'moment': moment,
      if (parentId != null) 'parent_id': parentId,
    };

    // Check connectivity
    final hasConnection = await ConnectivityService().hasConnection();

    if (!hasConnection) {
      // Queue the action for later sync
      final action = await _queue.enqueue(
        type: PendingActionTypes.comment,
        payload: payload,
        id: 'comment_${chapterId}_${DateTime.now().millisecondsSinceEpoch}',
      );

      return {
        'success': true,
        'offline': true,
        'queued': true,
        'actionId': action.id,
        'message': 'Comment queued and will be posted when online',
        // Optimistic data for UI
        'optimisticData': {
          'id': action.id,
          'chapter_id': chapterId,
          'type': type,
          'content': content,
          'moment': moment,
          'parent_id': parentId,
          'is_pending': true,
          'created_at': DateTime.now().toIso8601String(),
        },
      };
    }

    // Online - try to post immediately
    final url = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.discussion}');

    try {
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
      if (response.statusCode == 201 || response.statusCode == 200) {
        return {
          'success': true,
          'data': data['data'],
          'offline': false,
          'queued': false,
        };
      } else {
        // API failed, queue for retry
        final action = await _queue.enqueue(
          type: PendingActionTypes.comment,
          payload: payload,
          id: 'comment_${chapterId}_${DateTime.now().millisecondsSinceEpoch}',
        );

        return {
          'success': true, // Optimistic success for UI
          'offline': false,
          'queued': true,
          'actionId': action.id,
          'message': 'Comment saved locally, will sync when online',
          'optimisticData': {
            'id': action.id,
            'chapter_id': chapterId,
            'type': type,
            'content': content,
            'moment': moment,
            'parent_id': parentId,
            'is_pending': true,
            'created_at': DateTime.now().toIso8601String(),
          },
        };
      }
    } catch (e) {
      // Network error, queue for retry
      final action = await _queue.enqueue(
        type: PendingActionTypes.comment,
        payload: payload,
        id: 'comment_${chapterId}_${DateTime.now().millisecondsSinceEpoch}',
      );

      return {
        'success': true, // Optimistic success for UI
        'offline': true,
        'queued': true,
        'actionId': action.id,
        'message': 'Comment saved locally, will sync when online',
        'optimisticData': {
          'id': action.id,
          'chapter_id': chapterId,
          'type': type,
          'content': content,
          'moment': moment,
          'parent_id': parentId,
          'is_pending': true,
          'created_at': DateTime.now().toIso8601String(),
        },
      };
    }
  }

  /// Post voice discussion - requires online connection
  /// Voice files cannot be easily queued offline due to file handling
  Future<Map<String, dynamic>> _postVoiceDiscussion({
    required int chapterId,
    required File voiceFile,
    required int moment,
    int? parentId,
  }) async {
    final token = await _getToken();
    if (token == null) return {'success': false, 'message': 'No token found'};

    final url = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.discussion}');

    // Check if online first
    final hasConnection = await ConnectivityService().hasConnection();
    if (!hasConnection) {
      return {
        'success': false,
        'offline': true,
        'message': 'Voice comments require internet connection',
      };
    }

    try {
      var request = http.MultipartRequest('POST', url);
      request.headers.addAll({
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      });

      request.fields['chapter_id'] = chapterId.toString();
      request.fields['type'] = 'voice';
      request.fields['moment'] = moment.toString();
      if (parentId != null) {
        request.fields['parent_id'] = parentId.toString();
      }

      request.files.add(await http.MultipartFile.fromPath(
        'content',
        voiceFile.path,
        filename: basename(voiceFile.path),
        contentType: MediaType('audio', 'm4a'),
      ));

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);
      final data = jsonDecode(response.body);

      if (response.statusCode == 201 || response.statusCode == 200) {
        return {'success': true, 'data': data['data']};
      } else {
        return {
          'success': false,
          'message': data['message'] ?? 'Failed to post voice discussion',
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  /// Get cached discussions for a chapter
  List<dynamic> getCachedDiscussions({int? chapterId}) {
    if (chapterId != null) {
      return getAllCached(HiveBoxes.comments).where((item) {
        final data = _extractDiscussionData(item);
        return data?['chapter_id'] == chapterId;
      }).toList();
    }
    return getAllCached(HiveBoxes.comments);
  }

  /// Get pending comments for a chapter (for optimistic UI)
  List<Map<String, dynamic>> getPendingComments(int chapterId) {
    final pendingActions = _queue.getPendingActionsByType(PendingActionTypes.comment);
    return pendingActions
        .where((action) => action.payload['chapter_id'] == chapterId)
        .map((action) => {
              'id': action.id,
              ...action.payload,
              'is_pending': true,
              'created_at': DateTime.fromMillisecondsSinceEpoch(action.createdAt).toIso8601String(),
            })
        .toList();
  }

  /// Extract discussion data from cached entry
  Map<String, dynamic>? _extractDiscussionData(dynamic item) {
    if (item is Map<String, dynamic>) {
      if (item.containsKey('data')) {
        return item['data'] as Map<String, dynamic>?;
      }
      return item;
    }
    return null;
  }
}
