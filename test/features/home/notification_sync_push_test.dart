import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:learnoo/core/session/session_manager.dart';
import 'package:learnoo/features/home/data/notification_sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _row(String id, String at) => {
  'id': id,
  'type': 'platform',
  'notifiable_type': 'App\\Models\\User',
  'notifiable_id': 'u1',
  'data': {'title': 'T $id', 'message': 'M $id'},
  'read_at': null,
  'created_at': at,
  'updated_at': at,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final sync = NotificationSyncService();
  final shown = <String>[];
  var rows = <Map<String, dynamic>>[];
  var pushed = false;

  Future<void> run(Future<void> Function() action) => http.runWithClient(
    action,
    () => MockClient((_) async => http.Response(
      jsonEncode({'data': rows, 'meta': {'current_page': 1, 'last_page': 1}}),
      200,
    )),
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({'auth_token': 'student-token'});
    await SessionManager().setActiveToken('student-token');
    shown.clear();
    pushed = false;
    rows = [_row('a', '2026-11-16T10:00:00Z')];
    sync.display = (fresh) async => shown.addAll(fresh.map((n) => n.id));
    sync.pushDeliveryActive = () async => pushed;
    // First sync of a session only records the backlog.
    await run(sync.sync);
    expect(shown, isEmpty);
  });

  test('with push on, what arrived while closed is not shown a second time', () async {
    pushed = true;
    rows = [_row('b', '2026-11-16T10:05:00Z'), ...rows];
    await run(() => sync.sync(showNew: false));
    expect(shown, isEmpty);

    // A push arriving in the foreground: shown once, by the app.
    rows = [_row('c', '2026-11-16T10:06:00Z'), ...rows];
    await run(sync.sync);
    await run(sync.sync);
    expect(shown, ['c']);
  });

  test('without push, notifications that came while closed are shown on return', () async {
    rows = [_row('b', '2026-11-16T10:05:00Z'), ...rows];
    await run(() => sync.sync(showNew: !pushed));
    expect(shown, ['b']);
  });

  test('a foreground sync requested during a quiet catch-up still shows', () async {
    pushed = true;
    var requests = 0;
    await http.runWithClient(() async {
      final quiet = sync.sync(showNew: false);
      final loud = sync.sync();
      await Future.wait([quiet, loud]);
    }, () => MockClient((_) async {
      requests++;
      // The quiet pass sees b (arrived while closed); c arrives in the
      // foreground before the follow-up fetch.
      final page = [
        if (requests > 1) _row('c', '2026-11-16T10:06:00Z'),
        _row('b', '2026-11-16T10:05:00Z'),
        ...rows,
      ];
      return http.Response(jsonEncode({'data': page, 'meta': {'current_page': 1}}), 200);
    }));
    expect(requests, 2);
    expect(shown, ['c']);
  });
}
