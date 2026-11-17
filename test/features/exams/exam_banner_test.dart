import 'dart:convert';

import 'package:easy_localization/src/localization.dart';
import 'package:easy_localization/src/translations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learnoo/core/network/api_constants.dart';
import 'package:learnoo/features/exams/models/quiz_models.dart';
import 'package:learnoo/features/exams/presentation/screens/exam_notice_screen.dart';
import 'package:learnoo/features/exams/presentation/widgets/exam_banner.dart';

Quiz _quiz({Object? banner}) => Quiz.fromJson({
      'id': '7',
      'type': 'quizzes',
      'attributes': {
        'id': 7,
        'title': 'امتحان الفصل الأول',
        'type': 'exam',
        'duration': 30,
        'max_attempts': 2,
        'banner': banner,
      },
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Quiz.bannerUrl', () {
    test('reads the absolute banner URL the API sends', () {
      expect(
        _quiz(banner: 'https://api.learnoo.app/storage/quizzes/b.jpg').bannerUrl,
        'https://api.learnoo.app/storage/quizzes/b.jpg',
      );
    });

    test('prefixes a server-relative path with the API origin', () {
      expect(
        _quiz(banner: '/storage/quizzes/b.jpg').bannerUrl,
        '${ApiConstants.baseUrl}/storage/quizzes/b.jpg',
      );
    });

    test('is null when the exam has no banner', () {
      expect(_quiz().bannerUrl, isNull);
      expect(_quiz(banner: '').bannerUrl, isNull);
      expect(Quiz.fromJson({'id': '1', 'attributes': {'title': 'x'}}).bannerUrl, isNull);
    });
  });

  group('examBannerHeight', () {
    test('is a 4:1 strip in portrait', () {
      // iPhone 17 Pro portrait: 402 wide, minus the exam's 20 pt side padding.
      expect(examBannerHeight(362, 874), 90.5);
    });

    test('is capped at a fifth of the screen in landscape', () {
      expect(examBannerHeight(834, 402), closeTo(80.4, 0.001));
    });
  });

  group('ExamBanner', () {
    Future<void> pumpAt(WidgetTester tester, Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [ExamBanner(url: 'https://example.test/banner.jpg')],
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('fills the width at 4:1 in portrait', (tester) async {
      await pumpAt(tester, const Size(402, 874));
      expect(
        tester.getSize(find.byKey(const ValueKey('exam-banner'))),
        const Size(362, 90.5),
      );
    });

    testWidgets('keeps room for the question in landscape', (tester) async {
      await pumpAt(tester, const Size(874, 402));
      final finder = find.byKey(const ValueKey('exam-banner'));
      final size = tester.getSize(finder);
      // Height capped at a fifth of the screen; width follows at 4:1, centred.
      expect(size.height, closeTo(80.4, 0.001));
      expect(size.width, closeTo(321.6, 0.001));
      expect(tester.getCenter(finder).dx, 437);
    });
  });

  group('ExamNoticeScreen', () {
    late Translations translations;
    setUpAll(() async {
      final raw = await rootBundle.loadString('assets/translations/ar.json');
      translations = Translations(json.decode(raw) as Map<String, dynamic>);
    });
    setUp(() => Localization.load(
          const Locale('ar'),
          translations: translations,
          fallbackTranslations: translations,
        ));

    testWidgets('shows the banner above the exam details', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: ExamNoticeScreen(
          quiz: _quiz(banner: 'https://example.test/banner.jpg'),
        ),
      ));
      expect(find.byType(ExamBanner), findsOneWidget);
      expect(
        tester.getTopLeft(find.byType(ExamBanner)).dy,
        lessThan(tester.getTopLeft(find.text('امتحان الفصل الأول')).dy),
      );
    });

    testWidgets('looks exactly as before without a banner', (tester) async {
      await tester.pumpWidget(MaterialApp(home: ExamNoticeScreen(quiz: _quiz())));
      expect(find.byType(ExamBanner), findsNothing);
      expect(find.text('امتحان الفصل الأول'), findsOneWidget);
    });
  });
}
