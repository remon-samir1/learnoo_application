import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;

import 'package:learnoo/core/local/hive_boxes.dart';
import 'package:learnoo/core/network/api_client.dart';
import 'package:learnoo/core/network/api_constants.dart';
import 'package:learnoo/core/network/api_exception.dart';
import 'package:learnoo/core/services/device_service.dart';
import 'package:learnoo/core/session/session_manager.dart';

/// Auth + account repository.
///
/// Rewritten to match the Next.js student dashboard's model:
///
///  * Students sign in with a **phone number only** — no password field
///    anywhere in login or registration (`app/(auth)/login/page.tsx`).
///  * The login token is held as a *pending* session and is promoted to
///    persistent storage only after the OTP is verified, so closing the app
///    mid-verification returns the student to login rather than into the app.
///  * OTP verification is **mandatory on every sign-in**; the old
///    `phone_verified_at` / feature-flag bypasses are gone.
class AuthRepository {
  final ApiClient _api = ApiClient();
  final SessionManager _session = SessionManager();

  /// Device name sent with login/registration. The web sends `learnoo-web`.
  static const String _fallbackDeviceName = 'learnoo-mobile';

  // Current app version code - update this with each release
  static const int currentVersionCode = 1;

  // Cache keys for watermark data
  static const String _cachedStudentCodeKey = 'cached_student_code';
  static const String _cachedPhoneKey = 'cached_phone';

  // ---------------------------------------------------------------------
  // Result helpers — screens still consume `{success, message, data, errors}`
  // ---------------------------------------------------------------------

  Map<String, dynamic> _ok({
    String? message,
    dynamic data,
    Map<String, dynamic>? extra,
  }) =>
      {
        'success': true,
        if (message != null) 'message': message,
        if (data != null) 'data': data,
        ...?extra,
      };

  Map<String, dynamic> _fail(Object error, String fallback) {
    if (error is ApiException) {
      return {
        'success': false,
        'message': error.display(fallback),
        'errors': error.errors,
        'statusCode': error.status,
      };
    }
    return {'success': false, 'message': fallback, 'statusCode': 0};
  }

  // ---------------------------------------------------------------------
  // OTA update check (unauthenticated, custom key header)
  // ---------------------------------------------------------------------

  /// Check for OTA (Over-The-Air) app updates.
  /// Returns update info if a newer version is available, null otherwise.
  Future<Map<String, dynamic>?> checkForUpdate() async {
    final url = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.otaLatest}');

