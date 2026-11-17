import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learnoo/core/services/notification_service.dart';
import 'package:learnoo/core/services/push_service.dart';
import 'package:learnoo/core/session/session_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Never used: on a Huawei-only phone [PushService.initialize] replaces it
/// with the Huawei Push Kit messaging.
class _UnusedMessaging implements PushMessaging {
  @override
  String get provider => 'fcm';
  @override
  Future<bool> requestPermission() async => throw StateError('unused');
  @override
  Future<void> register() async => throw StateError('unused');
  @override
  Stream<String> get onRegistered => const Stream.empty();
}

class _FakeApi implements PushTokenApi {
  final List<Map<String, String>> registered = [];

  @override
  Future<bool> register({
    required String token,
    required String provider,
    required String platform,
  }) async {
    registered.add({'token': token, 'provider': provider, 'platform': platform});
    return true;
  }

  @override
  Future<void> unregister(String token) async {}
}

const _method = MethodChannel('com.huawei.flutter.push/method');
const _token = EventChannel('com.huawei.flutter.push/token');
const _received = EventChannel('com.huawei.flutter.push/remote_message_receive');
const _opened = EventChannel('com.huawei.flutter.push/notification_open');

/// What the huawei_push plugin reports for a tapped push (NotificationIntentListener):
/// the push's data as intent extras, and as `remoteMessage.dataOfMap`.
Map<String, dynamic> _tap(String id) => {
  'uriPage': null,
  'extras': {'notification_id': id, 'type': 'exam'},
  'remoteMessage': {'dataOfMap': jsonEncode({'notification_id': id, 'type': 'exam'})},
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<String> calls;
  Object? initialNotification;
  final sinks = <String, MockStreamHandlerEventSink>{};

  void stream(EventChannel channel) {
    messenger.setMockStreamHandler(
      channel,
      MockStreamHandler.inline(onListen: (_, sink) => sinks[channel.name] = sink),
    );
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({'auth_token': 'student-token'});
    await SessionManager().setActiveToken('student-token');
    calls = [];
    initialNotification = null;
    sinks.clear();
    messenger.setMockMethodCallHandler(_method, (call) async {
      calls.add(call.method);
      if (call.method == 'getInitialNotification') return initialNotification;
      if (call.method == 'getToken') {
        // Like the plugin: the token arrives on the token stream.
        scheduleMicrotask(() => sinks[_token.name]?.success('hms-token-1'));
      }
      return null;
    });
    stream(_token);
    stream(_received);
    stream(_opened);
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(_method, null);
    for (final channel in [_token, _received, _opened]) {
      messenger.setMockStreamHandler(channel, null);
    }
    NotificationService().setOpenNotificationsHandler(null);
  });

  PushService huaweiPhone(_FakeApi api) {
    final push = PushService.test(
      messaging: _UnusedMessaging(),
      api: api,
      platform: 'android',
    );
    push.providerLookup = () async => 'hms';
    push.ensureChannel = () async {};
    return push;
  }

  group('tap data from Huawei Push', () {
    test('reads the push data from the intent extras', () {
      final data = huaweiTapData({'extras': {'notification_id': 'n1', 'type': 'exam'}});
      expect(PushPayload.fromData(data)!.notificationId, 'n1');
    });

    test('falls back to remoteMessage.dataOfMap', () {
      final data = huaweiTapData({
        'extras': {'some_other_extra': 'x'},
        'remoteMessage': {'dataOfMap': '{"notification_id":"n2","course_id":"7"}'},
      });
      expect(PushPayload.fromData(data)!.notificationId, 'n2');
      expect(PushPayload.fromData(data)!.courseId, '7');
    });

    test('anything else is not ours', () {
      expect(huaweiTapData(null), isEmpty);
      expect(huaweiTapData('x'), isEmpty);
      expect(PushPayload.fromData(huaweiTapData({'remoteMessage': {'dataOfMap': 'not json'}})), isNull);
    });
  });

  group('a phone with Huawei Mobile Services only', () {
    test('registers its Huawei Push token with provider hms', () async {
      final api = _FakeApi();
      final push = huaweiPhone(api);
      await push.initialize();
      expect(push.available, isTrue);
      // The plugin's own usage statistics to Huawei are switched off.
      expect(calls, contains('disableLogger'));

      await push.start();
      await pumpEventQueue();
      expect(calls, contains('getToken'));
      expect(api.registered, [
        {'token': 'hms-token-1', 'provider': 'hms', 'platform': 'android'},
      ]);
      expect(await push.deliveryActive(), isTrue);

      // Push Kit issues a new token later.
      sinks[_token.name]!.success('hms-token-2');
      await pumpEventQueue();
      expect(api.registered.last['token'], 'hms-token-2');
    });

    test('a failed token request is logged, not thrown, and registers nothing', () async {
      final api = _FakeApi();
      final push = huaweiPhone(api);
      await push.initialize();
      messenger.setMockMethodCallHandler(_method, (call) async {
        if (call.method == 'getToken') {
          scheduleMicrotask(() => sinks[_token.name]?.error(code: '907135000', message: 'fingerprint'));
        }
        return null;
      });
      await push.start();
      await pumpEventQueue();
      expect(api.registered, isEmpty);
    });

    test('a tap that launched the app opens the notifications screen once', () async {
      var opened = 0;
      NotificationService().setOpenNotificationsHandler(() => opened++);
      initialNotification = _tap('n1');
      final push = huaweiPhone(_FakeApi());
      await push.initialize();
      // The plugin can also report the same launching tap as an open event.
      sinks[_opened.name]!.success(jsonEncode(_tap('n1')));
      await pumpEventQueue();
      expect(opened, 1);

      // A tap on another push while the app runs in the background.
      sinks[_opened.name]!.success(jsonEncode(_tap('n2')));
      await pumpEventQueue();
      expect(opened, 2);
    });

    test('a push while the app is open makes the app fetch and show it', () async {
      var fetched = 0;
      final push = huaweiPhone(_FakeApi());
      push.onForegroundMessage = () => fetched++;
      await push.initialize();

      sinks[_received.name]!.success(jsonEncode({
        'dataOfMap': jsonEncode({'notification_id': 'n3'}),
      }));
      await pumpEventQueue();
      expect(fetched, 1);

      // Not one of the student's notifications.
      sinks[_received.name]!.success(jsonEncode({'dataOfMap': '{}'}));
      await pumpEventQueue();
      expect(fetched, 1);
    });
  });
}
