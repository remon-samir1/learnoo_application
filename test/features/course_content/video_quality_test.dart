import 'package:better_player_plus/better_player_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learnoo/features/course_content/domain/video_quality.dart';

BetterPlayerAsmsTrack track(int w, int h, int bitrate) =>
    BetterPlayerAsmsTrack('', w, h, bitrate, 0, '', '');

void main() {
  test('lists real and fake renditions, highest first, ensuring at least four qualities', () {
    final options = videoQualityOptions([
      BetterPlayerAsmsTrack.defaultTrack(),
      track(854, 480, 1200000),
      track(1920, 1080, 5000000),
      track(1280, 720, 2800000),
    ]);
    expect(options.map((o) => o.label), ['1080p', '720p', '480p', '360p']);
    expect(options.firstWhere((o) => o.id == '1080p').isReal, isTrue);
    expect(options.firstWhere((o) => o.id == '720p').isReal, isTrue);
    expect(options.firstWhere((o) => o.id == '480p').isReal, isTrue);
    expect(options.firstWhere((o) => o.id == '360p').isReal, isFalse);
    expect(autoQualityLabel(options, 'Auto'), 'Auto (1080p)');
  });

  test('a single-rendition stream offers at least four qualities up to 1080p (plus Auto)', () {
    final options = videoQualityOptions([
      BetterPlayerAsmsTrack.defaultTrack(),
      track(854, 480, 1200000),
    ]);
    expect(options.map((o) => o.label), ['1080p', '720p', '480p', '360p']);
    expect(options.firstWhere((o) => o.id == '480p').isReal, isTrue);
    expect(options.firstWhere((o) => o.id == '1080p').isReal, isFalse);
    expect(options.firstWhere((o) => o.id == '720p').isReal, isFalse);
    expect(options.firstWhere((o) => o.id == '360p').isReal, isFalse);
    expect(autoQualityLabel(options, 'Auto'), 'Auto (1080p)');
  });

  test('progressive stream always offers at least four fake qualities up to 1080p', () {
    final options = videoQualityOptions(const []);
    expect(options.map((o) => o.label), ['1080p', '720p', '480p', '360p']);
    expect(options.every((o) => !o.isReal), isTrue);
    expect(autoQualityLabel(options, 'Auto'), 'Auto (1080p)');
  });

  test('same height collapses to the highest bitrate', () {
    final options = videoQualityOptions([
      track(1280, 720, 2000000),
      track(1280, 720, 3000000),
    ]);
    final opt720 = options.firstWhere((o) => o.id == '720p');
    expect(opt720.bitrate, 3000000);
    expect(opt720.isReal, isTrue);
    expect(options.map((o) => o.label), ['1080p', '720p', '480p', '360p']);
  });

  test('a variant without resolution is labelled by bitrate', () {
    final options = videoQualityOptions([track(0, 0, 850000)]);
    expect(options.any((o) => o.label == '850 kbps' && o.isReal), isTrue);
  });

  test('selection follows the player track; default means Auto', () {
    final options = videoQualityOptions([
      track(1280, 720, 2800000),
      track(854, 480, 1200000),
    ]);
    expect(selectedQualityOption(options, null), isNull);
    expect(
      selectedQualityOption(options, BetterPlayerAsmsTrack.defaultTrack()),
      isNull,
    );
    expect(
      selectedQualityOption(options, track(854, 480, 1200000))?.label,
      '480p',
    );
    expect(isAutoQualityTrack(BetterPlayerAsmsTrack.defaultTrack()), isTrue);
  });
}
