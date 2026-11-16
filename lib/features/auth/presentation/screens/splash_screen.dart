import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_logo.dart';
import '../../../../core/services/connectivity_service.dart';
import '../../../../core/services/feature_manager.dart';
import 'login_screen.dart';
import '../../domain/splash_router.dart';
import '../../../academic/presentation/screens/university_selection_screen.dart';
import '../../data/auth_repository.dart';
import '../../../parent/presentation/screens/parent_dashboard_screen.dart';
import '../../../../features/home/presentation/screens/main_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({
    super.key,
    this.router,
    this.splashDelay = const Duration(seconds: 2),
  });

  /// Decides the entry screen. Defaults to the production router built from
  /// [AuthRepository] and [ConnectivityService]; tests supply their own so no
  /// request leaves the process.
  final SplashRouter? router;

  /// How long the branding is held before routing.
  final Duration splashDelay;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final _authRepository = AuthRepository();
  final _featureManager = FeatureManager();

  late final SplashRouter _router = widget.router ??
      SplashRouter(
        readToken: _authRepository.getToken,
        hasConnection: ConnectivityService().hasConnection,
        fetchProfile: _authRepository.getProfile,
        clearToken: _authRepository.deleteToken,
      );

  @override
  void initState() {
    super.initState();
    _start();
  }

  /// Holds the branding, then routes. Whether this app version may open at
  /// all is decided above every screen by `AppUpdateGate`.
  Future<void> _start() async {
    await Future.delayed(widget.splashDelay);
    if (!mounted) return;
    await _checkAuth();
  }

  /// Decides the entry screen.
  ///
  /// A stored token now means "verified" — it is only written after the OTP is
  /// accepted — so there is no unverified-session branch any more. What remains
  /// is the web's profile gate: an authenticated student whose academic
  /// selection is incomplete goes to onboarding, everyone else to the app.
  Future<void> _checkAuth() async {
    final destination = await _router.resolve();
    if (!mounted) return;

    switch (destination) {
      case SplashDestination.login:
        _navigateToLogin();
        break;
      case SplashDestination.onboarding:
        _navigateTo(const UniversitySelectionScreen());
        break;
      case SplashDestination.studentHome:
        _navigateTo(const MainScreen());
        break;
      case SplashDestination.parentDashboard:
        _navigateTo(const ParentDashboardScreen());
        break;
    }
  }

  void _navigateTo(Widget screen) {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => screen),
    );
  }

  void _navigateToLogin() => _navigateTo(const LoginScreen());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background Image
          Positioned.fill(
            child: Image.asset(
              'assets/images/student_background.png',
              fit: BoxFit.cover,
            ),
          ),
          // Blue Overlay (Using semi-transparent primary blue)
          Positioned.fill(
            child: Container(
              color: AppColors.primaryBlue.withValues(alpha: 0.85),
            ),
          ),
          // Content
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Dynamic logo from FeatureManager
                _featureManager.logoUrl.isNotEmpty
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Image.network(
                          _featureManager.logoUrl,
                          width: 100,
                          height: 100,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return const AppLogo(size: 100);
                          },
                        ),
                      )
                    : const AppLogo(size: 100),
                const SizedBox(height: 15),
                // Dynamic platform name from FeatureManager
                Text(
                  _featureManager.platformName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                // Dynamic tagline from FeatureManager
                Text(
                  _featureManager.tagline.tr(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
