import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';

import 'device_downloads.dart';

/// Service for managing local notifications including download progress
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // Notification IDs
  static const int _downloadNotificationBaseId = 1000;
  final Map<String, int> _downloadNotificationIds = {};
  int _nextNotificationId = _downloadNotificationBaseId;

  bool _isInitialized = false;

  /// Initialize the notification service
  Future<void> initialize() async {
    if (_isInitialized) return;

    // Android initialization
    const AndroidInitializationSettings androidInitializationSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    // iOS initialization
    const DarwinInitializationSettings iosInitializationSettings =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initializationSettings =
        InitializationSettings(
      android: androidInitializationSettings,
      iOS: iosInitializationSettings,
    );

    await _notificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _onNotificationResponse,
    );

    _isInitialized = true;
    debugPrint('NotificationService initialized');

    // A tap on a "download complete" notification that launched the app.
    try {
      final launch = await _notificationsPlugin.getNotificationAppLaunchDetails();
      final payload = launch?.notificationResponse?.payload;
      if ((launch?.didNotificationLaunchApp ?? false) && payload != null) {
        _openDownloadFromPayload(payload);
      }
    } catch (_) {}
  }

  static const String _openDownloadPrefix = 'open_download|';

  /// Payload for a completed download notification: tapping it opens the file.
  static String openDownloadPayload(SavedDownload saved) =>
      '$_openDownloadPrefix${saved.mimeType}|${saved.uri}';

  void _openDownloadFromPayload(String payload) {
    if (!payload.startsWith(_openDownloadPrefix)) return;
    final rest = payload.substring(_openDownloadPrefix.length);
    final split = rest.indexOf('|');
    if (split <= 0) return;
    const DeviceDownloads().open(
      mimeType: rest.substring(0, split),
      uri: rest.substring(split + 1),
    );
  }

  /// Handle notification tap
  void _onNotificationResponse(NotificationResponse response) {
    final payload = response.payload;
    if (payload != null) _openDownloadFromPayload(payload);
  }

  /// Request notification permissions (mainly for iOS)
  Future<bool> requestPermissions() async {
    if (Platform.isIOS) {
      final bool? result = await _notificationsPlugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );
      return result ?? false;
    }

    if (Platform.isAndroid) {
      final AndroidFlutterLocalNotificationsPlugin? androidPlugin =
          _notificationsPlugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      final bool? granted = await androidPlugin?.requestNotificationsPermission();
      return granted ?? false;
    }

    return true;
  }

  /// Get or create a notification ID for a download
  int _getNotificationId(String url) {
    if (!_downloadNotificationIds.containsKey(url)) {
      _downloadNotificationIds[url] = _nextNotificationId++;
    }
    return _downloadNotificationIds[url]!;
  }

  /// Show a download progress notification
  Future<void> showDownloadProgress({
    required String url,
    required String title,
    required String body,
    required double progress,
    required int receivedBytes,
    required int totalBytes,
    bool indeterminate = false,
  }) async {
    if (!_isInitialized) await initialize();

    final int notificationId = _getNotificationId(url);
    final int progressPercent = (progress * 100).round();

    // Format file sizes
    final String receivedSize = _formatFileSize(receivedBytes);
    final String totalSize = _formatFileSize(totalBytes);

    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'download_channel',
      'Downloads',
      channelDescription: 'Shows download progress notifications',
      importance: Importance.low,
      priority: Priority.low,
      showWhen: true,
      onlyAlertOnce: true,
      ongoing: progress < 1.0,
      autoCancel: progress >= 1.0,
      progress: progressPercent,
      maxProgress: 100,
      indeterminate: indeterminate,
      showProgress: true,
      enableVibration: false,
      playSound: false,
      icon: '@mipmap/ic_launcher',
    );

    final DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: progress >= 1.0, // Only alert on completion
      presentBadge: false,
      presentSound: progress >= 1.0,
    );

    final NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notificationsPlugin.show(
      notificationId,
      title,
      '$body\n$receivedSize / $totalSize ($progressPercent%)',
      notificationDetails,
      payload: url,
    );
  }

  /// Show download started notification
  Future<void> showDownloadStarted({
    required String url,
    required String title,
    required String body,
  }) async {
    if (!_isInitialized) await initialize();

    final int notificationId = _getNotificationId(url);

    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'download_channel',
      'Downloads',
      channelDescription: 'Shows download progress notifications',
      importance: Importance.low,
      priority: Priority.low,
      showWhen: true,
      onlyAlertOnce: true,
      ongoing: true,
      autoCancel: false,
      indeterminate: true,
      showProgress: true,
      enableVibration: false,
      playSound: false,
      icon: '@mipmap/ic_launcher',
    );

    final DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: false,
      presentBadge: false,
      presentSound: false,
    );

    final NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notificationsPlugin.show(
      notificationId,
      title,
      body,
      notificationDetails,
      payload: url,
    );
  }

  /// Show download completed notification
  Future<void> showDownloadCompleted({
    required String url,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_isInitialized) await initialize();

    final int notificationId = _getNotificationId(url);

    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'download_channel',
      'Downloads',
      channelDescription: 'Shows download progress notifications',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      showWhen: true,
      onlyAlertOnce: false,
      ongoing: false,
      autoCancel: true,
      showProgress: false,
      enableVibration: true,
      playSound: true,
      icon: '@mipmap/ic_launcher',
    );

    final DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notificationsPlugin.show(
      notificationId,
      title,
      body,
      notificationDetails,
      payload: payload ?? url,
    );

    // Clean up the notification ID mapping
    _downloadNotificationIds.remove(url);
  }

  /// Show download failed notification
  Future<void> showDownloadFailed({
    required String url,
    required String title,
    required String body,
  }) async {
    if (!_isInitialized) await initialize();

    final int notificationId = _getNotificationId(url);

    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'download_channel',
      'Downloads',
      channelDescription: 'Shows download progress notifications',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      onlyAlertOnce: false,
      ongoing: false,
      autoCancel: true,
      showProgress: false,
      enableVibration: true,
      playSound: true,
      icon: '@mipmap/ic_launcher',
    );

    final DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notificationsPlugin.show(
      notificationId,
      title,
      body,
      notificationDetails,
      payload: url,
    );

    // Clean up the notification ID mapping
    _downloadNotificationIds.remove(url);
  }

  /// Show download cancelled notification
  Future<void> showDownloadCancelled({
    required String url,
    required String title,
    required String body,
  }) async {
    if (!_isInitialized) await initialize();

    final int notificationId = _getNotificationId(url);

    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'download_channel',
      'Downloads',
      channelDescription: 'Shows download progress notifications',
      importance: Importance.low,
      priority: Priority.low,
      showWhen: true,
      onlyAlertOnce: true,
      ongoing: false,
      autoCancel: true,
      showProgress: false,
      enableVibration: false,
      playSound: false,
      icon: '@mipmap/ic_launcher',
    );

    final DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: false,
      presentBadge: false,
      presentSound: false,
    );

    final NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notificationsPlugin.show(
      notificationId,
      title,
      body,
      notificationDetails,
      payload: url,
    );

    // Clean up the notification ID mapping
    _downloadNotificationIds.remove(url);
  }

  /// Cancel a download notification
  Future<void> cancelDownloadNotification(String url) async {
    final int? notificationId = _downloadNotificationIds[url];
    if (notificationId != null) {
      await _notificationsPlugin.cancel(notificationId);
      _downloadNotificationIds.remove(url);
    }
  }

  /// Cancel all notifications
  Future<void> cancelAllNotifications() async {
    await _notificationsPlugin.cancelAll();
    _downloadNotificationIds.clear();
  }

  /// Format file size to human readable string
  String _formatFileSize(int bytes) {
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

  /// Show an app notification (not download-related)
  Future<void> showAppNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_isInitialized) await initialize();

    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'app_notifications_channel',
      'App Notifications',
      channelDescription: 'Shows app notifications',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      icon: '@mipmap/ic_launcher',
    );

    final DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notificationsPlugin.show(
      DateTime.now().millisecondsSinceEpoch % 100000,
      title,
      body,
      notificationDetails,
      payload: payload,
    );
  }
}
