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
      expect(controller.promptSecondsLeft.value, isNull);

      // The window ends: the notice comes up and the screen stays on for it.
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();
      expect(controller.promptSecondsLeft.value, 15);
      expect(wakelock.on, isTrue, reason: 'no lock while the notice is up');
      expect(stoppedCount, 0, reason: 'the video keeps playing meanwhile');

      // Nobody answers it.
      async.elapse(const Duration(seconds: 15));
      async.flushMicrotasks();
      expect(controller.promptSecondsLeft.value, isNull);
      expect(wakelock.on, isFalse, reason: 'phone may sleep once paused');
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
      async.elapse(const Duration(hours: 1));
      expect(stoppedCount, 1, reason: 'it stays paused until play is pressed');
      expect(controller.promptSecondsLeft.value, isNull);

      controller.playbackStarted(); // played again: a new period starts
      async.flushMicrotasks();
      expect(wakelock.on, isTrue);
      async.elapse(const Duration(minutes: 3, seconds: 15));
      async.flushMicrotasks();
      expect(wakelock.on, isFalse);
      expect(stoppedCount, 2);
    });
  });

  test('"still watching" hides the notice and restarts the interval', () {
    fakeAsync((async) {
      limit = const Duration(minutes: 1);
      final controller = buildController();
      final shown = <int?>[];
      controller.promptSecondsLeft.addListener(
        () => shown.add(controller.promptSecondsLeft.value),
      );

      controller.playbackStarted();
      async.elapse(const Duration(minutes: 1));
      async.elapse(const Duration(seconds: 6));
      async.flushMicrotasks();
      expect(controller.promptSecondsLeft.value, 9);
      expect(shown, [15, 14, 13, 12, 11, 10, 9], reason: 'one step a second');

      controller.stillWatching();
      async.flushMicrotasks();
      expect(controller.promptSecondsLeft.value, isNull);
      expect(wakelock.on, isTrue);
      expect(stoppedCount, 0, reason: 'no interruption');

      // A full new interval runs before the next notice.
      async.elapse(const Duration(seconds: 59));
      expect(controller.promptSecondsLeft.value, isNull);
      async.elapse(const Duration(seconds: 1));
      expect(controller.promptSecondsLeft.value, 15);
      async.elapse(const Duration(seconds: 15));
      async.flushMicrotasks();
      expect(stoppedCount, 1);
      expect(wakelock.on, isFalse);
    });
  });

  test('only the button answers the notice', () {
    fakeAsync((async) {
      limit = const Duration(minutes: 1);
      final controller = buildController();
      controller.playbackStarted();
      async.elapse(const Duration(minutes: 1, seconds: 5));
      expect(controller.promptSecondsLeft.value, 10);

      // Tapping the video or seeking while the notice is up does not count as
      // an answer, nor does the dashboard value arriving.
      controller.userActivity();
      controller.timeoutChanged();
      async.elapse(const Duration(seconds: 1));
      expect(controller.promptSecondsLeft.value, 9);

      async.elapse(const Duration(seconds: 9));
      async.flushMicrotasks();
      expect(stoppedCount, 1);

      // Pressing the button after the video stopped does nothing.
      controller.stillWatching();
      async.flushMicrotasks();
      expect(wakelock.on, isFalse);
      expect(controller.promptSecondsLeft.value, isNull);
    });
  });

  test('pausing during the notice hides it; play starts a full interval', () {
    fakeAsync((async) {
      limit = const Duration(minutes: 1);
      final controller = buildController();
      controller.playbackStarted();
      async.elapse(const Duration(minutes: 1, seconds: 3));
      expect(controller.isPrompting, isTrue);

      controller.playbackStopped(); // the student paused it themselves
      async.flushMicrotasks();
      expect(controller.promptSecondsLeft.value, isNull);
      expect(wakelock.on, isFalse);
      async.elapse(const Duration(minutes: 5));
      expect(stoppedCount, 0);

      controller.playbackStarted();
      async.elapse(const Duration(seconds: 59));
      expect(controller.promptSecondsLeft.value, isNull);
      async.elapse(const Duration(seconds: 1));
      expect(controller.promptSecondsLeft.value, 15);
    });
  });

  test('leaving the screen during the notice cancels it for good', () {
    fakeAsync((async) {
      limit = const Duration(minutes: 1);
      final controller = buildController();
      controller.playbackStarted();
      async.elapse(const Duration(minutes: 1, seconds: 2));
      controller.dispose();
      async.elapse(const Duration(minutes: 1));
      async.flushMicrotasks();
      expect(stoppedCount, 0);
      expect(wakelock.on, isFalse);
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
      expect(wakelock.on, isTrue, reason: 'the notice holds the screen');
      expect(controller.isPrompting, isTrue);

      async.elapse(const Duration(seconds: 15));
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
      expect(controller.isPrompting, isTrue);
      expect(stoppedCount, 0);

      async.elapse(const Duration(seconds: 15));
      async.flushMicrotasks();
      expect(wakelock.on, isFalse);
      expect(stoppedCount, 1);
    });
  });
}
