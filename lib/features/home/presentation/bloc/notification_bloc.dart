import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:learnoo/features/auth/data/auth_repository.dart';
import 'package:learnoo/features/home/data/notification_repository.dart';
import 'package:learnoo/features/home/data/models/notification.dart';
import 'package:learnoo/core/services/websocket_service.dart';
import 'package:learnoo/core/services/notification_service.dart';
import 'notification_event.dart';
import 'notification_state.dart';

class NotificationBloc extends Bloc<NotificationEvent, NotificationState> {
  final NotificationRepository _notificationRepository;
  final WebSocketService _webSocketService;
  final NotificationService _notificationService;
  final AuthRepository _authRepository;

  NotificationBloc({
    required NotificationRepository notificationRepository,
    required WebSocketService webSocketService,
    required NotificationService notificationService,
    required AuthRepository authRepository,
  })  : _notificationRepository = notificationRepository,
        _webSocketService = webSocketService,
        _notificationService = notificationService,
        _authRepository = authRepository,
        super(const NotificationState()) {
    on<LoadNotificationsEvent>(_onLoadNotifications);
    on<LoadMoreNotificationsEvent>(_onLoadMoreNotifications);
    on<RefreshNotificationsEvent>(_onRefreshNotifications);
    on<NotificationReceivedEvent>(_onNotificationReceived);
    on<MarkAsReadEvent>(_onMarkAsRead);
    on<MarkAllAsReadEvent>(_onMarkAllAsRead);
    on<DeleteNotificationEvent>(_onDeleteNotification);
    on<LoadUnreadCountEvent>(_onLoadUnreadCount);

    _listenToWebSocket();
  }

  void _listenToWebSocket() {
    _webSocketService.notificationStream.listen((notificationData) {
      add(NotificationReceivedEvent(notificationData));
    });
  }

  Future<void> _onLoadNotifications(
    LoadNotificationsEvent event,
    Emitter<NotificationState> emit,
  ) async {
    emit(state.copyWith(
      isLoading: true,
      errorMessage: null,
    ));

    final result = await _notificationRepository.getNotifications(page: event.page);

    if (result['success']) {
      final notifications = result['data'] as List<Notification>;
      final meta = result['meta'] as NotificationMeta;
      
      emit(state.copyWith(
        notifications: notifications,
        meta: meta,
        unreadCount: meta.unreadCount,
        isLoading: false,
      ));
      
      // Load unread count separately
      add(LoadUnreadCountEvent());
    } else {
      emit(state.copyWith(
        isLoading: false,
        errorMessage: result['message'] ?? 'Failed to load notifications',
      ));
    }
  }

  Future<void> _onLoadMoreNotifications(
    LoadMoreNotificationsEvent event,
    Emitter<NotificationState> emit,
  ) async {
    if (state.hasReachedMax || state.isLoadingMore) return;

    emit(state.copyWith(isLoadingMore: true));

    final nextPage = (state.meta?.currentPage ?? 0) + 1;
    final result = await _notificationRepository.getNotifications(page: nextPage);

    if (result['success']) {
      final newNotifications = result['data'] as List<Notification>;
      final meta = result['meta'] as NotificationMeta;
      
      emit(state.copyWith(
        notifications: [...state.notifications, ...newNotifications],
        meta: meta,
        isLoadingMore: false,
      ));
    } else {
      emit(state.copyWith(
        isLoadingMore: false,
        errorMessage: result['message'] ?? 'Failed to load more notifications',
      ));
    }
  }

  Future<void> _onRefreshNotifications(
    RefreshNotificationsEvent event,
    Emitter<NotificationState> emit,
  ) async {
    emit(state.copyWith(isRefreshing: true));

    final result = await _notificationRepository.getNotifications(page: 1);

    if (result['success']) {
      final notifications = result['data'] as List<Notification>;
      final meta = result['meta'] as NotificationMeta;
      
      emit(state.copyWith(
        notifications: notifications,
        meta: meta,
        unreadCount: meta.unreadCount,
        isRefreshing: false,
      ));
      
      add(LoadUnreadCountEvent());
    } else {
      emit(state.copyWith(
        isRefreshing: false,
        errorMessage: result['message'] ?? 'Failed to refresh notifications',
      ));
    }
  }

