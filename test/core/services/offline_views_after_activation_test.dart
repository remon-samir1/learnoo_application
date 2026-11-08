import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:learnoo/core/local/hive_boxes.dart';
import 'package:learnoo/core/local/hive_service.dart';
import 'package:learnoo/core/local/models/pending_action.dart';
import 'package:learnoo/core/services/offline_view_service.dart';
import 'package:learnoo/core/sync/offline_queue_service.dart';
import 'package:learnoo/features/course_content/data/chapter_repository.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TempPaths extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _TempPaths(this.path);
  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('learnoo_hive_test');
    PathProviderPlatform.instance = _TempPaths(dir.path);
    await HiveService().initialize();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Hive.box<dynamic>(HiveBoxes.chapters).clear();
    await Hive.box<dynamic>(HiveBoxes.pendingActions).clear();
  });

  test('a successful code drops this device\'s spent views for the chapter',
      () async {
    final views = OfflineViewService();
    await views.incrementOfflineView('809');
    await views.incrementOfflineView('809');
    await views.incrementOfflineView('840');
    expect(views.getOfflineViewsSync('809'), 2);

    await views.discardViewsAfterActivation('809');

    expect(views.getOfflineViewsSync('809'), 0);
    final queued = OfflineQueueService()
        .getPendingActionsByType(PendingActionTypes.chapterView)
        .map((a) => '${a.payload['chapter_id']}')
        .toList();
    expect(queued, ['840'], reason: 'other chapters keep their queued views');
  });

  test('a downloaded lecture uses the chapter\'s view_by_minute', () async {
    final repository = ChapterRepository();
    expect(repository.cachedViewByMinute('809'), isNull);

    await HiveService().storeWithTimestamp(HiveBoxes.chapters, 'chapter_809', {
      'id': 809,
      'attributes': {'view_by_minute': 35},
    });

    expect(repository.cachedViewByMinute('809'), 35);
  });
}
