class NotificationData {
  final String title;
  final String message;
  final String type;
  final String device;
  final String ipAddress;
  final String createdAt;

  NotificationData({
    required this.title,
    required this.message,
    required this.type,
    required this.device,
    required this.ipAddress,
    required this.createdAt,
  });

  factory NotificationData.fromJson(Map<String, dynamic> json) {
    return NotificationData(
      title: json['title']?.toString() ?? '',
      message: json['message']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      device: json['device']?.toString() ?? '',
      ipAddress: json['ip_address']?.toString() ?? '',
      createdAt: json['created_at']?.toString() ?? '',
    );
  }
}

class Notification {
  final String id;
  final String type;
  final String notifiableType;
  final String notifiableId;
  final NotificationData data;
  final String? readAt;
  final String createdAt;
  final String updatedAt;

  Notification({
    required this.id,
    required this.type,
    required this.notifiableType,
    required this.notifiableId,
    required this.data,
    this.readAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Notification.fromJson(Map<String, dynamic> json) {
    return Notification(
      id: json['id']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      notifiableType: json['notifiable_type']?.toString() ?? '',
      notifiableId: json['notifiable_id']?.toString() ?? '',
      data: NotificationData.fromJson(
        json['data'] is Map ? Map<String, dynamic>.from(json['data'] as Map) : const {},
      ),
      readAt: json['read_at']?.toString(),
      createdAt: json['created_at']?.toString() ?? '',
      updatedAt: json['updated_at']?.toString() ?? '',
    );
  }

  bool get isUnread => readAt == null;
}

class NotificationMeta {
  final int currentPage;
  final int lastPage;
  final int perPage;
  final int total;
  final int unreadCount;

  NotificationMeta({
    required this.currentPage,
    required this.lastPage,
    required this.perPage,
    required this.total,
    required this.unreadCount,
  });

  factory NotificationMeta.fromJson(Map<String, dynamic> json) {
    return NotificationMeta(
      currentPage: json['current_page'] ?? 1,
      lastPage: json['last_page'] ?? 1,
      perPage: json['per_page'] ?? 20,
      total: json['total'] ?? 0,
      unreadCount: json['unread_count'] ?? 0,
    );
  }
}

class NotificationResponse {
  final List<Notification> data;
  final NotificationMeta meta;

  NotificationResponse({
    required this.data,
    required this.meta,
  });

  factory NotificationResponse.fromJson(Map<String, dynamic> json) {
    // `{data: [...], meta}` or a paginator nested under `data` (the web reads
    // both shapes in app/[locale]/student/layout.tsx).
    final raw = json['data'];
    final List<dynamic> dataList = raw is List
        ? raw
        : (raw is Map && raw['data'] is List ? raw['data'] as List : const []);
    final data = dataList
        .whereType<Map>()
        .map((e) => Notification.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    final rawMeta = json['meta'] ?? (raw is Map ? raw : null);
    final meta = NotificationMeta.fromJson(
      rawMeta is Map ? Map<String, dynamic>.from(rawMeta) : const {},
    );
    return NotificationResponse(data: data, meta: meta);
  }
}
