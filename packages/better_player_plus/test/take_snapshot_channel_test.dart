import 'package:better_player_plus/better_player_plus.dart';
import 'package:better_player_plus/src/video_player/method_channel_video_player.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The "ask about this moment" frame is read from the native player over
/// `better_player_channel`. These pin the contract both native sides answer:
/// method `takeSnapshot`, argument `textureId`, reply JPEG bytes or null.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('better_player_channel');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];

  void answerWith(Future<Object?> Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(channel, (call) {
      calls.add(call);
      return handler(call);
    });
  }

  setUp(calls.clear);
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('asks the native player of that texture for its current frame', () async {
    final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3]);
    answerWith((_) async => jpeg);

    final frame = await MethodChannelVideoPlayer().takeSnapshot(7);

    expect(frame, jpeg);
    expect(calls, hasLength(1));
    expect(calls.single.method, 'takeSnapshot');
    expect(calls.single.arguments, <String, dynamic>{'textureId': 7});
  });

  test('gives null when the player has no frame for this moment', () async {
    answerWith((_) async => null);

    expect(await MethodChannelVideoPlayer().takeSnapshot(7), isNull);
  });

  test('passes a native failure on to the caller', () {
    answerWith((_) async => throw PlatformException(code: 'NO_SURFACE'));

    expect(
      MethodChannelVideoPlayer().takeSnapshot(7),
      throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'NO_SURFACE')),
    );
  });

  test('a controller with no video loaded gives null without calling the player', () async {
    answerWith((_) async => Uint8List(4));
    final controller = BetterPlayerController(const BetterPlayerConfiguration());

    expect(await controller.takeSnapshot(), isNull);
    expect(calls.where((c) => c.method == 'takeSnapshot'), isEmpty);
  });
}
