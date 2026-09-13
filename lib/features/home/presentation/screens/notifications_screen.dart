import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart';
import 'package:learnoo/features/home/presentation/bloc/notification_bloc.dart';
import 'package:learnoo/features/home/presentation/bloc/notification_event.dart';
import 'package:learnoo/features/home/presentation/bloc/notification_state.dart';
import 'package:learnoo/features/home/data/models/notification.dart' as notification_model;
import 'package:learnoo/features/home/data/notification_repository.dart';
import 'package:learnoo/core/services/websocket_service.dart';
import 'package:learnoo/core/services/notification_service.dart';
import 'package:learnoo/features/auth/data/auth_repository.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final RefreshController _refreshController = RefreshController();
  final ScrollController _scrollController = ScrollController();

  late NotificationBloc _notificationBloc;

  @override
  void initState() {
    super.initState();
    _notificationBloc = NotificationBloc(
      notificationRepository: NotificationRepository(
        authRepository: AuthRepository(),
      ),
      webSocketService: WebSocketService(),
      notificationService: NotificationService(),
      authRepository: AuthRepository(),
    );
    _notificationBloc.add(LoadNotificationsEvent());
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _refreshController.dispose();
    _scrollController.dispose();
    _notificationBloc.close();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent * 0.8) {
      final state = _notificationBloc.state;
      if (!state.hasReachedMax && !state.isLoadingMore) {
        _notificationBloc.add(LoadMoreNotificationsEvent());
      }
    }
  }

  void _onRefresh() {
    _notificationBloc.add(RefreshNotificationsEvent());
    _notificationBloc.stream.listen((state) {
      if (!state.isRefreshing) {
        _refreshController.refreshCompleted();
      }
    });
  }

  String _formatTime(String dateTimeString) {
    try {
      final dateTime = DateTime.parse(dateTimeString);
      final now = DateTime.now();
      final difference = now.difference(dateTime);

      if (difference.inMinutes < 1) {
        return 'home.just_now'.tr();
      } else if (difference.inMinutes < 60) {
        return 'home.minutes_ago'.tr(args: ['${difference.inMinutes}']);
      } else if (difference.inHours < 24) {
        return 'home.hours_ago'.tr(args: ['${difference.inHours}']);
      } else if (difference.inDays < 7) {
        return 'home.days_ago'.tr(args: ['${difference.inDays}']);
      } else {
        return DateFormat('MMM d, yyyy').format(dateTime);
      }
    } catch (e) {
      return dateTimeString;
    }
  }

  FaIconData _getIconForType(String type) {
    if (type.contains('Login')) {
      return FontAwesomeIcons.userLock;
    } else if (type.contains('Lecture')) {
      return FontAwesomeIcons.bookOpen;
    } else if (type.contains('Exam') || type.contains('Quiz')) {
      return FontAwesomeIcons.calendarCheck;
    } else if (type.contains('Reply') || type.contains('Comment')) {
      return FontAwesomeIcons.commentDots;
    } else if (type.contains('Summary')) {
      return FontAwesomeIcons.fileLines;
    } else if (type.contains('Live')) {
      return FontAwesomeIcons.video;
    }
    return FontAwesomeIcons.bell;
  }

  Color _getIconBackgroundColor(String type) {
    if (type.contains('Login')) {
      return const Color(0xFFFFF0F0);
    } else if (type.contains('Lecture')) {
      return const Color(0xFFF0F5FF);
    } else if (type.contains('Exam') || type.contains('Quiz')) {
      return const Color(0xFFFFF8F0);
    } else if (type.contains('Reply') || type.contains('Comment')) {
      return const Color(0xFFF0FFF6);
    } else if (type.contains('Summary')) {
      return const Color(0xFFF0F5FF);
    } else if (type.contains('Live')) {
      return const Color(0xFFFFF0F0);
    }
    return const Color(0xFFF5F5F5);
  }

  Color _getIconColor(String type) {
    if (type.contains('Login')) {
      return const Color(0xFFFF4B4B);
    } else if (type.contains('Lecture')) {
      return const Color(0xFF5A75FF);
    } else if (type.contains('Exam') || type.contains('Quiz')) {
      return const Color(0xFFF2994A);
    } else if (type.contains('Reply') || type.contains('Comment')) {
      return const Color(0xFF27AE60);
    } else if (type.contains('Summary')) {
      return const Color(0xFF5A75FF);
    } else if (type.contains('Live')) {
      return const Color(0xFFFF4B4B);
    }
    return const Color(0xFF9CA3AF);
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => _notificationBloc,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              BlocBuilder<NotificationBloc, NotificationState>(
                builder: (context, state) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFFE5E7EB),
                                width: 1,
                              ),
                            ),
                            child: const Center(
                              child: FaIcon(
                                FontAwesomeIcons.arrowLeft,
                                color: Color(0xFF374151),
                                size: 18,
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Center(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'home.notifications_title'.tr(),
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF111827),
                                  ),
                                ),
                                if (state.unreadCount > 0) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF5A75FF),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      state.unreadCount > 99
                                          ? '99+'
                                          : '${state.unreadCount}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        if (state.unreadCount > 0)
                          GestureDetector(
                            onTap: () {
                              _notificationBloc.add(MarkAllAsReadEvent());
                            },
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: const Color(0xFFF0F5FF),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Center(
                                child: FaIcon(
                                  FontAwesomeIcons.checkDouble,
                                  color: Color(0xFF5A75FF),
                                  size: 16,
                                ),
                              ),
                            ),
                          )
                        else
                          const SizedBox(width: 40),
                      ],
                    ),
                  );
                },
              ),

              // Notifications List
              Expanded(
                child: BlocBuilder<NotificationBloc, NotificationState>(
                  builder: (context, state) {
                    if (state.isLoading && state.notifications.isEmpty) {
                      return const Center(
                        child: CircularProgressIndicator(),
                      );
                    }

                    if (state.errorMessage != null && state.notifications.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const FaIcon(
                              FontAwesomeIcons.exclamationCircle,
                              size: 48,
                              color: Color(0xFF9CA3AF),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              state.errorMessage!,
                              style: const TextStyle(
                                color: Color(0xFF6B7280),
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: () {
                                _notificationBloc.add(LoadNotificationsEvent());
                              },
                              child: Text('home.retry'.tr()),
                            ),
                          ],
                        ),
                      );
                    }

                    if (state.notifications.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const FaIcon(
                              FontAwesomeIcons.bellSlash,
                              size: 48,
                              color: Color(0xFF9CA3AF),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'home.no_notifications'.tr(),
                              style: const TextStyle(
                                color: Color(0xFF6B7280),
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    final unreadNotifications = state.notifications
                        .where((n) => n.isUnread)
                        .toList();
                    final readNotifications = state.notifications
                        .where((n) => !n.isUnread)
                        .toList();

                    return SmartRefresher(
                      controller: _refreshController,
                      onRefresh: _onRefresh,
                      enablePullDown: true,
                      enablePullUp: false,
                      child: ListView(
                        controller: _scrollController,
                        children: [
                          // New Section
                          if (unreadNotifications.isNotEmpty) ...[
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 12,
                              ),
                              color: const Color(0xFFF9FAFB),
                              child: Text(
                                'home.notifications_new'.tr(),
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF6B7280),
                                ),
                              ),
                            ),
                            ...unreadNotifications.map(
                              (notification) => _buildNotificationItem(
                                notification,
                                state,
                              ),
                            ),
                          ],

                          // Earlier Section
                          if (readNotifications.isNotEmpty) ...[
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 12,
                              ),
                              color: const Color(0xFFF9FAFB),
                              child: Text(
                                'home.notifications_earlier'.tr(),
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF6B7280),
                                ),
                              ),
                            ),
                            ...readNotifications.map(
                              (notification) => _buildNotificationItem(
                                notification,
                                state,
                              ),
                            ),
                          ],

                          // Loading indicator for pagination
                          if (state.isLoadingMore)
                            const Padding(
                              padding: EdgeInsets.all(20),
                              child: Center(
                                child: CircularProgressIndicator(),
                              ),
                            ),

                          const SizedBox(height: 20),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNotificationItem(
    notification_model.Notification notification,
    NotificationState state,
  ) {
    final icon = _getIconForType(notification.type);
    final iconBackgroundColor = _getIconBackgroundColor(notification.type);
    final iconColor = _getIconColor(notification.type);

    return Dismissible(
      key: Key(notification.id),
      direction: DismissDirection.endToStart,
      onDismissed: (direction) {
        _notificationBloc.add(DeleteNotificationEvent(notification.id));
      },
      background: Container(
        color: const Color(0xFFFF4B4B),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const FaIcon(
          FontAwesomeIcons.trash,
          color: Colors.white,
        ),
      ),
      child: GestureDetector(
        onTap: () {
          if (notification.isUnread) {
            _notificationBloc.add(MarkAsReadEvent(notification.id));
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: notification.isUnread
                ? const Color(0xFFF9FAFB)
                : Colors.white,
            border: const Border(
              bottom: BorderSide(
                color: Color(0xFFF3F4F6),
                width: 1,
              ),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon Container
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconBackgroundColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: FaIcon(
                    icon,
                    color: iconColor,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(width: 14),

              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title with unread dot
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            notification.data.title,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: notification.isUnread
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                              color: const Color(0xFF111827),
                            ),
                          ),
                        ),
                        if (notification.isUnread)
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(left: 8),
                            decoration: const BoxDecoration(
                              color: Color(0xFF5A75FF),
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),

                    // Description
                    Text(
                      notification.data.message,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        color: Color(0xFF6B7280),
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 6),

                    // Time
                    Text(
                      _formatTime(notification.data.createdAt),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: Color(0xFF9CA3AF),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
