import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:learnoo/core/services/video_settings_service.dart';
import 'package:learnoo/core/video/screen_awake_controller.dart';

/// A scheduler that hands the pending callback back to the test instead of
/// waiting on a real clock, so the countdown can be fired on demand.
class _FakeScheduler {
  void Function()? _callback;
  Duration? scheduledFor;
  int scheduleCount = 0;
  int cancelCount = 0;

  bool get hasPending => _callback != null;

  Timer schedule(Duration duration, void Function() callback) {
    scheduledFor = duration;
    _callback = callback;
    scheduleCount++;
    return _FakeTimer(this);
  }

  /// Run the pending callback as if the duration had elapsed.
  void fire() {
    final callback = _callback;
    expect(callback, isNotNull, reason: 'no countdown was scheduled');
    _callback = null;
    callback!();
  }

  void _cancel() {
    if (_callback != null) cancelCount++;
    _callback = null;
  }
}

class _FakeTimer implements Timer {
  _FakeTimer(this._owner);

  final _FakeScheduler _owner;
  bool _active = true;

  @override
  void cancel() {
    if (!_active) return;
    _active = false;
    _owner._cancel();
  }

  @override
  bool get isActive => _active;

  @override
  int get tick => 0;
}

void main() {
  group('parseSleepPerMinute', () {
    test('reads a plain number of minutes', () {
      expect(
        VideoSettingsService.parseSleepPerMinute(5),
        const Duration(minutes: 5),
      );
      expect(
        VideoSettingsService.parseSleepPerMinute(2.5),
        const Duration(minutes: 2, seconds: 30),
      );
    });

    test('reads a numeric string, with surrounding whitespace', () {
      expect(
        VideoSettingsService.parseSleepPerMinute('5'),
        const Duration(minutes: 5),
      );
      expect(
        VideoSettingsService.parseSleepPerMinute('  10  '),
        const Duration(minutes: 10),
      );
      expect(
        VideoSettingsService.parseSleepPerMinute('7.5'),
        const Duration(minutes: 7, seconds: 30),
      );
    });

    test('rejects missing, null, empty and non-numeric values', () {
      expect(VideoSettingsService.parseSleepPerMinute(null), isNull);
      expect(VideoSettingsService.parseSleepPerMinute(''), isNull);
      expect(VideoSettingsService.parseSleepPerMinute('   '), isNull);
      expect(VideoSettingsService.parseSleepPerMinute('abc'), isNull);
      expect(VideoSettingsService.parseSleepPerMinute(true), isNull);
      expect(VideoSettingsService.parseSleepPerMinute(<String, int>{}), isNull);
      expect(VideoSettingsService.parseSleepPerMinute(double.nan), isNull);
      expect(VideoSettingsService.parseSleepPerMinute(double.infinity), isNull);
      expect(
        VideoSettingsService.parseSleepPerMinute(double.negativeInfinity),
        isNull,
      );
    });

    test('rejects zero and negative values', () {
      expect(VideoSettingsService.parseSleepPerMinute(0), isNull);
      expect(VideoSettingsService.parseSleepPerMinute('0'), isNull);
      expect(VideoSettingsService.parseSleepPerMinute(-5), isNull);
      expect(VideoSettingsService.parseSleepPerMinute('-5'), isNull);
    });

    test('clamps an absurdly large value', () {
      expect(
        VideoSettingsService.parseSleepPerMinute(100000),
        VideoSettingsService.maxScreenAwakeTimeout,
      );
      expect(
        VideoSettingsService.parseSleepPerMinute('999999999999'),
        VideoSettingsService.maxScreenAwakeTimeout,
      );
    });

    test('clamps a value too small to be useful', () {
      expect(
        VideoSettingsService.parseSleepPerMinute(0.001),
        VideoSettingsService.minScreenAwakeTimeout,
      );
    });
  });

  group('readSleepPerMinute', () {
    test('reads the bare response the API returns today', () {
      expect(
        VideoSettingsService.readSleepPerMinute({'sleep_per_minute': 5}),
        5,
      );
    });

    test('reads it out of data / attributes envelopes', () {
      expect(
        VideoSettingsService.readSleepPerMinute({
          'data': {'sleep_per_minute': '8'},
        }),
        '8',
      );
      expect(
        VideoSettingsService.readSleepPerMinute({
          'data': {
            'data': {
              'attributes': {'sleep_per_minute': 3},
            },
          },
        }),
        3,
      );
      expect(
        VideoSettingsService.readSleepPerMinute({
          'data': [
            {'sleep_per_minute': 4},
          ],
        }),
        4,
      );
    });

    test('returns null when the key is absent', () {
      expect(VideoSettingsService.readSleepPerMinute(null), isNull);
      expect(VideoSettingsService.readSleepPerMinute({'other': 1}), isNull);
      expect(VideoSettingsService.readSleepPerMinute('nope'), isNull);
    });
  });

  group('ScreenAwakeController', () {
    late List<bool> toggles;
    late _FakeScheduler scheduler;
    late Duration? timeout;
    late int expiredCount;
    late ScreenAwakeController controller;

    setUp(() {
      toggles = <bool>[];
      scheduler = _FakeScheduler();
      timeout = const Duration(minutes: 5);
      expiredCount = 0;
      controller = ScreenAwakeController(
        setAwake: toggles.add,
        timeout: () => timeout,
        onExpired: () => expiredCount++,
        scheduler: scheduler.schedule,
      );
    });

    test('holds the screen when playback starts, and counts down', () {
      controller.playbackStarted();

      expect(toggles, [true]);
      expect(controller.isAwake, isTrue);
      expect(scheduler.scheduledFor, const Duration(minutes: 5));
    });

    test('releases the screen when the window elapses, playback continuing',
        () {
      controller.playbackStarted();
      scheduler.fire();

      expect(toggles, [true, false]);
      expect(controller.isAwake, isFalse);
      expect(controller.hasPendingTimeout, isFalse);
    });

    test('stops the lecture when the window elapses', () {
      controller.playbackStarted();
      scheduler.fire();

      expect(expiredCount, 1, reason: 'playback is paused with the screen');
      expect(controller.isAwake, isFalse);
      expect(controller.hasPendingTimeout, isFalse);
    });

    test('a value arriving mid-lecture starts the countdown', () {
      timeout = null;
      controller.playbackStarted();
      expect(scheduler.hasPending, isFalse);

      timeout = const Duration(minutes: 3);
      controller.timeoutChanged();

      expect(scheduler.scheduledFor, const Duration(minutes: 3));
      expect(controller.hasPendingTimeout, isTrue);
    });

    test('a value arriving while paused does not wake the screen', () {
      timeout = null;
      controller.playbackStarted();
      controller.playbackStopped();
      toggles.clear();

      timeout = const Duration(minutes: 3);
      controller.timeoutChanged();

      expect(toggles, isEmpty);
      expect(scheduler.hasPending, isFalse);
    });

    test('never times out when no value is known', () {
      timeout = null;
      controller.playbackStarted();

      expect(toggles, [true]);
      expect(scheduler.hasPending, isFalse);
      expect(controller.isAwake, isTrue);
    });

    test('restarts the countdown when playback resumes after a pause', () {
      controller.playbackStarted();
      controller.playbackStopped();
      expect(toggles, [true, false]);

      controller.playbackStarted();
      expect(toggles, [true, false, true]);
      expect(scheduler.scheduleCount, 2);
      expect(controller.hasPendingTimeout, isTrue);
    });

    test('restarts the countdown on a seek or on the controls appearing', () {
      controller.playbackStarted();
      controller.userActivity();

      expect(scheduler.scheduleCount, 2);
      // Already awake: no redundant platform call.
      expect(toggles, [true]);
    });

    test('after the window elapsed only pressing play takes the screen back',
        () {
      controller.playbackStarted();
      scheduler.fire();
      expect(controller.isAwake, isFalse);

      // The lecture is paused at this point, so touching the controls must not
      // light the screen back up on its own.
      controller.userActivity();
      expect(toggles, [true, false]);
      expect(controller.isAwake, isFalse);

      controller.playbackStarted();

      expect(toggles, [true, false, true]);
      expect(controller.isAwake, isTrue);
      expect(controller.hasPendingTimeout, isTrue);
    });

    test('activity while paused does not switch the screen back on', () {
      controller.playbackStarted();
      controller.playbackStopped();

      controller.userActivity();

      expect(toggles, [true, false]);
      expect(controller.isAwake, isFalse);
      expect(scheduler.hasPending, isFalse);
    });

    test('pausing cancels the countdown and releases the wakelock', () {
      controller.playbackStarted();
      controller.playbackStopped();

      expect(toggles, [true, false]);
      expect(scheduler.hasPending, isFalse);
      expect(scheduler.cancelCount, 1);
    });

    test('a newly edited value is picked up at the next restart', () {
      controller.playbackStarted();
      expect(scheduler.scheduledFor, const Duration(minutes: 5));

      timeout = const Duration(minutes: 20);
      controller.userActivity();

      expect(scheduler.scheduledFor, const Duration(minutes: 20));
    });

    test('disposing releases the wakelock and ignores later events', () {
      controller.playbackStarted();
      controller.dispose();

      expect(toggles, [true, false]);
      expect(scheduler.hasPending, isFalse);

      controller.playbackStarted();
      controller.userActivity();

      expect(toggles, [true, false]);
      expect(controller.isAwake, isFalse);
    });

    test('stopping without ever starting makes no platform call', () {
      controller.playbackStopped();

      expect(toggles, isEmpty);
    });
  });
}
