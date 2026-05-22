import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'dart:async';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../data/auth_repository.dart';
import '../../../../features/academic/presentation/screens/university_selection_screen.dart';
import '../../../home/presentation/screens/main_screen.dart';

class OtpVerificationScreen extends StatefulWidget {
  final bool isRegister;
  final String phone;
  final String token;
  final bool isEmail;
  final dynamic universityId;
  final dynamic facultyId;
  final dynamic centerIds;
  const OtpVerificationScreen({
    super.key,
    required this.isRegister,
    required this.phone,
    required this.token,
    required this.isEmail,
    this.universityId,
    this.facultyId,
    this.centerIds,
  });

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  final List<TextEditingController> _controllers = List.generate(6, (index) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (index) => FocusNode());
  int _secondsRemaining = 90;
  Timer? _timer;
  bool _isLoading = false;
  final _authRepository = AuthRepository();

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining > 0) {
        setState(() {
          _secondsRemaining--;
        });
      } else {
        _timer?.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (var controller in _controllers) {
      controller.dispose();
    }
    for (var node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
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
          children: [
            const SizedBox(height: 40),
            Text(
              widget.isEmail ? 'auth.verify_email_title'.tr() : 'auth.verify_phone_title'.tr(),
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(height: 16),
            RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                style: const TextStyle(fontSize: 14, color: AppColors.textGray, height: 1.5),
                children: [
                  TextSpan(
                    text: widget.isEmail
                        ? 'auth.sent_code_email'.tr()
                        : 'auth.sent_code_phone'.tr(),
                  ),
                  TextSpan(
                    text: widget.phone,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.textDark.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 48),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(6, (index) => _buildOtpField(index)),
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_secondsRemaining > 0) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8FDF2),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Text(
                      '0:${_secondsRemaining.toString().padLeft(2, '0')}',
                      style: const TextStyle(
                        color: Color(0xFF27AE60),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${'auth.resend_code_in'.tr()}0:${_secondsRemaining.toString().padLeft(2, '0')}',
                    style: const TextStyle(
                      color: AppColors.textDark,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ] else
                  TextButton(
                    onPressed: _isLoading ? null : _handleResend,
                    child: Text(
                      'auth.resend_code'.tr(),
                      style: const TextStyle(
                        color: AppColors.primaryBlue,
                        fontWeight: FontWeight.bold,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
              ],
            ),
            const Spacer(),
            PrimaryButton(
              text: 'auth.verify_btn'.tr(),
              isLoading: _isLoading,
              onPressed: _isLoading ? null : _handleVerify,
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildOtpField(int index) {
    return Container(
      width: 48,
      height: 56,
      decoration: BoxDecoration(
        color: AppColors.inputFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.inputBorder),
      ),
      child: TextField(
        controller: _controllers[index],
        focusNode: _focusNodes[index],
        textAlign: TextAlign.center,
        keyboardType: TextInputType.text,
        maxLength: 1,
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textDark),
        decoration: const InputDecoration(
          counterText: '',
          border: InputBorder.none,
        ),
        onChanged: (value) {
          if (value.isNotEmpty) {
            if (index < 5) {
              _focusNodes[index + 1].requestFocus();
            } else {
              _focusNodes[index].unfocus();
              if (_controllers.every((c) => c.text.isNotEmpty)) {
                _handleVerify();
              }
            }
          } else {
            if (index > 0) {
              _focusNodes[index - 1].requestFocus();
            }
          }
        },
      ),
    );
  }

  Future<void> _handleResend() async {
    setState(() {
      _isLoading = true;
      _secondsRemaining = 58;
    });
    
    final result = widget.isEmail
        ? await _authRepository.sendEmailVerification(widget.token)
        : await _authRepository.sendPhoneVerification(widget.token);

    setState(() => _isLoading = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message'] ?? 'auth.code_resent'.tr()),
          backgroundColor: result['success'] ? Colors.green : Colors.red,
        ),
      );
      if (result['success']) {
        _startTimer();
      }
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: const BoxDecoration(
                  color: Color(0xFFE8FDF2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle, color: Color(0xFF27AE60), size: 48),
              ),
              const SizedBox(height: 24),
              Text(
                'auth.verify_success_title'.tr(),
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(
                widget.isEmail
                    ? 'auth.email_verified_msg'.tr()
                    : 'auth.phone_verified_msg'.tr(),
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textGray, fontSize: 14),
              ),
              const SizedBox(height: 32),
              PrimaryButton(
                text: 'auth.go_home'.tr(),
                onPressed: () {
                  // Check if user has completed all academic selections (university, faculty, centers)
                  final hasCompleteProfile = widget.universityId != null &&
                      widget.facultyId != null &&
                      widget.centerIds != null &&
                      widget.centerIds is List &&
                      widget.centerIds.isNotEmpty;
                  if (hasCompleteProfile) {
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (context) => const MainScreen()),
                      (route) => false,
                    );
                  } else {
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (context) => const UniversitySelectionScreen()),
                      (route) => false,
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleVerify() async {
    final code = _controllers.map((c) => c.text).join();
    if (code.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('auth.enter_six_digit'.tr()), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isLoading = true);

    final result = widget.isEmail
        ? await _authRepository.verifyEmailOtp(widget.token, code)
        : await _authRepository.verifyPhoneOtp(widget.token, code);

    setState(() => _isLoading = false);

    if (mounted) {
      if (result['success']) {
        _showSuccessDialog();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result['message']), backgroundColor: Colors.red),
        );
      }
    }
  }
}
