import 'dart:io';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
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
  final Dio _dio = Dio();

  late final SplashRouter _router = widget.router ??
      SplashRouter(
        readToken: _authRepository.getToken,
        hasConnection: ConnectivityService().hasConnection,
        fetchProfile: _authRepository.getProfile,
        clearToken: _authRepository.deleteToken,
      );
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String _downloadStatus = '';

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
    final fileSize = updateInfo['fileSize'] ?? '';
    final downloadUrl = updateInfo['downloadUrl'] ?? '';
    final versionCode = updateInfo['versionCode'] as int?;

    showDialog(
      context: context,
      barrierDismissible: !isForceUpdate,
      builder: (context) => UpdateDialog(
        isForceUpdate: isForceUpdate,
        versionName: versionName,
        fileSize: fileSize,
        downloadUrl: downloadUrl,
        onSkip: () async {
          final navigator = Navigator.of(context);
          // Save this version as acknowledged so we don't prompt again
          if (versionCode != null) {
            await _authRepository.saveLastAcknowledgedVersionCode(versionCode);
          }
          if (navigator.canPop()) navigator.pop();
          _checkAuth();
        },
        onUpdate: (url, progress) => _downloadAndInstallApkWithPermission(url, progress, versionCode),
        progressNotifier: ValueNotifier(0.0),
      ),
    );
  }

  Future<void> _downloadAndInstallApkWithPermission(
    String downloadUrl,
    ValueNotifier<double> progressNotifier,
    int? versionCode,
  ) async {
    // Check and request install packages permission
    if (Platform.isAndroid) {
      final status = await Permission.requestInstallPackages.status;
      if (!status.isGranted) {
        final result = await Permission.requestInstallPackages.request();
        if (!result.isGranted) {
          _showError('Permission required to install updates. Please enable "Install unknown apps" in Settings.');
          return;
        }
      }
    }
    await _downloadAndInstallApk(downloadUrl, progressNotifier, versionCode);
  }

  /// Download APK and show progress, then install
  Future<void> _downloadAndInstallApk(
    String downloadUrl,
    ValueNotifier<double> progressNotifier,
    int? versionCode,
  ) async {
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
      _downloadStatus = 'Starting download...';
    });

    // Show download notification
    await _showDownloadNotification(0, 'Starting download...');

    try {
      // Get app-specific cache directory (no storage permission needed)
      final Directory cacheDir = await getTemporaryDirectory();
      final String fileName = 'learnoo_update.apk';
      final String savePath = '${cacheDir.path}/$fileName';

      // Delete old file if exists
      final oldFile = File(savePath);
      if (await oldFile.exists()) {
        await oldFile.delete();
      }

      // Download file with progress
      await _dio.download(
        downloadUrl,
        savePath,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            final progress = received / total;
            progressNotifier.value = progress;
            setState(() {
              _downloadProgress = progress;
              _downloadStatus =
                  '${_formatBytes(received)} / ${_formatBytes(total)}';
            });
            // Update notification
            _showDownloadNotification(
              (progress * 100).toInt(),
              '${_formatBytes(received)} / ${_formatBytes(total)}',
            );
          }
        },
      );

      setState(() {
        _isDownloading = false;
        _downloadStatus = 'Download complete. Installing...';
      });

      // Show completion notification
      await _showDownloadCompleteNotification();

      // Close the update dialog
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      // Save this version as acknowledged before installing
      if (versionCode != null) {
        await _authRepository.saveLastAcknowledgedVersionCode(versionCode);
      }

      // Install the APK
      await _installApk(savePath);
    } catch (e) {
      setState(() {
        _isDownloading = false;
      });
      _showDownloadNotification(-1, 'Download failed: $e');
      _showError('Download failed: $e');
    }
  }

  /// Show download progress notification
  Future<void> _showDownloadNotification(int progress, String status) async {
    final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
    
    // Initialize if not already
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    await flutterLocalNotificationsPlugin.initialize(initSettings);

    final androidDetails = AndroidNotificationDetails(
      'learnoo_downloads',
      'Learnoo Downloads',
      channelDescription: 'Download notifications for app updates',
      importance: Importance.low,
      priority: Priority.low,
      showProgress: progress >= 0 && progress < 100,
      maxProgress: 100,
      progress: progress,
      onlyAlertOnce: true,
      ongoing: progress >= 0 && progress < 100,
      autoCancel: progress < 0 || progress >= 100,
    );

    final details = NotificationDetails(android: androidDetails);

    await flutterLocalNotificationsPlugin.show(
      0,
      progress >= 100 ? 'Download Complete' : 'Downloading Update',
      status,
      details,
    );
  }

  /// Show download complete notification
  Future<void> _showDownloadCompleteNotification() async {
    final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
    
    const androidDetails = AndroidNotificationDetails(
      'learnoo_downloads',
      'Learnoo Downloads',
      channelDescription: 'Download notifications for app updates',
      importance: Importance.high,
      priority: Priority.high,
    );

    const details = NotificationDetails(android: androidDetails);

    await flutterLocalNotificationsPlugin.show(
      0,
      'Download Complete',
      'Tap to install the update',
      details,
    );
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB'];
    var i = 0;
    double size = bytes.toDouble();
    while (size >= 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(1)} ${suffixes[i]}';
  }

  /// Install APK file
  Future<void> _installApk(String filePath) async {
    try {
      final result = await OpenFile.open(
        filePath,
        type: 'application/vnd.android.package-archive',
      );

      if (result.type != ResultType.done) {
        // Show manual install dialog if automatic install fails
        _showManualInstallDialog(filePath, result.message);
      }
    } catch (e) {
      _showManualInstallDialog(filePath, e.toString());
    }
  }

  /// Show dialog to manually install APK when automatic install fails
  void _showManualInstallDialog(String filePath, String errorMessage) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Install Update'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('The APK has been downloaded but automatic install failed.'),
            const SizedBox(height: 8),
            Text(
              'File location: $filePath',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            if (errorMessage.isNotEmpty)
              Text(
                '\nError: $errorMessage',
                style: const TextStyle(fontSize: 12, color: Colors.red),
              ),
            const SizedBox(height: 16),
            const Text(
              'Please enable "Install unknown apps" permission for this app in Settings, then try again.',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _checkAuth();
            },
            child: const Text('Continue to App'),
          ),
          ElevatedButton(
            onPressed: () async {
              // Try opening the file again
              await OpenFile.open(filePath);
            },
            child: const Text('Try Install Again'),
          ),
        ],
      ),
    );
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

