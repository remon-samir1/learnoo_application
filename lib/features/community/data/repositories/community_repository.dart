import 'package:easy_localization/easy_localization.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_constants.dart';
import '../../../course_content/data/course_repository.dart';
import '../models/post_model.dart';
import '../models/social_link_model.dart';

class CommunityRepository {
  final _storage = const FlutterSecureStorage();

  Future<String?> getToken() async {
    return await _storage.read(key: 'auth_token');
  }

  /// Signed-in user's id, read from the `sub` claim of the bearer token.
  ///
  /// Used to decide which comments the student may delete, the same rule the
  /// web applies by comparing the comment author against the current user.
  Future<String?> currentUserId() async {
    final token = await getToken();
    if (token == null) return null;
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      return payload['sub']?.toString();
    } catch (_) {
      return null;
    }
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
    if (token == null) return {'success': false, 'message': 'errors.no_token'.tr()};

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
          'lang': ApiClient.locale,
        },
      ).timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        final List<dynamic> postData = data['data'] ?? [];
        final posts = <Post>[];
        for (final p in postData) {
          try {
            if (p is Map) {
              final post = Post.fromJson(Map<String, dynamic>.from(p));
              // Student feed: published posts only, as on the web.
              if (post.attributes.isPublished) posts.add(post);
            }
          } catch (_) {
            // Keep remaining posts rather than crashing whole list
          }
        }
        return {'success': true, 'data': posts};
      } else {
        return {
          'success': false,
          'message': _handleError(data, 'errors.failed_fetch_posts'.tr()),
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'course.connection_error'.tr(args: ['$e'])};
    }
  }

  /// Comments on a post.
  ///
  /// There is no separate comments endpoint: a comment is a post whose
  /// `parent_id` points at the thread it belongs to, listed with
  /// `GET /v1/post?parent_id={id}` — the same contract the web's
  /// `commentsApi` uses. The app had this feature commented out entirely, so
  /// app students could see a thread but never read or add a reply.
  Future<Map<String, dynamic>> getComments(String postId) async {
    final token = await getToken();
    if (token == null) return {'success': false, 'message': 'errors.no_token'.tr()};

    final url = Uri.parse(
      '${ApiConstants.baseUrl}${ApiConstants.posts}?parent_id=$postId',
    );

    try {
      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
          'lang': ApiClient.locale,
        },
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        final List<dynamic> commentData = data['data'] ?? [];
        final comments = commentData.map((c) => Post.fromJson(c)).toList();
        return {'success': true, 'data': comments};
      }
      return {
        'success': false,
        'message': _handleError(data, 'errors.failed_fetch_comments'.tr()),
      };
    } catch (e) {
      return {'success': false, 'message': 'course.connection_error'.tr(args: ['$e'])};
    }
  }

  /// Adds a comment to [postId].
  ///
  /// `title` is required by the endpoint even for a reply, so we derive it
  /// from the first 200 characters of the body exactly as the web does.
  Future<Map<String, dynamic>> addComment({
    required String postId,
    required String content,
  }) async {
    final token = await getToken();
    if (token == null) return {'success': false, 'message': 'errors.no_token'.tr()};

    final body = content.trim();
    if (body.isEmpty) {
      return {'success': false, 'message': 'errors.comment_empty'.tr()};
    }

    final title = body.length > 200 ? body.substring(0, 200) : body;
    final url = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.posts}');

    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
          'lang': ApiClient.locale,
        },
        body: jsonEncode({
          'parent_id': int.tryParse(postId) ?? postId,
          'content': body,
          'title': title,
          'status': 'published',
          'type': 'post',
        }),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 || response.statusCode == 201) {
        return {'success': true, 'data': data['data']};
      }
      return {
        'success': false,
        'message': _handleError(data, 'errors.failed_post_comment'.tr()),
      };
    } catch (e) {
      return {'success': false, 'message': 'course.connection_error'.tr(args: ['$e'])};
    }
  }

  /// Removes one of the student's own comments.
  Future<Map<String, dynamic>> deleteComment(String commentId) =>
      deletePost(commentId);

  // Get post by ID
  Future<Map<String, dynamic>> getPostById(String postId) async {
    final token = await getToken();
    if (token == null) return {'success': false, 'message': 'errors.no_token'.tr()};

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
          'message': _handleError(data, 'errors.failed_fetch_post'.tr()),
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'course.connection_error'.tr(args: ['$e'])};
    }
  }

  // Create a new post
  Future<Map<String, dynamic>> createPost(CreatePostRequest request) async {
    final token = await getToken();
    if (token == null) return {'success': false, 'message': 'errors.no_token'.tr()};

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
          'message': data['message'] ?? 'errors.post_created'.tr(),
        };
      } else {
        return {
          'success': false,
          'message': _handleError(data, 'community.failed_create_post'.tr()),
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'course.connection_error'.tr(args: ['$e'])};
    }
  }

  // Update a post
  Future<Map<String, dynamic>> updatePost(String postId, CreatePostRequest request) async {
    final token = await getToken();
    if (token == null) return {'success': false, 'message': 'errors.no_token'.tr()};

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
          'message': data['message'] ?? 'errors.post_updated'.tr(),
        };
      } else {
        return {
          'success': false,
          'message': _handleError(data, 'errors.failed_update_post'.tr()),
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'course.connection_error'.tr(args: ['$e'])};
    }
  }

  // Delete a post
  Future<Map<String, dynamic>> deletePost(String postId) async {
    final token = await getToken();
    if (token == null) return {'success': false, 'message': 'errors.no_token'.tr()};

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
          'message': data['message'] ?? 'errors.post_deleted'.tr(),
        };
      } else {
        return {
          'success': false,
          'message': _handleError(data, 'errors.failed_delete_post'.tr()),
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'course.connection_error'.tr(args: ['$e'])};
    }
  }

  // React to a post
  Future<Map<String, dynamic>> reactToPost(String postId, String reactionType) async {
    final token = await getToken();
    if (token == null) return {'success': false, 'message': 'errors.no_token'.tr()};

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
          'message': data['message'] ?? 'errors.reaction_added'.tr(),
          'data': data['data'],
        };
      } else {
        return {
          'success': false,
          'message': _handleError(data, 'errors.failed_react'.tr()),
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'course.connection_error'.tr(args: ['$e'])};
    }
  }

  // Remove reaction from a post
  Future<Map<String, dynamic>> removeReaction(String postId) async {
    final token = await getToken();
    if (token == null) return {'success': false, 'message': 'errors.no_token'.tr()};

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
          'message': data['message'] ?? 'errors.reaction_removed'.tr(),
        };
      } else {
        return {
          'success': false,
          'message': _handleError(data, 'errors.failed_remove_reaction'.tr()),
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'course.connection_error'.tr(args: ['$e'])};
    }
  }

  // Get all social links
  Future<Map<String, dynamic>> getSocialLinks({int? courseId}) async {
    final token = await getToken();
    if (token == null) return {'success': false, 'message': 'errors.no_token'.tr()};

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
          'lang': ApiClient.locale,
        },
      ).timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        final List<dynamic> linkData = data['data'] ?? [];
        final links = <SocialLink>[];
        for (final l in linkData) {
          try {
            if (l is Map) {
              links.add(SocialLink.fromJson(Map<String, dynamic>.from(l)));
            }
          } catch (_) {}
        }
        return {'success': true, 'data': links};
      } else {
        return {
          'success': false,
          'message': _handleError(data, 'errors.failed_fetch_social_links'.tr()),
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'course.connection_error'.tr(args: ['$e'])};
    }
  }

  // Get courses (defaults to activated=true to get student's enrolled courses with their social-links)
  Future<Map<String, dynamic>> getCourses({bool activated = true}) async {
    final token = await getToken();
    if (token == null) return {'success': false, 'message': 'errors.no_token'.tr()};

    var url = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.courses}');
    if (activated) {
      url = url.replace(queryParameters: {'activated': '1'});
    }

    try {
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
        final List<dynamic> courseData = data['data'] ?? [];
        return {'success': true, 'data': courseData};
      } else {
        return {
          'success': false,
          'message': _handleError(data, 'errors.failed_fetch_courses'.tr()),
        };
      }
    } catch (e) {
      // Offline fallback: try to get activated courses from CourseRepository
      try {
        final courseRepo = CourseRepository();
        final activatedCached = await courseRepo.getActivatedCourses();
        if (activatedCached['success'] == true && activatedCached['data'] != null) {
          return activatedCached;
        }
      } catch (_) {}
      return {'success': false, 'message': 'course.connection_error'.tr(args: ['$e'])};
    }
  }

  /// Get course details (including posts and social links) by course ID.
  Future<Map<String, dynamic>> getCourseById(String courseId) =>
      CourseRepository().getCourseById(courseId);

  /// Fetch posts strictly from the course details API for student's enrolled courses.
  ///
  /// If [courseId] is provided, fetches details for that course only.
  /// Otherwise, fetches details for all [enrolledCourses] in parallel and aggregates their posts.
  Future<Map<String, dynamic>> getEnrolledCoursesPosts({
    String? courseId,
    List<PostCourse>? enrolledCourses,
  }) async {
    try {
      List<PostCourse> courses = enrolledCourses ?? [];
      if (courses.isEmpty && (courseId == null || courseId.isEmpty)) {
        final courseRes = await getCourses(activated: true);
        if (courseRes['success'] && courseRes['data'] is List) {
          courses = (courseRes['data'] as List)
              .whereType<Map>()
              .map((c) => PostCourse.fromJson(Map<String, dynamic>.from(c)))
              .toList();
        }
      }

      if (courseId != null && courseId.isNotEmpty) {
        final res = await CourseRepository().getCourseById(courseId);
        if (res['success'] == true && res['data'] != null) {
          final courseObj = PostCourse.fromJson(res['data']);
          final posts = courseObj.attributes.posts
              .where((p) =>
                  (p.attributes.parentId == null || p.attributes.parentId!.isEmpty) &&
                  p.attributes.isPublished)
              .toList();
          posts.sort((a, b) => b.attributes.createdAt.compareTo(a.attributes.createdAt));
          return {
            'success': true,
            'data': posts,
            'course': courseObj,
            'socialLinks': courseObj.attributes.socialLinks,
          };
        } else {
          return {
            'success': false,
            'message': res['message'] ?? 'errors.failed_load_course_details'.tr(),
            'data': <Post>[],
          };
        }
      }

      // Aggregate from all enrolled courses
      if (courses.isEmpty) {
        return {
          'success': true,
          'data': <Post>[],
          'courses': <PostCourse>[],
        };
      }

      final enrichedCourses = await Future.wait(
        courses.map((c) async {
          try {
            final res = await CourseRepository().getCourseById(c.id);
            if (res['success'] == true && res['data'] != null) {
              return PostCourse.fromJson(res['data']);
            }
          } catch (_) {}
          return c;
        }),
      );

      final Map<String, Post> uniquePosts = {};
      for (final course in enrichedCourses) {
        for (final post in course.attributes.posts) {
          // Like the web feed: top-level, published posts only. A student's own
          // post awaiting admin approval is not shown as if it were live.
          if ((post.attributes.parentId == null || post.attributes.parentId!.isEmpty) &&
              post.attributes.isPublished) {
            uniquePosts[post.id] = post;
          }
        }
      }

      final allPosts = uniquePosts.values.toList();
      allPosts.sort((a, b) => b.attributes.createdAt.compareTo(a.attributes.createdAt));

      return {
        'success': true,
        'data': allPosts,
        'courses': enrichedCourses,
      };
    } catch (e) {
      return {'success': false, 'message': e.toString(), 'data': <Post>[]};
    }
  }
}
