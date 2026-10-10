import 'package:flutter_test/flutter_test.dart';
import 'package:learnoo/features/course_content/domain/library_material.dart';

void main() {
  test('course-scoped response keeps multi-course books and omitted relations', () {
    final multiCourse = {
      'id': '1',
      'attributes': {'title': 'test', 'course_ids': [174, 175], 'is_publish': true},
    };
    final withoutRelation = {
      'id': '2',
      'attributes': {'title': 'Another book'},
    };
    final unpublished = {
      'id': '3',
      'attributes': {'course_ids': [174], 'is_publish': false},
    };
    expect(
      publishedCourseLibraryItems([multiCourse, withoutRelation, unpublished]),
      [multiCourse, withoutRelation],
    );
  });
}
