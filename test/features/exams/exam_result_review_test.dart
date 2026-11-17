import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learnoo/features/exams/domain/exam_review.dart';
import 'package:learnoo/features/exams/domain/exam_score.dart';
import 'package:learnoo/features/exams/models/quiz_models.dart';
import 'package:learnoo/features/exams/presentation/widgets/review_option_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// `GET /v1/quiz-attempts/{id}/result` as the backend sends it since the
/// 16 Nov fix: the graded questions under `data.quiz.questions` and the
/// student's rows, with the options the server graded, under `data.answers`.
Map<String, dynamic> _resultPayload() => {
      'data': {
        'quiz': {
          'id': 7,
          'title': 'أسئلة الحصة الأولى',
          'total_marks': 4.0,
          'passing_marks': 50.0,
          'questions': [
            {
              'id': '31',
              'type': 'quiz-questions',
              'attributes': {
                'quiz_id': 7,
                'text': 'يتكون الدخل من',
                'score': 1.0,
                'type': 'single_choice',
                'answers': [
                  {'id': '1', 'type': 'quiz-question-answers', 'attributes': {'text': 'الإنتاج', 'is_correct': false}},
                  {'id': '2', 'type': 'quiz-question-answers', 'attributes': {'text': 'الإنفاق الكلي', 'is_correct': true, 'reason': 'الدخل = الإنفاق'}},
                ],
              },
            },
            {
              'id': '32',
              'type': 'quiz-questions',
              'attributes': {
                'quiz_id': 7,
                'text': 'يعبر GDP عن',
                'score': 3.0,
                'type': 'multiple_choice',
                'answers': [
                  {'id': '3', 'type': 'quiz-question-answers', 'attributes': {'text': 'C, I, G', 'is_correct': true}},
                  {'id': '4', 'type': 'quiz-question-answers', 'attributes': {'text': 'C', 'is_correct': false}},
                  {'id': '5', 'type': 'quiz-question-answers', 'attributes': {'text': 'X - M', 'is_correct': true}},
                ],
              },
            },
          ],
        },
        'answers': [
          {'id': 90, 'quiz_question_id': 31, 'answer_text': 'الإنتاج', 'score_earned': 0.0, 'is_correct': false, 'selected_answer_ids': [1]},
          {'id': 91, 'quiz_question_id': 32, 'answer_text': 'C, I, G, X - M', 'score_earned': 3.0, 'is_correct': true, 'selected_answer_ids': [3, 5]},
        ],
        'attempt': {'id': 12, 'earned_marks': 3.0, 'percentage': 75.0, 'passed': true},
      },
    };