  Future<void> _onNotificationReceived(
    NotificationReceivedEvent event,
    Emitter<NotificationState> emit,
  ) async {
    try {
      // Parse the notification data
      final notificationData = event.notificationData['data'];
      if (notificationData != null) {
        final notification = Notification.fromJson(notificationData);
        
        // Add to the beginning of the list
        emit(state.copyWith(
          notifications: [notification, ...state.notifications],
          unreadCount: state.unreadCount + 1,
        ));

        // Show local notification
        await _notificationService.showAppNotification(
          title: notification.data.title,
          body: notification.data.message,
          payload: notification.id,
        );

        // Update unread count
        add(LoadUnreadCountEvent());
      }
    } catch (e) {
      // Ignore parsing errors
    }
  }

  Future<void> _onMarkAsRead(
    MarkAsReadEvent event,
    Emitter<NotificationState> emit,
  ) async {
    final result = await _notificationRepository.markAsRead(event.notificationId);

    if (result['success']) {
      final updatedNotifications = state.notifications.map((n) {
        if (n.id == event.notificationId) {
          return Notification(
            id: n.id,
            type: n.type,
            notifiableType: n.notifiableType,
            notifiableId: n.notifiableId,
            data: n.data,
            readAt: DateTime.now().toIso8601String(),
            createdAt: n.createdAt,
            updatedAt: n.updatedAt,
          );
        }
        return n;
      }).toList();

      final unreadCount = state.unreadCount > 0 ? state.unreadCount - 1 : 0;

      emit(state.copyWith(
        notifications: updatedNotifications,
        unreadCount: unreadCount,
      ));
    }
  }

  Future<void> _onMarkAllAsRead(
    MarkAllAsReadEvent event,
    Emitter<NotificationState> emit,
  ) async {
    final result = await _notificationRepository.markAllAsRead();

    if (result['success']) {
      final updatedNotifications = state.notifications.map((n) {
        return Notification(
          id: n.id,
          type: n.type,
          notifiableType: n.notifiableType,
          notifiableId: n.notifiableId,
          data: n.data,
          readAt: DateTime.now().toIso8601String(),
          createdAt: n.createdAt,
          updatedAt: n.updatedAt,
        );
      }).toList();

      emit(state.copyWith(
        notifications: updatedNotifications,
        unreadCount: 0,
      ));
    }
  }

  Future<void> _onDeleteNotification(
    DeleteNotificationEvent event,
    Emitter<NotificationState> emit,
  ) async {
    final result = await _notificationRepository.deleteNotification(event.notificationId);

    if (result['success']) {
      final updatedNotifications = state.notifications
          .where((n) => n.id != event.notificationId)
          .toList();

      final deletedNotification = state.notifications.firstWhere(
        (n) => n.id == event.notificationId,
        orElse: () => state.notifications.first,
      );

      final unreadCount = deletedNotification.isUnread && state.unreadCount > 0
          ? state.unreadCount - 1
          : state.unreadCount;

      emit(state.copyWith(
        notifications: updatedNotifications,
        unreadCount: unreadCount,
      ));
    }
  }

  Future<void> _onLoadUnreadCount(
    LoadUnreadCountEvent event,
    Emitter<NotificationState> emit,
  ) async {
    final result = await _notificationRepository.getUnreadCount();

    if (result['success']) {
      emit(state.copyWith(
        unreadCount: result['count'] ?? 0,
      ));
    }
  }

  @override
  Future<void> close() {
    // Don't close WebSocket here as it's a singleton
    return super.close();
  }
}
