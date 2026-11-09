import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learnoo/features/profile/presentation/screens/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final language in ['en', 'ar']) {
    testWidgets('settings opens account deletion directly in $language', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      await EasyLocalization.ensureInitialized();
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/url_launcher'),
        (call) async {
          calls.add(call);
          return true;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/url_launcher'),
          null,
        ),
      );

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
              home: const SettingsScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final link = find.text(
        language == 'ar' ? 'حذف الحساب' : 'Delete Account',
      );
      await tester.scrollUntilVisible(link, 100);
      await tester.tap(link);
      await tester.pumpAndSettle();

      final launch = calls.singleWhere((call) => call.method == 'launch');
      expect(launch.arguments['url'], 'https://learnoo.app/delete-account');
      expect(launch.arguments['useSafariVC'], isFalse);
      expect(tester.takeException(), isNull);
    });
  }
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
