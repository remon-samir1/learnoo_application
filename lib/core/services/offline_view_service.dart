import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../sync/offline_queue_service.dart';
import '../local/models/pending_action.dart';

/// Views this device has spent but the server has not recorded yet.
///
/// A local view is exactly a `chapterView` action still waiting in the offline
/// queue: it is added when a view cannot be sent and disappears when the queue
/// delivers it (or gives up on it). Total views are therefore
/// `server views + views still queued`, and a view is never counted twice.
///
/// Earlier versions kept a separate counter in SharedPreferences that only
/// ever grew — it was not cleared when the queued view reached the server — so
/// each failed or late request kept a phantom view on the device and students
/// were locked out in the app while the website still let them watch. That
/// counter is now ignored and removed.
class OfflineViewService {
  static final OfflineViewService _instance = OfflineViewService._internal();
  factory OfflineViewService() => _instance;
  OfflineViewService._internal();

  static const String _prefsKeyPrefix = 'offline_views_';
  static const String _prefsKeySyncedPrefix = 'offline_views_synced_';

  SharedPreferences? _prefs;

  /// Initialize the service by loading SharedPreferences
  Future<void> initialize() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  List<PendingAction> _pendingViews(String chapterId) {
    try {
      return OfflineQueueService()
          .getPendingActionsByType(PendingActionTypes.chapterView)
          .where((action) => '${action.payload['chapter_id']}' == chapterId)
          .toList();
    } catch (e) {
      debugPrint('[OfflineViewService] Queue unavailable: $e');
      return const [];
    }
  }

  /// Removes the retired SharedPreferences counter for [chapterId].
  Future<void> _dropLegacyCounter(String chapterId) async {
    await initialize();
    await _prefs?.remove('$_prefsKeyPrefix$chapterId');
    await _prefs?.remove('$_prefsKeySyncedPrefix$chapterId');
  }

  /// A fresh key for one opening of a lesson. The server counts a view key
  /// once, so the same opening re-sent after a timeout, a failed request or
  /// from the offline queue can never be charged twice.
  static String newViewKey() {
    final random = Random.secure();
    return List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  /// Queues a view the server has not recorded, and returns how many views
  /// for [chapterId] are now waiting to be sent.
  ///
  /// [viewKey] identifies the opening the view belongs to: an opening already
  /// waiting in the queue is not queued a second time. [courseId] lets a
  /// course activation code discard the views it resets.
  Future<int> incrementOfflineView(
    String chapterId, {
    int? watchedMinutes,
    String? viewKey,
    String? courseId,
  }) async {
    await _dropLegacyCounter(chapterId);

    final chapterNumericId = int.tryParse(chapterId);
    final alreadyQueued = viewKey != null &&
        _pendingViews(chapterId).any((action) => action.payload['view_key'] == viewKey);
    if (chapterNumericId != null && chapterNumericId > 0 && !alreadyQueued) {
      await OfflineQueueService().enqueue(
        type: PendingActionTypes.chapterView,
        payload: {
          'chapter_id': chapterNumericId,
          if (watchedMinutes != null) 'watched_minutes': watchedMinutes,
          if (viewKey != null) 'view_key': viewKey,
          if (courseId != null && courseId.isNotEmpty) 'course_id': courseId,
        },
      );
    }

    final pending = _pendingViews(chapterId).length;
    debugPrint('[OfflineViewService] Queued a view for chapter $chapterId; $pending waiting to sync');
    return pending;
  }

  /// Views for [chapterId] still waiting to reach the server.
  Future<int> getOfflineViews(String chapterId) async => _pendingViews(chapterId).length;

  /// Same as [getOfflineViews], synchronously.
  int getOfflineViewsSync(String chapterId) => _pendingViews(chapterId).length;

  /// Calculate total views (API views + views still queued)
  int calculateTotalViews(int apiViews, String chapterId) =>
      apiViews + getOfflineViewsSync(chapterId);

  /// Called with fresh server data: drops the retired counter and returns the
  /// views still queued, which the server count does not include yet.
  Future<int> syncWithApi(String chapterId, int apiCurrentViews, int apiMaxViews) async {
    await _dropLegacyCounter(chapterId);
    final pending = getOfflineViewsSync(chapterId);
    debugPrint('[OfflineViewService] Chapter $chapterId: API=$apiCurrentViews, queued=$pending');
    return pending;
  }

  /// Clear the retired local counter for a specific chapter
  Future<void> clearOfflineViews(String chapterId) => _dropLegacyCounter(chapterId);

  /// An activation code resets the server's view count for its chapter, so
  /// views this device spent before it must neither keep the chapter locked
  /// here nor be sent later and charged against the new code.
  Future<void> discardViewsAfterActivation(String chapterId) async {
    await clearOfflineViews(chapterId);
    final queue = OfflineQueueService();
    for (final action in _pendingViews(chapterId)) {
      await queue.dequeue(action.id);
    }
  }

  /// A course activation code resets the views of every lesson in the
  /// course; drops the queued views recorded for that course.
  Future<void> discardViewsAfterCourseActivation(String courseId) async {
    final queue = OfflineQueueService();
    final List<PendingAction> pending;
    try {
      pending = queue.getPendingActionsByType(PendingActionTypes.chapterView);
    } catch (e) {
      debugPrint('[OfflineViewService] Queue unavailable: $e');
      return;
    }
    for (final action in pending) {
      if ('${action.payload['course_id']}' != courseId) continue;
      await clearOfflineViews('${action.payload['chapter_id']}');
      await queue.dequeue(action.id);
    }
  }

  /// Check if views are exhausted for a chapter (including queued views)
  bool areViewsExhausted(int apiCurrentViews, String chapterId, int maxViews) =>
      calculateTotalViews(apiCurrentViews, chapterId) >= maxViews;

  /// Get remaining views for a chapter
  int getRemainingViews(int apiCurrentViews, String chapterId, int maxViews) =>
      (maxViews - calculateTotalViews(apiCurrentViews, chapterId)).clamp(0, maxViews);

  /// Removes every retired local counter (e.g. on logout).
  Future<void> resetAllOfflineViews() async {
    await initialize();
    final keys = _prefs?.getKeys() ?? <String>{};
    for (final key in keys.where((key) =>
        key.startsWith(_prefsKeyPrefix) || key.startsWith(_prefsKeySyncedPrefix))) {
      await _prefs?.remove(key);
    }
    debugPrint('[OfflineViewService] Reset all offline views');
  }

  /// Chapters with views still queued (for debugging).
  Map<String, int> getAllOfflineViews() {
    final result = <String, int>{};
    try {
      for (final action in OfflineQueueService()
          .getPendingActionsByType(PendingActionTypes.chapterView)) {
        final id = '${action.payload['chapter_id']}';
        result[id] = (result[id] ?? 0) + 1;
      }
    } catch (_) {}
    return result;
  }
}
