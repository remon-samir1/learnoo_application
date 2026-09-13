import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/country_code_field.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../auth/data/auth_repository.dart';
import 'parent_dashboard_screen.dart';

/// Parent sign-in — the app's counterpart to the web's `/parent-login`.
///
/// Unlike the student flow this is phone **plus password** and there is no OTP
/// step: the web calls `loginWithCookies` and lands on the parent dashboard
/// immediately, so here the pending session is activated as soon as the login
/// call succeeds.
class ParentLoginScreen extends StatefulWidget {
  const ParentLoginScreen({super.key});

  @override
  State<ParentLoginScreen> createState() => _ParentLoginScreenState();
}

class _ParentLoginScreenState extends State<ParentLoginScreen> {
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authRepository = AuthRepository();

  String _countryCode = kDefaultCountryCode;
  bool _obscurePassword = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  Future<void> _handleLogin() async {
    final national = _phoneController.text.trim();
    final password = _passwordController.text;

    if (national.isEmpty || password.isEmpty) {
      _showError('auth.fill_all_fields'.tr());
      return;
    }

    setState(() => _isLoading = true);

    final fullPhone = CountryCodeField.fullNumber(_countryCode, national);
    final result = await _authRepository.login(
      phone: fullPhone,
      password: password,
    );

    if (!mounted) return;

    if (result['success'] != true) {
      setState(() => _isLoading = false);
      _showError(result['message']?.toString() ?? 'auth.login_failed'.tr());
      return;
    }

    final activated = await _authRepository.activateSession();

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (!activated) {
      _showError('auth.login_failed'.tr());
      return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const ParentDashboardScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.black87,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'auth.parent_login_title'.tr(),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1F2937),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'auth.parent_login_subtitle'.tr(),
                style: const TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
              ),
              const SizedBox(height: 32),
              CountryCodeField(
                controller: _phoneController,
                countryCode: _countryCode,
                onCountryChanged: (code) => setState(() => _countryCode = code),
                label: 'auth.phone'.tr(),
                hintText: 'auth.phone_hint'.tr(),
              ),
              const SizedBox(height: 20),
              Text(
                'auth.password'.tr(),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF374151),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  hintText: 'auth.password_hint'.tr(),
                  filled: true,
                  fillColor: AppColors.inputFill,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      color: const Color(0xFF9CA3AF),
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.inputBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.inputBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: AppColors.primaryBlue,
                      width: 2,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              PrimaryButton(
                text: 'auth.sign_in'.tr(),
                isLoading: _isLoading,
                onPressed: _handleLogin,
              ),
              const SizedBox(height: 16),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('auth.student_login_link'.tr()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
