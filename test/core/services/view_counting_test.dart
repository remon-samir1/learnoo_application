import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:learnoo/core/local/hive_boxes.dart';
import 'package:learnoo/core/local/hive_service.dart';
import 'package:learnoo/core/local/models/pending_action.dart';
import 'package:learnoo/core/services/offline_view_service.dart';
import 'package:learnoo/core/sync/offline_queue_service.dart';
import 'package:learnoo/core/sync/sync_processors.dart';
import 'package:learnoo/features/course_content/data/chapter_repository.dart';
import 'package:learnoo/features/course_content/domain/chapter_access.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TempPaths extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _TempPaths(this.path);
  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

List<PendingAction> _queuedViews() =>
    OfflineQueueService().getPendingActionsByType(PendingActionTypes.chapterView);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('learnoo_view_count_test');
    PathProviderPlatform.instance = _TempPaths(dir.path);
    await HiveService().initialize();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({'auth_token': 'token'});
    await Hive.box<dynamic>(HiveBoxes.chapters).clear();
    await Hive.box<dynamic>(HiveBoxes.pendingActions).clear();
  });

  group('one opening, one view', () {
    test('each opening gets its own key', () {
      final keys = {for (var i = 0; i < 50; i++) OfflineViewService.newViewKey()};
      expect(keys, hasLength(50));
      expect(keys.first, matches(RegExp(r'^[0-9a-f]{32}$')));
    });

    test('an opening already waiting in the queue is not queued again', () async {
      final views = OfflineViewService();
      await views.incrementOfflineView('809', viewKey: 'opening-1', courseId: '12');
      await views.incrementOfflineView('809', viewKey: 'opening-1', courseId: '12');

      expect(views.getOfflineViewsSync('809'), 1);
      expect(_queuedViews().single.payload,
          {'chapter_id': 809, 'view_key': 'opening-1', 'course_id': '12'});

      await views.incrementOfflineView('809', viewKey: 'opening-2');
      expect(views.getOfflineViewsSync('809'), 2);
    });
  });

  group('the server decides access', () {
    test('a spent last view the server still lets play is not locked here', () {
      expect(lockedByQueuedViews(serverViews: 3, queuedViews: 0, maxViews: 3), isFalse);
    });

    test('views the server has not received yet still count on this device', () {
      expect(lockedByQueuedViews(serverViews: 2, queuedViews: 1, maxViews: 3), isTrue);
      expect(lockedByQueuedViews(serverViews: 1, queuedViews: 1, maxViews: 3), isFalse);
    });

    test('no limit never locks', () {
      expect(lockedByQueuedViews(serverViews: 9, queuedViews: 9, maxViews: 0), isFalse);
    });
  });

  group('recording a view', () {
    Future<Map<String, dynamic>> record(http.Client client) => http.runWithClient(
          () => ChapterRepository().incrementViewCount(chapterId: 809, viewKey: 'opening-1'),
          () => client,
        );

    test('sends the opening key and reads the server count', () async {
      late http.Request sent;
      final result = await record(MockClient((request) async {
        sent = request;
        return http.Response(
          jsonEncode({
            'data': {'attributes': {'current_user_views': 2}},
          }),
          200,
        );
      }));

      expect(sent.url.path, '/v1/chapter/809/view');
      expect(jsonDecode(sent.body), {'view_key': 'opening-1'});
      expect(result['success'], isTrue);
      expect(result['current_views'], 2);
    });

    test('a refusal from the server is final and not queued', () async {
      final result = await record(MockClient((_) async => http.Response(
            jsonEncode({'message': 'limit', 'watch_access_state': 'view_limit_reached'}),
            403,
          )));

      expect(result['success'], isFalse);
      expect(result['retryable'], isFalse);
      expect(result['watch_access_state'], 'view_limit_reached');
    });

    test('a server failure or no answer may be re-sent', () async {
      final failed = await record(MockClient((_) async => http.Response('oops', 500)));
      expect(failed['retryable'], isTrue);

      final lost = await record(
          MockClient((_) async => throw const SocketException('connection reset')));
      expect(lost['success'], isFalse);
      expect(lost['retryable'], isTrue);
    });
  });

  group('the offline queue', () {
    test('re-sends the opening key', () async {
      late http.Request sent;
      final done = await http.runWithClient(
        () => SyncProcessors.processChapterView(PendingAction(
          id: 'a',
          type: PendingActionTypes.chapterView,
          payload: {'chapter_id': 809, 'view_key': 'opening-1'},
          createdAt: 0,
        )),
        () => MockClient((request) async {
          sent = request;
          return http.Response('{}', 200);
        }),
      );

      expect(done, isTrue);
      expect(jsonDecode(sent.body), {'view_key': 'opening-1'});
    });

    test('drops a view the server refused instead of retrying it', () {
      expect(SyncProcessors.isFinalViewResponse(200), isTrue);
      expect(SyncProcessors.isFinalViewResponse(403), isTrue);
      expect(SyncProcessors.isFinalViewResponse(404), isTrue);
      expect(SyncProcessors.isFinalViewResponse(422), isTrue);
      expect(SyncProcessors.isFinalViewResponse(401), isFalse);
      expect(SyncProcessors.isFinalViewResponse(429), isFalse);
      expect(SyncProcessors.isFinalViewResponse(500), isFalse);
    });
  });

  group('an activation code', () {
    Future<Map<String, dynamic>> activate(String type, int id) => http.runWithClient(
          () => ChapterRepository().activateCode(code: 'ZJYQAD2K', itemId: id, itemType: type),
          () => MockClient((_) async => http.Response(jsonEncode({'message': 'ok'}), 200)),
        );

    test('for the lesson drops its queued views, from any screen', () async {
      final views = OfflineViewService();
      await views.incrementOfflineView('809', viewKey: 'a');
      await views.incrementOfflineView('840', viewKey: 'b');

      expect((await activate('chapter', 809))['success'], isTrue);

      expect(views.getOfflineViewsSync('809'), 0);
      expect(views.getOfflineViewsSync('840'), 1);
    });

    test('for the course drops the queued views of its lessons', () async {
      final views = OfflineViewService();
      await views.incrementOfflineView('809', viewKey: 'a', courseId: '12');
      await views.incrementOfflineView('810', viewKey: 'b', courseId: '12');
      await views.incrementOfflineView('840', viewKey: 'c', courseId: '13');

      expect((await activate('course', 12))['success'], isTrue);

      expect(_queuedViews().map((a) => a.payload['chapter_id']), [840]);
    });

    test('that is rejected keeps the queued views', () async {
      final views = OfflineViewService();
      await views.incrementOfflineView('809', viewKey: 'a');

      final result = await http.runWithClient(
        () => ChapterRepository().activateCode(code: 'X', itemId: 809, itemType: 'chapter'),
        () => MockClient((_) async =>
            http.Response(jsonEncode({'message': 'This code has already been used.'}), 422)),
      );

      expect(result['success'], isFalse);
      expect(views.getOfflineViewsSync('809'), 1);
    });
  });
}

