import '../../../../core/utils/coerce.dart';

/// A scheduled or running live session.
///
/// Status now comes from the API's own `status` field first, falling back to
/// the timestamp comparison the app used to rely on exclusively. The web reads
/// the same field (`src/lib/student-live-room.ts`), so a session an instructor
/// has actually started shows as live in both places even when the clock says
/// otherwise.
class LiveRoom {
  final String id;
  final String title;
  final String description;
  final String instructorFirstName;
  final String instructorLastName;
  final String instructorEmail;
  final String? courseId;
  final String? courseTitle;
  final String? courseThumbnail;

  /// Every course this session belongs to — the API may attach several.
  final List<String> courseIds;

  /// Raw `attributes.status`, lower-cased. Empty when the API omits it.
  final String rawStatus;

  final DateTime startedAt;
  final DateTime endedAt;
  final DateTime maxJoinTime;
  final int maxStudents;
  final DateTime createdAt;
  final DateTime updatedAt;

  LiveRoom({
    required this.id,
    required this.title,
    required this.description,
    required this.instructorFirstName,
    required this.instructorLastName,
    required this.instructorEmail,
    this.courseId,
    this.courseTitle,
    this.courseThumbnail,
    this.courseIds = const [],
    this.rawStatus = '',
    required this.startedAt,
    required this.endedAt,
    required this.maxJoinTime,
    required this.maxStudents,
    required this.createdAt,
    required this.updatedAt,
  });

  String get instructorName => '$instructorFirstName $instructorLastName'.trim();

  /// Session state, API-first.
  ///
  /// `live` and `started` both mean "join now" on the web; `ended`,
  /// `completed` and `finished` all mean it is over.
  SessionStatus get status {
    switch (rawStatus) {
      case 'live':
      case 'started':
        return SessionStatus.now;
      case 'upcoming':
      case 'scheduled':
        return SessionStatus.upcoming;
      case 'ended':
      case 'completed':
      case 'finished':
        return SessionStatus.recorded;
    }

    final now = DateTime.now().toUtc();
    if (now.isAfter(startedAt) && now.isBefore(endedAt)) {
      return SessionStatus.now;
    } else if (now.isBefore(startedAt)) {
      return SessionStatus.upcoming;
    }
    return SessionStatus.recorded;
  }

  bool get isLive => status == SessionStatus.now;
  bool get isUpcoming => status == SessionStatus.upcoming;
  bool get isEnded => status == SessionStatus.recorded;

  String get formattedTime {
    final now = DateTime.now();
    final localStartedAt = startedAt.toLocal();
    final localEndedAt = endedAt.toLocal();

    final isToday = localStartedAt.year == now.year &&
        localStartedAt.month == now.month &&
        localStartedAt.day == now.day;
    final isTomorrow = localStartedAt.year == now.year &&
        localStartedAt.month == now.month &&
        localStartedAt.day == now.day + 1;

    final timeStr =
        '${localStartedAt.hour.toString().padLeft(2, '0')}:${localStartedAt.minute.toString().padLeft(2, '0')}';
    final endTimeStr =
        '${localEndedAt.hour.toString().padLeft(2, '0')}:${localEndedAt.minute.toString().padLeft(2, '0')}';

    if (isToday) {
      return 'Today, $timeStr - $endTimeStr';
    } else if (isTomorrow) {
      return 'Tomorrow, $timeStr - $endTimeStr';
    } else {
      final day = localStartedAt.day.toString().padLeft(2, '0');
      final month = localStartedAt.month.toString().padLeft(2, '0');
      return '$day/$month, $timeStr - $endTimeStr';
    }
  }

  String get duration {
    final diff = endedAt.difference(startedAt);
    final hours = diff.inHours;
    final minutes = diff.inMinutes % 60;

    if (hours > 0 && minutes > 0) {
      return '${hours}h ${minutes}m';
    } else if (hours > 0) {
      return '${hours}h';
    }
    return '${minutes}m';
  }

