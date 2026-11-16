import 'dart:convert';

import 'package:easy_localization/src/localization.dart';
import 'package:easy_localization/src/translations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learnoo/features/course_content/presentation/widgets/live_tools_bar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final translations = <String, Translations>{};
  setUpAll(() async {
    for (final code in ['en', 'ar']) {
      final raw = await rootBundle.loadString('assets/translations/$code.json');
      translations[code] =
          Translations(json.decode(raw) as Map<String, dynamic>);
    }
  });

  void useLanguage(String code) => Localization.load(
        Locale(code),
        translations: translations[code],
        fallbackTranslations: translations[code],
      );

  setUp(() => useLanguage('en'));

  Future<List<String>> pump(
    WidgetTester tester, {
    bool enabled = true,
    bool chatEnabled = true,
    bool audioMuted = true,
    bool handRaised = false,
    bool chatOpen = false,
    int unread = 0,
  }) async {
    final calls = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: LiveToolsBar(
          enabled: enabled,
          chatEnabled: chatEnabled,
          audioMuted: audioMuted,
          handRaised: handRaised,
          chatOpen: chatOpen,
          unreadChatCount: unread,
          onToggleAudio: () => calls.add('toggleAudio'),
          onToggleRaiseHand: () => calls.add('toggleRaiseHand'),
          onToggleChat: () => calls.add('toggleChat'),
        ),
      ),
    ));
    return calls;
  }

  testWidgets('same three tools as the website, each sending its command',
      (tester) async {
    final calls = await pump(tester);
    expect(find.text('Live Interaction Tools'), findsOneWidget);
    expect(find.text('Unmute microphone'), findsOneWidget);
    expect(find.text('Raise Hand'), findsOneWidget);
    expect(find.text('Live Chat'), findsOneWidget);

    await tester.tap(find.byKey(const Key('live-tool-mic')));
    await tester.tap(find.byKey(const Key('live-tool-hand')));
    await tester.tap(find.byKey(const Key('live-tool-chat')));
    expect(calls, ['toggleAudio', 'toggleRaiseHand', 'toggleChat']);
  });

  testWidgets('nothing works before the student is inside the conference',
      (tester) async {
    final calls = await pump(tester, enabled: false);
    await tester.tap(find.byKey(const Key('live-tool-mic')));
    await tester.tap(find.byKey(const Key('live-tool-hand')));
    await tester.tap(find.byKey(const Key('live-tool-chat')));
    expect(calls, isEmpty);
  });

  testWidgets('no chat button when the room has chat turned off',
      (tester) async {
    await pump(tester, chatEnabled: false);
    expect(find.byKey(const Key('live-tool-chat')), findsNothing);
  });

  testWidgets('labels follow the meeting state; unread count capped at 9+',
      (tester) async {
    await pump(tester, audioMuted: false, handRaised: true, unread: 12);
    expect(find.text('Mute microphone'), findsOneWidget);
    expect(find.text('Lower Hand'), findsOneWidget);
    expect(find.text('9+'), findsOneWidget);

    await pump(tester, chatOpen: true, unread: 3);
    expect(find.text('Hide Chat'), findsOneWidget);
    expect(find.text('3'), findsNothing);
  });

  testWidgets('Arabic labels are the website\'s', (tester) async {
    useLanguage('ar');
    await pump(tester);
    expect(find.text('أدوات التفاعل المباشر'), findsOneWidget);
    expect(find.text('تشغيل الميكروفون'), findsOneWidget);
    expect(find.text('رفع اليد'), findsOneWidget);
    expect(find.text('الدردشة المباشرة'), findsOneWidget);
  });
}
