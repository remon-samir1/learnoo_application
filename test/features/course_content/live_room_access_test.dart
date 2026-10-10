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
}