  factory LiveRoom.fromJson(Map<String, dynamic> json) {
    final attributes = json['attributes'] ?? {};
    final userData = attributes['user']?['data']?['attributes'] ?? {};
    final courseData = attributes['course']?['data'];

    return LiveRoom(
      id: json['id']?.toString() ?? '',
      title: attributes['title']?.toString() ?? '',
      description: attributes['description']?.toString() ?? '',
      instructorFirstName: userData['first_name']?.toString() ?? '',
      instructorLastName: userData['last_name']?.toString() ?? '',
      instructorEmail: userData['email']?.toString() ?? '',
      courseId: courseData?['id']?.toString() ?? coerceId(attributes['course_id']),
      courseTitle: courseData?['attributes']?['title']?.toString(),
      courseThumbnail: courseData?['attributes']?['thumbnail']?.toString(),
      courseIds: extractCourseIds(attributes),
      rawStatus:
          (attributes['status']?.toString() ?? '').trim().toLowerCase(),
      startedAt:
          DateTime.tryParse(attributes['started_at']?.toString() ?? '')?.toUtc() ??
              DateTime.now().toUtc(),
      endedAt:
          DateTime.tryParse(attributes['ended_at']?.toString() ?? '')?.toUtc() ??
              DateTime.now().toUtc(),
      maxJoinTime: DateTime.tryParse(
                  attributes['max_join_time']?.toString() ?? '')
              ?.toUtc() ??
          DateTime.now().toUtc(),
      maxStudents:
          int.tryParse(attributes['max_students']?.toString() ?? '0') ?? 0,
      createdAt:
          DateTime.tryParse(attributes['created_at']?.toString() ?? '')?.toUtc() ??
              DateTime.now().toUtc(),
      updatedAt:
          DateTime.tryParse(attributes['updated_at']?.toString() ?? '')?.toUtc() ??
              DateTime.now().toUtc(),
    );
  }

  /// Every course id attached to a session.
  ///
  /// Ported from `getLiveRoomCourseIds`: `course_ids`, then a `courses` list
  /// (bare or JSON:API), then the single `course` relation or direct `course_id`. The home screen
  /// filters sessions by these against the student's enrolled courses.
  static List<String> extractCourseIds(dynamic attributes) {
    if (attributes is! Map) return const [];

    final attrs = attributes['attributes'] is Map
        ? attributes['attributes'] as Map
        : attributes;

    final ids = <String>{};

    final directCourseId = coerceId(attrs['course_id']);
    if (directCourseId != null) ids.add(directCourseId);

    final courseIds = attrs['course_ids'];
    if (courseIds is List) {
      for (final id in courseIds) {
        final s = coerceId(id);
        if (s != null) ids.add(s);
      }
    }

    final rawCourses = attrs['courses'];
    final coursesList = rawCourses is List
        ? rawCourses
        : (rawCourses is Map && rawCourses['data'] is List
            ? rawCourses['data'] as List
            : null);

    if (coursesList != null) {
      for (final course in coursesList) {
        if (course is! Map) continue;
        final id = coerceId(course['id']) ??
            (course['data'] is Map
                ? coerceId((course['data'] as Map)['id'])
                : null);
        if (id != null) ids.add(id);
      }
    }

    final single = attrs['course'];
    if (single is Map) {
      final id = (single['data'] is Map
              ? coerceId((single['data'] as Map)['id'])
              : null) ??
          coerceId(single['id']);
      if (id != null) ids.add(id);
    }

    return ids.toList();
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': 'live-rooms',
      'attributes': {
        'title': title,
        'description': description,
        'status': rawStatus,
        'started_at': startedAt.toIso8601String(),
        'ended_at': endedAt.toIso8601String(),
        'max_join_time': maxJoinTime.toIso8601String(),
        'max_students': maxStudents,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      },
    };
  }
}

enum SessionStatus { now, upcoming, recorded }
