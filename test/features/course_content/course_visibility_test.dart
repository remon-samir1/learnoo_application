import 'package:flutter_test/flutter_test.dart';
import 'package:learnoo/features/course_content/domain/course_visibility.dart';

Map<String, dynamic> course(Map<String, dynamic> attributes) => {
      'id': '240',
      'attributes': attributes,
    };

void main() {
  group('draft courses', () {
    test('status 0 is a draft, in every form the API sends', () {
      expect(courseIsDraft(course({'status': 0})), isTrue);
      expect(courseIsDraft(course({'status': '0'})), isTrue);
      expect(courseIsDraft(course({'status': 'draft'})), isTrue);
    });

    test('published courses are kept', () {
      expect(courseIsDraft(course({'status': 1})), isFalse);
      expect(courseIsDraft(course({'status': 'active'})), isFalse);
      expect(courseIsDraft(course({})), isFalse);
    });

    test('the list keeps only what a student may see', () {
      final list = [
        course({'title': 'Live one', 'status': 1}),
        course({'title': 'Hidden', 'status': 0}),
      ];
      final visible = visibleStudentCourses(list);
      expect(visible, hasLength(1));
      expect((visible.single as Map)['attributes']['title'], 'Live one');
    });
  });
}
