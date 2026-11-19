import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learnoo/features/course_content/data/models/live_room.dart';
import 'package:learnoo/features/course_content/presentation/screens/live_stream_webview_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

void main() {
  testWidgets('live chat keyboard and fullscreen keep the same meeting view',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/permissions/methods'),
      (call) async => call.method == 'requestPermissions'
          ? {for (final permission in call.arguments as List) permission: 1}
          : 1,
    );
    final platform = _MeetingPlatform();
    WebViewPlatform.instance = platform;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: LiveStreamWebViewScreen(
        liveRoom: LiveRoom.fromJson({
          'id': '193',
          'attributes': {'title': 'Live test', 'enable_chat': true},
        }),
      ),
    ));
    for (var i = 0; i < 10 && platform.controller.channel == null; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(platform.controller.channel, isNotNull);
    platform.controller.channel!.onMessageReceived(
      const JavaScriptMessage(message: '{"type":"conferenceJoined"}'),
    );
    await tester.pumpAndSettle();
    final meeting = tester.element(find.byKey(const Key('test-live-webview')));
    final originalHeight = tester.getSize(find.byKey(const Key('test-live-webview'))).height;
    tester.view.viewInsets = const FakeViewPadding(bottom: 360);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byKey(const Key('test-live-webview'))).height, originalHeight);
    tester.view.viewInsets = const FakeViewPadding();
    await tester.pump();
    await tester.tap(find.byKey(const Key('live-fullscreen')));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(const Key('test-live-webview'))).height, greaterThan(originalHeight));
    expect(tester.element(find.byKey(const Key('test-live-webview'))), same(meeting));
    await tester.tap(find.byKey(const Key('live-fullscreen')));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(const Key('test-live-webview'))).height, originalHeight);
    expect(platform.controller.loads, 1);
    await tester.pumpWidget(const SizedBox());
  });
}

class _MeetingPlatform extends WebViewPlatform {
  final controller = _MeetingController();
  @override
  PlatformWebViewController createPlatformWebViewController(PlatformWebViewControllerCreationParams params) => controller;
  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(PlatformNavigationDelegateCreationParams params) => _MeetingDelegate(params);
  @override
  PlatformWebViewWidget createPlatformWebViewWidget(PlatformWebViewWidgetCreationParams params) => _MeetingWidget(params);
}

class _MeetingController extends PlatformWebViewController {
  _MeetingController() : super.implementation(const PlatformWebViewControllerCreationParams());
  JavaScriptChannelParams? channel;
  int loads = 0;
  @override
  Future<void> setJavaScriptMode(JavaScriptMode mode) async {}
  @override
  Future<void> setBackgroundColor(Color color) async {}
  @override
  Future<void> addJavaScriptChannel(JavaScriptChannelParams params) async { channel = params; }
  @override
  Future<void> setPlatformNavigationDelegate(PlatformNavigationDelegate delegate) async {}
  @override
  Future<void> loadHtmlString(String html, {String? baseUrl}) async { loads++; }
  @override
  Future<void> runJavaScript(String script) async {}
}

class _MeetingDelegate extends PlatformNavigationDelegate {
  _MeetingDelegate(super.params) : super.implementation();
  @override
  Future<void> setOnWebResourceError(WebResourceErrorCallback callback) async {}
}

class _MeetingWidget extends PlatformWebViewWidget {
  _MeetingWidget(super.params) : super.implementation();
  @override
  Widget build(BuildContext context) => const SizedBox.expand(key: Key('test-live-webview'));
}
