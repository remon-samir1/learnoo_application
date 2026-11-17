import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:learnoo/core/network/api_constants.dart';
import 'package:learnoo/core/services/notification_service.dart';
import 'package:learnoo/core/services/push_service.dart';
import 'package:learnoo/core/session/session_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeMessaging implements PushMessaging {
  _FakeMessaging(this.id);

  /// What the provider hands out on register(); null = registration fails.
  String? id;
  int permissionRequests = 0;
  int registrations = 0;
  final StreamController<String> registered = StreamController<String>.broadcast();

  @override
  String get provider => 'fcm';

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return true;
  }

  @override
  Future<void> register() async {
    registrations++;
    final value = id;
    if (value == null) throw StateError('no APNs token');
    // Like FCM: the id is delivered on the stream, after register() returns.
    scheduleMicrotask(() => registered.add(value));
  }

  @override
  Stream<String> get onRegistered => registered.stream;
}

class _FakeApi implements PushTokenApi {
  bool enabled = true;
  final List<Map<String, String>> registered = [];
  final List<String> removed = [];

  @override
  Future<bool> register({
    required String token,
    required String provider,
    required String platform,
  }) async {
    registered.add({'token': token, 'provider': provider, 'platform': platform});
    return enabled;
  }

  @override
  Future<void> unregister(String token) async => removed.add(token);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({'auth_token': 'student-token'});
    // Re-read the (mocked) stored session.
    await SessionManager().setActiveToken('student-token');
  });

  group('push payload', () {
    test('a pushed row of the notifications list carries its id', () {
      final payload = PushPayload.fromData({
        'notification_id': '9b1d7c2e-0000-4000-8000-000000000001',
        'notification_type': 'platform',
        'type': 'course',
        'course_id': '7',
      })!;
      expect(payload.notificationId, '9b1d7c2e-0000-4000-8000-000000000001');
      expect(payload.type, 'course');
      expect(payload.courseId, '7');
    });

    test('anything else is not ours', () {
      expect(PushPayload.fromData({}), isNull);
      expect(PushPayload.fromData({'notification_id': '  '}), isNull);
      expect(PushPayload.fromData({'type': 'course'}), isNull);
      expect(PushPayload.fromData({'notification_id': 'x', 'type': ''})!.type, isNull);
    });
  });

  group('tapping a push', () {
    tearDown(() => NotificationService().setOpenNotificationsHandler(null));

    test('opens the notifications screen, like a tap on the app\'s own', () {
      var opened = 0;
      NotificationService().setOpenNotificationsHandler(() => opened++);
      final push = PushService.test(messaging: _FakeMessaging('t'), api: _FakeApi(), platform: 'ios');

      expect(push.openFromTap({'notification_id': 'n1', 'type': 'exam'}), isTrue);
      expect(opened, 1);
      expect(push.openFromTap({'google.c.a.e': '1'}), isFalse);
      expect(opened, 1);
    });

    test('a tap that launched the app opens the screen once home is shown', () {
      var opened = 0;
      final push = PushService.test(messaging: _FakeMessaging('t'), api: _FakeApi(), platform: 'ios');
      push.openFromTap({'notification_id': 'n1'});
      expect(opened, 0);

      NotificationService().setOpenNotificationsHandler(() => opened++);
      NotificationService().openPendingNotificationsScreen();
      NotificationService().openPendingNotificationsScreen();
      expect(opened, 1);
    });
  });

  group('token registration', () {
    late _FakeMessaging messaging;
    late _FakeApi api;
    late PushService push;

    setUp(() {
      messaging = _FakeMessaging('fid-1');
      api = _FakeApi();
      push = PushService.test(messaging: messaging, api: api, platform: 'android');
      push.ensureChannel = () async {};
    });

    test('signed in: asks permission, registers the push id, follows changes', () async {
      await push.start();
      await pumpEventQueue();
      expect(messaging.permissionRequests, 1);
      expect(messaging.registrations, 1);
      expect(api.registered, [
        {'token': 'fid-1', 'provider': 'fcm', 'platform': 'android'},
      ]);
      expect(await push.deliveryActive(), isTrue);

      // The provider issues a new id later.
      messaging.registered.add('fid-2');
      await pumpEventQueue();
      expect(api.registered.last['token'], 'fid-2');

      // Calling start again (home shown again) does not double-listen.
      await push.start();
      messaging.registered.add('fid-3');
      await pumpEventQueue();
      expect(api.registered.where((r) => r['token'] == 'fid-3'), hasLength(1));
    });

    test('the server not pushing yet keeps the app showing notifications itself', () async {
      api.enabled = false;
      await push.start();
      await pumpEventQueue();
      expect(api.registered, hasLength(1));
      expect(await push.deliveryActive(), isFalse);
    });

    test('nothing is registered when the provider fails or without a session', () async {
      messaging.id = null;
      await push.start();
      await pumpEventQueue();
      expect(api.registered, isEmpty);

      messaging.id = 'fid-1';
      await SessionManager().clear();
      await push.start();
      await pumpEventQueue();
      expect(api.registered, isEmpty);
      expect(await push.deliveryActive(), isFalse);
    });

    test('signing out removes the push id from the server and turns delivery off', () async {
      await push.start();
      await pumpEventQueue();
      await push.unregister();
      expect(api.removed, ['fid-1']);
      expect(await push.deliveryActive(), isFalse);

      // Nothing left to remove.
      await push.unregister();
      expect(api.removed, ['fid-1']);
    });

    test('a session dropped by the server turns delivery off', () async {
      await push.start();
      await pumpEventQueue();
      expect(await push.deliveryActive(), isTrue);
      await SessionManager().clear();
      await pumpEventQueue();
      expect(await push.deliveryActive(), isFalse);
    });
  });

  group('push token API', () {
    test('registers with the token, provider and platform and reads push_enabled', () async {
      late http.Request sent;
      final enabled = await http.runWithClient(
        () => const ApiPushTokenApi().register(token: 'fcm-token', provider: 'fcm', platform: 'ios'),
        () => MockClient((request) async {
          sent = request;
          return http.Response(jsonEncode({'data': {'push_enabled': true}}), 200);
        }),
      );
      expect(enabled, isTrue);
      expect(sent.method, 'POST');
      expect(sent.url.toString(), '${ApiConstants.baseUrl}/v1/push-tokens');
      expect(sent.headers['Authorization'], 'Bearer student-token');
      expect(sent.headers['X-Device-ID'], isNotEmpty);
      expect(jsonDecode(sent.body), {'token': 'fcm-token', 'provider': 'fcm', 'platform': 'ios'});
    });

    test('push_enabled false or missing means the server is not pushing', () async {
      for (final body in [
        {'data': {'push_enabled': false}},
        {'data': <String, dynamic>{}},
      ]) {
        final enabled = await http.runWithClient(
          () => const ApiPushTokenApi().register(token: 't', provider: 'fcm', platform: 'android'),
          () => MockClient((_) async => http.Response(jsonEncode(body), 200)),
        );
        expect(enabled, isFalse);
      }
    });

    test('removes the token with DELETE', () async {
      late http.Request sent;
      await http.runWithClient(
        () => const ApiPushTokenApi().unregister('fcm-token'),
        () => MockClient((request) async {
          sent = request;
          return http.Response('', 204);
        }),
      );
      expect(sent.method, 'DELETE');
      expect(sent.url.path, '/v1/push-tokens');
      expect(jsonDecode(sent.body), {'token': 'fcm-token'});
    });
  });
}
