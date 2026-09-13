import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easy_localization/easy_localization.dart' hide TextDirection;

import '../../../../core/realtime/otp_listener.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../../features/academic/presentation/screens/university_selection_screen.dart';
import '../../../home/presentation/screens/main_screen.dart';
import '../../data/auth_repository.dart';
import '../../domain/student_profile.dart';

/// Code screen — the only door into the app.
///
/// Matches `app/(auth)/verification-code/page.tsx`:
///
///  * the notification endpoint is called automatically on mount, and any
///    `user.otp` in its response pre-fills the boxes;
///  * the private Reverb channel is joined in parallel, so a code issued while
///    this screen is open lands instantly;
///  * a successful verify promotes the pending token to a real session, which
///    is the only place that ever happens.
class OtpVerificationScreen extends StatefulWidget {
  const OtpVerificationScreen({
    super.key,
    required this.isRegister,
    required this.phone,
    this.isEmail = false,
  });

  /// Sends the student to academic onboarding instead of the dashboard.
  final bool isRegister;

  /// Shown in the "we sent a code to …" line.
  final String phone;

  /// Verifies the e-mail channel instead of the phone.
  final bool isEmail;

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  static const int _codeLength = 6;
  static const int _resendSeconds = 81;

  final List<TextEditingController> _controllers =
      List.generate(_codeLength, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(_codeLength, (_) => FocusNode());

  final _authRepository = AuthRepository();
  final _otpListener = OtpListener();

  Timer? _timer;
  int _secondsRemaining = _resendSeconds;
  bool _isLoading = false;
  bool _isSending = false;
  bool _autoSubmitted = false;

  @override
  void initState() {
    super.initState();
    _startTimer();
    // Join the realtime channel first, then ask for the code: a broadcast
    // issued before we are subscribed is gone for good. The join is capped by
    // a timeout inside the client, so a websocket that never comes up only
    // delays the request briefly — the code still arrives in the HTTP body.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _startRealtimeListener();
      if (mounted) await _requestCode();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _otpListener.otp.removeListener(_onRealtimeOtp);
    _otpListener.stop();
    for (final controller in _controllers) {
      controller.dispose();
    }
    for (final node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  // ------------------------------------------------------------------
  // Realtime
  // ------------------------------------------------------------------

  Future<void> _startRealtimeListener() async {
    final userId = _authRepository.pendingUserId;
    if (userId == null) return;
    _otpListener.otp.addListener(_onRealtimeOtp);
    await _otpListener.start(userId);
  }

  void _onRealtimeOtp() {
    final code = _otpListener.otp.value;
    if (code == null || code.isEmpty) return;
    _fillCode(code);
    _otpListener.clear();
  }

  // ------------------------------------------------------------------
  // Code entry
  // ------------------------------------------------------------------

  String get _code => _controllers.map((c) => c.text).join();

  void _fillCode(String code) {
    // The backend issues six alphanumeric characters (e.g. "0CRFWQ"), so
    // stripping to digits would collapse a real code to one character.
    final chars = _normalizeCode(code);
    if (chars.isEmpty) return;

    for (var i = 0; i < _codeLength; i++) {
      _controllers[i].text = i < chars.length ? chars[i] : '';
    }
    if (mounted) setState(() {});

    if (chars.length >= _codeLength) {
      FocusScope.of(context).unfocus();
      _autoSubmit();
    }
  }

  /// Uppercases and drops separators so a pasted or broadcast code lands in
  /// the same shape the API issues.
  String _normalizeCode(String raw) =>
      raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  /// Verifies as soon as a full code arrives, so a realtime code needs no tap.
  void _autoSubmit() {
    if (_autoSubmitted || _isLoading) return;
    _autoSubmitted = true;
    Future.delayed(const Duration(milliseconds: 250), () {
      if (mounted && _code.length == _codeLength) _handleVerify();
    });
  }

  void _onDigitChanged(int index, String value) {
    // Handle a paste of the whole code into one box.
    if (value.length > 1) {
      _fillCode(value);
      return;
    }

    if (value.isNotEmpty && index < _codeLength - 1) {
      _focusNodes[index + 1].requestFocus();
    } else if (value.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    }

    setState(() {});

    if (_code.length == _codeLength && !_code.contains(' ')) {
      final filled = _controllers.every((c) => c.text.isNotEmpty);
      if (filled) {
        FocusScope.of(context).unfocus();
        _autoSubmit();
      }
    }
  }

  // ------------------------------------------------------------------
  // Timer
  // ------------------------------------------------------------------

  void _startTimer() {
    _timer?.cancel();
    _secondsRemaining = _resendSeconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_secondsRemaining > 0) {
        setState(() => _secondsRemaining--);
      } else {
        timer.cancel();
      }
    });
  }

