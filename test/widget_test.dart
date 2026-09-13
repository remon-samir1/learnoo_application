import 'dart:convert';

import 'package:easy_localization/src/localization.dart';
import 'package:easy_localization/src/translations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learnoo/features/auth/domain/splash_router.dart';
import 'package:learnoo/features/auth/presentation/screens/login_screen.dart';
import 'package:learnoo/features/auth/presentation/screens/splash_screen.dart';

/// Splash screen widget tests.
///
/// The screen is driven through injected collaborators, so nothing here opens a
/// socket or reads the keystore. The previous version built the whole app
/// against the live API and sat until the ten-minute framework timeout.
///
/// Translations are loaded straight into [Localization]'s singleton rather than
/// by mounting an `EasyLocalization` widget: that widget keeps global state and
/// renders an empty tree when mounted a second time in the same isolate, which
/// silently blanked every test after the first.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final raw = await rootBundle.loadString('assets/translations/en.json');
    final decoded = json.decode(raw) as Map<String, dynamic>;
    Localization.load(
      const Locale('en'),
      translations: Translations(decoded),
      fallbackTranslations: Translations(decoded),
    );
  });

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  /// The minimum the screen needs: material localizations and a navigator.
  Widget harness({
    required SplashRouter router,
    Future<Map<String, dynamic>?> Function()? checkForUpdate,
    Locale locale = const Locale('en'),
  }) {
    return MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('ar')],
      home: SplashScreen(
        router: router,
        checkForUpdate: checkForUpdate ?? () async => null,
        splashDelay: Duration.zero,
      ),
    );
  }

  /// Builds each destination out of the real decision logic rather than by
  /// stubbing `resolve`, so the wiring under test stays honest.
  SplashRouter routerReturning(
    SplashDestination destination, {
    void Function()? onResolve,
  }) {
    Future<String?> token(String? value) async {
      onResolve?.call();
      return value;
    }

    switch (destination) {
      case SplashDestination.login:
        return SplashRouter(
          readToken: () => token(null),
          hasConnection: () async => true,
          fetchProfile: () async => const {'success': false},
          clearToken: () async {},
        );
      case SplashDestination.parentDashboard:
        return SplashRouter(
          readToken: () => token('session'),
          hasConnection: () async => true,
          fetchProfile: () async => const {
            'success': true,
            'data': {
              'attributes': {'role': 'Parent'},
            },
          },
          clearToken: () async {},
        );
      case SplashDestination.onboarding:
        return SplashRouter(
          readToken: () => token('session'),
          hasConnection: () async => true,
          fetchProfile: () async => const {
            'success': true,
            'data': {
              'attributes': {'role': 'Student'},
            },
          },
          clearToken: () async {},
        );
      case SplashDestination.studentHome:
        return SplashRouter(
          readToken: () => token('session'),
          hasConnection: () async => false,
          fetchProfile: () async => const {'success': false},
          clearToken: () async {},
        );
    }
  }

  /// Advances the splash delay and the async gaps behind it.
  ///
  /// `pumpAndSettle` is not enough on its own: the routing chain is a timer
  /// followed by several awaits, and settling stops as soon as no frame is
  /// scheduled.
  Future<void> settleSplash(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('renders the splash before routing anywhere', (tester) async {
    await tester.pumpWidget(
      harness(router: routerReturning(SplashDestination.login)),
    );
    await tester.pump();

    expect(find.byType(SplashScreen), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);

    await settleSplash(tester);
  });

  testWidgets('an unauthenticated session lands on the login screen',
      (tester) async {
    await tester.pumpWidget(
      harness(router: routerReturning(SplashDestination.login)),
    );
    await settleSplash(tester);

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(SplashScreen), findsNothing);
  });

  testWidgets('a rejected token clears the session and reaches login',
      (tester) async {
    var cleared = false;
    await tester.pumpWidget(
      harness(
        router: SplashRouter(
          readToken: () async => 'stale',
          hasConnection: () async => true,
          fetchProfile: () async => const {
            'success': false,
            'statusCode': 401,
          },
          clearToken: () async => cleared = true,
        ),
      ),
    );
    await settleSplash(tester);

    expect(cleared, isTrue);
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('a parent session leaves the splash for the parent app',
      (tester) async {
    await tester.pumpWidget(
      harness(router: routerReturning(SplashDestination.parentDashboard)),
    );
    await settleSplash(tester);

    // The parent dashboard loads its own data, so the assertion is that the
    // splash handed off to it and did not fall through to login.
    expect(find.byType(SplashScreen), findsNothing);
    expect(find.byType(LoginScreen), findsNothing);
  });

  testWidgets('the router is consulted exactly once', (tester) async {
    var resolveCount = 0;
    await tester.pumpWidget(
      harness(
        router: routerReturning(
          SplashDestination.login,
          onResolve: () => resolveCount++,
        ),
      ),
    );
    await settleSplash(tester);

    expect(resolveCount, 1);
  });

  testWidgets('a failing update check still routes rather than hanging',
      (tester) async {
    await tester.pumpWidget(
      harness(
        router: routerReturning(SplashDestination.login),
        checkForUpdate: () async => throw Exception('offline'),
      ),
    );
    await settleSplash(tester);

    // An unreachable OTA endpoint must never strand a user on the splash.
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('routes the same way in Arabic', (tester) async {
    await tester.pumpWidget(
      harness(
        router: routerReturning(SplashDestination.login),
        locale: const Locale('ar'),
      ),
    );
    await settleSplash(tester);

    expect(find.byType(LoginScreen), findsOneWidget);
  });
}
