import '../../../../core/utils/coerce.dart';

/// A scheduled or running live session (`GET /v1/live-room`).
///
/// Mirrors the website's student helpers in `src/lib/student-live-room.ts`
/// and `src/lib/student-faculty-tree.ts`: the status comes only from the API's
/// own `status` field, the instructor and course titles are resolved the same
/// way, and [accessFor] reproduces `resolveLiveRoomAccessState`.
class LiveRoom {
  final String id;
  final String title;
  final String description;

  /// Resolved like `getInstructorDisplayName`: course instructor's
  /// `full_name`, then the room owner's `full_name`.
  final String instructorFullName;
  final String instructorFirstName;
  final String instructorLastName;
  final String instructorEmail;
  final String? courseId;
  final String? courseTitle;
  final String? courseThumbnail;

  /// Every course title attached to the session (`getCourseTitles`).
  final List<String> courseTitles;

  /// Every course this session belongs to — the API may attach several.
  final List<String> courseIds;

  /// Raw `attributes.status`, lower-cased. Empty when the API omits it.
  final String rawStatus;

  /// Raw `attributes.is_public`, lower-cased (`public`, `private`, `included`).
  final String isPublic;

  /// `attributes.has_activation` — the student activated this private room.
  final bool hasActivation;

  /// `attributes.enable_chat` — only an explicit `false` disables chat.
  final bool enableChat;

  /// First non-empty of `recording_url`, `playback_url`, `video_url`.
  final String? recordingUrl;

  /// `started_at` as sent by the API, `null` when absent or unparsable.
  final DateTime? startedAtValue;

  final DateTime startedAt;
  final DateTime endedAt;
  final DateTime maxJoinTime;

  /// `max_students` when the API sends a number.
  final int? maxStudentsValue;
  final int maxStudents;
  final DateTime createdAt;
  final DateTime updatedAt;

  LiveRoom({
    required this.id,
    required this.title,
    required this.description,
    this.instructorFullName = '',
    required this.instructorFirstName,
    required this.instructorLastName,
    required this.instructorEmail,
    this.courseId,
    this.courseTitle,
    this.courseThumbnail,
    this.courseTitles = const [],
    this.courseIds = const [],
    this.rawStatus = '',
    this.isPublic = '',
    this.hasActivation = false,
    this.enableChat = true,
    this.recordingUrl,
    this.startedAtValue,
    required this.startedAt,
    required this.endedAt,
    required this.maxJoinTime,
    this.maxStudentsValue,
    required this.maxStudents,
    required this.createdAt,
    required this.updatedAt,
  });

  String get instructorName {
    if (instructorFullName.trim().isNotEmpty) return instructorFullName.trim();
    return '$instructorFirstName $instructorLastName'.trim();
  }

  /// Course titles joined the way the website joins them.
  String get courseTitlesLabel => courseTitles.join('، ');

  bool get hasRecording => recordingUrl != null;

  /// Session state, from the API `status` only — exactly like the website.
  ///
  /// `live`/`started` mean "join now"; `upcoming` (and `pending`, which the
  /// website detail page and course tab also treat as upcoming) mean it has
  /// not started; `ended`/`completed`/`finished` mean it is over. Anything
  /// else is [SessionStatus.unknown].
  SessionStatus get status {
    switch (rawStatus) {
      case 'live':
      case 'started':
        return SessionStatus.now;
      case 'upcoming':
      case 'pending':
        return SessionStatus.upcoming;
      case 'ended':
      case 'completed':
      case 'finished':
        return SessionStatus.recorded;
    }
    return SessionStatus.unknown;
  }

  bool get isLive => status == SessionStatus.now;
  bool get isUpcoming => status == SessionStatus.upcoming;
  bool get isEnded => status == SessionStatus.recorded;

  /// Port of `resolveLiveRoomAccessState`.
  ///
  /// [enrolledCourseIds] are the student's unlocked courses.
  LiveRoomAccess accessFor(Set<String> enrolledCourseIds) {
    final pub = isPublic.isEmpty ? 'unknown' : isPublic;

    if (pub == 'included') {
      if (courseIds.isNotEmpty &&
          !courseIds.any(enrolledCourseIds.contains)) {
        return LiveRoomAccess.courseNotEnrolled;
      }
      return LiveRoomAccess.available;
    }

    if (pub == 'false' || pub == 'private') {
      return hasActivation
          ? LiveRoomAccess.available
          : LiveRoomAccess.lockedPrivate;
    }

    return LiveRoomAccess.available;
  }

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
    final rawAttributes = json['attributes'];
    final Map attributes = rawAttributes is Map ? rawAttributes : const {};
    final userData = _attrsOf(attributes['user']);
    final courseRel = attributes['course'];
    final courseData = courseRel is Map
        ? (courseRel['data'] is Map ? courseRel['data'] as Map : courseRel)
        : null;
    final courseAttrs = _attrsOf(courseRel);

    final startedAtValue =
        DateTime.tryParse(attributes['started_at']?.toString() ?? '')?.toUtc();

