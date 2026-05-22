import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import '../local/models/pending_action.dart';
import 'offline_queue_service.dart';

/// Callback signature for processing a pending action
/// Returns true if successful, false or throws if failed
typedef ActionProcessor = Future<bool> Function(PendingAction action);

/// Service to handle background synchronization
/// Monitors connectivity and syncs pending actions when online
class SyncService extends ChangeNotifier {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  final OfflineQueueService _queue = OfflineQueueService();
  final Connectivity _connectivity = Connectivity();

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _isOnline = false;
  bool _isSyncing = false;
  SyncStatus _status = SyncStatus.idle;
  String? _lastError;

  // Registered action processors
  final Map<String, ActionProcessor> _processors = {};

  // Callbacks for UI updates
  VoidCallback? onSyncStarted;
  VoidCallback? onSyncCompleted;
  Function(String error)? onSyncError;
  Function(int completed, int total)? onSyncProgress;

  // Getters
  bool get isOnline => _isOnline;
  bool get isSyncing => _isSyncing;
  SyncStatus get status => _status;
  String? get lastError => _lastError;
  int get pendingCount => _queue.getPendingCount();

  /// Initialize the sync service
  Future<void> initialize() async {
    // Check initial connectivity
    final results = await _connectivity.checkConnectivity();
    final result = results.isNotEmpty ? results.first : ConnectivityResult.none;
    _updateConnectivityStatus(result);

    // Listen for connectivity changes
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen((results) {
      final result = results.isNotEmpty ? results.first : ConnectivityResult.none;
      _updateConnectivityStatus(result);
      if (_isOnline && _queue.hasPendingActions()) {
        syncPendingActions();
      }
    });
  }

  /// Dispose resources
  void dispose() {
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  /// Register a processor for a specific action type
  void registerProcessor(String actionType, ActionProcessor processor) {
    _processors[actionType] = processor;
  }

  /// Unregister a processor
  void unregisterProcessor(String actionType) {
    _processors.remove(actionType);
  }

  /// Update connectivity status
  void _updateConnectivityStatus(ConnectivityResult result) {
    final wasOnline = _isOnline;
    _isOnline = result != ConnectivityResult.none;

    if (_isOnline != wasOnline) {
      notifyListeners();
    }
  }

  /// Manually trigger sync
  Future<SyncResult> syncPendingActions() async {
    if (_isSyncing) return SyncResult.alreadySyncing;
    if (!_isOnline) return SyncResult.offline;

    final actions = _queue.getActionsReadyForRetry();
    if (actions.isEmpty) return SyncResult.nothingToSync;

    _isSyncing = true;
    _status = SyncStatus.syncing;
    _lastError = null;
    notifyListeners();
    onSyncStarted?.call();

    int completed = 0;
    int failed = 0;
    int skipped = 0;

    for (int i = 0; i < actions.length; i++) {
      final action = actions[i];

      // Report progress
      onSyncProgress?.call(i, actions.length);

      // Check if we have a processor for this action type
      final processor = _processors[action.type];
      if (processor == null) {
        skipped++;
        continue;
      }

      try {
        final success = await processor(action);

        if (success) {
          await _queue.markSuccessful(action.id);
          completed++;
        } else {
          await _queue.markFailed(action.id, 'Processing returned false');
          failed++;
        }
      } catch (e) {
        await _queue.markFailed(action.id, e.toString());
        failed++;
      }

      // Small delay to prevent overwhelming the API
      if (i < actions.length - 1) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }

    _isSyncing = false;

    if (failed > 0) {
      _status = SyncStatus.partialError;
      _lastError = '$failed action(s) failed to sync';
    } else {
      _status = SyncStatus.success;
    }

    notifyListeners();
    onSyncCompleted?.call();

    return failed > 0 ? SyncResult.partialSuccess : SyncResult.success;
  }

  /// Force sync regardless of connectivity (for retry scenarios)
  Future<SyncResult> forceSync() async {
    return syncPendingActions();
  }

  /// Check connectivity status manually
  Future<bool> checkConnectivity() async {
    final results = await _connectivity.checkConnectivity();
    final result = results.isNotEmpty ? results.first : ConnectivityResult.none;
    _updateConnectivityStatus(result);
    return _isOnline;
  }

  /// Clear completed/failed actions that exceeded retry limit
  Future<int> cleanupFailedActions() async {
    final actions = _queue.getAllPendingActions();
    int removed = 0;

    for (final action in actions) {
      if (!action.shouldRetry(maxRetries: 5)) {
        await _queue.dequeue(action.id);
        removed++;
      }
    }

    return removed;
  }

  /// Deduplicate pending actions
  Future<void> deduplicate() async {
    await _queue.deduplicate();
    notifyListeners();
  }
}

/// Sync status enumeration
enum SyncStatus {
  idle,
  syncing,
  success,
  partialError,
  offline,
}

/// Sync result enumeration
enum SyncResult {
  success,
  partialSuccess,
  offline,
  nothingToSync,
  alreadySyncing,
}

/// Extension to get display name for sync status
extension SyncStatusExtension on SyncStatus {
  String get displayName {
    switch (this) {
      case SyncStatus.idle:
        return 'Idle';
      case SyncStatus.syncing:
        return 'Syncing...';
      case SyncStatus.success:
        return 'Synced';
      case SyncStatus.partialError:
        return 'Some items failed';
      case SyncStatus.offline:
        return 'Offline';
    }
  }

  bool get isError => this == SyncStatus.partialError || this == SyncStatus.offline;
}