  String get _formattedTime {
    final m = _secondsRemaining ~/ 60;
    final s = _secondsRemaining % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  // ------------------------------------------------------------------
  // Requests
  // ------------------------------------------------------------------

  Future<void> _requestCode({bool isResend = false}) async {
    if (_isSending) return;
    setState(() => _isSending = true);

    final result = widget.isEmail
        ? await _authRepository.sendEmailVerification()
        : await _authRepository.sendPhoneVerification();

    if (!mounted) return;
    setState(() => _isSending = false);

    if (result['success'] != true) {
      _showMessage(
        result['message']?.toString() ?? 'auth.failed_send_code'.tr(),
        isError: true,
      );
      return;
    }

    // The backend echoes the code back in some environments; use it.
    final otp = result['otp']?.toString();
    if (otp != null && otp.isNotEmpty) {
      _fillCode(otp);
    }

    if (isResend) {
      _startTimer();
      _showMessage('auth.code_resent'.tr());
    }
  }

  Future<void> _handleVerify() async {
    final code = _code;
    if (code.length != _codeLength) {
      _showMessage('auth.enter_six_digit'.tr(), isError: true);
      return;
    }

    setState(() => _isLoading = true);

    final result = widget.isEmail
        ? await _authRepository.verifyEmailOtp(code)
        : await _authRepository.verifyPhoneOtp(code);

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result['success'] != true) {
      _autoSubmitted = false;

      // The pending token is gone (app was backgrounded too long) — the only
      // safe move is a fresh sign-in.
      if (result['sessionLost'] == true) {
        _showMessage(result['message']?.toString() ?? '', isError: true);
        Navigator.of(context).popUntil((route) => route.isFirst);
        return;
      }

      _showMessage(
        result['message']?.toString() ?? 'auth.failed_verify'.tr(),
        isError: true,
      );
      _clearCode();
      return;
    }

    await _routeAfterVerification();
  }

  void _clearCode() {
    for (final controller in _controllers) {
      controller.clear();
    }
    if (mounted) {
      setState(() {});
      _focusNodes.first.requestFocus();
    }
  }

  /// The session is live now — decide between onboarding and the dashboard the
  /// same way the web's profile gate does.
  Future<void> _routeAfterVerification() async {
    final profileResult = await _authRepository.getProfile();
    if (!mounted) return;

    final profile = StudentProfile.fromData(
      profileResult['success'] == true && profileResult['data'] is Map
          ? Map<String, dynamic>.from(profileResult['data'] as Map)
          : null,
    );

    final needsOnboarding =
        widget.isRegister || !profile.isAcademicProfileComplete;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (context) => needsOnboarding
            ? const UniversitySelectionScreen()
            : const MainScreen(),
      ),
      (route) => false,
    );
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted || message.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : AppColors.joinLiveGreen,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ------------------------------------------------------------------
  // UI
  // ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final isComplete = _controllers.every((c) => c.text.isNotEmpty);

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
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Column(
          children: [
            const SizedBox(height: 24),
            Text(
              widget.isEmail
                  ? 'auth.verify_email_title'.tr()
                  : 'auth.verify_phone_title'.tr(),
              textAlign: TextAlign.center,
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
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textGray,
                  height: 1.5,
                ),
                children: [
                  TextSpan(
                    text: widget.isEmail
                        ? 'auth.sent_code_email'.tr()
                        : 'auth.sent_code_phone'.tr(),
                  ),
                  TextSpan(
                    text: ' ${widget.phone}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.textDark.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            ValueListenableBuilder<bool>(
              valueListenable: _otpListener.connected,
              builder: (context, connected, _) {
                if (!connected) return const SizedBox.shrink();
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8FDF2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.bolt,
                          size: 16, color: Color(0xFF27AE60)),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'auth.auto_fill_ready'.tr(),
                          style: const TextStyle(
                            color: Color(0xFF27AE60),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 28),
            Directionality(
              textDirection: TextDirection.ltr,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children:
                    List.generate(_codeLength, (index) => _buildOtpField(index)),
              ),
            ),
            const SizedBox(height: 28),
            if (_secondsRemaining > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8FDF2),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  _formattedTime,
                  style: const TextStyle(
                    color: Color(0xFF27AE60),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            else
              TextButton(
                onPressed:
                    _isSending ? null : () => _requestCode(isResend: true),
                child: Text(
                  'auth.resend_code'.tr(),
                  style: const TextStyle(
                    color: AppColors.primaryBlue,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            const SizedBox(height: 32),
            PrimaryButton(
              text: 'auth.verify_btn'.tr(),
              isLoading: _isLoading,
              onPressed: (_isLoading || !isComplete) ? null : _handleVerify,
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildOtpField(int index) {
    return SizedBox(
      width: 48,
      height: 56,
      child: TextField(
        controller: _controllers[index],
        focusNode: _focusNodes[index],
        textAlign: TextAlign.center,
        // Codes mix letters and digits, so a number pad plus a digits-only
        // filter would lock the student out of typing their own code.
        keyboardType: TextInputType.text,
        textCapitalization: TextCapitalization.characters,
        autofillHints: const [AutofillHints.oneTimeCode],
        maxLength: 1,
        style: const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.bold,
          color: AppColors.textDark,
        ),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
          _UpperCaseFormatter(),
        ],
        decoration: InputDecoration(
          counterText: '',
          filled: true,
          fillColor: AppColors.inputFill,
          contentPadding: EdgeInsets.zero,
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
            borderSide: const BorderSide(color: AppColors.primaryBlue, width: 2),
          ),
        ),
        onChanged: (value) => _onDigitChanged(index, value),
      ),
    );
  }
}

/// Keeps the boxes in the uppercase form the API issues codes in, so a code
/// typed in lowercase still matches on verify.
class _UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final upper = newValue.text.toUpperCase();
    if (upper == newValue.text) return newValue;
    return newValue.copyWith(
      text: upper,
      selection: newValue.selection,
      composing: TextRange.empty,
    );
  }
}
