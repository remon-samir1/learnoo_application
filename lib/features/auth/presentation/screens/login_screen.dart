import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_logo.dart';
import '../../../../core/widgets/country_code_field.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../data/auth_repository.dart';
import '../../domain/device_authorization.dart';
import '../../../parent/presentation/screens/parent_login_screen.dart';
import '../screens/forgot_password_screen.dart';
import '../screens/otp_verification_screen.dart';
import '../screens/profile_screen.dart';

/// Passwordless sign-in, matching `app/(auth)/login/page.tsx`.
///
/// The student enters a phone number; the backend answers with a token that is
/// held as a *pending* session and a code sent over SMS and the private Reverb
/// channel. Nothing is persisted until that code is verified — so there is no
/// password field here, and no bypass of the code screen.
///
/// Device authorization is handled exactly like the web: the account is bound
/// to one device (the `X-Device-ID` header every request carries), and a login
/// from any other device is refused with `code: device_transfer_required`. The
/// refusal is shown inline together with an action that asks staff to move the
/// account to this device; once the request is sent the action disappears and
/// the student waits for approval, then signs in again normally.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.sessionNotice});

  /// Why the student landed here, when they were pushed back by a revoked
  /// session. Mirrors `/login?session=device-changed|expired` on the web.
  final SessionEndReason? sessionNotice;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phoneController = TextEditingController();
  final _authRepository = AuthRepository();

  String _countryCode = kDefaultCountryCode;
  bool _isLoading = false;

  /// Inline message for the last failed attempt (the web's `error` box).
  String? _errorMessage;

  /// Set when that failure was "this device is not authorized".
  DeviceAuthorizationChallenge? _challenge;

  bool _requestingAuthorization = false;
  bool _authorizationRequestSent = false;

  @override
  void initState() {
    super.initState();
    _phoneController.addListener(_clearDeviceState);
  }

  @override
  void dispose() {
    _phoneController.removeListener(_clearDeviceState);
    _phoneController.dispose();
    super.dispose();
  }

  /// Editing the number (or switching country) invalidates the refusal and the
  /// transfer token it carried — the web resets the same three pieces of state
  /// in `useEffect(..., [phone, country])`.
  void _clearDeviceState() {
    if (_errorMessage == null &&
        _challenge == null &&
        !_authorizationRequestSent) {
      return;
    }
    setState(() {
      _errorMessage = null;
      _challenge = null;
      _authorizationRequestSent = false;
    });
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Flattens a Laravel validation bag into one readable message.
  String _errorText(Map<String, dynamic> result, String fallback) {
    final errors = result['errors'];
    if (errors is Map) {
      final messages = errors.entries
          .where((e) => e.value is List && (e.value as List).isNotEmpty)
          .map((e) {
            final field = e.key;
            final first = (e.value as List).first.toString();
            // Device-limit errors read as full sentences already.
            return field == 'device' ? first : '$field: $first';
          })
          .join('\n');
      if (messages.isNotEmpty) return messages;
    }
    return result['message']?.toString() ?? fallback;
  }

  Future<void> _handleLogin() async {
    final national = _phoneController.text.trim();

    if (national.isEmpty) {
      _showError('auth.fill_all_fields'.tr());
      return;
    }

    // A leading trunk zero is accepted and stripped silently by
    // [CountryCodeField.fullNumber], matching the web client.
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _challenge = null;
      _authorizationRequestSent = false;
    });

    final fullPhone = CountryCodeField.fullNumber(_countryCode, national);
    final result = await _authRepository.login(phone: fullPhone);

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result['success'] != true) {
      final fallback = 'auth.login_failed'.tr();
      final message = _errorText(result, fallback);
      final challenge = DeviceAuthorizationChallenge.fromResult(
        result,
        fallbackMessage: message,
      );
      setState(() {
        _errorMessage = message;
        _challenge = challenge;
      });
      // A device refusal is explained inline, with the action attached to it;
      // anything else also pops the usual snackbar, like the web's toast.
      if (challenge == null) _showError(message);
      return;
    }

    // Verification is mandatory on every sign-in — the session is still pending.
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => OtpVerificationScreen(
          isRegister: false,
          phone: fullPhone,
          isEmail: false,
        ),
      ),
    );
  }

  /// Sends the authorization request for this device and switches to the
  /// "waiting for approval" state. On failure the student keeps the action and
  /// can try again — there is no cooldown, on the web either.
  Future<void> _requestDeviceAuthorization() async {
    final challenge = _challenge;
    if (challenge == null || !challenge.canRequestAuthorization) return;
    if (_requestingAuthorization) return;

    setState(() => _requestingAuthorization = true);
    final result =
        await _authRepository.requestDeviceTransfer(challenge.transferToken);

    if (!mounted) return;
    setState(() {
      _requestingAuthorization = false;
      if (result['success'] == true) {
        _authorizationRequestSent = true;
        _errorMessage = null;
        _challenge = null;
      } else {
        _errorMessage =
            _errorText(result, 'auth.device_request_failed'.tr());
      }
    });
  }

  Widget _noticeBox({
    required String message,
    required Color background,
    required Color border,
    required Color text,
    Widget? action,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: TextStyle(color: text, fontSize: 13, height: 1.5),
          ),
          if (action != null) ...[const SizedBox(height: 8), action],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.only(top: 80, bottom: 50),
              decoration: const BoxDecoration(
                gradient: AppColors.mainGradient,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(50),
                  bottomRight: Radius.circular(50),
                ),
              ),
              child: Column(
                children: [
                  const AppLogo(size: 85),
                  const SizedBox(height: 24),
                  Text(
                    'auth.welcome_login'.tr(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Text(
                      'auth.verify_identity_login'.tr(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24.0, vertical: 40.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.sessionNotice != null)
                    _noticeBox(
                      message: widget.sessionNotice ==
                              SessionEndReason.deviceChanged
                          ? 'auth.session_device_changed'.tr()
                          : 'auth.session_expired'.tr(),
                      background: const Color(0xFFEFF6FF),
                      border: const Color(0xFFBFDBFE),
                      text: const Color(0xFF1E40AF),
                    ),
                  if (_errorMessage != null)
                    _noticeBox(
                      message: _errorMessage!,
                      background: const Color(0xFFFEF2F2),
                      border: const Color(0xFFFECACA),
                      text: const Color(0xFFB91C1C),
                      action: (_challenge?.canRequestAuthorization ?? false)
                          ? TextButton(
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: const Size(0, 32),
                                tapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                alignment: AlignmentDirectional.centerStart,
                              ),
                              onPressed:
                                  _requestingAuthorization || _isLoading
                                      ? null
                                      : _requestDeviceAuthorization,
                              child: Text(
                                _requestingAuthorization
                                    ? 'auth.sending_device_request'.tr()
                                    : 'auth.send_device_request'.tr(),
                                style: const TextStyle(
                                  color: AppColors.primaryBlue,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            )
                          : null,
                    ),
                  if (_authorizationRequestSent)
                    _noticeBox(
                      message: 'auth.device_request_sent'.tr(),
                      background: const Color(0xFFECFDF5),
                      border: const Color(0xFFA7F3D0),
                      text: const Color(0xFF065F46),
                    ),
                  CountryCodeField(
                    controller: _phoneController,
                    countryCode: _countryCode,
                    onCountryChanged: (code) {
                      setState(() => _countryCode = code);
                      _clearDeviceState();
                    },
                    label: 'auth.phone'.tr(),
                    hintText: 'auth.phone_hint'.tr(),
                    enabled: !_isLoading,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'auth.login_code_hint'.tr(),
                    style: const TextStyle(
                      color: AppColors.textGray,
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 32),
                  PrimaryButton(
                    text: 'auth.login'.tr(),
                    isLoading: _isLoading,
                    onPressed: _isLoading ? null : _handleLogin,
                  ),
                  const SizedBox(height: 20),
                  Center(
                    child: TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const ForgotPasswordScreen(),
                          ),
                        );
                      },
                      child: Text(
                        'auth.forget_password'.tr(),
                        style: const TextStyle(
                          color: AppColors.textGray,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                  Center(
                    child: TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const ParentLoginScreen(),
                          ),
                        );
                      },
                      child: Text(
                        'auth.parent_login_link'.tr(),
                        style: const TextStyle(
                          color: AppColors.primaryBlue,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'auth.dont_have_account'.tr(),
                        style: const TextStyle(
                          color: AppColors.textGray,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const ProfileScreen(),
                            ),
                          );
                        },
                        child: Text(
                          'auth.sign_up'.tr(),
                          style: const TextStyle(
                            color: Colors.blue,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
