import 'dart:async';
import 'dart:convert';

import 'package:easy_localization/src/localization.dart';
import 'package:easy_localization/src/translations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learnoo/core/services/app_update_service.dart';
import 'package:learnoo/core/widgets/app_update_gate.dart';

const _iosStore = 'https://apps.apple.com/app/id6825859916';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Read once outside the widget tests: asset I/O does not finish inside
  // testWidgets' fake-async zone.
  final translations = <String, Translations>{};
  setUpAll(() async {
    for (final code in ['en', 'ar']) {
      final raw = await rootBundle.loadString('assets/translations/$code.json');
      translations[code] = Translations(
        json.decode(raw) as Map<String, dynamic>,
      );
    }
  });

  void useLanguage(String code) => Localization.load(
    Locale(code),
    translations: translations[code],
    fallbackTranslations: translations[code],
  );

  setUp(() => useLanguage('en'));

  /// Same shape as main.dart: the gate wraps the navigator in `builder`.
  Widget app({
    required Future<AppUpdateStatus> Function() check,
    Future<bool> Function(Uri)? openStore,
    TextDirection direction = TextDirection.ltr,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const Text('lesson screen')),
              ),
              child: const Text('home screen'),
            ),
          ),
        ),
      ),
      builder: (context, child) => Directionality(
        textDirection: direction,
        child: AppUpdateGate(
          check: check,
          openStore: openStore ?? (_) async => true,
          child: child!,
        ),
      ),
    );
  }

  testWidgets(
    'below the minimum: only the update screen, nothing else is built',
    (tester) async {
      final opened = <Uri>[];
      await tester.pumpWidget(
        app(
          check: () async => const AppUpdateStatus.required(_iosStore),
          openStore: (uri) async {
            opened.add(uri);
            return true;
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(UpdateRequiredScreen), findsOneWidget);
      expect(find.text('Update required'), findsOneWidget);
      expect(find.text('home screen'), findsNothing);
      expect(find.byType(Navigator), findsNothing);

      // Back does not get past it.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(UpdateRequiredScreen), findsOneWidget);

      await tester.tap(find.text('Update now'));
      await tester.pumpAndSettle();
      expect(opened, [Uri.parse(_iosStore)]);
      expect(find.byType(UpdateRequiredScreen), findsOneWidget);
    },
  );

  testWidgets('up to date, or the server cannot be reached: the app opens', (
    tester,
  ) async {
    for (final status in [AppUpdateStatus.allowed, AppUpdateStatus.unknown]) {
      await tester.pumpWidget(app(check: () async => status));
      await tester.pumpAndSettle();
      expect(find.text('home screen'), findsOneWidget, reason: '$status');
      expect(
        find.byType(UpdateRequiredScreen),
        findsNothing,
        reason: '$status',
      );
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets(
    'a slow check does not hold the app; a later "required" still blocks',
    (tester) async {
      final answer = Completer<AppUpdateStatus>();
      await tester.pumpWidget(app(check: () => answer.future));
      await tester.pump();
      expect(find.text('home screen'), findsOneWidget);

      await tester.tap(find.text('home screen'));
      await tester.pumpAndSettle();
      expect(find.text('lesson screen'), findsOneWidget);

      answer.complete(const AppUpdateStatus.required(_iosStore));
      await tester.pumpAndSettle();
      expect(find.text('lesson screen'), findsNothing);
      expect(find.byType(UpdateRequiredScreen), findsOneWidget);
    },
  );

  testWidgets('checked again on return to the foreground', (tester) async {
    final answers = <AppUpdateStatus>[
      AppUpdateStatus.allowed,
      const AppUpdateStatus.required(_iosStore),
      // Came back from the store without updating, now offline: stays blocked.
      AppUpdateStatus.unknown,
      // The minimum was lowered on the dashboard: opens again.
      AppUpdateStatus.allowed,
    ];
    var calls = 0;
    await tester.pumpWidget(app(check: () async => answers[calls++]));
    await tester.pumpAndSettle();
    expect(find.text('home screen'), findsOneWidget);

    Future<void> resume() async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
    }

    await resume();
    expect(find.byType(UpdateRequiredScreen), findsOneWidget);
    await resume();
    expect(find.byType(UpdateRequiredScreen), findsOneWidget);
    await resume();
    expect(find.text('home screen'), findsOneWidget);
    expect(calls, 4);
  });

  testWidgets('the store cannot be opened: the student is told, still blocked', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        check: () async => const AppUpdateStatus.required(_iosStore),
        openStore: (_) async => false,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Update now'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Could not open the store. Please open it and update the app manually.',
      ),
      findsOneWidget,
    );
    expect(find.byType(UpdateRequiredScreen), findsOneWidget);
  });

  testWidgets('Arabic', (tester) async {
    useLanguage('ar');
    await tester.pumpWidget(
      app(
        check: () async => const AppUpdateStatus.required(_iosStore),
        direction: TextDirection.rtl,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('التحديث مطلوب'), findsOneWidget);
    expect(find.text('تحديث الآن'), findsOneWidget);
  });
}
