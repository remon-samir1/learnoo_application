/// Which courses a student may see in "My Courses" and on the home page.
library;
///
/// The dashboard saves a course as a draft (`status` 0) until it is ready.
/// The website's student pages never render a draft course — its community feed
/// drops everything belonging to `status === 0` — so the app hides them too.

Map _attributes(dynamic course) {
  if (course is! Map) return const {};
  final attrs = course['attributes'];
  return attrs is Map ? attrs : course;
}

/// A course the dashboard has not published yet.
bool courseIsDraft(dynamic course) {
  final status = _attributes(course)['status'];
  if (status == null) return false;
  if (status is num) return status == 0;
  final text = status.toString().trim().toLowerCase();
  if (text.isEmpty) return false;
  return text == '0' || text == 'draft' || text == 'inactive';
}

/// The student's courses, without the ones the dashboard keeps hidden.
List<dynamic> visibleStudentCourses(List<dynamic> courses) =>
    courses.where((course) => !courseIsDraft(course)).toList();
