import 'package:flutter_test/flutter_test.dart';
import 'package:learnoo/features/academic/domain/academic_tree.dart';

void main() {
  test('university filters centers and each center filters its faculties', () {
    final faculties = [
      {
        'id': 30,
        'attributes': {
          'name': 'Faculty A',
          'parent': {
            'data': {
              'id': 7,
              'attributes': {
                'name': 'Center A',
                'parent': {
                  'data': {'id': '1'},
                },
              },
            },
          },
        },
      },
      {
        'id': 31,
        'attributes': {
          'name': 'Faculty B',
          'parent_id': '8',
          'parent': {
            'data': {
              'id': 8,
              'attributes': {'name': 'Center B', 'parent_id': 2},
            },
          },
        },
      },
    ];

    final centers = centerOptionsForUniversity(faculties, 1);
    expect(centers.map((option) => option.id), ['7']);
    expect(centers.single.label, 'Center A');
    final options = facultyOptionsForCenter(faculties, centers.single.id);
    expect(options.map((option) => option.id), ['30']);
    expect(options.single.label, 'Faculty A');
    expect(centerOptionsForUniversity(faculties, 3), isEmpty);
    expect(facultyOptionsForCenter(faculties, 9), isEmpty);
  });
}
