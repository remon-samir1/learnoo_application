import 'package:flutter_test/flutter_test.dart';
import 'package:learnoo/features/course_content/data/course_repository.dart';

void main() {
  group('mergeActivatedWithCatalogue', () {
    final catalogue = [
      {
        'id': 240,
        'attributes': {
          'title': 'كورس تجربة',
          'thumbnail': 'https://api.learnoo.app/storage/courses/240.png',
          'description': 'From the catalogue',
          'status': 'draft',
        },
      },
      {
        'id': 12,
        'attributes': {'title': 'Not enrolled', 'thumbnail': 'x.png'},
      },
    ];

    test('missing cover is filled from the catalogue row', () {
      final merged = CourseRepository.mergeActivatedWithCatalogue(
        [
          {
            'id': '240',
            'attributes': {'title': 'كورس تجربة', 'thumbnail': null, 'status': 1},
          },
        ],
        catalogue,
      );
      final attrs = (merged.single as Map)['attributes'] as Map;
      expect(attrs['thumbnail'], 'https://api.learnoo.app/storage/courses/240.png');
      expect(attrs['description'], 'From the catalogue');
      // Enrolment fields of the activated row are kept.
      expect(attrs['status'], 1);
    });

    test('only activated courses are returned', () {
      final merged = CourseRepository.mergeActivatedWithCatalogue(
        [
          {'id': 240, 'attributes': <String, dynamic>{}},
        ],
        catalogue,
      );
      expect(merged, hasLength(1));
      expect((merged.single as Map)['id'], 240);
    });

    test('catalogue failure leaves the activated rows untouched', () {
      final rows = [
        {'id': 240, 'attributes': {'thumbnail': 'null'}},
      ];
      expect(CourseRepository.mergeActivatedWithCatalogue(rows, const []), rows);
    });
  });
}
