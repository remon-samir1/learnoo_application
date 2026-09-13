import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../sync/offline_queue_service.dart';
import '../local/models/pending_action.dart';

/// Service for managing offline video view counts.
/// 
/// This service tracks views locally when the user watches videos offline,
/// and allows syncing with the API when back online.
/// 
/// The total views calculation is: Total = API Views + Offline Views
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

  /// Get the storage key for a chapter's offline views
  String _getViewsKey(String chapterId) => '$_prefsKeyPrefix$chapterId';

  /// Get the storage key for tracking if views were synced
  String _getSyncedKey(String chapterId) => '$_prefsKeySyncedPrefix$chapterId';

  /// Increment the offline view count for a chapter
  /// Returns the new offline view count and enqueues an offline sync action
  Future<int> incrementOfflineView(String chapterId, {int? watchedMinutes}) async {
    await initialize();
    
    final key = _getViewsKey(chapterId);
    final currentViews = _prefs?.getInt(key) ?? 0;
    final newViews = currentViews + 1;
    
    await _prefs?.setInt(key, newViews);
    await _prefs?.setBool(_getSyncedKey(chapterId), false);

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
    
    debugPrint('[OfflineViewService] Incremented offline views for chapter $chapterId: $currentViews -> $newViews and queued sync action');
    return newViews;
  }

  /// Get the current offline view count for a chapter
  Future<int> getOfflineViews(String chapterId) async {
    await initialize();
    
    final key = _getViewsKey(chapterId);
    final views = _prefs?.getInt(key) ?? 0;
    
    return views;
  }

  /// Get offline views synchronously (requires initialize() to be called first)
  int getOfflineViewsSync(String chapterId) {
    final key = _getViewsKey(chapterId);
    return _prefs?.getInt(key) ?? 0;
  }

  /// Calculate total views (API views + offline views)
  int calculateTotalViews(int apiViews, String chapterId) {
    final offlineViews = getOfflineViewsSync(chapterId);
    return apiViews + offlineViews;
  }

  /// Sync offline views with API data
  /// - If API current views exceed local total, clear local offline views
  /// - Mark views as synced
  /// Returns the resolved offline view count after sync
  Future<int> syncWithApi(String chapterId, int apiCurrentViews, int apiMaxViews) async {
    await initialize();
    
    final offlineViews = getOfflineViewsSync(chapterId);
    final localTotal = apiCurrentViews + offlineViews;
    
    // If API shows more views than our local total (watched on another device),
    // clear the offline views since they're already accounted for
    if (apiCurrentViews >= localTotal && offlineViews > 0) {
      await clearOfflineViews(chapterId);
      debugPrint('[OfflineViewService] Cleared offline views for chapter $chapterId - API already has $apiCurrentViews views');
      return 0;
    }
    
    await _prefs?.setBool(_getSyncedKey(chapterId), true);
    
    debugPrint('[OfflineViewService] Synced offline views for chapter $chapterId: API=$apiCurrentViews, Offline=$offlineViews, Total=$localTotal');
    return offlineViews;
  }

  /// Clear offline views for a specific chapter
  Future<void> clearOfflineViews(String chapterId) async {
    await initialize();
    
    final key = _getViewsKey(chapterId);
    final syncedKey = _getSyncedKey(chapterId);
    
    await _prefs?.remove(key);
    await _prefs?.remove(syncedKey);
    
    debugPrint('[OfflineViewService] Cleared offline views for chapter $chapterId');
  }

  /// Check if views are exhausted for a chapter (including offline views)
  bool areViewsExhausted(int apiCurrentViews, String chapterId, int maxViews) {
    final offlineViews = getOfflineViewsSync(chapterId);
    final totalViews = apiCurrentViews + offlineViews;
    
    return totalViews >= maxViews;
  }

  /// Get remaining views for a chapter
  int getRemainingViews(int apiCurrentViews, String chapterId, int maxViews) {
    final offlineViews = getOfflineViewsSync(chapterId);
    final totalViews = apiCurrentViews + offlineViews;
    
    return (maxViews - totalViews).clamp(0, maxViews);
  }

  /// Reset all offline views (useful for testing or when user logs out)
  Future<void> resetAllOfflineViews() async {
    await initialize();
    
    final keys = _prefs?.getKeys() ?? <String>{};
    final offlineKeys = keys.where((key) => 
      key.startsWith(_prefsKeyPrefix) || key.startsWith(_prefsKeySyncedPrefix)
    );
    
    for (final key in offlineKeys) {
      await _prefs?.remove(key);
    }
    
    debugPrint('[OfflineViewService] Reset all offline views');
  }

  /// Get all chapters with offline views (for debugging/migration)
  Map<String, int> getAllOfflineViews() {
    final keys = _prefs?.getKeys() ?? <String>{};
    final result = <String, int>{};
    
    for (final key in keys) {
      if (key.startsWith(_prefsKeyPrefix)) {
        final chapterId = key.substring(_prefsKeyPrefix.length);
        final views = _prefs?.getInt(key) ?? 0;
        if (views > 0) {
          result[chapterId] = views;
        }
      }
    }
    
    return result;
  }
}
