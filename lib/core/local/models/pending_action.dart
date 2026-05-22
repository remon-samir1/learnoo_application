import 'dart:convert';

/// Represents a pending action to be synced when online
class PendingAction {
  final String id;
  final String type; // 'comment', 'progress', 'post', 'reaction', etc.
  final Map<String, dynamic> payload;
  final int createdAt;
  final int retryCount;
  final String? lastError;
  final int? lastAttemptAt;

  PendingAction({
    required this.id,
    required this.type,
    required this.payload,
    required this.createdAt,
    this.retryCount = 0,
    this.lastError,
    this.lastAttemptAt,
  });

  /// Create from JSON map
  factory PendingAction.fromJson(Map<String, dynamic> json) {
    return PendingAction(
      id: json['id'] as String,
      type: json['type'] as String,
      payload: json['payload'] as Map<String, dynamic>,
      createdAt: json['createdAt'] as int,
      retryCount: json['retryCount'] as int? ?? 0,
      lastError: json['lastError'] as String?,
      lastAttemptAt: json['lastAttemptAt'] as int?,
    );
  }

  /// Convert to JSON map
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'payload': payload,
      'createdAt': createdAt,
      'retryCount': retryCount,
      'lastError': lastError,
      'lastAttemptAt': lastAttemptAt,
    };
  }

  /// Convert to JSON string
  String toJsonString() => jsonEncode(toJson());

  /// Create from JSON string
  factory PendingAction.fromJsonString(String jsonString) {
    return PendingAction.fromJson(jsonDecode(jsonString) as Map<String, dynamic>);
  }

  /// Copy with new values
  PendingAction copyWith({
    String? id,
    String? type,
    Map<String, dynamic>? payload,
    int? createdAt,
    int? retryCount,
    String? lastError,
    int? lastAttemptAt,
  }) {
    return PendingAction(
      id: id ?? this.id,
      type: type ?? this.type,
      payload: payload ?? this.payload,
      createdAt: createdAt ?? this.createdAt,
      retryCount: retryCount ?? this.retryCount,
      lastError: lastError ?? this.lastError,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
    );
  }

  /// Mark action as attempted (increment retry count and set last attempt time)
  PendingAction markAttempted(String? error) {
    return copyWith(
      retryCount: retryCount + 1,
      lastError: error,
      lastAttemptAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// Check if action should be retried based on exponential backoff
  bool shouldRetry({int maxRetries = 5}) {
    if (retryCount >= maxRetries) return false;

    if (lastAttemptAt == null) return true;

    // Exponential backoff: 2^retryCount * 1000ms (1s, 2s, 4s, 8s, 16s)
    final backoffMs = (1 << retryCount) * 1000;
    final timeSinceLastAttempt = DateTime.now().millisecondsSinceEpoch - lastAttemptAt!;

    return timeSinceLastAttempt >= backoffMs;
  }

  @override
  String toString() => 'PendingAction(id: $id, type: $type, retryCount: $retryCount)';
}

/// Types of pending actions
class PendingActionTypes {
  static const String comment = 'comment';
  static const String progress = 'progress';
  static const String post = 'post';
  static const String reaction = 'reaction';
  static const String deletePost = 'delete_post';
  static const String updatePost = 'update_post';
}
