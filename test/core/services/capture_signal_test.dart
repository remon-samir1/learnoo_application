import 'package:flutter_test/flutter_test.dart';
import 'package:learnoo/core/services/capture_signal.dart';

void main() {
  group('CaptureSignal', () {
    test('starts clear', () {
      expect(CaptureSignal().isCapturing, isFalse);
    });

    test('either source turns capture on', () {
      final fromNative = CaptureSignal()..setNative(true);
      expect(fromNative.isCapturing, isTrue);

      final fromPlugin = CaptureSignal()..setPlugin(true);
      expect(fromPlugin.isCapturing, isTrue);
    });

    test('one source stopping does not clear the other', () {
      final signal = CaptureSignal()
        ..setNative(true)
        ..setPlugin(true);

      signal.setNative(false);

      expect(signal.isCapturing, isTrue);
    });

    test('verify clears a latched signal that was never cancelled', () {
      // What iOS does: both sources report capture at launch (AirPlay,
      // mirroring, a recording started earlier) and no stop event follows.
      final signal = CaptureSignal()
        ..setNative(true)
        ..setPlugin(true);
      expect(signal.isCapturing, isTrue);

      expect(signal.verify(false), isTrue, reason: 'capture state moved');
      expect(signal.isCapturing, isFalse);
      expect(signal.nativeReported, isFalse);
      expect(signal.pluginReported, isFalse);
    });

    test('verify keeps protection on while capture really is running', () {
      final signal = CaptureSignal();

      expect(signal.verify(true), isTrue);
      expect(signal.isCapturing, isTrue);

      // Re-verifying the same answer is not a change.
      expect(signal.verify(true), isFalse);
      expect(signal.isCapturing, isTrue);
    });

    test('reports whether the combined answer moved', () {
      final signal = CaptureSignal();

      expect(signal.setNative(true), isTrue);
      expect(signal.setPlugin(true), isFalse, reason: 'already capturing');
      expect(signal.setNative(false), isFalse, reason: 'plugin still on');
      expect(signal.setPlugin(false), isTrue);
    });
  });
}
