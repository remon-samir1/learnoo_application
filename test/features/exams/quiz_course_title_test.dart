import 'package:flutter_test/flutter_test.dart';
import 'package:learnoo/features/exams/domain/quiz_course_title.dart';

void main() {
  group('quizCourseTitle', () {
    test('reads a JSON:API course relation', () {
      expect(
        quizCourseTitle({
          'course': {
            'data': {
              'id': 240,
              'attributes': {'title': 'كورس تجربة'},
            },
          },
        }),
        'كورس تجربة',
      );
    });

    test('reads a flat course object and a flat title', () {
      expect(quizCourseTitle({'course': {'title': 'Anatomy'}}), 'Anatomy');
      expect(quizCourseTitle({'course_title': ' Physics '}), 'Physics');
    });

    test('takes the first of several courses', () {
      expect(
        quizCourseTitle({
          'courses': [
            {'attributes': {'title': 'First'}},
            {'attributes': {'title': 'Second'}},
          ],
        }),
        'First',
      );
    });

    test('falls back to the chapter course for a chapter exam', () {
      expect(
        quizCourseTitle({
          'chapter': {
            'data': {
              'attributes': {
                'course': {'data': {'attributes': {'name': 'Accounting'}}},
              },
            },
          },
        }),
        'Accounting',
      );
    });

    test('no course means no row', () {
      expect(quizCourseTitle(null), isNull);
      expect(quizCourseTitle({}), isNull);
      expect(quizCourseTitle({'course_title': '   '}), isNull);
      expect(quizCourseTitle({'course': {'attributes': {'title': ''}}}), isNull);
    });
  });
}
