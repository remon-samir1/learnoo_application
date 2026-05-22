import 'package:equatable/equatable.dart';
import 'package:learnoo/features/home/data/models/notification.dart';

class NotificationState extends Equatable {
  final List<Notification> notifications;
  final NotificationMeta? meta;
  final int unreadCount;
  final bool isLoading;
  final bool isLoadingMore;
  final bool isRefreshing;
  final String? errorMessage;

  const NotificationState({
    this.notifications = const [],
    this.meta,
    this.unreadCount = 0,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.isRefreshing = false,
    this.errorMessage,
  });

  NotificationState copyWith({
    List<Notification>? notifications,
    NotificationMeta? meta,
    int? unreadCount,
    bool? isLoading,
    bool? isLoadingMore,
    bool? isRefreshing,
    String? errorMessage,
  }) {
    return NotificationState(
      notifications: notifications ?? this.notifications,
      meta: meta ?? this.meta,
      unreadCount: unreadCount ?? this.unreadCount,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      errorMessage: errorMessage,
    );
  }

  bool get hasReachedMax =>
      meta != null && meta!.currentPage >= meta!.lastPage;

  @override
  List<Object?> get props => [
        notifications,
        meta,
        unreadCount,
        isLoading,
        isLoadingMore,
        isRefreshing,
        errorMessage,
      ];
}
