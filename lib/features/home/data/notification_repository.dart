import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:learnoo/core/network/api_constants.dart';
import 'package:learnoo/features/auth/data/auth_repository.dart';
import 'package:learnoo/features/home/data/models/notification.dart';

class NotificationRepository {
  final AuthRepository _authRepository;

  NotificationRepository({required AuthRepository authRepository})
      : _authRepository = authRepository;

  Future<String?> _getToken() async {
    return await _authRepository.getToken();
  }

  Map<String, dynamic> _handleError(dynamic data, String defaultMessage) {
    if (data == null) {
      return {'message': defaultMessage, 'errors': null};
    }

    if (data['message'] != null) {
      final message = data['message'].toString();
      if (data['errors'] != null && data['errors'] is Map) {
        return {'message': message, 'errors': data['errors'] as Map<String, dynamic>};
      }
      return {'message': message, 'errors': null};
    }

    if (data['errors'] != null && data['errors'] is Map) {
      final errors = data['errors'] as Map<String, dynamic>;
      final errorMessages = errors.values
          .map((e) {
            if (e is List) return e.join(', ');
            return e.toString();
          })
          .join('\n');
      return {'message': errorMessages, 'errors': errors};
    }

    return {'message': defaultMessage, 'errors': null};
  }

  Future<Map<String, dynamic>> getNotifications({int page = 1}) async {
    final token = await _getToken();
    if (token == null) return {'success': false, 'message': 'No token found'};

    final url = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.notifications}').replace(
      queryParameters: {'page': page.toString()},
    );

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
        final notificationResponse = NotificationResponse.fromJson(data);
        return {
          'success': true,
          'data': notificationResponse.data,
          'meta': notificationResponse.meta,
        };
      } else {
        final errorData = _handleError(data, 'Failed to fetch notifications');
        return {
          'success': false,
          'message': errorData['message'],
          'errors': errorData['errors'],
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  Future<Map<String, dynamic>> getUnreadNotifications({int page = 1}) async {
    final token = await _getToken();
    if (token == null) return {'success': false, 'message': 'No token found'};

    final url = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.notificationsUnread}').replace(
      queryParameters: {'page': page.toString()},
    );

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
        final notificationResponse = NotificationResponse.fromJson(data);
        return {
          'success': true,
          'data': notificationResponse.data,
          'meta': notificationResponse.meta,
        };
      } else {
        final errorData = _handleError(data, 'Failed to fetch unread notifications');
        return {
          'success': false,
          'message': errorData['message'],
          'errors': errorData['errors'],
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  Future<Map<String, dynamic>> markAsRead(String notificationId) async {
    final token = await _getToken();
    if (token == null) return {'success': false, 'message': 'No token found'};

    final endpoint = ApiConstants.notificationsRead.replaceAll('{id}', notificationId);
    final url = Uri.parse('${ApiConstants.baseUrl}$endpoint');

    try {
      final response = await http.patch(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = response.body.isNotEmpty ? jsonDecode(response.body) : null;
      if (response.statusCode == 200) {
        return {
          'success': true,
          'message': data?['message'] ?? 'Notification marked as read',
        };
      } else {
        final errorData = _handleError(data, 'Failed to mark notification as read');
        return {
          'success': false,
          'message': errorData['message'],
          'errors': errorData['errors'],
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  Future<Map<String, dynamic>> markAllAsRead() async {
    final token = await _getToken();
    if (token == null) return {'success': false, 'message': 'No token found'};

    final url = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.notificationsReadAll}');

    try {
      final response = await http.patch(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = response.body.isNotEmpty ? jsonDecode(response.body) : null;
      if (response.statusCode == 200) {
        return {
          'success': true,
          'message': data?['message'] ?? 'All notifications marked as read',
        };
      } else {
        final errorData = _handleError(data, 'Failed to mark all notifications as read');
        return {
          'success': false,
          'message': errorData['message'],
          'errors': errorData['errors'],
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  Future<Map<String, dynamic>> deleteNotification(String notificationId) async {
    final token = await _getToken();
    if (token == null) return {'success': false, 'message': 'No token found'};

    final endpoint = ApiConstants.notificationsDelete.replaceAll('{id}', notificationId);
    final url = Uri.parse('${ApiConstants.baseUrl}$endpoint');

    try {
      final response = await http.delete(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = response.body.isNotEmpty ? jsonDecode(response.body) : null;
      if (response.statusCode == 200 || response.statusCode == 204) {
        return {
          'success': true,
          'message': data?['message'] ?? 'Notification deleted',
        };
      } else {
        final errorData = _handleError(data, 'Failed to delete notification');
        return {
          'success': false,
          'message': errorData['message'],
          'errors': errorData['errors'],
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  Future<Map<String, dynamic>> getUnreadCount() async {
    final token = await _getToken();
    if (token == null) return {'success': false, 'message': 'No token found'};

    final url = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.notificationsCount}');

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
        return {
          'success': true,
          'count': data['count'] ?? 0,
        };
      } else {
        final errorData = _handleError(data, 'Failed to fetch unread count');
        return {
          'success': false,
          'message': errorData['message'],
          'errors': errorData['errors'],
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }
}
