import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:learnoo/core/widgets/custom_text_field.dart';
import 'package:learnoo/core/widgets/header_back_button.dart';
import 'package:learnoo/core/widgets/primary_button.dart';
import 'package:learnoo/features/auth/data/auth_repository.dart';
import 'package:learnoo/features/auth/presentation/screens/login_screen.dart';
import 'package:learnoo/features/auth/presentation/screens/profile_screen.dart';
import 'package:learnoo/features/parent/presentation/screens/parent_login_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Parent registration is paused in the app (doctor's list, 16 Nov): new
/// accounts are students only, while existing parents still sign in.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const texts = {
    'ar': (
      title: 'أكمل ملفك الشخصي',
      student: 'طالب',
      parent: 'ولي أمر',
      password: 'كلمة المرور',
      confirmPassword: 'تأكيد كلمة المرور',
      codeHint: 'هنبعتلك كود تفعيل على رقم الموبايل ده. مش محتاج كلمة مرور.',
      signUp: 'تسجيل جديد',
      parentLogin: 'تسجيل الدخول كولي أمر',
    ),
    'en': (
      title: 'Complete your profile',
      student: 'Student',
      parent: 'Parent',
      password: 'Password',
      confirmPassword: 'Confirm password',
      codeHint:
          'We will text a one-time code to this number. No password needed.',
      signUp: 'Sign up',
      parentLogin: 'Sign in as a parent',
    ),
  };

  Future<void> pump(WidgetTester tester, String language, Widget home) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
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
            home: home,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final language in texts.keys) {
    final t = texts[language]!;

    testWidgets('sign-up offers no parent account in $language', (
      tester,
    ) async {
      await pump(tester, language, const ProfileScreen());

      expect(find.text(t.title), findsOneWidget);
      expect(find.text(t.parent), findsNothing);
      expect(find.text(t.student), findsNothing);
      expect(find.text(t.password), findsNothing);
      expect(find.text(t.confirmPassword), findsNothing);
      // First name, last name, email, phone — and nothing to type a password in.
      expect(find.byType(TextField), findsNWidgets(4));
      expect(
        tester
            .widgetList<CustomTextField>(find.byType(CustomTextField))
            .where((field) => field.isPassword),
        isEmpty,
      );
      expect(find.text(t.codeHint), findsOneWidget);
    });

    testWidgets('sign-up registers a student with the entered details in '
        '$language', (tester) async {
      final auth = _RecordingAuth();
      await pump(tester, language, ProfileScreen(authRepository: auth));

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'Sara');
      await tester.enterText(fields.at(1), 'Ali');
      await tester.enterText(fields.at(2), 'sara@gmail.com');
      await tester.enterText(fields.at(3), '01012345678');
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.tap(find.byType(PrimaryButton));
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));

      expect(auth.calls, [
        {
          'firstName': 'Sara',
          'lastName': 'Ali',
          'phone': '201012345678',
          'email': 'sara@gmail.com',
        },
      ]);
      // The refusal is shown and the student stays on the form.
      expect(find.text('taken'), findsOneWidget);
      expect(find.byType(ProfileScreen), findsOneWidget);
    });

    testWidgets('login keeps the parent sign-in and opens a student-only '
        'sign-up in $language', (tester) async {
      await pump(tester, language, const LoginScreen());

      expect(find.text(t.parentLogin), findsOneWidget);

      await tester.tap(find.text(t.signUp));
      await tester.pumpAndSettle();
      expect(find.byType(ProfileScreen), findsOneWidget);
      expect(find.text(t.parent), findsNothing);

      await tester.tap(find.byType(HeaderBackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text(t.parentLogin));
      await tester.pumpAndSettle();
      expect(find.byType(ParentLoginScreen), findsOneWidget);
    });
  }

  test('registration sends the student role and no password', () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    late http.Request sent;

    final result = await http.runWithClient(
      () => AuthRepository().register(
        firstName: 'Sara',
        lastName: 'Ali',
        phone: '201012345678',
        email: 'sara@gmail.com',
      ),
      () => MockClient((request) async {
        sent = request;
        return http.Response(
          jsonEncode({
            'data': {'id': 7},
            'meta': {'token': 'pending-token'},
          }),
          201,
        );
      }),
    );

    expect(result['success'], isTrue);
    expect(sent.url.path, '/v1/auth/register');
    final body = jsonDecode(sent.body) as Map<String, dynamic>;
    expect(body['role'], 0);
    expect(body.containsKey('password'), isFalse);
    expect(body, containsPair('phone', '201012345678'));
  });
}

class _RecordingAuth extends AuthRepository {
  final calls = <Map<String, String>>[];

  @override
  Future<Map<String, dynamic>> register({
    required String firstName,
    required String lastName,
    required String phone,
    required String email,
  }) async {
    calls.add({
      'firstName': firstName,
      'lastName': lastName,
      'phone': phone,
      'email': email,
    });
    return {'success': false, 'message': 'taken'};
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
