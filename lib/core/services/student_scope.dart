import 'package:flutter/foundation.dart';

import '../network/api_client.dart';
import '../network/api_constants.dart';
import '../utils/coerce.dart';

/// Which courses the student may see, and which they have actually activated.
///
/// The web builds this once and filters everything through it — continue
/// watching, notes, library, live sessions, exams and the subject tree all get
/// narrowed to the student's own courses
/// (`app/[locale]/student/page.tsx`, `StudentExamsHub.tsx`). The app showed
/// whatever the API returned, so a student saw material for courses they were
/// not enrolled in.
///
/// Two sets, because they answer different questions:
///
///  * [visibleCourseIds] — every course the API returned for this student.
///    Used to hide content belonging to courses that are not theirs at all.
///  * [enrolledCourseIds] — the courses `GET /v1/course?activated=1` reports as
///    active, which is exactly the set the web's home page filters through.
class StudentScope {
  const StudentScope({
    required this.visibleCourseIds,
    required this.enrolledCourseIds,
    required this.courses,
    this.isLoaded = true,
  });

  const StudentScope.empty()
      : visibleCourseIds = const {},
        enrolledCourseIds = const {},
        courses = const [],
        isLoaded = false;

  final Set<String> visibleCourseIds;
  final Set<String> enrolledCourseIds;
  final List<dynamic> courses;

  /// `true` once the course list has actually come back from the API.
  ///
  /// This is what separates "the student is enrolled in nothing" — where the
  /// web renders empty sections — from "we could not reach the API", where the
  /// app keeps showing cached content rather than a blank home screen. Without
  /// the flag both look like an empty [enrolledCourseIds].
  final bool isLoaded;

  bool get isEmpty => courses.isEmpty;

  /// True when [courseId] is one the student has activated.
  bool isEnrolled(dynamic courseId) {
    final id = coerceId(courseId);
    return id != null && enrolledCourseIds.contains(id);
  }

  /// True when any of [courseIds] is activated.
  bool isAnyEnrolled(Iterable<dynamic> courseIds) {
    for (final id in courseIds) {
      if (isEnrolled(id)) return true;
    }
    return false;
  }

  /// True when the course is at least visible to this student.
  bool isVisible(dynamic courseId) {
    final id = coerceId(courseId);
    return id != null && visibleCourseIds.contains(id);
  }

  /// Keeps only items whose `course_id` is an activated course.
  ///
  /// [courseIdOf] pulls the course id out of one item; items with no course id
  /// are dropped, matching the web (an unattached note or file is not shown).
  List<T> filterByEnrolled<T>(
    Iterable<T> items,
    dynamic Function(T item) courseIdOf,
  ) {
    return items.where((item) => isEnrolled(courseIdOf(item))).toList();
  }
}

/// Loads and caches the student's course scope.
///
/// The result is memoised for [_ttl] so the six sections of the home screen
/// share one network call instead of each fetching the course list.
class StudentScopeService {
  StudentScopeService._internal();
  static final StudentScopeService _instance = StudentScopeService._internal();
  factory StudentScopeService() => _instance;

  static const Duration _ttl = Duration(minutes: 5);

  final ApiClient _api = ApiClient();

  StudentScope? _cached;
  DateTime? _loadedAt;
  Future<StudentScope>? _inFlight;

  /// Returns the cached scope when fresh, otherwise fetches it.
  ///
  /// Concurrent callers share one request.
  Future<StudentScope> load({bool forceRefresh = false}) {
    if (!forceRefresh && _cached != null && _loadedAt != null) {
      if (DateTime.now().difference(_loadedAt!) < _ttl) {
        return Future.value(_cached);
      }
    }

    if (_inFlight != null && !forceRefresh) return _inFlight!;

    final future = _fetch();
    _inFlight = future;
    return future.whenComplete(() => _inFlight = null);
  }

  /// The last loaded scope without touching the network.
  StudentScope get current => _cached ?? const StudentScope.empty();

  void invalidate() {
    _cached = null;
    _loadedAt = null;
  }

  /// The activated course ids, from the same call the web's student home makes:
  /// `GET /v1/course?activated=1`, keeping only rows whose `status` is active.
  ///
  /// Falls back to deriving enrolment from `is_locked` on [allCourses] when the
  /// call fails, so an API hiccup does not empty every section.
  Future<Set<String>> _fetchEnrolledIds(List<dynamic> allCourses) async {
    try {
      final payload = await _api.get(
        ApiConstants.courses,
        query: {'activated': 1},
        fallback: 'Failed to load activated courses',
      );

      final ids = <String>{};
      for (final course in unwrapList(payload)) {
        if (course is! Map) continue;
        final id = coerceId(course['id']);
        if (id == null) continue;

        final attrs = course['attributes'];
        final source = attrs is Map ? attrs : course;
        final status = source['status'];
        if (status != null && status != 1 && status != '1' && status != 'active') {
          continue;
        }

        ids.add(id);
      }
      return ids;
    } catch (e) {
      debugPrint('[StudentScope] activated course load failed: $e');
      final ids = <String>{};
      for (final course in allCourses) {
        if (course is! Map) continue;
        final id = coerceId(course['id']);
        if (id == null) continue;
        final attrs = course['attributes'];
        final source = attrs is Map ? attrs : course;
        if (coerceFlagOrNull(source['is_locked']) != true) ids.add(id);
      }
      return ids;
    }
  }

  Future<StudentScope> _fetch() async {
    try {
      // The full catalogue the student can see. Enrolment is a narrower set and
      // comes from its own call below.
      final payload = await _api.get(
        ApiConstants.courses,
        query: {'per_page': 500},
        fallback: 'Failed to load courses',
      );

      final courses = unwrapList(payload);
      final visible = <String>{};
      for (final course in courses) {
        final id = course is Map ? coerceId(course['id']) : null;
        if (id != null) visible.add(id);
      }

      final enrolled = await _fetchEnrolledIds(courses);

      final scope = StudentScope(
        visibleCourseIds: visible,
        enrolledCourseIds: enrolled,
        courses: courses,
      );

      _cached = scope;
      _loadedAt = DateTime.now();
      return scope;
    } catch (e) {
      debugPrint('[StudentScope] load failed: $e');
      // Keep whatever we had; an empty scope would blank the whole home screen.
      return _cached ?? const StudentScope.empty();
    }
  }
}
