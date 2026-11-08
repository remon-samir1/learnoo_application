import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learnoo/features/course_content/presentation/screens/lecture_detail_screen.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

class _FakeWakelock extends WakelockPlusPlatformInterface {
  bool on = false;

  @override
  Future<void> toggle({required bool enable}) async => on = enable;

  @override
  Future<bool> get enabled async => on;
}

void main() {
  late _FakeWakelock wakelock;

  setUp(() {
    wakelock = _FakeWakelock();
    wakelockPlusPlatformInstance = wakelock;
  });

  test('screen stays on only for the admin sleep interval while playing', () {
    fakeAsync((async) {
      final handler = VideoControllerHandler()
        ..screenAwakeLimit = const Duration(minutes: 3);

      handler.keepScreenAwake(true); // play
      async.flushMicrotasks();
      expect(wakelock.on, isTrue);

      async.elapse(const Duration(minutes: 2, seconds: 59));
      handler.keepScreenAwake(true); // progress events keep arriving
      async.flushMicrotasks();
      expect(wakelock.on, isTrue);

      async.elapse(const Duration(seconds: 1));
      expect(wakelock.on, isFalse, reason: 'phone may sleep after 3 minutes');

      handler.keepScreenAwake(true); // later progress must not re-hold it
      async.flushMicrotasks();
      expect(wakelock.on, isFalse);

      handler.keepScreenAwake(false); // paused (e.g. phone locked)
      handler.keepScreenAwake(true); // played again: a new period starts
      async.flushMicrotasks();
      expect(wakelock.on, isTrue);
      async.elapse(const Duration(minutes: 3));
      expect(wakelock.on, isFalse);
    });
  });

  test('without the setting the screen stays on for the whole video', () {
    fakeAsync((async) {
      final handler = VideoControllerHandler();
      handler.keepScreenAwake(true);
      async.elapse(const Duration(hours: 2));
      expect(wakelock.on, isTrue);
      handler.keepScreenAwake(false);
      async.flushMicrotasks();
      expect(wakelock.on, isFalse);
    });
  });
}
