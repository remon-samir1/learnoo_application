import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:learnoo/core/network/api_constants.dart';
import 'package:learnoo/core/services/device_service.dart';
import 'package:learnoo/core/local/hive_boxes.dart';

class AuthRepository {
  final _storage = const FlutterSecureStorage();

  // Current app version code - update this with each release
  static const int currentVersionCode = 1;

  // Cache keys for watermark data
  static const String _cachedStudentCodeKey = 'cached_student_code';
  static const String _cachedPhoneKey = 'cached_phone';

  /// Check for OTA (Over-The-Air) app updates
  /// Returns update info if a newer version is available, null otherwise
  Future<Map<String, dynamic>?> checkForUpdate() async {
    final url = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.otaLatest}');

    try {
      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'X-OTA-Key':"196716f9c69164c7b8ef9e2a4bfb9bced668065997b3e987cc900803c7b78c43"
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final attributes = data['data']?['attributes'];

        if (attributes == null) return null;

        final versionCode = attributes['version_code'];
        final isForceUpdate = attributes['is_force_update'] ?? false;
        final downloadUrl = attributes['download_url'];
        final versionName = attributes['version_name'];
        final releaseNotes = attributes['release_notes'];
        final fileSizeHuman = attributes['file_size_human'];

        // Check if update is needed
        if (versionCode != null && versionCode > currentVersionCode) {
          // Check if user has already acknowledged this version (updated or skipped)
          final lastAcknowledgedVersion = await getLastAcknowledgedVersionCode();
          if (lastAcknowledgedVersion != null && versionCode <= lastAcknowledgedVersion) {
            // User has already seen this version, don't prompt again
            return null;
          }

          return {
            'hasUpdate': true,
            'versionCode': versionCode,
            'versionName': versionName,
            'isForceUpdate': isForceUpdate,
            'downloadUrl': downloadUrl,
            'releaseNotes': releaseNotes,
            'fileSize': fileSizeHuman,
          };
        }
      }
      return null;
    } catch (e) {
      // Silently fail - don't block app startup on update check failure
      return null;
    }
  }

  Future<void> saveToken(String token) async {
    await _storage.write(key: 'auth_token', value: token);
  }

  Future<String?> getToken() async {
    return await _storage.read(key: 'auth_token');
  }

  Future<void> deleteToken() async {
    await _storage.delete(key: 'auth_token');
  }

  /// Get the last acknowledged version code (user updated or skipped this version)
  Future<int?> getLastAcknowledgedVersionCode() async {
    final value = await _storage.read(key: 'last_acknowledged_version_code');
    return value != null ? int.tryParse(value) : null;
  }

  /// Save the last acknowledged version code
  Future<void> saveLastAcknowledgedVersionCode(int versionCode) async {
    await _storage.write(key: 'last_acknowledged_version_code', value: versionCode.toString());
  }

  Map<String, dynamic> _handleError(dynamic data, String defaultMessage) {
    if (data == null) {
      return {'message': defaultMessage, 'errors': null};
    }

    // Check if there's a direct message field
    if (data['message'] != null) {
      final message = data['message'].toString();
      // Check for validation errors object
      if (data['errors'] != null && data['errors'] is Map) {
        return {'message': message, 'errors': data['errors'] as Map<String, dynamic>};
      }
      return {'message': message, 'errors': null};
    }

    // Check for validation errors object
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

  Future<Map<String, dynamic>> register({
    required String firstName,
    required String lastName,
    required String phone,
    required String email,
    required String password,
  }) async {
    final url = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.register}');

    final deviceName = await DeviceService.getDeviceName();

    final body = {
      'first_name': firstName,
      'last_name': lastName,
      'phone': phone,
      'email': email,
      'password': password,
      'device_name': deviceName,
    };

    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(body),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 201 || response.statusCode == 200) {
        final token = data['meta']['token'];
        if (token != null) {
          await saveToken(token);
        }
        return {
          'success': true,
          'message': data['message'] ?? 'Registration succeeded',
          'data': data,
        };
      } else {
        final errorData = _handleError(data, 'Registration failed');
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

  Future<Map<String, dynamic>> sendEmailVerification(String token) async {
    final url = Uri.parse(
      '${ApiConstants.baseUrl}${ApiConstants.emailVerificationNotification}',
    );

    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );


      if (response.statusCode >= 200 && response.statusCode < 300) {
        dynamic data;
        if (response.body.isNotEmpty) {
          data = jsonDecode(response.body);
        }
        return {
          'success': true,
          'message': data?['message'] ?? 'Verification email sent',
        };
      } else {
        final data = response.body.isNotEmpty ? jsonDecode(response.body) : null;
        final errorData = _handleError(data, 'Failed to send verification email');
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

  Future<Map<String, dynamic>> sendPhoneVerification(String token) async {
    final url = Uri.parse(
      '${ApiConstants.baseUrl}${ApiConstants.phoneVerificationNotification}',
    );

    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );



      if (response.statusCode >= 200 && response.statusCode < 300) {
        dynamic data;
        if (response.body.isNotEmpty) {
          data = jsonDecode(response.body);
        }
        return {
          'success': true,
          'message': data?['message'] ?? 'Verification phone queued/sent',
        };
      } else {
        final data = response.body.isNotEmpty ? jsonDecode(response.body) : null;
        final errorData = _handleError(data, 'Failed to send verification phone');
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

  Future<Map<String, dynamic>> verifyEmailOtp(String token, String code) async {
    final url = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.verifyEmail}');

    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'code': code}),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 || response.statusCode == 201) {
        return {
          'success': true,
          'message': data['message'] ?? 'Email verified successfully',
        };
      } else {
        final errorData = _handleError(data, 'Failed to verify email');
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

  Future<Map<String, dynamic>> verifyPhoneOtp(String token, String code) async {
    final url = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.verifyPhone}');

    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'code': code}),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 || response.statusCode == 201) {
        return {
          'success': true,
          'message': data['message'] ?? 'Phone verified successfully',
        };
      } else {
        final errorData = _handleError(data, 'Failed to verify phone');
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

  Future<Map<String, dynamic>> getUniversities() async {
    final token = await getToken();
    if (token == null) return {'success': false, 'message': 'No token found'};

    final url = Uri.parse(
      '${ApiConstants.baseUrl}${ApiConstants.universities}',
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
        return {'success': true, 'data': data['data']};
      } else {
        final errorData = _handleError(data, 'Failed to fetch universities');
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

  Future<Map<String, dynamic>> getCenters() async {
    final token = await getToken();
    if (token == null) return {'success': false, 'message': 'No token found'};

    final url = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.centers}');
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
        return {'success': true, 'data': data['data']};
      } else {
        final errorData = _handleError(data, 'Failed to fetch centers');
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

  Future<Map<String, dynamic>> getFaculties() async {
    final token = await getToken();
    if (token == null) return {'success': false, 'message': 'No token found'};

    final url = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.faculties}');
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
        return {'success': true, 'data': data['data']};
      } else {
        final errorData = _handleError(data, 'Failed to fetch faculties');
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

  Future<Map<String, dynamic>> updateAcademicProfile({
    required dynamic universityId,
    required List<dynamic> centerIds,
    required dynamic facultyId,
  }) async {
    // Convert center IDs to list of integers
    final centerIdsList = centerIds.map((id) => int.tryParse(id.toString()) ?? id).toList();

    return updateProfile({
      'university_id': universityId.toString(),
      'centers': centerIdsList,
      'faculty_id': int.tryParse(facultyId.toString()) ?? facultyId,
    });
  }

  Future<Map<String, dynamic>> updateProfile(Map<String, dynamic> body) async {
    final token = await getToken();
    if (token == null) return {'success': false, 'message': 'No token found'};

    final url = Uri.parse(
      '${ApiConstants.baseUrl}${ApiConstants.updateProfile}',
    );
    try {
      final response = await http.put(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {
          'success': true,
          'message': data['message'] ?? 'Profile updated successfully',
          'data': data['data'],
        };
      } else {
        final errorData = _handleError(data, 'Failed to update profile');
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

  Future<Map<String, dynamic>> updateProfileWithImage({
    required Map<String, dynamic> profileData,
    File? imageFile,
  }) async {
    final token = await getToken();
    if (token == null) return {'success': false, 'message': 'No token found'};

    final url = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.updateProfile}');

    try {
      final request = http.MultipartRequest('PUT', url);
      request.headers['Authorization'] = 'Bearer $token';
      request.headers['Accept'] = 'application/json';

      // Add profile fields
      profileData.forEach((key, value) {
        if (value != null) {
          request.fields[key] = value.toString();
        }
      });

      // Add image file if provided
      if (imageFile != null) {
        final fileName = imageFile.path.split('/').last;
        final extension = fileName.split('.').last.toLowerCase();
        final contentType = extension == 'png'
            ? MediaType('image', 'png')
            : extension == 'jpg' || extension == 'jpeg'
                ? MediaType('image', 'jpeg')
                : MediaType('image', 'jpeg');

        request.files.add(await http.MultipartFile.fromPath(
          'image',
          imageFile.path,
          contentType: contentType,
        ));
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {
          'success': true,
          'message': data['message'] ?? 'Profile updated successfully',
          'data': data['data'],
        };
      } else {
        final errorData = _handleError(data, 'Failed to update profile');
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

  Future<Map<String, dynamic>> login({
    required String identifier,
    required String password,
  }) async {
    final url = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.login}');
    final deviceName = await DeviceService.getDeviceName();

    final body = {
      'phone_or_email': identifier,
      'password': password,
      'device_name': deviceName,
    };

    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(body),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final token = data['meta']['token'];
        if (token != null) {
          await saveToken(token);
        }
        return {
          'success': true,
          'message': data['message'] ?? 'Login successful',
          'data': data,
        };
      } else {
        final errorData = _handleError(data, 'Login failed');
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

  Future<Map<String, dynamic>> getProfile() async {
    final token = await getToken();
    if (token == null) return {'success': false, 'message': 'No token found'};

    final url = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.me}');
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
        // Cache watermark data for offline use
        await _cacheWatermarkData(data['data']);
        return {
          'success': true,
          'data': data['data'],
        };
      } else {
        final errorData = _handleError(data, 'Failed to fetch profile');
        return {
          'success': false,
          'message': errorData['message'],
          'errors': errorData['errors'],
          'statusCode': response.statusCode,
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  /// Cache watermark data (student_code and phone) to Hive for offline use
  Future<void> _cacheWatermarkData(Map<String, dynamic>? userData) async {
    try {
      if (userData == null) return;
      final attributes = userData['attributes'];
      if (attributes == null) return;

      final box = Hive.box<dynamic>(HiveBoxes.userProfile);
      final studentCode = attributes['student_code']?.toString();
      final phone = attributes['phone']?.toString();

      if (studentCode != null && studentCode.isNotEmpty) {
        await box.put(_cachedStudentCodeKey, studentCode);
      }
      if (phone != null && phone.isNotEmpty) {
        await box.put(_cachedPhoneKey, phone);
      }
    } catch (e) {
      debugPrint('Error caching watermark data: $e');
    }
  }

  /// Get cached watermark data for offline use
  /// Returns map with 'student_code' and 'phone' keys, values may be null
  Map<String, String?> getCachedWatermarkData() {
    try {
      final box = Hive.box<dynamic>(HiveBoxes.userProfile);
      return {
        'student_code': box.get(_cachedStudentCodeKey) as String?,
        'phone': box.get(_cachedPhoneKey) as String?,
      };
    } catch (e) {
      debugPrint('Error retrieving cached watermark data: $e');
      return {'student_code': null, 'phone': null};
    }
  }

  /// Clear cached watermark data (call on logout)
  Future<void> clearCachedWatermarkData() async {
    try {
      final box = Hive.box<dynamic>(HiveBoxes.userProfile);
      await box.delete(_cachedStudentCodeKey);
      await box.delete(_cachedPhoneKey);
    } catch (e) {
      debugPrint('Error clearing cached watermark data: $e');
    }
  }

  Future<Map<String, dynamic>> requestPasswordReset(String phoneOrEmail) async {
    final url = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.passwordForgot}');

    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({'phone_or_email': phoneOrEmail}),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 || response.statusCode == 201) {
        return {
          'success': true,
          'message': data['message'] ?? 'Password reset code sent successfully',
          'data': data,
        };
      } else {
        final errorData = _handleError(data, 'Failed to send password reset code');
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

  Future<Map<String, dynamic>> verifyPasswordReset({
    required String phoneOrEmail,
    required String code,
  }) async {
    final url = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.passwordReset}');

    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'type': 'verify',
          'code': code,
          'phone_or_email': phoneOrEmail,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 || response.statusCode == 201) {
        return {
          'success': true,
          'message': data['message'] ?? 'Code verified successfully',
          'data': data,
        };
      } else {
        final errorData = _handleError(data, 'Failed to verify code');
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

  Future<Map<String, dynamic>> resetPassword({
    required String phoneOrEmail,
    required String code,
    required String password,
    required String passwordConfirmation,
  }) async {
    final url = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.passwordReset}');

    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'type': 'reset',
          'code': code,
          'phone_or_email': phoneOrEmail,
          'password': password,
          'password_confirmation': passwordConfirmation,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 || response.statusCode == 201) {
        return {
          'success': true,
          'message': data['message'] ?? 'Password reset successfully',
          'data': data,
        };
      } else {
        final errorData = _handleError(data, 'Failed to reset password');
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

  Future<Map<String, dynamic>> logout() async {
    final token = await getToken();
    if (token == null) return {'success': false, 'message': 'No token found'};

    final url = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.logout}');
    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      // Clear token and cached watermark data regardless of API response
      await deleteToken();
      await clearCachedWatermarkData();

      if (response.statusCode == 200 || response.statusCode == 204) {
        return {'success': true, 'message': 'Logged out successfully'};
      } else {
        final data = response.body.isNotEmpty ? jsonDecode(response.body) : null;
        return {
          'success': true, // Still consider success since we cleared local token
          'message': data?['message'] ?? 'Logged out locally',
        };
      }
    } catch (e) {
      // Even if API call fails, clear local token and cached watermark data
      await deleteToken();
      await clearCachedWatermarkData();
      return {'success': true, 'message': 'Logged out locally'};
    }
  }
}
