import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_logo.dart';
import '../../../../core/widgets/custom_text_field.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../data/auth_repository.dart';
import 'reset_password_verification_screen.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _authRepository = AuthRepository();
  bool _isLoading = false;
  bool _isEmailMode = true;

  @override
  void dispose() {
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _handleSend() async {
    final contact = _isEmailMode
        ? _emailController.text.trim()
        : _phoneController.text.trim();

    if (contact.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isEmailMode
              ? 'auth.enter_email_snack'.tr()
              : 'auth.enter_phone_snack'.tr()),
        ),
      );
      return;
    }

    if (_isEmailMode && !_isValidEmail(contact)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('auth.valid_email_snack'.tr())),
      );
      return;
    }

    setState(() => _isLoading = true);

    final result = await _authRepository.requestPasswordReset(contact);

    setState(() => _isLoading = false);

    if (mounted) {
      if (result['success']) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ResetPasswordVerificationScreen(
              phoneOrEmail: contact,
              isEmail: _isEmailMode,
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'auth.failed_send_code'.tr()),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  bool _isValidEmail(String email) {
    return email.contains('@') && email.contains('.');
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
                    _isEmailMode
                        ? 'auth.forgot_email_desc'.tr()
                        : 'auth.forgot_phone_desc'.tr(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildModeToggle(),
                  const SizedBox(height: 24),
                  if (_isEmailMode)
                    CustomTextField(
                      label: 'auth.email_label'.tr(),
                      hintText: 'auth.email_hint'.tr(),
                      keyboardType: TextInputType.emailAddress,
                      controller: _emailController,
                    )
                  else
                    CustomTextField(
                      label: 'auth.phone_label'.tr(),
                      hintText: 'auth.phone_hint'.tr(),
                      keyboardType: TextInputType.phone,
                      controller: _phoneController,
                    ),
                  const SizedBox(height: 40),
                  PrimaryButton(
                    text: 'auth.send'.tr(),
                    isLoading: _isLoading,
                    onPressed: _isLoading ? null : _handleSend,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeToggle() {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: const Color(0xFFF0F2FF),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _isEmailMode = true),
              child: Container(
                decoration: BoxDecoration(
                  color: _isEmailMode ? AppColors.primaryBlue : Colors.transparent,
                  borderRadius: BorderRadius.circular(22),
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.email_outlined,
                      size: 16,
                      color: _isEmailMode ? Colors.white : AppColors.textGray,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'auth.email'.tr(),
                      style: TextStyle(
                        color: _isEmailMode ? Colors.white : AppColors.textGray,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _isEmailMode = false),
              child: Container(
                decoration: BoxDecoration(
                  color: !_isEmailMode ? AppColors.primaryBlue : Colors.transparent,
                  borderRadius: BorderRadius.circular(22),
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.phone_outlined,
                      size: 16,
                      color: !_isEmailMode ? Colors.white : AppColors.textGray,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'auth.phone'.tr(),
                      style: TextStyle(
                        color: !_isEmailMode ? Colors.white : AppColors.textGray,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
