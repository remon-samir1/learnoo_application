import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../local/hive_service.dart';
import '../sync/offline_queue_service.dart';
import '../sync/sync_service.dart';
import '../local/models/pending_action.dart';

/// Mixin that provides offline-first capabilities to repositories
/// Usage: Extend your repository and call offlineFirstFetch for GET requests
/// and queueAction for POST/PUT/DELETE that should work offline
mixin OfflineFirstRepository {
  final HiveService _hive = HiveService();
  final OfflineQueueService _queue = OfflineQueueService();
  final Connectivity _connectivity = Connectivity();

  /// Check if device is currently online
  Future<bool> isOnline() async {
    final result = await _connectivity.checkConnectivity();
    return result != ConnectivityResult.none;
  }

  /// Fetch data with offline-first strategy:
  /// 1. Try to fetch from API if online
  /// 2. Cache successful API response
  /// 3. Return cached data if API fails or offline
  ///
  /// [apiFetcher]: Function that performs the actual API call
  /// [boxName]: Hive box name for caching
  /// [cacheKey]: Unique key for this data in cache
  /// [maxCacheAge]: How long cached data remains valid
  Future<Map<String, dynamic>> offlineFirstFetch({
    required Future<Map<String, dynamic>> Function() apiFetcher,
    required String boxName,
    required String cacheKey,
    Duration maxCacheAge = const Duration(hours: 24),
  }) async {
    final online = await isOnline();

    // Try API first if online
    if (online) {
      try {
        final result = await apiFetcher();

        if (result['success'] == true && result['data'] != null) {
          // Cache the successful response
          await _hive.storeWithTimestamp(boxName, cacheKey, result['data']);
          return {
            ...result,
            'fromCache': false,
            'offline': false,
          };
        }
      } catch (e) {
        // Check if this is an authorization error (403/401) - don't fall back to cache
        if (e is Map<String, dynamic> &&
            (e['statusCode'] == 403 || e['statusCode'] == 401)) {
          return {
            'success': false,
            'message': e['message'] ?? 'Access denied',
            'statusCode': e['statusCode'],
            'authorizationError': true,
            'fromCache': false,
            'offline': false,
          };
        }
        // API failed, fall through to cache
      }
    }

    // Try to return cached data
    final cached = _hive.retrieveWithTimestamp(boxName, cacheKey);
    if (cached != null) {
      final ageMs = cached['ageMs'] as int;
      final isValid = ageMs < maxCacheAge.inMilliseconds;

      return {
        'success': true,
        'data': cached['data'],
        'fromCache': true,
        'offline': !online,
        'cacheExpired': !isValid,
        'cacheAgeMs': ageMs,
      };
    }

    // No cache available
    if (!online) {
      return {
        'success': false,
        'message': 'No internet connection and no cached data available',
        'offline': true,
        'fromCache': false,
      };
    }

    // Online but API failed and no cache
    return {
      'success': false,
      'message': 'Failed to fetch data',
      'offline': false,
      'fromCache': false,
    };
  }

  /// Queue an action to be performed when online
  /// Returns immediately with optimistic success for UI updates
  ///
  /// [actionType]: Type of action (use PendingActionTypes constants)
  /// [payload]: Data to send to API
  /// [optimisticId]: Optional ID for optimistic UI tracking
  /// [deduplicate]: Whether to remove duplicate actions before adding
  Future<Map<String, dynamic>> queueAction({
    required String actionType,
    required Map<String, dynamic> payload,
    String? optimisticId,
    bool deduplicate = true,
  }) async {
    final online = await isOnline();

    // If online and not forcing queue, try immediate execution
    if (online && !SyncService().isSyncing) {
      // Return indication that action should be attempted immediately
      return {
        'success': true,
        'queued': false,
        'offline': false,
        'optimisticId': optimisticId,
        'actionType': actionType,
        'payload': payload,
      };
    }

    // Queue the action for later sync
    final action = await _queue.enqueue(
      type: actionType,
      payload: payload,
      id: optimisticId,
    );

    // If deduplicate requested, clean up duplicates
    if (deduplicate) {
      await _queue.deduplicate();
    }

    // Trigger sync if we're online
    if (online) {
      unawaited(SyncService().syncPendingActions());
    }

    return {
      'success': true,
      'queued': true,
      'offline': !online,
      'actionId': action.id,
      'optimisticId': optimisticId,
      'actionType': actionType,
    };
  }

  /// Mark an item as pending in cache (for optimistic UI)
  Future<void> markPending(String boxName, String key, dynamic data) async {
    final pendingData = {
      ...data as Map<String, dynamic>,
      '_isPending': true,
      '_pendingSince': DateTime.now().millisecondsSinceEpoch,
    };
    await _hive.storeWithTimestamp(boxName, key, pendingData);
  }

  /// Remove pending mark from cached item
  Future<void> unmarkPending(String boxName, String key, dynamic cleanData) async {
    await _hive.storeWithTimestamp(boxName, key, cleanData);
  }

  /// Get cached data by key
  dynamic getCached(String boxName, String key) {
    final cached = _hive.retrieveWithTimestamp(boxName, key);
    return cached?['data'];
  }

  /// Get all cached data from a box
  List<dynamic> getAllCached(String boxName) {
    final keys = _hive.getAllKeys(boxName);
    final results = <dynamic>[];

    for (final key in keys) {
      final cached = _hive.retrieveWithTimestamp(boxName, key.toString());
      if (cached != null) {
        results.add(cached['data']);
      }
    }

    return results;
  }

  /// Clear cache for specific box
  Future<void> clearCache(String boxName) async {
    final box = _hive.getBox(boxName);
    await box.clear();
  }

  /// Get cache statistics
  Map<String, dynamic> getCacheStats(String boxName) {
    final keys = _hive.getAllKeys(boxName);
    int validCount = 0;
    int expiredCount = 0;

    for (final key in keys) {
      final cached = _hive.retrieveWithTimestamp(boxName, key.toString());
      if (cached != null) {
        final ageMs = cached['ageMs'] as int;
        if (ageMs < const Duration(hours: 24).inMilliseconds) {
          validCount++;
        } else {
          expiredCount++;
        }
      }
    }

    return {
      'total': keys.length,
      'valid': validCount,
      'expired': expiredCount,
    };
  }
}

/// Utility to allow unawaited futures
void unawaited(Future<void> future) {}
