import 'package:flutter_test/flutter_test.dart';
import 'package:learnoo/features/exams/models/quiz_models.dart';

/// Regression coverage for the course-details "no exams" bug.
///
/// The website's own `examAttrsForQuizPolicy` reads
/// `attributes.field ?? topLevel.field` for `remaining_attempts`,
/// `current_attempts`, `max_attempts`/`maxAttempts` and `has_activation` —
/// proof that `GET /v1/course/{id}`'s nested `attributes.exams[]` can carry
/// those fields at the top level of the exam object instead of inside
/// `attributes`. `Quiz.fromJson` only ever read `attributes`, so an exam
/// shaped that way parsed with `quizId == 0` (every such exam collided on the
/// same map key) and lost its gating fields — the course-details Exams tab
/// showed "No exams available" even though the web showed the exam fine.
void main() {
  group('Quiz.fromJson top-level fallback', () {
    test('falls back to the top-level id when attributes has none', () {
      final quiz = Quiz.fromJson({
        'id': '58',
        'type': 'quizzes',
        'attributes': {
          'title': 'اختبار تجربة',
          'type': 'exam',
          // No 'id' key here — the exact shape that used to zero every exam.
          'duration': 2,
          'total_marks': 100,
          'passing_marks': 50,
          'start_time': '2026-09-01T00:00:00Z',
          'end_time': '2026-09-18T15:45:00Z',
          'course_id': 240,
        },
      });

      expect(quiz.id, '58');
      expect(quiz.quizId, 58,
          reason: 'quizId must fall back to the top-level resource id');
      expect(quiz.title, 'اختبار تجربة');
      expect(quiz.courseId, 240);
    });

    test('reads gating fields from the top level when attributes omits them',
        () {
      final quiz = Quiz.fromJson({
        'id': '58',
        'type': 'quizzes',
        'attributes': {
          'id': 58,
          'title': 'اختبار تجربة',
          'course_id': 240,
        },
        // Exactly the shape `examAttrsForQuizPolicy` defends against on the
        // web: gating fields riding on the top-level exam object.
        'remaining_attempts': 98,
        'current_attempts': 2,
        'max_attempts': 100,
        'has_activation': true,
      });

      expect(quiz.remainingAttempts, 98);
      expect(quiz.currentAttempts, 2);
      expect(quiz.maxAttempts, 100);
      expect(quiz.hasActivation, isTrue);
    });

    test('nested attributes still win over the top level when both are present',
        () {
      final quiz = Quiz.fromJson({
        'id': '58',
        'type': 'quizzes',
        'attributes': {
          'id': 58,
          'title': 'From attributes',
          'type': 'homework',
        },
        'title': 'From top level',
        'type': 'quizzes',
      });

      expect(quiz.title, 'From attributes');
      expect(quiz.type, 'homework',
          reason:
              "the JSON:API envelope's resource type must never leak into the exam's own type");
    });

    test('two exams with distinct ids never collapse onto the same key', () {
      final a = Quiz.fromJson({
        'id': '1',
        'type': 'quizzes',
        'attributes': {'title': 'First'},
      });
      final b = Quiz.fromJson({
        'id': '2',
        'type': 'quizzes',
        'attributes': {'title': 'Second'},
      });

      final merged = <String, Quiz>{};
      merged[a.id] = a;
      merged[b.id] = b;

      expect(merged, hasLength(2));
      expect(merged['1']!.title, 'First');
      expect(merged['2']!.title, 'Second');
    });
  });
}
