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
      title: json['title'] ?? '',
      message: json['message'] ?? '',
      type: json['type'] ?? '',
      device: json['device'] ?? '',
      ipAddress: json['ip_address'] ?? '',
      createdAt: json['created_at'] ?? '',
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
      id: json['id'] ?? '',
      type: json['type'] ?? '',
      notifiableType: json['notifiable_type'] ?? '',
      notifiableId: json['notifiable_id'] ?? '',
      data: NotificationData.fromJson(json['data'] ?? {}),
      readAt: json['read_at'],
      createdAt: json['created_at'] ?? '',
      updatedAt: json['updated_at'] ?? '',
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
    final List<dynamic> dataList = json['data'] ?? [];
    final data = dataList.map((e) => Notification.fromJson(e)).toList();
    final meta = NotificationMeta.fromJson(json['meta'] ?? {});
    return NotificationResponse(data: data, meta: meta);
  }
}
