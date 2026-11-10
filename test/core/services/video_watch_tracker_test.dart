import 'package:flutter_test/flutter_test.dart';
import 'package:learnoo/core/services/video_watch_tracker.dart';

/// The view is charged on media time, like the website's
/// `useChapterViewRecording.ts`: only small forward steps of the lecture's own
/// clock count, so dragging the bar forward can never buy a view.
void main() {
  group('credited media time', () {
    int credited(Duration? previous, Duration current) =>
        VideoWatchTracker.creditedDeltaMs(previous, current);

    test('normal playback credits the step between samples', () {
      expect(
        credited(const Duration(seconds: 10), const Duration(seconds: 11)),
        1000,
      );
      // Two-times speed covers two seconds of lecture per real second, and
      // both count — the platform credits the lecture's own minutes.
      expect(
        credited(const Duration(seconds: 10), const Duration(seconds: 12)),
        2000,
      );
    });

    test('the first sample only sets the baseline', () {
      expect(credited(null, const Duration(seconds: 30)), 0);
    });

    test('dragging forward past the requirement credits nothing', () {
      expect(
        credited(const Duration(seconds: 5), const Duration(minutes: 31)),
        0,
      );
    });

    test('a jump just over the three second rule is a seek', () {
      expect(
        credited(const Duration(seconds: 10), const Duration(seconds: 13)),
        3000,
      );
      expect(
        credited(
          const Duration(seconds: 10),
          const Duration(seconds: 13, milliseconds: 1),
        ),
        0,
      );
    });

    test('going back, or a paused player, credits nothing', () {
      expect(
        credited(const Duration(minutes: 5), const Duration(minutes: 1)),
        0,
      );
      expect(
        credited(const Duration(seconds: 10), const Duration(seconds: 10)),
        0,
      );
    });
  });
}
