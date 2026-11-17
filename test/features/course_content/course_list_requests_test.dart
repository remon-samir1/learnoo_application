import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:learnoo/core/local/hive_service.dart';
import 'package:learnoo/core/services/student_scope.dart';
import 'package:learnoo/features/course_content/data/course_repository.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TempPaths extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _TempPaths(this.path);
  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

Map<String, dynamic> _course(int id, {String? thumbnail, bool locked = false}) => {
      'id': '$id',
      'type': 'courses',
      'attributes': {
        'title': 'Course $id',
        'status': 1,
        'is_locked': locked,
        'thumbnail': thumbnail,
      },
    };

/// A server that answers the course list calls after a short delay and
/// remembers how many of them were waiting at the same time.
class _CourseServer {
  _CourseServer({this.activatedStatus = 200});

  final int activatedStatus;
  final List<String> calls = [];
  int _waiting = 0;
  int mostAtOnce = 0;

  late final MockClient client = MockClient((request) async {
    final query = request.url.queryParameters;
    calls.add(request.url.query);
    _waiting++;
    if (_waiting > mostAtOnce) mostAtOnce = _waiting;
    await Future<void>.delayed(const Duration(milliseconds: 30));
    _waiting--;

    if (query['activated'] == '1') {
      if (activatedStatus != 200) {
        return http.Response(jsonEncode({'message': 'oops'}), activatedStatus);
      }
      return http.Response(jsonEncode({'data': [_course(1), _course(2)]}), 200);
    }
    return http.Response(
      jsonEncode({
        'data': [
          _course(1, thumbnail: 'https://cdn/1.jpg'),
          _course(2, thumbnail: 'https://cdn/2.jpg'),
          _course(3, locked: true),
        ],
      }),
      200,
    );
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('learnoo_course_lists_test');
    PathProviderPlatform.instance = _TempPaths(dir.path);
    await HiveService().initialize();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async => call.method == 'check' ? <String>['wifi'] : null,
    );
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({
      'auth_token': 'token',
      'learnoo_device_id': '0123456789abcdef0123',
    });
    StudentScopeService().invalidate();
  });

  group('student scope', () {
    test('asks for the catalogue and the activated courses at the same time',
        () async {
      final server = _CourseServer();
      final scope = await http.runWithClient(
        () => StudentScopeService().load(forceRefresh: true),
        () => server.client,
      );

      expect(server.calls, hasLength(2));
      expect(server.mostAtOnce, 2);
      expect(scope.visibleCourseIds, {'1', '2', '3'});
      expect(scope.enrolledCourseIds, {'1', '2'});
    });

    test('a failed activated call still falls back to the catalogue lock flags',
        () async {
      final server = _CourseServer(activatedStatus: 500);
      final scope = await http.runWithClient(
        () => StudentScopeService().load(forceRefresh: true),
        () => server.client,
      );

      expect(scope.visibleCourseIds, {'1', '2', '3'});
      expect(scope.enrolledCourseIds, {'1', '2'});
    });
  });

  group('my courses', () {
    test('asks for the activated courses and the catalogue at the same time',
        () async {
      final server = _CourseServer();
      final result = await http.runWithClient(
        () => CourseRepository().getActivatedCourses(),
        () => server.client,
      );

      expect(server.calls, hasLength(2));
      expect(server.mostAtOnce, 2);
      expect(result['success'], isTrue);
      final rows = (result['data'] as List).cast<Map>();
      expect(rows.map((r) => r['id']), ['1', '2']);
      // The catalogue still supplies the cover the activated rows lack.
      expect(rows.map((r) => r['attributes']['thumbnail']),
          ['https://cdn/1.jpg', 'https://cdn/2.jpg']);
    });
  });
}
