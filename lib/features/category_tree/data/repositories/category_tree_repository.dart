import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart' hide Category;
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_constants.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/utils/coerce.dart';
import '../models/category_tree_model.dart';

class CategoryTreeRepository {
  final ApiClient _apiClient;

  CategoryTreeRepository({ApiClient? apiClient})
      : _apiClient = apiClient ?? ApiClient();

  /// Fetches the user profile from `/v1/auth/me` and extracts `facultyId`.
  /// Path: `response['data']['attributes']['faculty']['data']['id']`.
  Future<String?> getFacultyId() async {
    try {
      final response = await _apiClient.get(
        ApiConstants.me,
        fallback: 'errors.failed_fetch_user_profile'.tr(),
      );

      if (response == null) return null;

      // Extract facultyId from standard JSON:API response
      if (response is Map) {
        final data = response['data'];
        if (data is Map) {
          final attrs = data['attributes'];
          if (attrs is Map) {
            // Nested faculty relation: data.attributes.faculty.data.id
            final faculty = attrs['faculty'];
            if (faculty is Map && faculty['data'] is Map) {
              final id = coerceId(faculty['data']['id']);
              if (id != null) return id;
            }

            // Flat faculty_id attribute: data.attributes.faculty_id
            final directAttrId = coerceId(attrs['faculty_id']);
            if (directAttrId != null) return directAttrId;
          }

          // Flat relation under data: data.faculty.data.id or data.faculty_id
          final flatFaculty = data['faculty'];
          if (flatFaculty is Map && flatFaculty['data'] is Map) {
            final id = coerceId(flatFaculty['data']['id']);
            if (id != null) return id;
          }
          final flatId = coerceId(data['faculty_id']);
          if (flatId != null) return flatId;
        }

        // Top-level fallbacks
        final topFaculty = response['faculty'];
        if (topFaculty is Map && topFaculty['data'] is Map) {
          final id = coerceId(topFaculty['data']['id']);
          if (id != null) return id;
        }
        final topId = coerceId(response['faculty_id']);
        if (topId != null) return topId;
      }
      return null;
    } catch (e) {
      debugPrint('[CategoryTreeRepository] Error fetching facultyId: $e');
      return null;
    }
  }

  /// Fetches all categories/departments from `/v1/department`.
  Future<List<Category>> getCategories() async {
    try {
      final response = await _apiClient.get(
        ApiConstants.departments,
        fallback: 'errors.failed_fetch_categories'.tr(),
      );

      if (response == null) return [];

      dynamic rawList;
      if (response is Map) {
        rawList = response['data'] ?? response['categories'] ?? response['departments'];
      } else if (response is List) {
        rawList = response;
      }

      if (rawList is! List) return [];

      final List<Category> categories = [];
      for (final item in rawList) {
        if (item is Map) {
          categories.add(Category.fromJson(item));
        }
      }
      return categories;
    } on ApiException catch (e) {
      debugPrint('[CategoryTreeRepository] API Error fetching categories: ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('[CategoryTreeRepository] Error fetching categories: $e');
      throw ApiException(0, e.toString());
    }
  }

  /// Activates a course with a redemption code, exactly like the website's
  /// `StudentCourseActivationModal` / `activateCourseCode`:
  /// `POST /v1/code/activate` with `{code, item_id, item_type: "course"}`.
  ///
  /// Any 2xx is a success (the website does not inspect the body for
  /// courses); a non-2xx surfaces the server's message. [genericError] is
  /// shown when the server gave no message or the request never reached it.
  Future<Map<String, dynamic>> activateCourse({
    required String courseId,
    required String code,
    required String genericError,
  }) async {
    final itemId = int.tryParse(courseId.trim());
    if (itemId == null || itemId < 1) {
      return {'success': false, 'invalidId': true};
    }

    try {
      final response = await _apiClient.post(
        ApiConstants.codeActivate,
        body: {
          'code': code.trim(),
          'item_id': itemId,
          'item_type': 'course',
        },
        // A wrong code must never sign the student out.
        skipAuthRedirect: true,
        fallback: genericError,
      );

      return {'success': true, 'data': response};
    } on ApiException catch (e) {
      return {
        'success': false,
        'message': e.isNetwork ? genericError : e.display(genericError),
        'statusCode': e.status,
      };
    } catch (_) {
      return {'success': false, 'message': genericError};
    }
  }
}
