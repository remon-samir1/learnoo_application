import 'package:flutter_test/flutter_test.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:learnoo/main.dart';
import 'package:learnoo/core/services/feature_manager.dart';
import 'package:learnoo/core/theme/dynamic_theme.dart';

void main() {
  testWidgets('Splash screen shows Learnoo app name', (WidgetTester tester) async {
    // Initialize services
    final featureManager = FeatureManager();
    await featureManager.initialize();

    final themeService = DynamicThemeService();
    await themeService.initialize();

    // Build our app and trigger a frame.
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en'), Locale('ar')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en'),
        child: LearnooApp(
          themeService: themeService,
          featureManager: featureManager,
        ),
      ),
    );

    // Verify that Learnoo app name is shown.
    expect(find.text('Learnoo'), findsOneWidget);
    expect(find.text('Your academic journey starts here'), findsOneWidget);

    // Allow the splash timer to complete to avoid pending timer error
    await tester.pumpAndSettle(const Duration(seconds: 3));
  });
}
