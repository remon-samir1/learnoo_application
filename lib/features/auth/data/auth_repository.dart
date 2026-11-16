import 'package:easy_localization/easy_localization.dart';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:learnoo/core/local/hive_boxes.dart';
import 'package:learnoo/core/network/api_client.dart';
import 'package:learnoo/core/network/api_constants.dart';
import 'package:learnoo/core/network/api_exception.dart';
import 'package:learnoo/core/services/device_service.dart';
import 'package:learnoo/core/services/push_service.dart';
import 'package:learnoo/core/services/student_scope.dart';
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
        // `code` / `transferToken` carry the device-authorization refusal
        // (`device_transfer_required`) to the screen, like `ApiError` does on
        // the web.
        'code': ?error.code,
        'transferToken': ?error.transferToken,
      };
    }
    return {'success': false, 'message': fallback, 'statusCode': 0};
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

  // ---------------------------------------------------------------------
  // Registration & sign-in — passwordless
  // ---------------------------------------------------------------------

  /// Role id sent to `POST /v1/auth/register`: the server's
  /// `UserRole::STUDENT`, the same `role: 0` the web's create-account sends.
  static const int studentRoleId = 0;

  /// `POST /v1/auth/register` — student accounts only.
  ///
  /// Students register passwordless and verify by OTP. Parent registration is
  /// paused in the app and refused by the server; existing parents sign in
  /// through [login] with a password. The returned token becomes the *pending*
  /// session; the account is not signed in until the OTP is verified.
  Future<Map<String, dynamic>> register({
    required String firstName,
    required String lastName,
    required String phone,
    required String email,
  }) async {
    try {
      final deviceName = await _deviceName();

      final payload = await _api.post(
        ApiConstants.register,
        includeAuth: false,
        fallback: 'auth.register_failed'.tr(),
        body: {
          'first_name': firstName,
          'last_name': lastName,
          'phone': normalizePhone(phone),
          'email': email,
          'device_name': deviceName,
          'role': studentRoleId,
        },
      );

      _capturePendingAuth(payload);

      return _ok(
        message: payload?['message']?.toString() ?? 'errors.registration_succeeded'.tr(),
        data: payload,
      );
    } catch (e) {
      return _fail(e, 'auth.register_failed'.tr());
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
        fallback: 'auth.login_failed'.tr(),
        body: {
          'phone': normalizePhone(phone),
          'device_name': deviceName,
          if (password != null && password.isNotEmpty) 'password': password,
        },
      );

      _capturePendingAuth(payload);

      return _ok(
        message: payload?['message']?.toString() ?? 'errors.login_successful'.tr(),
        data: payload,
      );
    } catch (e) {
      return _fail(e, 'auth.login_failed'.tr());
    }
  }

  /// `POST /v1/auth/device-transfer`.
  ///
  /// Asks staff to authorize the device that was just refused, replaying the
  /// one-shot `transfer_token` from the `device_transfer_required` body. The
  /// call is unauthenticated (the student has no session yet) and opts out of
  /// the 401 redirect, exactly like `authApi.requestDeviceTransfer` on the web.
  ///
  /// Staff see the request in the dashboard's device approvals and, once they
  /// approve, the student signs in normally from this device.
  Future<Map<String, dynamic>> requestDeviceTransfer(
      String transferToken) async {
    if (transferToken.isEmpty) {
      return {
        'success': false,
        'message': 'auth.device_request_failed'.tr(),
        'statusCode': 0,
      };
    }

    try {
      final payload = await _api.post(
        ApiConstants.deviceTransfer,
        includeAuth: false,
        skipAuthRedirect: true,
        body: {'transfer_token': transferToken},
        fallback: 'auth.device_request_failed'.tr(),
      );

      return _ok(
        message: payload?['message']?.toString() ??
            'auth.device_request_sent'.tr(),
        data: payload,
      );
    } catch (e) {
      return _fail(e, 'auth.device_request_failed'.tr());
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
        fallback: 'auth.failed_send_code'.tr(),
      );

      return _ok(
        message: payload?['message']?.toString() ?? 'errors.verification_code_sent'.tr(),
        data: payload,
        extra: {'otp': _readOtp(payload)},
      );
    } catch (e) {
      return _fail(e, 'auth.failed_send_code'.tr());
    }
  }

  Future<Map<String, dynamic>> sendEmailVerification([String? token]) async {
    try {
      final payload = await _api.post(
        ApiConstants.emailVerificationNotification,
        fallback: 'errors.failed_send_verification_email'.tr(),
      );

      return _ok(
        message: payload?['message']?.toString() ?? 'errors.verification_email_sent'.tr(),
        data: payload,
        extra: {'otp': _readOtp(payload)},
      );
    } catch (e) {
      return _fail(e, 'errors.failed_send_verification_email'.tr());
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
        fallback: 'errors.failed_verify_phone'.tr(),
      );

      final activated = await _session.activateSession();
      if (!activated) {
        return {
          'success': false,
          'message': 'errors.session_expired_sign_in'.tr(),
          'sessionLost': true,
        };
      }

      return _ok(
        message: payload?['message']?.toString() ?? 'errors.phone_verified'.tr(),
        data: payload,
      );
    } catch (e) {
      return _fail(e, 'errors.failed_verify_phone'.tr());
    }
  }

  Future<Map<String, dynamic>> verifyEmailOtp(String code) async {
    try {
      final payload = await _api.post(
        ApiConstants.verifyEmail,
        body: {'code': code},
        skipAuthRedirect: true,
        fallback: 'errors.failed_verify_email'.tr(),
      );

      final activated = await _session.activateSession();
      if (!activated) {
        return {
          'success': false,
          'message': 'errors.session_expired_sign_in'.tr(),
          'sessionLost': true,
        };
      }

      return _ok(
        message: payload?['message']?.toString() ?? 'errors.email_verified'.tr(),
        data: payload,
      );
    } catch (e) {
      return _fail(e, 'errors.failed_verify_email'.tr());
    }
  }

  // ---------------------------------------------------------------------
  // Academic hierarchy
  // ---------------------------------------------------------------------

  Future<Map<String, dynamic>> getUniversities() =>
      _list(ApiConstants.universities, 'errors.failed_fetch_universities'.tr());

  Future<Map<String, dynamic>> getCenters() =>
      _list(ApiConstants.centers, 'errors.failed_fetch_centers'.tr());

  Future<Map<String, dynamic>> getFaculties() =>
      _list(ApiConstants.faculties, 'errors.failed_fetch_faculties'.tr());

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
        fallback: 'profile.failed_update_profile'.tr(),
      );

      return _ok(
        message: payload?['message']?.toString() ?? 'errors.profile_updated'.tr(),
        data: payload?['data'],
      );
    } catch (e) {
      return _fail(e, 'profile.failed_update_profile'.tr());
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
        fallback: 'profile.failed_update_profile'.tr(),
      );

      return _ok(
        message: payload?['message']?.toString() ?? 'errors.profile_updated'.tr(),
        data: payload?['data'],
      );
    } catch (e) {
      return _fail(e, 'profile.failed_update_profile'.tr());
    }
  }

  // ---------------------------------------------------------------------
  // Profile
  // ---------------------------------------------------------------------

  Future<Map<String, dynamic>> getProfile() async {
    try {
      final payload = await _api.get(
        ApiConstants.me,
        fallback: 'errors.failed_fetch_profile'.tr(),
      );

      final data = payload is Map ? payload['data'] : null;
      await _cacheWatermarkData(data is Map ? Map<String, dynamic>.from(data) : null);

      return _ok(data: data);
    } catch (e) {
      return _fail(e, 'errors.failed_fetch_profile'.tr());
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
        fallback: 'errors.failed_send_reset_code'.tr(),
      );
      return _ok(
        message: payload?['message']?.toString() ??
            'errors.reset_code_sent'.tr(),
        data: payload,
      );
    } catch (e) {
      return _fail(e, 'errors.failed_send_reset_code'.tr());
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
        fallback: 'auth.failed_verify'.tr(),
      );
      return _ok(
        message: payload?['message']?.toString() ?? 'errors.code_verified'.tr(),
        data: payload,
      );
    } catch (e) {
      return _fail(e, 'auth.failed_verify'.tr());
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
        fallback: 'auth.failed_reset'.tr(),
      );
      return _ok(
        message: payload?['message']?.toString() ?? 'errors.password_reset'.tr(),
        data: payload,
      );
    } catch (e) {
      return _fail(e, 'auth.failed_reset'.tr());
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
    String message = 'errors.logged_out'.tr();
    // While still signed in: this phone stops getting the student's pushes.
    await PushService().unregister();
    try {
      final payload = await _api.post(
        ApiConstants.logout,
        skipAuthRedirect: true,
        fallback: 'errors.logout_failed'.tr(),
      );
      final m = payload is Map ? payload['message']?.toString() : null;
      if (m != null && m.isNotEmpty) message = m;
    } on ApiException catch (e) {
      if (!e.isUnauthorized) {
        await _clearLocalSession();
        return {'success': false, 'message': e.display('errors.logout_failed'.tr())};
      }
      message = 'errors.session_expired_logged_out'.tr();
    } catch (_) {
      // Network failure — still clear locally so the student is not stuck.
    }

    await _clearLocalSession();
    return _ok(message: message);
  }

  Future<void> _clearLocalSession() async {
    await clearCachedWatermarkData();
    // The memoised course scope belongs to this student; the next account
    // signing in on this device must not inherit it.
    StudentScopeService().invalidate();
    await _session.clear();
  }
}
