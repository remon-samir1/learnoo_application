import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:learnoo/core/services/notification_service.dart';
import 'package:learnoo/core/services/websocket_service.dart';
import 'package:learnoo/core/session/session_manager.dart';
import 'package:learnoo/features/auth/data/auth_repository.dart';
import 'package:learnoo/features/home/data/models/notification.dart';
import 'package:learnoo/features/home/data/notification_repository.dart';

/// Mirrors the student's notifications (`GET /v1/notifications`, the same
/// endpoint the web dashboard reads in `getStudentNotifications`) into the
/// phone's notification bar while the app is running.
///
/// The backend has no push service, so this only works while the process is
/// alive: on start, on resume, every [pollInterval] while in the foreground,
/// and shortly after any realtime broadcast. Delivery while the app is closed
/// needs FCM/APNs from the backend.
///
/// Rules:
/// * The first sync for a session only records what is already there — the
///   backlog is never shown.
/// * Afterwards only unread notifications that were not seen before and are
///   not older than the newest one already seen are shown.
/// * Every id seen is remembered (SharedPreferences), so nothing is shown
///   twice, across restarts too. The state is dropped when the session ends.
class NotificationSyncService {
  NotificationSyncService._internal();
  static final NotificationSyncService _instance =
      NotificationSyncService._internal();
  factory NotificationSyncService() => _instance;

  static const Duration pollInterval = Duration(minutes: 3);

  static const String _initializedKey = 'notif_sync_initialized';
  static const String _seenIdsKey = 'notif_sync_seen_ids';
  static const String _latestAtKey = 'notif_sync_latest_at';

  /// Ids kept in storage; page 1 of the API is far smaller than this.
  static const int _maxRememberedIds = 300;

  /// More new notifications than this at once collapse into a summary.
  static const int _maxIndividual = 3;

  final NotificationRepository _repository =
      NotificationRepository(authRepository: AuthRepository());
  final NotificationService _notificationService = NotificationService();

  Timer? _pollTimer;
  Timer? _debounce;
  StreamSubscription<Map<String, dynamic>>? _realtimeSubscription;
  Future<void>? _running;
  bool _started = false;

  /// Starts syncing. Safe to call more than once.
  void start() {
    if (_started) return;
    _started = true;
    SessionManager().sessionRevoked.addListener(_onSessionRevoked);
    // A broadcast on the realtime channel is not necessarily for this
    // student, so it only triggers a fetch of the student's own list.
    _realtimeSubscription =
        WebSocketService().notificationStream.listen((_) => syncSoon());
    resume();
  }

  /// App came to the foreground: sync now and keep polling.
  void resume() {
    if (!_started) return;
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(pollInterval, (_) => unawaited(sync()));
    unawaited(sync());
  }

  /// App went to the background: stop polling.
  void pause() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _debounce?.cancel();
    _debounce = null;
  }

  /// Sync after a short delay, coalescing bursts of triggers.
  void syncSoon() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () => unawaited(sync()));
  }

  /// Fetches the latest notifications and shows the new unread ones.
  Future<void> sync() {
    final running = _running;
    if (running != null) return running;
    final future = _sync().whenComplete(() => _running = null);
    _running = future;
    return future;
  }

  Future<void> _sync() async {
    try {
      if (!await SessionManager().isSignedIn) return;

      final result = await _repository.getNotifications(page: 1);
      if (result['success'] != true || result['data'] is! List<Notification>) {
        return;
      }
      final items = (result['data'] as List<Notification>)
          .where((n) => n.id.isNotEmpty)
          .toList();

      // The session may have ended while the request was in flight.
      if (!await SessionManager().isSignedIn) return;

      final prefs = await SharedPreferences.getInstance();
      final initialized = prefs.getBool(_initializedKey) ?? false;
      final seen = prefs.getStringList(_seenIdsKey) ?? const <String>[];
      final seenSet = seen.toSet();
      final latestAt = prefs.getInt(_latestAtKey);

      var newestAt = latestAt;
      for (final n in items) {
        final t = _timeOf(n);
        if (t != null && (newestAt == null || t > newestAt)) newestAt = t;
      }

      final fresh = initialized
          ? items.where((n) {
              if (!n.isUnread || seenSet.contains(n.id)) return false;
              final t = _timeOf(n);
              // Same-second timestamps are allowed; the id check dedupes.
              return latestAt == null || t == null || t >= latestAt;
            }).toList()
          : const <Notification>[];

      // Persist before showing so a crash mid-way never re-shows anything.
      final updatedSeen = <String>[
        ...items.map((n) => n.id).where((id) => !seenSet.contains(id)),
        ...seen,
      ];
      await prefs.setStringList(
        _seenIdsKey,
        updatedSeen.take(_maxRememberedIds).toList(),
      );
      if (newestAt != null) await prefs.setInt(_latestAtKey, newestAt);
      if (!initialized) await prefs.setBool(_initializedKey, true);

      if (fresh.isEmpty) return;
      await _show(fresh);
    } catch (e) {
      debugPrint('[NotificationSync] sync failed: ${e.runtimeType}');
    }
  }

  Future<void> _show(List<Notification> fresh) async {
    // Newest first from the API; post the oldest first so the newest ends up
    // on top of the tray.
    final shown = fresh.take(_maxIndividual).toList().reversed;
    for (final n in shown) {
      final title = n.data.title.trim().isNotEmpty
          ? n.data.title.trim()
          : 'notifications_push.fallback_title'.tr();
      final body = n.data.message.trim().isNotEmpty
          ? n.data.message.trim()
          : 'notifications_push.fallback_message'.tr();
      await _notificationService.showGeneralNotification(
        key: n.id,
        title: title,
        body: body,
      );
    }
    final remaining = fresh.length - _maxIndividual;
    if (remaining > 0) {
      await _notificationService.showGeneralNotification(
        key: 'summary',
        title: 'notifications_push.summary_title'.tr(),
        body: 'notifications_push.summary_body'.tr(args: ['$remaining']),
      );
    }
  }

  int? _timeOf(Notification n) =>
      DateTime.tryParse(n.createdAt)?.millisecondsSinceEpoch;

  void _onSessionRevoked() => unawaited(_reset());

  /// Forget everything so the next student's first sync starts clean.
  Future<void> _reset() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_initializedKey);
      await prefs.remove(_seenIdsKey);
      await prefs.remove(_latestAtKey);
    } catch (e) {
      debugPrint('[NotificationSync] reset failed: ${e.runtimeType}');
    }
  }

  @visibleForTesting
  void stop() {
    pause();
    _realtimeSubscription?.cancel();
    _realtimeSubscription = null;
    SessionManager().sessionRevoked.removeListener(_onSessionRevoked);
    _started = false;
  }
}
