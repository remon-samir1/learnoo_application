import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learnoo/core/video/screen_awake_controller.dart';
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
  late Duration? limit;
  late int stoppedCount;

  /// The same wiring the lecture screen uses: a real [Timer] for the countdown
  /// and the platform wakelock behind [ScreenAwakeController], so this exercises
  /// the clock and the plugin call rather than a stubbed scheduler.
  ScreenAwakeController buildController() => ScreenAwakeController(
    setAwake: (value) => WakelockPlus.toggle(enable: value),
    timeout: () => limit,
    onExpired: () => stoppedCount++,
  );

  setUp(() {
    wakelock = _FakeWakelock();
    wakelockPlusPlatformInstance = wakelock;
    limit = null;
    stoppedCount = 0;
  });

  test('screen stays on only for the admin sleep interval while playing', () {
    fakeAsync((async) {
      limit = const Duration(minutes: 3);
      final controller = buildController();

      controller.playbackStarted(); // play
      async.flushMicrotasks();
      expect(wakelock.on, isTrue);

      async.elapse(const Duration(minutes: 2, seconds: 59));
      async.flushMicrotasks();
      expect(wakelock.on, isTrue);

      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();
      expect(wakelock.on, isFalse, reason: 'phone may sleep after 3 minutes');
      expect(
        stoppedCount,
        1,
        reason: 'the lecture is stopped with the screen, as the client asked',
      );

      // The window has elapsed and playback was stopped with it, so the
      // controls coming up must not light the screen back on by itself.
      controller.userActivity();
      async.flushMicrotasks();
      expect(wakelock.on, isFalse);

      controller.playbackStarted(); // played again: a new period starts
      async.flushMicrotasks();
      expect(wakelock.on, isTrue);
      async.elapse(const Duration(minutes: 3));
      async.flushMicrotasks();
      expect(wakelock.on, isFalse);
      expect(stoppedCount, 2);
    });
  });

  test('pausing starts a new period on the next play', () {
    fakeAsync((async) {
      limit = const Duration(minutes: 3);
      final controller = buildController();

      controller.playbackStarted();
      async.elapse(const Duration(minutes: 2));
      controller.playbackStopped(); // paused (e.g. the phone locked)
      async.flushMicrotasks();
      expect(wakelock.on, isFalse);

      controller.playbackStarted();
      async.elapse(const Duration(minutes: 2, seconds: 30));
      async.flushMicrotasks();
      expect(
        wakelock.on,
        isTrue,
        reason: 'the window restarted, it did not carry the earlier 2 minutes',
      );

      async.elapse(const Duration(seconds: 30));
      async.flushMicrotasks();
      expect(wakelock.on, isFalse);
    });
  });

  test('without the setting the screen stays on for the whole video', () {
    fakeAsync((async) {
      final controller = buildController();
      controller.playbackStarted();
      async.elapse(const Duration(hours: 2));
      async.flushMicrotasks();
      expect(wakelock.on, isTrue);
      expect(stoppedCount, 0);
      controller.playbackStopped();
      async.flushMicrotasks();
      expect(wakelock.on, isFalse);
    });
  });

  test('a value arriving after playback began still applies', () {
    fakeAsync((async) {
      final controller = buildController();
      controller.playbackStarted();
      async.elapse(const Duration(minutes: 1));

      limit = const Duration(minutes: 3);
      controller.timeoutChanged();
      async.elapse(const Duration(minutes: 2, seconds: 59));
      async.flushMicrotasks();
      expect(wakelock.on, isTrue);

      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();
      expect(wakelock.on, isFalse);
      expect(stoppedCount, 1);
    });
  });
}
