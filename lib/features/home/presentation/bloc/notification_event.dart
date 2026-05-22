import 'package:equatable/equatable.dart';

abstract class NotificationEvent extends Equatable {
  const NotificationEvent();

  @override
  List<Object?> get props => [];
}

class LoadNotificationsEvent extends NotificationEvent {
  final int page;

  const LoadNotificationsEvent({this.page = 1});

  @override
  List<Object?> get props => [page];
}

class LoadMoreNotificationsEvent extends NotificationEvent {}

class RefreshNotificationsEvent extends NotificationEvent {}

class NotificationReceivedEvent extends NotificationEvent {
  final Map<String, dynamic> notificationData;

  const NotificationReceivedEvent(this.notificationData);

  @override
  List<Object?> get props => [notificationData];
}

class MarkAsReadEvent extends NotificationEvent {
  final String notificationId;

  const MarkAsReadEvent(this.notificationId);

  @override
  List<Object?> get props => [notificationId];
}

class MarkAllAsReadEvent extends NotificationEvent {}

class DeleteNotificationEvent extends NotificationEvent {
  final String notificationId;

  const DeleteNotificationEvent(this.notificationId);

  @override
  List<Object?> get props => [notificationId];
}

class LoadUnreadCountEvent extends NotificationEvent {}
