import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../../core/network/api_constants.dart';
import '../models/post_model.dart';
import '../models/social_link_model.dart';

class CommunityRepository {
  final _storage = const FlutterSecureStorage();

  Future<String?> getToken() async {
    return await _storage.read(key: 'auth_token');
  }

  String _handleError(dynamic data, String defaultMessage) {
    if (data == null) return defaultMessage;

    if (data['message'] != null) {
      return data['message'].toString();
    }

    if (data['errors'] != null && data['errors'] is Map) {
      final errors = data['errors'] as Map<String, dynamic>;
      return errors.values
          .map((e) {
            if (e is List) return e.join(', ');
            return e.toString();
          })
          .join('\n');
    }

    return defaultMessage;
  }

  // Get all posts
  Future<Map<String, dynamic>> getPosts({int? courseId}) async {
    final token = await getToken();
    if (token == null) return {'success': false, 'message': 'No token found'};

    var urlString = '${ApiConstants.baseUrl}${ApiConstants.posts}';
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
        final List<dynamic> postData = data['data'] ?? [];
        final posts = postData.map((p) => Post.fromJson(p)).toList();
        return {'success': true, 'data': posts};
      } else {
        return {
          'success': false,
          'message': _handleError(data, 'Failed to fetch posts'),
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  // Get post by ID
  Future<Map<String, dynamic>> getPostById(String postId) async {
    final token = await getToken();
    if (token == null) return {'success': false, 'message': 'No token found'};

    final url = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.posts}/$postId');
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
        final post = Post.fromJson(data['data']);
        return {'success': true, 'data': post};
      } else {
        return {
          'success': false,
          'message': _handleError(data, 'Failed to fetch post'),
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  // Create a new post
  Future<Map<String, dynamic>> createPost(CreatePostRequest request) async {
    final token = await getToken();
    if (token == null) return {'success': false, 'message': 'No token found'};

    final url = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.posts}');
    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(request.toJson()),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 201 || response.statusCode == 200) {
        final post = Post.fromJson(data['data']);
        return {
          'success': true,
          'data': post,
          'message': data['message'] ?? 'Post created successfully',
        };
      } else {
        return {
          'success': false,
          'message': _handleError(data, 'Failed to create post'),
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  // Update a post
  Future<Map<String, dynamic>> updatePost(String postId, CreatePostRequest request) async {
    final token = await getToken();
    if (token == null) return {'success': false, 'message': 'No token found'};

    final url = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.posts}/$postId');
    try {
      final response = await http.put(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(request.toJson()),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        final post = Post.fromJson(data['data']);
        return {
          'success': true,
          'data': post,
          'message': data['message'] ?? 'Post updated successfully',
        };
      } else {
        return {
          'success': false,
          'message': _handleError(data, 'Failed to update post'),
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  // Delete a post
  Future<Map<String, dynamic>> deletePost(String postId) async {
    final token = await getToken();
    if (token == null) return {'success': false, 'message': 'No token found'};

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

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 || response.statusCode == 204) {
        return {
          'success': true,
          'message': data['message'] ?? 'Post deleted successfully',
        };
      } else {
        return {
          'success': false,
          'message': _handleError(data, 'Failed to delete post'),
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  // React to a post
  Future<Map<String, dynamic>> reactToPost(String postId, String reactionType) async {
    final token = await getToken();
    if (token == null) return {'success': false, 'message': 'No token found'};

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

      final data = jsonDecode(response.body);
      if (response.statusCode == 201 || response.statusCode == 200) {
        return {
          'success': true,
          'message': data['message'] ?? 'Reaction added successfully',
          'data': data['data'],
        };
      } else {
        return {
          'success': false,
          'message': _handleError(data, 'Failed to react to post'),
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  // Remove reaction from a post
  Future<Map<String, dynamic>> removeReaction(String postId) async {
    final token = await getToken();
    if (token == null) return {'success': false, 'message': 'No token found'};

    final url = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.posts}/$postId/react');
    try {
      final response = await http.delete(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 || response.statusCode == 204) {
        return {
          'success': true,
          'message': data['message'] ?? 'Reaction removed successfully',
        };
      } else {
        return {
          'success': false,
          'message': _handleError(data, 'Failed to remove reaction'),
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  // Get all social links
  Future<Map<String, dynamic>> getSocialLinks({int? courseId}) async {
    final token = await getToken();
    if (token == null) return {'success': false, 'message': 'No token found'};

    var urlString = '${ApiConstants.baseUrl}${ApiConstants.socialLinks}';
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
        final List<dynamic> linkData = data['data'] ?? [];
        final links = linkData.map((l) => SocialLink.fromJson(l)).toList();
        return {'success': true, 'data': links};
      } else {
        return {
          'success': false,
          'message': _handleError(data, 'Failed to fetch social links'),
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  // Get courses for tagging (using the existing courses endpoint)
  Future<Map<String, dynamic>> getCourses() async {
    final token = await getToken();
    if (token == null) return {'success': false, 'message': 'No token found'};

    final url = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.courses}');
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
        final List<dynamic> courseData = data['data'] ?? [];
        return {'success': true, 'data': courseData};
      } else {
        return {
          'success': false,
          'message': _handleError(data, 'Failed to fetch courses'),
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }
}
