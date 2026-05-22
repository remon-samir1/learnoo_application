import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_logo.dart';
import '../../../../core/widgets/custom_text_field.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../../core/services/feature_manager.dart';
import '../screens/verification_method_screen.dart';
import '../screens/login_screen.dart';
import '../../data/auth_repository.dart';
import '../../../../features/academic/presentation/screens/university_selection_screen.dart';

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

  bool _isLoading = false;
  bool _acceptTerms = false;
  final _authRepository = AuthRepository();
  final _featureManager = FeatureManager();

  final List<Map<String, String>> _countryCodes = [
    {'code': '20', 'flag': '🇪🇬', 'name': 'auth.country_egypt'},
    {'code': '966', 'flag': '🇸🇦', 'name': 'auth.country_ksa'},
    {'code': '971', 'flag': '🇦🇪', 'name': 'auth.country_uae'},
    {'code': '965', 'flag': '🇰🇼', 'name': 'auth.country_kuwait'},
    {'code': '974', 'flag': '🇶🇦', 'name': 'auth.country_qatar'},
    {'code': '962', 'flag': '🇯🇴', 'name': 'auth.country_jordan'},
  ];
  String _selectedCountryCode = '20';
  String _selectedFlag = '🇪🇬';

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    if (!_acceptTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('auth.accept_terms_snack'.tr()),
          backgroundColor: Colors.blue,
        ),
      );
      return;
    }

    if (_firstNameController.text.isEmpty ||
        _lastNameController.text.isEmpty ||
        _emailController.text.isEmpty ||
        _phoneController.text.isEmpty ||
        _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('auth.fill_all_fields_snack'.tr()),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Validate phone number doesn't start with 0 (only for Egypt)
    if (_selectedCountryCode == '20' && _phoneController.text.startsWith('0')) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.warning_amber_outlined, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(child: Text('auth.phone_start_with_zero'.tr())),
            ],
          ),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    final fullPhone = '$_selectedCountryCode${_phoneController.text}';

    final result = await _authRepository.register(
      firstName: _firstNameController.text,
      lastName: _lastNameController.text,
      phone: fullPhone,
      email: _emailController.text,
      password: _passwordController.text,
    );

    setState(() => _isLoading = false);

    if (result['success']) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Text(result['message']),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );

        final token = result['data']['meta']['token'] ?? '';

        // Check feature flags for OTP flow
        final otpEnabled = _featureManager.isOtpVerificationEnabled;

        if (!otpEnabled) {
          // Skip verification if OTP is disabled
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
              builder: (context) => const UniversitySelectionScreen(),
            ),
            (route) => false,
          );
          return;
        }

        // Navigation with animation to verification
        Navigator.push(
          context,
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) =>
                VerificationMethodScreen(
                  token: token,
                  email: _emailController.text,
                  phone: fullPhone,
                ),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
              const begin = Offset(1.0, 0.0);
              const end = Offset.zero;
              const curve = Curves.easeInOutBack;
              var tween = Tween(
                begin: begin,
                end: end,
              ).chain(CurveTween(curve: curve));
              return SlideTransition(
                position: animation.drive(tween),
                child: child,
              );
            },
            transitionDuration: const Duration(milliseconds: 600),
          ),
        );
      }
    } else {
      if (mounted) {
        final errors = result['errors'];
        String errorText = result['message'];
        if (errors != null && errors is Map) {
          final errorMessages = errors.entries
              .where((e) => e.value is List && (e.value as List).isNotEmpty)
              .map((e) {
                final fieldName = e.key;
                final fieldErrors = e.value as List;
                // If it's a 'device' error, don't show the field name prefix
                if (fieldName == 'device') {
                  return fieldErrors.first.toString();
                }
                return '$fieldName: ${fieldErrors.first.toString()}';
              })
              .join('\n');
          if (errorMessages.isNotEmpty) {
            errorText = errorMessages;
          }
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(child: Text(errorText)),
              ],
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Top Header Section
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

            // Form Section
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 24.0,
                vertical: 32.0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                  Text(
                    'auth.phone_label'.tr(),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.labelGray,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      PopupMenuButton<Map<String, String>>(
                        color: Colors.white,
                        onSelected: (Map<String, String> country) {
                          setState(() {
                            _selectedCountryCode = country['code']!;
                            _selectedFlag = country['flag']!;
                          });
                        },
                        itemBuilder: (BuildContext context) {
                          return _countryCodes.map((
                            Map<String, String> country,
                          ) {
                            return PopupMenuItem<Map<String, String>>(
                              value: country,
                              child: Row(
                                children: [
                                  Text(
                                    country['flag']!,
                                    style: const TextStyle(fontSize: 20),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    country['code']!,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    country['name']!.tr(),
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: AppColors.textGray,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList();
                        },
                        child: Container(
                          height: 56,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: AppColors.inputFill,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.inputBorder),
                          ),
                          child: Row(
                            children: [
                              Text(
                                _selectedFlag,
                                style: const TextStyle(fontSize: 20),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _selectedCountryCode,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const Icon(
                                Icons.keyboard_arrow_down,
                                size: 20,
                                color: AppColors.textGray,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          onChanged: (value) {
                            // Real-time validation for phone number starting with 0 (only for Egypt)
                            if (_selectedCountryCode == '20' && value.startsWith('0') && value.length == 1) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Row(
                                    children: [
                                      const Icon(Icons.info_outline, color: Colors.white),
                                      const SizedBox(width: 8),
                                      Expanded(child: Text('auth.phone_start_with_zero'.tr())),
                                    ],
                                  ),
                                  backgroundColor: Colors.orange,
                                  behavior: SnackBarBehavior.floating,
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            }
                          },
                          decoration: InputDecoration(
                            hintText: 'auth.phone_hint'.tr(),
                            hintStyle: const TextStyle(
                              color: AppColors.inputHint,
                            ),
                            filled: true,
                            fillColor: AppColors.inputFill,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 18,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: AppColors.inputBorder,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: AppColors.inputBorder,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  CustomTextField(
                    label: 'auth.password'.tr(),
                    hintText: 'auth.create_strong'.tr(),
                    isPassword: true,
                    controller: _passwordController,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      SizedBox(
                        height: 24,
                        width: 24,
                        child: Checkbox(
                          value: _acceptTerms,
                          onChanged: (val) {
                            setState(() => _acceptTerms = val ?? false);
                          },
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
                                style: TextStyle(
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
                    onPressed: _handleRegister,
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
