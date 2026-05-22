import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/auth_repository.dart';
import 'otp_verification_screen.dart';

class VerificationMethodScreen extends StatefulWidget {
  final String token;
  final String email;
  final String phone;

  const VerificationMethodScreen({
    super.key,
    required this.token,
    required this.email,
    required this.phone,
  });

  @override
  State<VerificationMethodScreen> createState() => _VerificationMethodScreenState();
}

class _VerificationMethodScreenState extends State<VerificationMethodScreen> {
  final _authRepository = AuthRepository();
  bool _isLoadingEmail = false;
  bool _isLoadingPhone = false;

  Future<void> _handleEmailVerification() async {
    setState(() => _isLoadingEmail = true);
    final result = await _authRepository.sendEmailVerification(widget.token);
    setState(() => _isLoadingEmail = false);

    if (mounted) {
      if (result['success']) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message']),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => OtpVerificationScreen(
              isRegister: true,
              phone: widget.phone,
              token: widget.token,
              isEmail: true,
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message']),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _handlePhoneVerification() async {
    setState(() => _isLoadingPhone = true);
    final result = await _authRepository.sendPhoneVerification(widget.token);
    setState(() => _isLoadingPhone = false);

    if (mounted) {
      if (result['success']) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message']),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => OtpVerificationScreen(
              isRegister: true,
              phone: widget.phone,
              token: widget.token,
              isEmail: false,
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message']),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundWhite,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textDark),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 40),
            Text(
              'auth.select_verification'.tr(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(height: 60),
            _buildMethodCard(
              context,
              icon: Icons.smartphone_outlined,
              title: 'auth.send_via_mobile'.tr(),
              isSelected: true,
              isLoading: _isLoadingPhone,
              onTap: _isLoadingPhone || _isLoadingEmail ? null : _handlePhoneVerification,
            ),
            const SizedBox(height: 16),
            _buildMethodCard(
              context,
              icon: Icons.email_outlined,
              title: 'auth.send_via_email'.tr(),
              isSelected: false,
              isLoading: _isLoadingEmail,
              onTap: _isLoadingPhone || _isLoadingEmail ? null : _handleEmailVerification,
            ),
            const Spacer(),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'auth.cancel'.tr(),
                style: const TextStyle(
                  fontSize: 16,
                  color: AppColors.textGray,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildMethodCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required bool isSelected,
    required bool isLoading,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFF0F2FF) : AppColors.backgroundWhite,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppColors.primaryBlue : AppColors.inputBorder,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            if (isLoading)
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(
                icon,
                color: isSelected ? AppColors.primaryBlue : AppColors.textGray,
                size: 28,
              ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  color: isSelected ? AppColors.primaryBlue : AppColors.textGray,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