/// Stateful dialog widget to properly handle download state
class UpdateDialog extends StatefulWidget {
  final bool isForceUpdate;
  final String versionName;
  final String fileSize;
  final String downloadUrl;
  final VoidCallback onSkip;
  final Function(String, ValueNotifier<double>) onUpdate;
  final ValueNotifier<double> progressNotifier;

  const UpdateDialog({
    super.key,
    required this.isForceUpdate,
    required this.versionName,
    required this.fileSize,
    required this.downloadUrl,
    required this.onSkip,
    required this.onUpdate,
    required this.progressNotifier,
  });

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _isDownloading = false;

  @override
  void initState() {
    super.initState();
    widget.progressNotifier.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    widget.progressNotifier.removeListener(() {});
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = widget.progressNotifier.value;
    return WillPopScope(
      onWillPop: () async => !widget.isForceUpdate && !_isDownloading,
      child: AlertDialog(
        title: Text('update_available'.tr()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${'new_version'.tr()}: ${widget.versionName}'),
            if (widget.fileSize.isNotEmpty)
              Text('${'file_size'.tr()}: ${widget.fileSize}'),
            const SizedBox(height: 16),
            if (_isDownloading) ...[
              LinearProgressIndicator(value: progress),
              const SizedBox(height: 8),
              Text(
                '${(progress * 100).toStringAsFixed(0)}%',
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 8),
            ],
            Text(
              widget.isForceUpdate
                  ? 'force_update_message'.tr()
                  : 'optional_update_message'.tr(),
              style: const TextStyle(fontSize: 14),
            ),
          ],
        ),
        actions: [
          if (!widget.isForceUpdate && !_isDownloading)
            TextButton(
              onPressed: widget.onSkip,
              child: Text('skip'.tr()),
            ),
          ElevatedButton(
            onPressed: _isDownloading
                ? null
                : () {
                    if (widget.downloadUrl.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Download link is not available. Please try again later.'),
                        ),
                      );
                      return;
                    }
                    setState(() {
                      _isDownloading = true;
                    });
                    widget.onUpdate(widget.downloadUrl, widget.progressNotifier).then((_) {
                      if (mounted) {
                        setState(() {
                          _isDownloading = false;
                        });
                      }
                    });
                  },
            child: _isDownloading
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('${(progress * 100).toStringAsFixed(0)}%'),
                    ],
                  )
                : Text('update_now'.tr()),
          ),
        ],
      ),
    );
  }
}
