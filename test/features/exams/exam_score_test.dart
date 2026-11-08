import 'package:flutter_test/flutter_test.dart';
import 'package:learnoo/features/exams/domain/exam_score.dart';

/// The app used to grade, total and judge an exam entirely on the device, and
/// called the student passed at a hard-coded `percentage >= 60`. The website
/// reads `GET /v1/quiz-attempts/{id}/result` and applies the precedence in
/// `src/lib/student-exam-score.ts` + `ExamResultView.tsx`. These lock that
/// precedence down.
void main() {
  group('clampPercentage', () {
    test('squeezes into 0..100', () {
      expect(clampPercentage(50), 50);
      expect(clampPercentage(-12), 0);
      expect(clampPercentage(140), 100);
      expect(clampPercentage(99.5), 99.5);
    });

    test('accepts numeric strings and rejects junk', () {
      expect(clampPercentage('72.5'), 72.5);
      expect(clampPercentage('abc'), isNull);
      expect(clampPercentage(null), isNull,
          reason: 'an absent percentage must fall through to score / total');
      expect(clampPercentage(double.nan), isNull);
    });
  });

  group('percentageFromScore', () {
    test('computes and clamps', () {
      expect(percentageFromScore(8, 10), 80);
      expect(percentageFromScore(12, 10), 100);
      expect(percentageFromScore('5', '20'), 25);
    });

    test('refuses a zero or missing total', () {
      expect(percentageFromScore(5, 0), isNull);
      expect(percentageFromScore(5, null), isNull);
      expect(percentageFromScore(null, 10), isNull);
      expect(percentageFromScore(5, -4), isNull);
    });
  });

  group('readPercentageWithScoreFallback', () {
    test("the server's percentage wins", () {
      expect(readPercentageWithScoreFallback(42, 1, 10), 42);
    });

    test('falls back to score / total only when it is unusable', () {
      expect(readPercentageWithScoreFallback(null, 1, 10), 10);
      expect(readPercentageWithScoreFallback('', 1, 10), 0,
          reason: "mirrors JS Number('') === 0, as the website does");
      expect(readPercentageWithScoreFallback('oops', 3, 4), 75);
      expect(readPercentageWithScoreFallback(null, null, null), isNull);
    });
  });

  group('isExamPassed', () {
    test('a boolean from the backend always wins', () {
      expect(isExamPassed(true, 10, 90), isTrue);
      expect(isExamPassed(false, 100, 50), isFalse);
    });

    test('otherwise compares the percentage against the threshold', () {
      expect(isExamPassed(null, 60, 50), isTrue);
      expect(isExamPassed(null, 50, 50), isTrue);
      expect(isExamPassed(null, 49.9, 50), isFalse);
    });

    test('a non-boolean "passed" is not a verdict', () {
      expect(isExamPassed(1, 10, 50), isFalse,
          reason: "the website only honours `typeof passed === 'boolean'`");
      expect(isExamPassed('true', 90, 50), isTrue,
          reason: 'it falls through to the percentage comparison instead');
    });

    test('no threshold and no backend flag means failed', () {
      expect(isExamPassed(null, 100, null), isFalse);
      expect(isExamPassed(null, null, 50), isFalse);
    });
  });

  group('formatTimeTakenForDisplay', () {
    test('hides invalid and negative values', () {
      expect(formatTimeTakenForDisplay(12), 12);
      expect(formatTimeTakenForDisplay('7.5'), 7.5);
      expect(formatTimeTakenForDisplay(-1), isNull);
      expect(formatTimeTakenForDisplay(null), isNull);
      expect(formatTimeTakenForDisplay('later'), isNull);
    });
  });

  group('ExamScoreSummary.fromResultPayload', () {
    test('reads the flat `results` + `quiz_info` shape', () {
      final summary = ExamScoreSummary.fromResultPayload({
        'results': {
          'score': 18,
          'total_score': 20,
          'percentage': 90,
          'passed': true,
          'time_taken': 11,
          'finished_at': '2026-03-02T10:15:00Z',
        },
        'quiz_info': {
          'title': '  اختبار الوحدة الأولى  ',
          'total_marks': 20,
          'passing_marks': 50,
        },
      });

      expect(summary, isNotNull);
      expect(summary!.score, 18);
      expect(summary.total, 20);
      expect(summary.percentage, 90);
      expect(summary.passingPercentage, 50);
      expect(summary.passed, isTrue);
      expect(summary.timeTaken, 11);
      expect(summary.finishedAt, '2026-03-02T10:15:00Z');
      expect(summary.quizTitle, 'اختبار الوحدة الأولى');
    });

    test('falls back through data.attempt / data.quiz', () {
      final summary = ExamScoreSummary.fromResultPayload({
        'data': {
          'attempt': {'earned_marks': 6},
          'quiz': {
            'attributes': {'total_marks': 8, 'passing_marks': 70},
          },
        },
      });

      expect(summary!.score, 6);
      expect(summary.total, 8);
      expect(summary.percentage, 75);
      expect(summary.passingPercentage, 70);
      expect(summary.passed, isTrue);
    });

    test('`attempt.data` is read before a bare `attempt`', () {
      final summary = ExamScoreSummary.fromResultPayload({
        'attempt': {
          'data': {'score': 3, 'total_score': 4},
        },
      });
      expect(summary!.percentage, 75);
    });

    test("the backend's `passed: false` beats a perfect percentage", () {
      final summary = ExamScoreSummary.fromResultPayload({
        'results': {'score': 10, 'total_score': 10, 'passed': false},
        'quiz_info': {'passing_marks': 50},
      });
      expect(summary!.percentage, 100);
      expect(summary.passed, isFalse);
    });

    test('a quiz without numeric passing marks has no threshold', () {
      final summary = ExamScoreSummary.fromResultPayload({
        'results': {'score': 10, 'total_score': 10},
        'quiz_info': {'passing_marks': '50'},
      });
      expect(summary!.passingPercentage, isNull,
          reason: "the website requires `typeof passing_marks === 'number'`");
      expect(summary.passed, isFalse);
    });

    test('the in-memory quiz only fills in what the payload lacks', () {
      final withPayloadMarks = ExamScoreSummary.fromResultPayload(
        {
          'results': {'score': 5, 'total_score': 10},
          'quiz_info': {'passing_marks': 40},
        },
        fallbackPassingMarks: 90,
      );
      expect(withPayloadMarks!.passingPercentage, 40);
      expect(withPayloadMarks.passed, isTrue);

      final withoutPayloadMarks = ExamScoreSummary.fromResultPayload(
        {
          'results': {'score': 5, 'total_score': 10},
        },
        fallbackPassingMarks: 90,
      );
      expect(withoutPayloadMarks!.passingPercentage, 90);
      expect(withoutPayloadMarks.passed, isFalse);
    });

    test('a JSON:API attempt resource still yields its figures', () {
      final summary = ExamScoreSummary.fromResultPayload({
        'data': {
          'attempt': {
            'id': '12',
            'type': 'quiz-attempts',
            'attributes': {'score': 4, 'total_score': 5, 'passed': true},
          },
        },
      });
      expect(summary!.percentage, 80);
      expect(summary.passed, isTrue);
    });

    test('returns null when there is nothing to read', () {
      expect(ExamScoreSummary.fromResultPayload(null), isNull);
      expect(ExamScoreSummary.fromResultPayload('nope'), isNull);
      expect(ExamScoreSummary.fromResultPayload({'data': {}}), isNull);
    });

    test('hasServerFigures is false for an empty attempt', () {
      final summary = ExamScoreSummary.fromResultPayload({
        'quiz_info': {'title': 'Only a title'},
      });
      expect(summary!.hasServerFigures, isFalse);
    });
  });

  group('formatMarks', () {
    test('keeps whole marks whole', () {
      expect(formatMarks(18), '18');
      expect(formatMarks(18.5), '18.5');
      expect(formatMarks(null), '—');
    });
  });
}
