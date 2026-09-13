import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_logo.dart';
import '../../../../core/widgets/country_code_field.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../data/auth_repository.dart';
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
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phoneController = TextEditingController();
  final _authRepository = AuthRepository();

  String _countryCode = kDefaultCountryCode;
  bool _isLoading = false;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
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
    setState(() => _isLoading = true);

    final fullPhone = CountryCodeField.fullNumber(_countryCode, national);
    final result = await _authRepository.login(phone: fullPhone);

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result['success'] != true) {
      _showError(_errorText(result, 'auth.login_failed'.tr()));
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
                  CountryCodeField(
                    controller: _phoneController,
                    countryCode: _countryCode,
                    onCountryChanged: (code) =>
                        setState(() => _countryCode = code),
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
