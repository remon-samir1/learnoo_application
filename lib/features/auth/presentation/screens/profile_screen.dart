import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_logo.dart';
import '../../../../core/widgets/country_code_field.dart';
import '../../../../core/widgets/custom_text_field.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../data/auth_repository.dart';
import '../../../parent/presentation/screens/link_student_screen.dart';
import '../screens/login_screen.dart';
import '../screens/otp_verification_screen.dart';

/// Which account the form is creating. Maps to `role: 1` / `role: 3`.
enum RegisterRole { student, parent }

/// Registration, matching `app/(auth)/create-account/page.tsx`.
///
/// The role switch at the top decides the whole flow, exactly as on the web:
/// a student registers passwordless and continues to the OTP screen, while a
/// parent sets a password, is signed in immediately and continues to
/// "link a student".
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  final _authRepository = AuthRepository();

  String _countryCode = kDefaultCountryCode;
  RegisterRole _role = RegisterRole.student;
  bool _isLoading = false;
  bool _acceptTerms = false;

  bool get _isParent => _role == RegisterRole.parent;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _showSnack(String message, Color color, IconData icon) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _errorText(Map<String, dynamic> result, String fallback) {
    final errors = result['errors'];
    if (errors is Map) {
      final messages = errors.entries
          .where((e) => e.value is List && (e.value as List).isNotEmpty)
          .map((e) {
            final field = e.key;
            final first = (e.value as List).first.toString();
            return field == 'device' ? first : '$field: $first';
          })
          .join('\n');
      if (messages.isNotEmpty) return messages;
    }
    return result['message']?.toString() ?? fallback;
  }

  Future<void> _handleRegister() async {
    if (!_acceptTerms) {
      _showSnack('auth.accept_terms_snack'.tr(), Colors.blue, Icons.info_outline);
      return;
    }

    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    final email = _emailController.text.trim();
    final national = _phoneController.text.trim();

    if (firstName.isEmpty ||
        lastName.isEmpty ||
        email.isEmpty ||
        national.isEmpty) {
      _showSnack(
        'auth.fill_all_fields_snack'.tr(),
        Colors.red,
        Icons.error_outline,
      );
      return;
    }

    final password = _passwordController.text;
    if (_isParent) {
      if (password.isEmpty || password != _confirmPasswordController.text) {
        _showSnack(
          'auth.password_mismatch'.tr(),
          Colors.red,
          Icons.error_outline,
        );
        return;
      }
    }

    setState(() => _isLoading = true);

    final fullPhone = CountryCodeField.fullNumber(_countryCode, national);

    final result = await _authRepository.register(
      firstName: firstName,
      lastName: lastName,
      phone: fullPhone,
      email: email,
      password: _isParent ? password : null,
      role: _isParent
          ? AuthRepository.parentRoleId
          : AuthRepository.studentRoleId,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result['success'] != true) {
      _showSnack(
        _errorText(result, 'auth.register_failed'.tr()),
        Colors.red,
        Icons.error_outline,
      );
      return;
    }

    _showSnack(
      result['message']?.toString() ?? 'auth.register_success'.tr(),
      AppColors.joinLiveGreen,
      Icons.check_circle,
    );

    if (_isParent) {
      // The web activates the session right away and routes to link-student —
      // parents never see the OTP screen.
      await _authRepository.activateSession();
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LinkStudentScreen()),
      );
      return;
    }

    // Straight to the code screen — same as the web, which never offers a
    // channel picker for students.
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => OtpVerificationScreen(
          isRegister: true,
          phone: fullPhone,
          isEmail: false,
        ),
      ),
    );
  }

  /// Segmented Student / Parent switch, the app's version of the web's role
  /// tab strip.
  Widget _roleSelector() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _roleTab(RegisterRole.student, 'auth.role_student'.tr()),
          _roleTab(RegisterRole.parent, 'auth.role_parent'.tr()),
        ],
      ),
    );
  }

  Widget _roleTab(RegisterRole role, String label) {
    final selected = _role == role;
    return Expanded(
      child: GestureDetector(
        onTap: _isLoading ? null : () => setState(() => _role = role),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: selected
                ? const [
                    BoxShadow(
                      color: Color(0x14000000),
                      blurRadius: 4,
                      offset: Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: selected ? const Color(0xFF1F2937) : AppColors.textGray,
            ),
          ),
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
                    'auth.complete_profile'.tr(),
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
                      'auth.profile_verify_desc'.tr(),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 24.0,
                vertical: 32.0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _roleSelector(),
                  const SizedBox(height: 18),
                  CustomTextField(
                    label: 'auth.first_name'.tr(),
                    hintText: 'auth.first_name_hint'.tr(),
                    controller: _firstNameController,
                  ),
                  const SizedBox(height: 18),
                  CustomTextField(
                    label: 'auth.last_name'.tr(),
                    hintText: 'auth.last_name_hint'.tr(),
                    controller: _lastNameController,
                  ),
                  const SizedBox(height: 18),
                  CustomTextField(
                    label: 'auth.email_label'.tr(),
                    hintText: 'auth.email_hint'.tr(),
                    keyboardType: TextInputType.emailAddress,
                    controller: _emailController,
                  ),
                  const SizedBox(height: 18),
                  CountryCodeField(
                    controller: _phoneController,
                    countryCode: _countryCode,
                    onCountryChanged: (code) =>
                        setState(() => _countryCode = code),
                    label: 'auth.phone_label'.tr(),
                    hintText: 'auth.phone_hint'.tr(),
                    enabled: !_isLoading,
                  ),
                  if (_isParent) ...[
                    const SizedBox(height: 18),
                    CustomTextField(
                      label: 'auth.password'.tr(),
                      hintText: 'auth.password_hint'.tr(),
                      isPassword: true,
                      controller: _passwordController,
                    ),
                    const SizedBox(height: 18),
                    CustomTextField(
                      label: 'auth.confirm_password'.tr(),
                      hintText: 'auth.confirm_password_hint'.tr(),
                      isPassword: true,
                      controller: _confirmPasswordController,
                    ),
                  ],
                  const SizedBox(height: 16),
                  if (!_isParent)
                    Text(
                      'auth.login_code_hint'.tr(),
                      style: const TextStyle(
                        color: AppColors.textGray,
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      SizedBox(
                        height: 24,
                        width: 24,
                        child: Checkbox(
                          value: _acceptTerms,
                          onChanged: (val) =>
                              setState(() => _acceptTerms = val ?? false),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: RichText(
                          text: TextSpan(
                            style: const TextStyle(
                              color: AppColors.textGray,
                              fontSize: 13,
                              height: 1.4,
                              fontFamily: 'Inter',
                            ),
                            children: [
                              TextSpan(text: 'auth.read_accept'.tr()),
                              TextSpan(
                                text: 'auth.terms_conditions'.tr(),
                                style: const TextStyle(
                                  color: Colors.blue,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  PrimaryButton(
                    text: 'auth.create_account'.tr(),
                    isLoading: _isLoading,
                    onPressed: _isLoading ? null : _handleRegister,
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'auth.have_account'.tr(),
                        style: const TextStyle(
                          color: AppColors.textGray,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const LoginScreen(),
                            ),
                          );
                        },
                        child: Text(
                          'auth.login_link'.tr(),
                          style: const TextStyle(
                            color: Colors.blue,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
