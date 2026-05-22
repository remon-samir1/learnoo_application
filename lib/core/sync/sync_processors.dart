import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../local/models/pending_action.dart';
import '../network/api_constants.dart';
import 'sync_service.dart';

/// Collection of action processors for the sync service
/// Each processor handles a specific action type
class SyncProcessors {
  static const _storage = FlutterSecureStorage();

  /// Get auth token
  static Future<String?> _getToken() async {
    return await _storage.read(key: 'auth_token');
  }

  /// Register all processors with the sync service
  static void registerAll(SyncService syncService) {
    syncService.registerProcessor(PendingActionTypes.comment, _processComment);
    syncService.registerProcessor(PendingActionTypes.progress, _processProgress);
    syncService.registerProcessor(PendingActionTypes.post, _processPost);
    syncService.registerProcessor(PendingActionTypes.reaction, _processReaction);
    syncService.registerProcessor(PendingActionTypes.deletePost, _processDeletePost);
    syncService.registerProcessor(PendingActionTypes.updatePost, _processUpdatePost);
  }

  /// Process a pending comment action
  static Future<bool> _processComment(PendingAction action) async {
    final token = await _getToken();
    if (token == null) return false;

    final url = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.discussion}');

    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(action.payload),
      );

      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      throw Exception('Failed to post comment: $e');
    }
  }

  /// Process a pending progress update action
  static Future<bool> _processProgress(PendingAction action) async {
    final token = await _getToken();
    if (token == null) return false;

    final url = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.userProgress}');

    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(action.payload),
      );

      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      throw Exception('Failed to update progress: $e');
    }
  }

  /// Process a pending post creation action
  static Future<bool> _processPost(PendingAction action) async {
    final token = await _getToken();
    if (token == null) return false;

    final url = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.posts}');

    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(action.payload),
      );

      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      throw Exception('Failed to create post: $e');
    }
  }

  /// Process a pending reaction action
  static Future<bool> _processReaction(PendingAction action) async {
    final token = await _getToken();
    if (token == null) return false;

    final postId = action.payload['post_id'];
    final reactionType = action.payload['type'];

    if (postId == null || reactionType == null) {
      return false;
    }

    final url = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.posts}/$postId/react');

    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'type': reactionType}),
      );

      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      throw Exception('Failed to add reaction: $e');
    }
  }

  /// Process a pending post deletion action
  static Future<bool> _processDeletePost(PendingAction action) async {
    final token = await _getToken();
    if (token == null) return false;

    final postId = action.payload['post_id'];
    if (postId == null) return false;

    final url = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.posts}/$postId');

    try {
      final response = await http.delete(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      return response.statusCode == 200 || response.statusCode == 204;
    } catch (e) {
      throw Exception('Failed to delete post: $e');
    }
  }

  /// Process a pending post update action
  static Future<bool> _processUpdatePost(PendingAction action) async {
    final token = await _getToken();
    if (token == null) return false;

    final postId = action.payload['post_id'];
    if (postId == null) return false;

    // Remove post_id from payload before sending
    final payload = Map<String, dynamic>.from(action.payload);
    payload.remove('post_id');

    final url = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.posts}/$postId');

    try {
      final response = await http.put(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(payload),
      );

      return response.statusCode == 200;
    } catch (e) {
      throw Exception('Failed to update post: $e');
    }
  }
}