void main() {
  group('the result payload drives the review', () {
    final payload = _resultPayload();
    final questions = questionsFromResultPayload(payload);
    final rows = QuizAnswerReview.mapFromResultPayload(payload);

    test('reads the graded questions and the rows with their graded options', () {
      expect(questions.map((q) => q.questionId), [31, 32]);
      expect(questions.first.correctAnswers.map((a) => a.text), ['الإنفاق الكلي']);
      expect(rows['31']!.selectedAnswerIds, [1]);
      expect(rows['32']!.selectedAnswerIds, [3, 5]);
    });

    test("the server's graded options win over the device's picks and over splitting the text", () {
      final multi = questions[1]..selectedAnswerIds = [4];
      final review = buildQuestionReview(multi, rows['32']);
      // Split on commas the text would pick "C" too; the server read two whole options.
      expect(review.selected.map((a) => a.text), ['C, I, G', 'X - M']);
      expect(review.correct, isTrue);
      expect(review.usedLocalSelection, isFalse);
    });

    test('a wrong single choice shows the pick and the right option', () {
      final review = buildQuestionReview(questions.first, rows['31']);
      expect(review.correct, isFalse);
      expect(review.selected.map((a) => a.text), ['الإنتاج']);
      expect(review.correctAnswers.map((a) => a.text), ['الإنفاق الكلي']);
    });

    test('a row from an older backend (no selected_answer_ids) keeps the old order', () {
      final row = QuizAnswerReview.fromJson({'quiz_question_id': 31, 'answer_text': 'الإنتاج', 'is_correct': false});
      expect(row!.selectedAnswerIds, isNull);
      final review = buildQuestionReview(questions.first, row);
      expect(review.selected.map((a) => a.text), ['الإنتاج']);
    });
  });

  group('the score the result screen opens on', () {
    test('the finish response already carries the server grade', () {
      final summary = ExamScoreSummary.fromResultPayload({
        'attempt': {'data': {'id': '12', 'type': 'quiz-attempts', 'attributes': {'score': 3.0}}},
        'results': {'score': 3.0, 'total_score': 10.0, 'percentage': 30.0, 'passed': false},
        'quiz_info': {'title': 'x', 'passing_marks': 50.0, 'total_marks': 10.0},
      });
      expect(summary!.score, 3);
      expect(summary.total, 10);
      expect(summary.percentage, 30);
      expect(summary.passed, isFalse);
    });

    test('percentages print like the website: one decimal at most', () {
      expect(formatPercent(66.666), '66.7%');
      expect(formatPercent(50), '50%');
      expect(formatPercent(0), '0%');
      expect(formatPercent(100), '100%');
    });
  });

  group('ReviewAnswerSummary', () {
    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      await EasyLocalization.ensureInitialized();
    });

    Future<void> pump(WidgetTester tester, ExamQuestionReview review) async {
      await tester.pumpWidget(
        EasyLocalization(
          supportedLocales: const [Locale('en')],
          startLocale: const Locale('en'),
          saveLocale: false,
          path: 'assets/translations',
          assetLoader: const _FileTranslations(),
          child: Builder(
            builder: (context) => MaterialApp(
              locale: context.locale,
              supportedLocales: context.supportedLocales,
              localizationsDelegates: context.localizationDelegates,
              home: Scaffold(body: ReviewAnswerSummary(review: review)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Color boxBorder(WidgetTester tester, String key) {
      final box = tester.widget<Container>(find.byKey(ValueKey(key)));
      return ((box.decoration! as BoxDecoration).border! as Border).top.color;
    }

    testWidgets('a wrong pick in red, the right answer beneath it in green', (tester) async {
      final questions = questionsFromResultPayload(_resultPayload());
      final rows = QuizAnswerReview.mapFromResultPayload(_resultPayload());
      await pump(tester, buildQuestionReview(questions.first, rows['31']));

      expect(find.text('Your answer'), findsOneWidget);
      expect(find.text('الإنتاج'), findsOneWidget);
      expect(find.text('Correct answer'), findsOneWidget);
      expect(find.text('الإنفاق الكلي'), findsOneWidget);
      expect(find.text('N/A'), findsNothing);
      expect(tester.getTopLeft(find.byKey(const ValueKey('review-correct-answer'))).dy,
          greaterThan(tester.getTopLeft(find.byKey(const ValueKey('review-your-answer'))).dy));
      expect(boxBorder(tester, 'review-your-answer').r, greaterThan(boxBorder(tester, 'review-your-answer').g));
      expect(boxBorder(tester, 'review-correct-answer').g, greaterThan(boxBorder(tester, 'review-correct-answer').r));
    });

    testWidgets('a right pick is green and needs no correction', (tester) async {
      final questions = questionsFromResultPayload(_resultPayload());
      final rows = QuizAnswerReview.mapFromResultPayload(_resultPayload());
      await pump(tester, buildQuestionReview(questions[1], rows['32']));

      expect(find.text('Your answer (correct)'), findsOneWidget);
      expect(find.text('C, I, G'), findsOneWidget);
      expect(find.text('X - M'), findsOneWidget);
      expect(find.byKey(const ValueKey('review-correct-answer')), findsNothing);
    });

    testWidgets('with the right options hidden, no placeholder is printed', (tester) async {
      final question = QuizQuestion.fromJson({
        'id': '40',
        'attributes': {
          'text': 'q',
          'type': 'single_choice',
          'score': 1,
          'answers': [
            {'id': '8', 'attributes': {'text': 'A'}},
            {'id': '9', 'attributes': {'text': 'B'}},
          ],
        },
      });
      final row = QuizAnswerReview.fromJson({'quiz_question_id': 40, 'answer_text': 'A', 'is_correct': false, 'selected_answer_ids': [8]});
      await pump(tester, buildQuestionReview(question, row));

      expect(find.text('A'), findsOneWidget);
      expect(find.byKey(const ValueKey('review-correct-answer')), findsNothing);
      expect(find.text('N/A'), findsNothing);
    });
  });
}

class _FileTranslations extends AssetLoader {
  const _FileTranslations();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(File('$path/${locale.languageCode}.json').readAsStringSync())
          as Map<String, dynamic>;
}
