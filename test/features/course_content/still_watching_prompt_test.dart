import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learnoo/features/course_content/presentation/widgets/still_watching_prompt.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const texts = {
    'ar': (
      title: 'هل ما زلت تتابع الفيديو؟',
      countdown: 'سيتوقف الفيديو خلال 15 ثانية',
      after: 'سيتوقف الفيديو خلال 14 ثانية',
      button: 'ما زلت أتابع',
    ),
    'en': (
      title: 'Are you still watching?',
      countdown: 'The video will stop in 15 seconds',
      after: 'The video will stop in 14 seconds',
      button: 'Still watching',
    ),
  };

  // The inline player is 220pt tall at phone width; fullscreen is landscape.
  const sizes = {
    'inline portrait': Size(393, 220),
    'fullscreen landscape': Size(852, 393),
    'small inline': Size(320, 180),
  };

  Future<void> pump(
    WidgetTester tester, {
    required String language,
    required Size size,
    required ValueNotifier<int?> seconds,
    required VoidCallback onStillWatching,
    VoidCallback? onBackdropTap,
  }) async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en'), Locale('ar')],
        startLocale: Locale(language),
        saveLocale: false,
        path: 'assets/translations',
        assetLoader: const _TestTranslations(),
        child: Builder(
          builder: (context) => MaterialApp(
            locale: context.locale,
            supportedLocales: context.supportedLocales,
            localizationsDelegates: context.localizationDelegates,
            home: Scaffold(
              body: Align(
                alignment: Alignment.topCenter,
                child: SizedBox.fromSize(
                  size: size,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Stands in for the player and its controls underneath.
                      GestureDetector(
                        key: const Key('player-underneath'),
                        behavior: HitTestBehavior.opaque,
                        onTap: onBackdropTap,
                      ),
                      StillWatchingPrompt(
                        secondsLeft: seconds,
                        total: const Duration(seconds: 15),
                        onStillWatching: onStillWatching,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final language in texts.keys) {
    for (final entry in sizes.entries) {
      testWidgets('notice in $language, ${entry.key}', (tester) async {
        final t = texts[language]!;
        final seconds = ValueNotifier<int?>(null);
        var pressed = 0;
        await pump(
          tester,
          language: language,
          size: entry.value,
          seconds: seconds,
          onStillWatching: () => pressed++,
        );

        expect(find.byKey(StillWatchingPrompt.cardKey), findsNothing);

        seconds.value = 15;
        await tester.pump();
        expect(find.text(t.title), findsOneWidget);
        expect(find.text(t.countdown), findsOneWidget);
        expect(find.text('15'), findsOneWidget);
        expect(find.text(t.button), findsOneWidget);

        seconds.value = 14;
        await tester.pump();
        expect(find.text(t.after), findsOneWidget);
        expect(find.text('14'), findsOneWidget);

        // The card fits inside the player, button included.
        final player = tester.getRect(
          find.byKey(const Key('player-underneath')),
        );
        final card = tester.getRect(find.byKey(StillWatchingPrompt.cardKey));
        expect(player.contains(card.topLeft), isTrue);
        expect(player.contains(card.bottomRight - const Offset(1, 1)), isTrue);

        await tester.tap(find.byKey(StillWatchingPrompt.buttonKey));
        expect(pressed, 1);

        seconds.value = null;
        await tester.pump();
        expect(find.byKey(StillWatchingPrompt.cardKey), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('the dimmed backdrop lets taps reach the player controls', (
    tester,
  ) async {
    final seconds = ValueNotifier<int?>(10);
    var backdropTaps = 0;
    var pressed = 0;
    await pump(
      tester,
      language: 'ar',
      size: const Size(393, 220),
      seconds: seconds,
      onStillWatching: () => pressed++,
      onBackdropTap: () => backdropTaps++,
    );

    final player = tester.getRect(find.byKey(const Key('player-underneath')));
    await tester.tapAt(player.topLeft + const Offset(8, 8));
    expect(backdropTaps, 1, reason: 'pause/controls stay usable');
    expect(pressed, 0);
  });
}

class _TestTranslations extends AssetLoader {
  const _TestTranslations();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async {
    return jsonDecode(
          File('$path/${locale.languageCode}.json').readAsStringSync(),
        )
        as Map<String, dynamic>;
  }
}
