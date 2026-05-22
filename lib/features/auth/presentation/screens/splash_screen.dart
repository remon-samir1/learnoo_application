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
import 'profile_screen.dart';
import 'verification_method_screen.dart';
import '../../data/auth_repository.dart';
import '../../../../features/home/presentation/screens/main_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final _authRepository = AuthRepository();
  final _featureManager = FeatureManager();
  final Dio _dio = Dio();
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
    await Future.delayed(const Duration(seconds: 2));

    final updateInfo = await _authRepository.checkForUpdate();

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
          // Save this version as acknowledged so we don't prompt again
          if (versionCode != null) {
            await _authRepository.saveLastAcknowledgedVersionCode(versionCode);
          }
          Navigator.of(context).pop();
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

  Future<void> _checkAuth() async {
    final token = await _authRepository.getToken();
    
    // No token found → go to login/register
    if (token == null) {
      _navigateToProfile();
      return;
    }

    // Check internet connectivity
    final hasInternet = await ConnectivityService().hasConnection();
    
    // No internet but token exists → allow entry (offline mode)
    if (!hasInternet) {
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const MainScreen()),
        );
      }
      return;
    }

    // Internet available → validate token with API
    final result = await _authRepository.getProfile();
    if (result['success']) {
      final profileData = result['data'];

      // Check if the user has verified their email or phone.
      // If both are null, the account is unverified — send to verification flow.
      final attributes = profileData?['attributes'] ?? profileData;
      final emailVerifiedAt = attributes?['email_verified_at'];
      final phoneVerifiedAt = attributes?['phone_verified_at'];
      final isVerified = emailVerifiedAt != null || phoneVerifiedAt != null;

      // Check if OTP verification is enabled globally
      final otpEnabled = _featureManager.isOtpVerificationEnabled;

      if (otpEnabled && !isVerified) {
        // User registered but never verified — redirect to verification
        if (mounted) {
          final email = profileData?['email'] ?? '';
          final phone = profileData?['phone'] ?? '';
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => VerificationMethodScreen(
                token: token,
                email: email,
                phone: phone,
              ),
            ),
          );
        }
        return;
      }

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const MainScreen()),
        );
      }
    } else {
      // API validation failed (401/403) → token is invalid, logout and go to login
      final statusCode = result['statusCode'];
      if (statusCode == 401 || statusCode == 403) {
        await _authRepository.deleteToken();
      }
      _navigateToProfile();
    }
  }

  void _navigateToProfile() {
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const ProfileScreen()),
      );
    }
  }

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