    try {
      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'X-OTA-Key':
              '196716f9c69164c7b8ef9e2a4bfb9bced668065997b3e987cc900803c7b78c43',
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

        if (versionCode != null && versionCode > currentVersionCode) {
          final lastAcknowledgedVersion = await getLastAcknowledgedVersionCode();
          if (lastAcknowledgedVersion != null &&
              versionCode <= lastAcknowledgedVersion) {
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

  // ---------------------------------------------------------------------
  // Token / session
  // ---------------------------------------------------------------------

  /// Persists a token directly. Prefer [activateSession] for the OTP flow.
  Future<void> saveToken(String token) => _session.setActiveToken(token);

  /// The verified token, or the pending one while OTP is in flight.
  Future<String?> getToken() => _session.currentToken();

  Future<void> deleteToken() => _session.clear();

  /// Promotes the pending login token into persistent storage.
  Future<bool> activateSession() => _session.activateSession();

  Future<int?> getLastAcknowledgedVersionCode() async {
    try {
      final box = Hive.box<dynamic>(HiveBoxes.userProfile);
      final value = box.get('last_acknowledged_version_code');
      return value == null ? null : int.tryParse(value.toString());
    } catch (_) {
      return null;
    }
  }

  Future<void> saveLastAcknowledgedVersionCode(int versionCode) async {
    try {
      final box = Hive.box<dynamic>(HiveBoxes.userProfile);
      await box.put('last_acknowledged_version_code', versionCode.toString());
    } catch (e) {
      debugPrint('Error saving acknowledged version: $e');
    }
  }

  // ---------------------------------------------------------------------
  // Registration & sign-in — passwordless
  // ---------------------------------------------------------------------

  /// Role id sent to `POST /v1/auth/register`, matching the web's
  /// `role: role === "Parent" ? 3 : 1`.
  static const int studentRoleId = 1;
  static const int parentRoleId = 3;

  /// `POST /v1/auth/register`.
  ///
  /// [password] and `role: 3` are sent for the Parent role only — students
  /// register passwordless and verify by OTP. The returned token becomes the
  /// *pending* session; the account is not signed in until either the OTP is
  /// verified (student) or [activateSession] is called (parent, which the web
  /// does immediately because parents skip verification).
  Future<Map<String, dynamic>> register({
    required String firstName,
    required String lastName,
    required String phone,
    required String email,
    String? password,
    int role = studentRoleId,
  }) async {
    try {
      final deviceName = await _deviceName();

      final payload = await _api.post(
        ApiConstants.register,
        includeAuth: false,
        fallback: 'Registration failed',
        body: {
          'first_name': firstName,
          'last_name': lastName,
          'phone': normalizePhone(phone),
          'email': email,
          'device_name': deviceName,
          'role': role,
          if (password != null && password.isNotEmpty) 'password': password,
        },
      );

      _capturePendingAuth(payload);

      return _ok(
        message: payload?['message']?.toString() ?? 'Registration succeeded',
        data: payload,
      );
    } catch (e) {
      return _fail(e, 'Registration failed');
    }
  }

  /// `POST /v1/auth/login`.
  ///
  /// Students send the phone alone and verify by OTP, exactly like the web's
  /// `/login`; parents send [password] as well and are signed in straight away,
  /// like the web's `/parent-login`.
  ///
  /// The token lands in the pending session either way; [activateSession] is
  /// what actually signs the account in.
  Future<Map<String, dynamic>> login({
    required String phone,
    String? password,
  }) async {
    try {
      final deviceName = await _deviceName();

      final payload = await _api.post(
        ApiConstants.login,
        includeAuth: false,
        fallback: 'Login failed',
        body: {
          'phone': normalizePhone(phone),
          'device_name': deviceName,
          if (password != null && password.isNotEmpty) 'password': password,
        },
      );

      _capturePendingAuth(payload);

      return _ok(
        message: payload?['message']?.toString() ?? 'Login successful',
        data: payload,
      );
    } catch (e) {
      return _fail(e, 'Login failed');
    }
  }

  /// Stores `meta.token` + `data` as the pending session.
  void _capturePendingAuth(dynamic payload) {
    if (payload is! Map) return;
    final token = payload['meta']?['token']?.toString();
    if (token == null || token.isEmpty) return;

    final user = payload['data'];
    _session.setPendingAuth(
      token: token,
      user: user is Map ? Map<String, dynamic>.from(user) : null,
    );
  }

  Future<String> _deviceName() async {
    try {
      final name = await DeviceService.getDeviceName();
      return name.trim().isEmpty ? _fallbackDeviceName : name;
    } catch (_) {
      return _fallbackDeviceName;
    }
  }

  /// Strips spaces and leading zeros so `0100…` and `100…` both reach the API
  /// in the same shape the web sends (`login/page.tsx`).
  static String normalizePhone(String raw) {
    return raw.trim().replaceAll(RegExp(r'\s+'), '').replaceFirst(RegExp(r'^0+'), '');
  }

  /// The user id from the pending session — needed to subscribe to the
  /// private OTP channel before the student is signed in.
  String? get pendingUserId {
    final user = _session.pendingUser;
    final id = user?['id'];
    return id?.toString();
  }

  Map<String, dynamic>? get pendingUserAttributes {
    final user = _session.pendingUser;
    final attrs = user?['attributes'];
    return attrs is Map ? Map<String, dynamic>.from(attrs) : null;
  }

  // ---------------------------------------------------------------------
  // OTP
  // ---------------------------------------------------------------------

  /// `POST /v1/auth/phone/verification-notification`.
  ///
  /// The web calls this automatically when the code screen mounts and reads
  /// `response.user.otp` to pre-fill the field, so we return it too.
  /// [token] is accepted for call-site compatibility and ignored — the client
  /// resolves the pending token itself.
  Future<Map<String, dynamic>> sendPhoneVerification([String? token]) async {
    try {
      final payload = await _api.post(
        ApiConstants.phoneVerificationNotification,
        fallback: 'Failed to send verification code',
      );

      return _ok(
        message: payload?['message']?.toString() ?? 'Verification code sent',
        data: payload,
        extra: {'otp': _readOtp(payload)},
      );
    } catch (e) {
      return _fail(e, 'Failed to send verification code');
    }
  }

  Future<Map<String, dynamic>> sendEmailVerification([String? token]) async {
    try {
      final payload = await _api.post(
        ApiConstants.emailVerificationNotification,
        fallback: 'Failed to send verification email',
      );

      return _ok(
        message: payload?['message']?.toString() ?? 'Verification email sent',
        data: payload,
        extra: {'otp': _readOtp(payload)},
      );
    } catch (e) {
      return _fail(e, 'Failed to send verification email');
    }
  }

  /// Pulls the login code out of a verification-notification response.
  ///
  /// The endpoint answers {"message":"sent","code":"O0268A"} — a six character
  /// **alphanumeric** code under `code`. The web reads `response.user.otp`,
  /// which is not in that body at all, so its HTTP fill silently does nothing
  /// and it depends on the websocket alone. Read `code` first and keep the
  /// other shapes as fallbacks in case the broadcast payload is shaped
  /// differently.
  String? _readOtp(dynamic payload) {
    if (payload is! Map) return null;

    final user = payload['user'];
    for (final candidate in [
      payload['code'],
      payload['otp'],
      user is Map ? user['otp'] : null,
      user is Map ? user['code'] : null,
    ]) {
      final s = candidate?.toString().trim();
      if (s != null && s.isNotEmpty) return s;
    }
    return null;
  }

  /// `POST /v1/auth/phone/verify`, then promotes the pending session.
  ///
  /// A wrong code answers 401 — a business rule, not an expired session — so
  /// the auth redirect is skipped and the student stays on the code screen.
  Future<Map<String, dynamic>> verifyPhoneOtp(String code) async {
    try {
      final payload = await _api.post(
        ApiConstants.verifyPhone,
        body: {'code': code},
        skipAuthRedirect: true,
        fallback: 'Failed to verify phone',
      );

      final activated = await _session.activateSession();
      if (!activated) {
        return {
          'success': false,
          'message': 'Session expired, please sign in again',
          'sessionLost': true,
        };
      }

      return _ok(
        message: payload?['message']?.toString() ?? 'Phone verified successfully',
        data: payload,
      );
    } catch (e) {
      return _fail(e, 'Failed to verify phone');
    }
  }

  Future<Map<String, dynamic>> verifyEmailOtp(String code) async {
    try {
      final payload = await _api.post(
        ApiConstants.verifyEmail,
        body: {'code': code},
        skipAuthRedirect: true,
        fallback: 'Failed to verify email',
      );

      final activated = await _session.activateSession();
      if (!activated) {
        return {
          'success': false,
          'message': 'Session expired, please sign in again',
          'sessionLost': true,
        };
      }

      return _ok(
        message: payload?['message']?.toString() ?? 'Email verified successfully',
        data: payload,
      );
    } catch (e) {
      return _fail(e, 'Failed to verify email');
    }
  }

  // ---------------------------------------------------------------------
  // Academic hierarchy
  // ---------------------------------------------------------------------

  Future<Map<String, dynamic>> getUniversities() =>
      _list(ApiConstants.universities, 'Failed to fetch universities');

  Future<Map<String, dynamic>> getCenters() =>
      _list(ApiConstants.centers, 'Failed to fetch centers');

  Future<Map<String, dynamic>> getFaculties() =>
      _list(ApiConstants.faculties, 'Failed to fetch faculties');

  Future<Map<String, dynamic>> _list(String path, String fallback) async {
    try {
      final payload = await _api.get(path, fallback: fallback);
      return _ok(data: unwrapList(payload));
    } catch (e) {
      return _fail(e, fallback);
    }
  }

  /// `PUT /v1/auth/update` with the academic selection.
  ///
  /// Sends the same field set as `buildStudentAcademicUpdatePayload` on the
  /// web: `centers[]` **and** the singular `center_id`, plus the optional
  /// `department_id` the app used to omit entirely.
  Future<Map<String, dynamic>> updateAcademicProfile({
    required dynamic universityId,
    required dynamic centerId,
    required dynamic facultyId,
    dynamic departmentId,
  }) {
    final center = int.tryParse(centerId.toString()) ?? centerId;

    return updateProfile({
      'university_id': universityId.toString(),
      'faculty_id': int.tryParse(facultyId.toString()) ?? facultyId,
      'centers': [center],
      'center_id': center,
      if (departmentId != null && departmentId.toString().isNotEmpty)
        'department_id':
            int.tryParse(departmentId.toString()) ?? departmentId,
    });
  }

  Future<Map<String, dynamic>> updateProfile(Map<String, dynamic> body) async {
    try {
      final payload = await _api.put(
        ApiConstants.updateProfile,
        body: body,
        fallback: 'Failed to update profile',
      );

      return _ok(
        message: payload?['message']?.toString() ?? 'Profile updated successfully',
        data: payload?['data'],
      );
    } catch (e) {
      return _fail(e, 'Failed to update profile');
    }
  }

  Future<Map<String, dynamic>> updateProfileWithImage({
    required Map<String, dynamic> profileData,
    File? imageFile,
  }) async {
    try {
      final payload = await _api.multipart(
        ApiConstants.updateProfile,
        method: 'PUT',
        fields: profileData,
        files: imageFile == null ? const {} : {'image': imageFile.path},
        fallback: 'Failed to update profile',
      );

      return _ok(
        message: payload?['message']?.toString() ?? 'Profile updated successfully',
        data: payload?['data'],
      );
    } catch (e) {
      return _fail(e, 'Failed to update profile');
    }
  }

  // ---------------------------------------------------------------------
  // Profile
  // ---------------------------------------------------------------------

  Future<Map<String, dynamic>> getProfile() async {
    try {
      final payload = await _api.get(
        ApiConstants.me,
        fallback: 'Failed to fetch profile',
      );

      final data = payload is Map ? payload['data'] : null;
      await _cacheWatermarkData(data is Map ? Map<String, dynamic>.from(data) : null);

      return _ok(data: data);
    } catch (e) {
      return _fail(e, 'Failed to fetch profile');
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

  Future<void> clearCachedWatermarkData() async {
    try {
      final box = Hive.box<dynamic>(HiveBoxes.userProfile);
      await box.delete(_cachedStudentCodeKey);
      await box.delete(_cachedPhoneKey);
    } catch (e) {
      debugPrint('Error clearing cached watermark data: $e');
    }
  }

  // ---------------------------------------------------------------------
  // Password reset — unchanged contract, matches the web exactly
  // ---------------------------------------------------------------------

  Future<Map<String, dynamic>> requestPasswordReset(String phoneOrEmail) async {
    try {
      final payload = await _api.post(
        ApiConstants.passwordForgot,
        includeAuth: false,
        body: {'phone_or_email': phoneOrEmail},
        fallback: 'Failed to send password reset code',
      );
      return _ok(
        message: payload?['message']?.toString() ??
            'Password reset code sent successfully',
        data: payload,
      );
    } catch (e) {
      return _fail(e, 'Failed to send password reset code');
    }
  }

  Future<Map<String, dynamic>> verifyPasswordReset({
    required String phoneOrEmail,
    required String code,
  }) async {
    try {
      final payload = await _api.post(
        ApiConstants.passwordReset,
        includeAuth: false,
        skipAuthRedirect: true,
        body: {
          'type': 'verify',
          'code': code,
          'phone_or_email': phoneOrEmail,
        },
        fallback: 'Failed to verify code',
      );
      return _ok(
        message: payload?['message']?.toString() ?? 'Code verified successfully',
        data: payload,
      );
    } catch (e) {
      return _fail(e, 'Failed to verify code');
    }
  }

  Future<Map<String, dynamic>> resetPassword({
    required String phoneOrEmail,
    required String code,
    required String password,
    required String passwordConfirmation,
  }) async {
    try {
      final payload = await _api.post(
        ApiConstants.passwordReset,
        includeAuth: false,
        skipAuthRedirect: true,
        body: {
          'type': 'reset',
          'code': code,
          'phone_or_email': phoneOrEmail,
          'password': password,
          'password_confirmation': passwordConfirmation,
        },
        fallback: 'Failed to reset password',
      );
      return _ok(
        message: payload?['message']?.toString() ?? 'Password reset successfully',
        data: payload,
      );
    } catch (e) {
      return _fail(e, 'Failed to reset password');
    }
  }

  // ---------------------------------------------------------------------
  // Logout
  // ---------------------------------------------------------------------

  /// `POST /v1/auth/logout`.
  ///
  /// 204 and 401 both count as success (the web treats an already-expired
  /// token as a completed logout), and the local session is cleared either way.
  Future<Map<String, dynamic>> logout() async {
    String message = 'Logged out successfully';
    try {
      final payload = await _api.post(
        ApiConstants.logout,
        skipAuthRedirect: true,
        fallback: 'Logout failed',
      );
      final m = payload is Map ? payload['message']?.toString() : null;
      if (m != null && m.isNotEmpty) message = m;
    } on ApiException catch (e) {
      if (!e.isUnauthorized) {
        await _clearLocalSession();
        return {'success': false, 'message': e.display('Logout failed')};
      }
      message = 'Session expired, logged out';
    } catch (_) {
      // Network failure — still clear locally so the student is not stuck.
    }

    await _clearLocalSession();
    return _ok(message: message);
  }

  Future<void> _clearLocalSession() async {
    await clearCachedWatermarkData();
    await _session.clear();
  }
}
