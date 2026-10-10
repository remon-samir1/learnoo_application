import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';
import 'package:learnoo/core/services/capture_media_guard.dart';
import 'package:learnoo/core/services/screen_protection_service.dart';

class FakePlayer extends VideoPlayerController {
  FakePlayer({double volume = 0.6}) : super.networkUrl(Uri.parse('https://example.com/lecture.mp4')) {
    value = value.copyWith(isInitialized: true, isPlaying: true, volume: volume);
  }
  @override
  Future<void> pause() async { value = value.copyWith(isPlaying: false); }
  @override
  Future<void> setVolume(double volume) async { value = value.copyWith(volume: volume); }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final capture = ScreenProtectionService().mediaCaptureActive as ValueNotifier<bool>;
  tearDown(() => capture.value = false);

  test('capture pauses and mutes, blocks play, then restores volume without autoplay', () async {
    final player = FakePlayer();
    CaptureMediaGuard.attachVideoPlayer(player);
    capture.value = true;
    await Future<void>.delayed(Duration.zero);
    expect(player.value.volume, 0);
    expect(player.value.isPlaying, false);
    player.value = player.value.copyWith(isPlaying: true, volume: 1);
    await Future<void>.delayed(Duration.zero);
    expect(player.value.volume, 0);
    expect(player.value.isPlaying, false);
    capture.value = false;
    await Future<void>.delayed(Duration.zero);
    expect(player.value.volume, 0.6);
    expect(player.value.isPlaying, false);
    CaptureMediaGuard.detach(player);
  });
  test('player created during recording stays silent and preserves prior mute', () async {
    capture.value = true;
    final player = FakePlayer(volume: 0);
    CaptureMediaGuard.attachVideoPlayer(player);
    await Future<void>.delayed(Duration.zero);
    expect(player.value.isPlaying, false);
    capture.value = false;
    await Future<void>.delayed(Duration.zero);
    expect(player.value.volume, 0);
    CaptureMediaGuard.detach(player);
  });
}