    return LiveRoom(
      id: json['id']?.toString() ?? '',
      title: coerceString(attributes['title']) ?? '',
      description: coerceString(attributes['description']) ?? '',
      instructorFullName: _instructorFullName(attributes),
      instructorFirstName: userData['first_name']?.toString() ?? '',
      instructorLastName: userData['last_name']?.toString() ?? '',
      instructorEmail: userData['email']?.toString() ?? '',
      courseId: coerceId(courseData?['id']) ?? coerceId(attributes['course_id']),
      courseTitle: coerceString(courseAttrs['title']),
      courseThumbnail: extractCourseThumbnail(attributes),
      courseTitles: extractCourseTitles(attributes),
      courseIds: extractCourseIds(attributes),
      rawStatus: (attributes['status']?.toString() ?? '').trim().toLowerCase(),
      isPublic: (attributes['is_public']?.toString() ?? '').trim().toLowerCase(),
      hasActivation: attributes['has_activation'] == true,
      enableChat: attributes['enable_chat'] != false,
      recordingUrl: coerceString(attributes['recording_url']) ??
          coerceString(attributes['playback_url']) ??
          coerceString(attributes['video_url']),
      startedAtValue: startedAtValue,
      startedAt: startedAtValue ?? DateTime.now().toUtc(),
      endedAt:
          DateTime.tryParse(attributes['ended_at']?.toString() ?? '')?.toUtc() ??
              DateTime.now().toUtc(),
      maxJoinTime: DateTime.tryParse(
                  attributes['max_join_time']?.toString() ?? '')
              ?.toUtc() ??
          DateTime.now().toUtc(),
      maxStudentsValue: attributes['max_students'] is num
          ? (attributes['max_students'] as num).toInt()
          : null,
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

  /// `attributes` of a JSON:API relation (`{data: {attributes}}`) or of a bare
  /// object (`{attributes}`), or the object itself.
  static Map _attrsOf(dynamic rel) {
    if (rel is! Map) return const {};
    final data = rel['data'];
    if (data is Map) {
      final a = data['attributes'];
      return a is Map ? a : data;
    }
    final a = rel['attributes'];
    return a is Map ? a : rel;
  }

  static String _instructorFullName(Map attributes) {
    final course = attributes['course'];
    if (course is Map && course['data'] is Map) {
      final courseAttrs = (course['data'] as Map)['attributes'];
      if (courseAttrs is Map) {
        final instructor = _attrsOf(courseAttrs['instructor']);
        final name = coerceString(instructor['full_name']);
        if (name != null) return name;
      }
    }
    final user = attributes['user'];
    if (user is Map && user['data'] is Map) {
      final userAttrs = (user['data'] as Map)['attributes'];
      if (userAttrs is Map) {
        final name = coerceString(userAttrs['full_name']);
        if (name != null) return name;
      }
    }
    return '';
  }

  static List? _coursesList(Map attrs) {
    final raw = attrs['courses'];
    if (raw is List) return raw;
    if (raw is Map && raw['data'] is List) return raw['data'] as List;
    return null;
  }

  /// Port of `getCourseTitles`.
  static List<String> extractCourseTitles(Map attributes) {
    final titles = <String>[];
    void add(dynamic t) {
      final s = coerceString(t);
      if (s != null && !titles.contains(s)) titles.add(s);
    }

    final list = _coursesList(attributes);
    if (list != null) {
      for (final c in list) {
        if (c is! Map) continue;
        final attrs = c['attributes'];
        final data = c['data'];
        add((attrs is Map ? attrs['title'] : null) ??
            c['title'] ??
            (data is Map && data['attributes'] is Map
                ? (data['attributes'] as Map)['title']
                : null) ??
            (data is Map ? data['title'] : null));
      }
    }

    final single = attributes['course'];
    if (single is Map) {
      final data = single['data'];
      final attrs = single['attributes'];
      add((data is Map && data['attributes'] is Map
              ? (data['attributes'] as Map)['title']
              : null) ??
          (attrs is Map ? attrs['title'] : null) ??
          (data is Map ? data['title'] : null) ??
          single['title']);
    }
    return titles;
  }

  /// Port of `getCourseThumbnail`.
  static String? extractCourseThumbnail(Map attributes) {
    String? fromThumb(dynamic th) {
      if (th is String) return coerceString(th);
      if (th is Map) return coerceString(th['url']);
      return null;
    }

    final single = _attrsOf(attributes['course']);
    final fromSingle = fromThumb(single['thumbnail']);
    if (fromSingle != null) return fromSingle;

    final list = _coursesList(attributes);
    if (list != null) {
      for (final c in list) {
        if (c is! Map) continue;
        final t = fromThumb(_attrsOf(c)['thumbnail']);
        if (t != null) return t;
      }
    }
    return null;
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

    final coursesList = _coursesList(attrs);
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
        'is_public': isPublic,
        'has_activation': hasActivation,
        'enable_chat': enableChat,
        'recording_url': recordingUrl,
        'started_at': startedAtValue?.toIso8601String(),
        'ended_at': endedAt.toIso8601String(),
        'max_join_time': maxJoinTime.toIso8601String(),
        'max_students': maxStudentsValue,
        'course_ids': courseIds,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      },
    };
  }
}

/// `unknown` covers any status the API sends that the website does not map.
enum SessionStatus { now, upcoming, recorded, unknown }

/// The website's `LiveRoomAccessState`.
enum LiveRoomAccess { available, lockedPrivate, courseNotEnrolled }
