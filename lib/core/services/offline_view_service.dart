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

  /// Queues a view the server has not recorded, and returns how many views
  /// for [chapterId] are now waiting to be sent.
  Future<int> incrementOfflineView(String chapterId, {int? watchedMinutes}) async {
    await _dropLegacyCounter(chapterId);

    final chapterNumericId = int.tryParse(chapterId);
    if (chapterNumericId != null && chapterNumericId > 0) {
      await OfflineQueueService().enqueue(
        type: PendingActionTypes.chapterView,
        payload: {
          'chapter_id': chapterNumericId,
          if (watchedMinutes != null) 'watched_minutes': watchedMinutes,
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
