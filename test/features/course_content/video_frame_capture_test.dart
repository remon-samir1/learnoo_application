// The frame attached to an "ask about this moment" question.
//
// On iPhone the picture came out black with only the watermark on it: the
// player is a native view Flutter cannot rasterise, and the only capture that
// "succeeded" was Flutter's own image of the player box. The frame now comes
// from the player itself, and that black image is never used on iOS.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learnoo/features/course_content/services/video_frame_capture_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _TempPaths extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _TempPaths(this.path);
  final String path;

  @override
  Future<String?> getTemporaryPath() async => path;
}

const _thumbnailChannel = MethodChannel('plugins.justsoft.xyz/video_thumbnail');
const _hlsUrl = 'http://localhost:8000/hls/chapter/1/playlist';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final service = VideoFrameCaptureService();
  final thumbnailCalls = <MethodCall>[];
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('learnoo_frame_capture');
    PathProviderPlatform.instance = _TempPaths(tempDir.path);
  });

  tearDownAll(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  setUp(() {
    thumbnailCalls.clear();
    // The stream is HLS: re-reading it for a still fails on both platforms.
    messenger.setMockMethodCallHandler(_thumbnailChannel, (call) async {
      thumbnailCalls.add(call);
      return null;
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(_thumbnailChannel, null));

  /// A player box as Flutter sees it on iOS: only the overlay is drawn.
  Future<GlobalKey> pumpPlayerBox(WidgetTester tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: RepaintBoundary(
            key: key,
            child: Container(
              width: 160,
              height: 90,
              color: Colors.black,
              alignment: Alignment.center,
              child: Container(width: 60, height: 10, color: Colors.white),
            ),
          ),
        ),
      ),
    );
    return key;
  }

  group('the frame comes from the player', () {
    test('the bytes the player returns are the attached image', () async {
      final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 9, 8, 7, 6]);
      var asked = 0;

      final file = await service.capture(
        videoUrl: _hlsUrl,
        positionSeconds: 110,
        chapterId: '5',
        playerSnapshot: () async {
          asked++;
          return jpeg;
        },
      );

      expect(asked, 1);
      expect(file, isNotNull);
      expect(await file!.readAsBytes(), jpeg);
      expect(file.path, contains('moment_5_110_'));
      expect(thumbnailCalls, isEmpty, reason: 'no second capture is needed');
    });

    test('a player error falls back to the next capture', () async {
      final file = await service.capture(
        videoUrl: _hlsUrl,
        positionSeconds: 12,
        chapterId: '5',
        playerSnapshot: () async =>
            throw PlatformException(code: 'NO_SURFACE'),
      );

      expect(thumbnailCalls, hasLength(1));
      expect(thumbnailCalls.single.method, 'data');
      expect(thumbnailCalls.single.arguments['timeMs'], 12000);
      expect(file, isNull, reason: 'nothing could read a frame');
    });

    test('an empty reply from the player is not attached', () async {
      final file = await service.capture(
        videoUrl: _hlsUrl,
        positionSeconds: 12,
        chapterId: '5',
        playerSnapshot: () async => Uint8List(0),
      );

      expect(thumbnailCalls, hasLength(1));
      expect(file, isNull);
    });

    testWidgets('a player that never answers does not block the question', (
      tester,
    ) async {
      File? result;
      var done = false;
      unawaited(
        service
            .capture(
              videoUrl: _hlsUrl,
              positionSeconds: 12,
              chapterId: '5',
              playerSnapshot: () => Completer<Uint8List?>().future,
            )
            .then((file) {
              result = file;
              done = true;
            }),
      );

      await tester.pump(const Duration(seconds: 7));
      expect(done, isFalse);

      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(done, isTrue);
      expect(result, isNull);
    });
  });

  group('the black image of the player box', () {
    testWidgets(
      'is never attached on iPhone, where Flutter cannot see the video',
      (tester) async {
        final key = await pumpPlayerBox(tester);

        final file = await tester.runAsync(
          () => service.capture(
            videoUrl: _hlsUrl,
            positionSeconds: 110,
            chapterId: '5',
            playerSnapshot: () async => null,
            boundaryKey: key,
          ),
        );

        expect(VideoFrameCaptureService.videoIsPlatformView, isTrue);
        expect(thumbnailCalls, hasLength(1));
        expect(
          file,
          isNull,
          reason: 'the question posts without an image rather than a black one',
        );
      },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    );

    testWidgets(
      'Android still falls back to the player box, which holds the video',
      (tester) async {
        final key = await pumpPlayerBox(tester);

        final file = await tester.runAsync(
          () => service.capture(
            videoUrl: _hlsUrl,
            positionSeconds: 110,
            chapterId: '5',
            playerSnapshot: () async => null,
            boundaryKey: key,
          ),
        );

        expect(VideoFrameCaptureService.videoIsPlatformView, isFalse);
        expect(file, isNotNull);
        final bytes = await tester.runAsync(() => file!.readAsBytes());
        // PNG signature: the rasterised player box.
        expect(bytes!.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
  });
}
