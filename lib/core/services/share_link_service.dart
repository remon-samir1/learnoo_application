import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/widgets.dart';

/// What a shared link points at.
@immutable
sealed class ShareLinkTarget {
  const ShareLinkTarget(this.id);

  final String id;

  /// Reads the exam / live session links teachers copy from the dashboard:
  /// `https://learnoo.app/{locale}/student/exams/start-exam/{id}` and
  /// `https://learnoo.app/{locale}/student/live-sessions/{id}` (the website's
  /// student pages, `share-links.ts` in the dashboard). Anything else is not
  /// ours and returns `null`.
  static ShareLinkTarget? parse(Uri uri) {
    if (uri.scheme != 'https' && uri.scheme != 'http') return null;
    if (uri.host != 'learnoo.app' && uri.host != 'www.learnoo.app') return null;
    final s = uri.pathSegments.where((p) => p.isNotEmpty).toList();
    if (s.length < 4 || (s[0] != 'ar' && s[0] != 'en') || s[1] != 'student') {
      return null;
    }
    bool isId(String v) => RegExp(r'^\d+$').hasMatch(v);
    if (s.length == 5 &&
        s[2] == 'exams' &&
        s[3] == 'start-exam' &&
        isId(s[4])) {
      return ExamLinkTarget(s[4]);
    }
    if (s.length == 4 && s[2] == 'live-sessions' && isId(s[3])) {
      return LiveSessionLinkTarget(s[3]);
    }
    return null;
  }
}

final class ExamLinkTarget extends ShareLinkTarget {
  const ExamLinkTarget(super.id);

  @override
  bool operator ==(Object other) => other is ExamLinkTarget && other.id == id;
  @override
  int get hashCode => Object.hash('exam', id);
}

final class LiveSessionLinkTarget extends ShareLinkTarget {
  const LiveSessionLinkTarget(super.id);

  @override
  bool operator ==(Object other) =>
      other is LiveSessionLinkTarget && other.id == id;
  @override
  int get hashCode => Object.hash('live', id);
}

/// Opens an exam or live session link in the app.
///
/// The link can arrive at any moment: it may start the app (cold start), come
/// in while the app runs, or reach a student who is signed out. It is kept
/// until the student's home screen ([MainScreen]) is up — after the splash
/// screen, sign-in or onboarding — and then opened on top of it, exactly like
/// a tap on that exam or session inside the app.
class ShareLinkService {
  ShareLinkService._internal();
  static ShareLinkService _instance = ShareLinkService._internal();
  factory ShareLinkService() => _instance;

  @visibleForTesting
  ShareLinkService.test({required this.open});

  @visibleForTesting
  static set instance(ShareLinkService service) => _instance = service;

  /// Shows [target] above the home screen whose context is given. Set by the
  /// app (`main.dart`); tests supply their own.
  late Future<void> Function(BuildContext context, ShareLinkTarget target) open;

  StreamSubscription<Uri>? _subscription;
  ShareLinkTarget? _pending;
  BuildContext? _home;

  @visibleForTesting
  ShareLinkTarget? get pending => _pending;

  /// Called once from `main()`: listens for links, including the one that
  /// started the app.
  void start() {
    _subscription ??= AppLinks().uriLinkStream.listen(
      receive,
      onError: (Object e) => debugPrint('[ShareLink] ${e.runtimeType}'),
    );
  }

  /// A link reached the app.
  @visibleForTesting
  void receive(Uri uri) {
    final target = ShareLinkTarget.parse(uri);
    if (target == null) return;
    _pending = target;
    _openPending();
  }

  /// The student's home screen is showing: open a waiting link now, and any
  /// later one straight away.
  void attachHome(BuildContext context) {
    _home = context;
    _openPending();
  }

  /// The home screen left (signed out, or replaced by a new one).
  void detachHome(BuildContext context) {
    if (identical(_home, context)) _home = null;
  }

  void _openPending() {
    final home = _home;
    final target = _pending;
    if (home == null || target == null || !home.mounted) return;
    _pending = null;
    unawaited(open(home, target));
  }
}
