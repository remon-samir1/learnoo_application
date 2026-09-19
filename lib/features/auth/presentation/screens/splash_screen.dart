import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:url_launcher/url_launcher.dart';
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

/// The app's Play Store listing. Updates are delivered exclusively through
/// Google Play — downloading and side-loading an APK from our own server is
/// against Play's Updates policy and can get the app suspended, so that path
/// was removed. Keep this in sync with android/app/build.gradle.kts
/// (applicationId).
const String _playStorePackageId = 'com.sunmed.learnoo';
final Uri _playStoreUri = Uri.parse(
  'https://play.google.com/store/apps/details?id=$_playStorePackageId',
);

class SplashScreen extends StatefulWidget {
  const SplashScreen({
    super.key,
    this.router,
    this.checkForUpdate,
    this.splashDelay = const Duration(seconds: 2),
  });

  /// Decides the entry screen. Defaults to the production router built from
  /// [AuthRepository] and [ConnectivityService]; tests supply their own so no
  /// request leaves the process.
  final SplashRouter? router;

  /// The OTA check. Injectable for the same reason.
  final Future<Map<String, dynamic>?> Function()? checkForUpdate;

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
    _checkForUpdates();
  }

  /// First check for app updates, then proceed with auth
  Future<void> _checkForUpdates() async {
    // Artificial delay for splash effect
    await Future.delayed(widget.splashDelay);

    Map<String, dynamic>? updateInfo;
    try {
      updateInfo = await (widget.checkForUpdate == null
          ? _authRepository.checkForUpdate()
          : widget.checkForUpdate!());
    } catch (_) {
      // An unreachable OTA endpoint must never strand the user here.
      updateInfo = null;
    }

    if (updateInfo != null && updateInfo['hasUpdate'] == true) {
      if (mounted) {
        _showUpdateDialog(updateInfo);
      }
    } else {
      // No update needed, proceed with auth check
      _checkAuth();
    }
  }

  /// Show update dialog with optional skip based on is_force_update
  void _showUpdateDialog(Map<String, dynamic> updateInfo) {
    final isForceUpdate = updateInfo['isForceUpdate'] ?? false;
    final versionName = updateInfo['versionName'] ?? '';
    final versionCode = updateInfo['versionCode'] as int?;

    showDialog(
      context: context,
      barrierDismissible: !isForceUpdate,
      builder: (context) => UpdateDialog(
        isForceUpdate: isForceUpdate,
        versionName: versionName,
        onSkip: () async {
          final navigator = Navigator.of(context);
          // Save this version as acknowledged so we don't prompt again
          if (versionCode != null) {
            await _authRepository.saveLastAcknowledgedVersionCode(versionCode);
          }
          if (navigator.canPop()) navigator.pop();
          _checkAuth();
        },
        onUpdate: () => _openPlayStore(versionCode),
      ),
    );
  }

  /// Send the user to the app's Play Store listing to update. Updates must
  /// go through Google Play, not an in-app APK download/install.
  Future<void> _openPlayStore(int? versionCode) async {
    try {
      final launched = await launchUrl(
        _playStoreUri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        _showError('Could not open the Play Store. Please update the app manually.');
        return;
      }
    } catch (e) {
      _showError('Could not open the Play Store: $e');
      return;
    }

    // The user left to update; remember they've seen this version so we
    // don't nag them again the moment they come back without having
    // updated yet.
    if (versionCode != null) {
      await _authRepository.saveLastAcknowledgedVersionCode(versionCode);
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    }
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

/// Dialog prompting the user to update via the Play Store.
class UpdateDialog extends StatefulWidget {
  final bool isForceUpdate;
  final String versionName;
  final VoidCallback onSkip;
  final Future<void> Function() onUpdate;

  const UpdateDialog({
    super.key,
    required this.isForceUpdate,
    required this.versionName,
    required this.onSkip,
    required this.onUpdate,
  });

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _isOpeningStore = false;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !widget.isForceUpdate && !_isOpeningStore,
      child: AlertDialog(
        title: Text('update_available'.tr()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.versionName.isNotEmpty)
              Text('${'new_version'.tr()}: ${widget.versionName}'),
            const SizedBox(height: 16),
            Text(
              widget.isForceUpdate
                  ? 'force_update_message'.tr()
                  : 'optional_update_message'.tr(),
              style: const TextStyle(fontSize: 14),
            ),
          ],
        ),
        actions: [
          if (!widget.isForceUpdate && !_isOpeningStore)
            TextButton(
              onPressed: widget.onSkip,
              child: Text('skip'.tr()),
            ),
          ElevatedButton(
            onPressed: _isOpeningStore
                ? null
                : () async {
                    setState(() => _isOpeningStore = true);
                    await widget.onUpdate();
                    if (mounted) {
                      setState(() => _isOpeningStore = false);
                    }
                  },
            child: _isOpeningStore
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text('update_now'.tr()),
          ),
        ],
      ),
    );
  }
}
