import 'package:flutter_test/flutter_test.dart';
import 'package:learnoo/core/services/student_scope.dart';
import 'package:learnoo/features/course_content/data/live_room_repository.dart';
import 'package:learnoo/features/course_content/data/models/live_room.dart';

/// One row of `GET /v1/live-room`, in the shape the backend's
/// `LiveRoomResource` sends (captured from a local backend, 16 Nov 2026).
Map<String, dynamic> apiRoom({
  required String id,
  required String title,
  required String isPublic,
  String status = 'live',
  List<int> courseIds = const [1],
  String startedAt = '2026-11-16T22:33:11+02:00',
  String endedAt = '2026-11-17T01:38:11+02:00',
}) {
  Map<String, dynamic> course(int cid) => {
        'id': '$cid',
        'type': 'courses',
        'attributes': {'title': 'مادة $cid'},
      };
  return {
    'id': id,
    'type': 'live-rooms',
    'attributes': {
      'title': title,
      'can_view': true,
      'has_activation': false,
      'description': null,
      'user': {
        'data': {
          'id': 'u1',
          'type': 'users',
          'attributes': {'full_name': 'E2E Admin'},
        },
      },
      'course': courseIds.isEmpty ? null : {'data': course(courseIds.first)},
      'course_ids': courseIds,
      'courses': [for (final c in courseIds) course(c)],
      'started_at': startedAt,
      'ended_at': endedAt,
      'publication_status': 'active',
      'max_students': 0,
      'max_join_time': null,
      'enable_chat': true,
      'enable_recording': true,
      'is_public': isPublic,
      'status': status,
      'created_at': '2026-11-16T22:38:11+02:00',
      'updated_at': '2026-11-16T22:38:11+02:00',
    },
  };
}

LiveRoom room(Map<String, dynamic> json) => LiveRoom.fromJson(json);

StudentScope scope(Set<String> enrolled) => StudentScope(
      visibleCourseIds: enrolled,
      enrolledCourseIds: enrolled,
      courses: const [],
    );

void main() {
  group('LiveRoom.fromJson on the backend payload', () {
    test('a public course session', () {
      final r = room(apiRoom(id: '1', title: 'بث عام', isPublic: 'true'));
      expect(r.id, '1');
      expect(r.title, 'بث عام');
      expect(r.isPublic, 'true');
      expect(r.status, SessionStatus.now);
      expect(r.courseIds, ['1']);
      expect(r.courseTitles, ['مادة 1']);
      expect(r.instructorName, 'E2E Admin');
      // Same instant the website formats with `new Date(started_at)`.
      expect(r.startedAtValue, DateTime.utc(2026, 11, 16, 20, 33, 11));
      expect(r.endedAt, DateTime.utc(2026, 11, 16, 23, 38, 11));
    });

    test('status comes from the API only, like the website', () {
      SessionStatus of(String s) =>
          room(apiRoom(id: '1', title: 't', isPublic: 'true', status: s))
              .status;
      expect(of('live'), SessionStatus.now);
      expect(of('upcoming'), SessionStatus.upcoming);
      expect(of('ended'), SessionStatus.recorded);
      expect(of('draft'), SessionStatus.unknown);
    });

    test('a session linked to several courses keeps every course id', () {
      final r = room(apiRoom(
          id: '2', title: 't', isPublic: 'included', courseIds: [3, 1]));
      expect(r.courseIds.toSet(), {'1', '3'});
    });
  });

  group('Live tab (website live sessions page)', () {
    final public = room(apiRoom(id: '1', title: 'عام', isPublic: 'true'));
    final included =
        room(apiRoom(id: '2', title: 'مضمن', isPublic: 'included'));
    final private = room(apiRoom(id: '3', title: 'خاص', isPublic: 'false'));
    final otherFaculty = room(
        apiRoom(id: '4', title: 'كلية أخرى', isPublic: 'true', courseIds: [9]));
    final noCourse =
        room(apiRoom(id: '5', title: 'عام بدون كورس', isPublic: 'true', courseIds: []));

    test('shows every session of the student\'s faculty tree, enrolled or not',
        () {
      const access = LiveRoomAccessContext(
        facultyCourseIds: {'1', '2'},
        enrolledCourseIds: {},
      );
      final visible = access
          .filterVisible([public, included, private, otherFaculty, noCourse]);
      expect(visible.map((r) => r.id), ['1', '2', '3', '5']);
    });

    test('a public session can be joined without activating its course', () {
      const access = LiveRoomAccessContext(
        facultyCourseIds: {'1'},
        enrolledCourseIds: {},
      );
      expect(access.accessFor(public), LiveRoomAccess.available);
      expect(access.accessFor(included), LiveRoomAccess.courseNotEnrolled);
      expect(access.accessFor(private), LiveRoomAccess.lockedPrivate);
    });

    test('a course session opens once the course is activated', () {
      const access = LiveRoomAccessContext(
        facultyCourseIds: {'1'},
        enrolledCourseIds: {'1'},
      );
      expect(access.accessFor(included), LiveRoomAccess.available);
    });

    test('without a faculty tree every returned session is shown', () {
      const access = LiveRoomAccessContext.empty();
      expect(access.filterVisible([public, otherFaculty]).length, 2);
    });
  });

  group('Home "upcoming live classes" (website student home)', () {
    final public = room(apiRoom(id: '1', title: 'عام', isPublic: 'true'));
    final included =
        room(apiRoom(id: '2', title: 'مضمن', isPublic: 'included'));
    final otherCourse = room(
        apiRoom(id: '3', title: 'كورس آخر', isPublic: 'true', courseIds: [9]));
    final noCourse =
        room(apiRoom(id: '4', title: 'بدون كورس', isPublic: 'true', courseIds: []));

    test('keeps the sessions of the student\'s activated courses only', () {
      final home = liveRoomsForHome(
          [public, included, otherCourse, noCourse], scope({'1'}));
      expect(home.map((r) => r.id), ['1', '2']);
    });

    test('a student with no activated course sees none, like the website', () {
      expect(liveRoomsForHome([public, included], scope({})), isEmpty);
    });

    test('shows everything until the student\'s courses have loaded', () {
      expect(
        liveRoomsForHome([public, otherCourse], const StudentScope.empty())
            .length,
        2,
      );
    });
  });
}
