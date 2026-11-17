import 'package:flutter_test/flutter_test.dart';
import 'package:learnoo/features/course_content/data/models/live_room.dart';

void main() {
  LiveRoom room(String visibility, {bool activated = false, String status = 'live'}) => LiveRoom.fromJson({
    'id': '1',
    'attributes': {'is_public': visibility, 'has_activation': activated, 'status': status, 'course_ids': ['10']},
  });
  for (final status in ['live', 'upcoming', 'ended']) {
    test('Private $status session requires its own activation even in an enrolled course', () {
      expect(room('private', status: status).accessFor({'10'}), LiveRoomAccess.lockedPrivate);
      expect(room('private', status: status, activated: true).accessFor({'10'}), LiveRoomAccess.available);
    });
  }
  test('Public and included rooms retain their access rules', () {
    expect(room('public').accessFor({}), LiveRoomAccess.available);
    expect(room('included').accessFor({}), LiveRoomAccess.courseNotEnrolled);
    expect(room('included').accessFor({'10'}), LiveRoomAccess.available);
    expect(room('false').accessFor({'10'}), LiveRoomAccess.lockedPrivate);
  });
  test('A session opened by its link knows whether the student may join (can_view)', () {
    LiveRoom withCanView(Object? value) => LiveRoom.fromJson({
      'id': '1',
      'attributes': {'is_public': 'false', 'can_view': ?value},
    });
    expect(withCanView(false).canView, isFalse);
    expect(withCanView(true).canView, isTrue);
    // Older payloads without the flag only came for rooms the student could open.
    expect(withCanView(null).canView, isTrue);
    expect(LiveRoom.fromJson(withCanView(false).toJson()).canView, isFalse);
  });
}
