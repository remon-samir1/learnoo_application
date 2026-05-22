import 'package:flutter/material.dart';
import 'video_view_tracker.dart';

/// Provider for managing VideoViewTracker lifecycle
class VideoViewTrackerProvider extends InheritedNotifier<VideoViewTracker> {
  const VideoViewTrackerProvider({
    super.key,
    required VideoViewTracker tracker,
    required super.child,
  }) : super(notifier: tracker);

  static VideoViewTracker? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<VideoViewTrackerProvider>()
        ?.notifier;
  }

  static VideoViewTracker of(BuildContext context) {
    final tracker = maybeOf(context);
    assert(tracker != null, 'No VideoViewTrackerProvider found in context');
    return tracker!;
  }

  @override
  bool updateShouldNotify(covariant VideoViewTrackerProvider oldWidget) {
    return notifier != oldWidget.notifier;
  }
}

/// Mixin for widgets that need video view tracking
mixin VideoViewTrackingMixin<T extends StatefulWidget> on State<T> {
  VideoViewTracker? _tracker;
  
  VideoViewTracker? get videoTracker => _tracker;
  
  void initVideoTracker({
    required String chapterId,
    required int viewByMinute,
    required Function(int watchedMinutes) onViewCounted,
  }) {
    _tracker?.dispose();
    _tracker = VideoViewTracker(
      chapterId: chapterId,
      viewByMinute: viewByMinute,
      onViewCounted: onViewCounted,
    );
  }
  
  void disposeVideoTracker() {
    _tracker?.dispose();
    _tracker = null;
  }
  
  @override
  void dispose() {
    disposeVideoTracker();
    super.dispose();
  }
}
