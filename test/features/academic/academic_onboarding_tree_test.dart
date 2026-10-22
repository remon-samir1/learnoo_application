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

  test('option images come from attributes.image like the web picker', () {
    final faculties = [
      {
        'id': 30,
        'attributes': {
          'name': 'Faculty A',
          'image': '/storage/faculties/a.png',
          'parent': {
            'data': {
              'id': 7,
              'attributes': {
                'name': 'Center A',
                'image': 'https://api.learnoo.app/storage/centers/a.png',
                'parent_id': 1,
              },
            },
          },
        },
      },
      {
        'id': 31,
        'attributes': {
          'name': 'Faculty B',
          'image': 'null',
          'parent': {
            'data': {
              'id': 7,
              'attributes': {'name': 'Center A', 'parent_id': 1},
            },
          },
        },
      },
    ];

    final center = centerOptionsForUniversity(faculties, 1).single;
    expect(center.imageUrl, 'https://api.learnoo.app/storage/centers/a.png');

    final options = facultyOptionsForCenter(faculties, center.id);
    expect(
      options.firstWhere((option) => option.id == '30').imageUrl,
      endsWith('/storage/faculties/a.png'),
    );
    // "null" arrives as a string on records without a picture.
    expect(options.firstWhere((option) => option.id == '31').imageUrl, isNull);
  });

  test('entityImageUrl reads flat and media-object shapes', () {
    expect(
      entityImageUrl({
        'id': 1,
        'name': 'Flat center',
        'image': 'https://cdn.learnoo.app/c.png',
      }),
      'https://cdn.learnoo.app/c.png',
    );
    expect(
      entityImageUrl({
        'id': 2,
        'attributes': {
          'image': {
            'data': {
              'attributes': {'url': 'https://cdn.learnoo.app/u.png'},
            },
          },
        },
      }),
      'https://cdn.learnoo.app/u.png',
    );
    expect(entityImageUrl({'id': 3, 'attributes': {}}), isNull);
    expect(entityImageUrl('not a map'), isNull);
  });
}
