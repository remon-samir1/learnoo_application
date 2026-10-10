import 'package:flutter_test/flutter_test.dart';
import 'package:learnoo/features/academic/data/academic_scope_service.dart';
import 'package:learnoo/features/auth/domain/student_profile.dart';

void main() {
  group('AcademicSelection.differsFrom', () {
    final profile = StudentProfile.fromAttributes({
      'university': {
        'data': {'id': 1},
      },
      'faculty': {
        'data': {'id': 30},
      },
      'centers': [
        {'id': 7},
      ],
      'department_id': 44,
    });

    final loaded = AcademicSelection.fromProfile(profile);

    test('reads ids from the /me relation shapes', () {
      expect(loaded.universityId, '1');
      expect(loaded.centerId, '7');
      expect(loaded.facultyId, '30');
      expect(loaded.departmentId, '44');
    });

    test('same ids are not a change', () {
      const same = AcademicSelection(
        universityId: '1',
        centerId: '7',
        facultyId: '30',
        departmentId: '44',
      );
      expect(same.differsFrom(loaded), isFalse);
    });

    test('a new university, centre or faculty is a change', () {
      expect(
        const AcademicSelection(
          universityId: '2',
          centerId: '7',
          facultyId: '30',
          departmentId: '44',
        ).differsFrom(loaded),
        isTrue,
      );
      expect(
        const AcademicSelection(
          universityId: '1',
          centerId: '8',
          facultyId: '30',
          departmentId: '44',
        ).differsFrom(loaded),
        isTrue,
      );
      expect(
        const AcademicSelection(
          universityId: '1',
          centerId: '7',
          facultyId: '31',
          departmentId: '44',
        ).differsFrom(loaded),
        isTrue,
      );
    });

    test('a cleared department is a change', () {
      expect(
        const AcademicSelection(
          universityId: '1',
          centerId: '7',
          facultyId: '30',
        ).differsFrom(loaded),
        isTrue,
      );
    });

    test('blank and null ids compare equal', () {
      expect(
        const AcademicSelection(universityId: ' ', centerId: '')
            .differsFrom(const AcademicSelection()),
        isFalse,
      );
    });
  });
}
