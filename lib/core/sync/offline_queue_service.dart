import 'dart:convert';
import '../local/hive_service.dart';
import '../local/hive_boxes.dart';
import '../local/models/pending_action.dart';

/// Service to manage the offline action queue
/// Stores actions that need to be synced when connection is restored
class OfflineQueueService {
  static final OfflineQueueService _instance = OfflineQueueService._internal();
  factory OfflineQueueService() => _instance;
  OfflineQueueService._internal();

  final HiveService _hive = HiveService();

  /// Add a new action to the queue
  Future<PendingAction> enqueue({
    required String type,
    required Map<String, dynamic> payload,
    String? id,
  }) async {
    final action = PendingAction(
      id: id ?? '${type}_${DateTime.now().millisecondsSinceEpoch}_${DateTime.now().microsecond}',
      type: type,
      payload: payload,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );

    final box = _hive.getBox(HiveBoxes.pendingActions);
    await box.put(action.id, action.toJsonString());

    return action;
  }

  /// Get all pending actions
  List<PendingAction> getAllPendingActions() {
    final box = _hive.getBox(HiveBoxes.pendingActions);
    final actions = <PendingAction>[];

    for (final value in box.values) {
      try {
        actions.add(PendingAction.fromJsonString(value.toString()));
      } catch (e) {
        // Skip corrupted entries
        continue;
      }
    }

    // Sort by creation time (oldest first)
    actions.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return actions;
  }

  /// Get pending actions by type
  List<PendingAction> getPendingActionsByType(String type) {
    return getAllPendingActions().where((a) => a.type == type).toList();
  }

  /// Remove a completed action from the queue
  Future<void> dequeue(String actionId) async {
    final box = _hive.getBox(HiveBoxes.pendingActions);
    await box.delete(actionId);
  }

  /// Update an action after retry attempt
  Future<void> updateAction(PendingAction action) async {
    final box = _hive.getBox(HiveBoxes.pendingActions);
    await box.put(action.id, action.toJsonString());
  }

  /// Mark action as failed with error message
  Future<void> markFailed(String actionId, String error) async {
    final actions = getAllPendingActions();
    final action = actions.firstWhere(
      (a) => a.id == actionId,
      orElse: () => throw StateError('Action not found: $actionId'),
    );

    final updated = action.markAttempted(error);
    await updateAction(updated);
  }

  /// Mark action as successful and remove from queue
  Future<void> markSuccessful(String actionId) async {
    await dequeue(actionId);
  }

  /// Get count of pending actions
  int getPendingCount() {
    return _hive.getBox(HiveBoxes.pendingActions).length;
  }

  /// Check if there are any pending actions
  bool hasPendingActions() {
    return getPendingCount() > 0;
  }

  /// Clear all pending actions (use with caution)
  Future<void> clearAll() async {
    await _hive.clearPendingActions();
  }

  /// Get actions that are ready to retry (based on backoff strategy)
  List<PendingAction> getActionsReadyForRetry() {
    return getAllPendingActions().where((a) => a.shouldRetry()).toList();
  }

  /// Remove duplicate actions (same type and comparable payload)
  Future<int> deduplicate() async {
    final actions = getAllPendingActions();
    final seen = <String>{};
    final duplicates = <String>[];

    for (final action in actions) {
      // Create a key based on type and relevant payload fields
      final key = _createDedupKey(action);

      if (seen.contains(key)) {
        duplicates.add(action.id);
      } else {
        seen.add(key);
      }
    }

    // Remove duplicates
    for (final id in duplicates) {
      await dequeue(id);
    }

    return duplicates.length;
  }

  /// Create a deduplication key for an action
  String _createDedupKey(PendingAction action) {
    // Include type and specific payload fields based on action type
    final payload = action.payload;

    switch (action.type) {
      case PendingActionTypes.progress:
        return '${action.type}_${payload['chapter_id']}';
      case PendingActionTypes.comment:
      case PendingActionTypes.post:
        return '${action.type}_${payload['content']}_${payload['lecture_id'] ?? payload['course_id']}';
      case PendingActionTypes.reaction:
        return '${action.type}_${payload['post_id']}_${payload['type']}';
      default:
        return '${action.type}_${jsonEncode(payload)}';
    }
  }
}
