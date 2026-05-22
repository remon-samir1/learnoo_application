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
    required this.startedAt,
    required this.endedAt,
    required this.maxJoinTime,
    required this.maxStudents,
    required this.createdAt,
    required this.updatedAt,
  });

  String get instructorName => '$instructorFirstName $instructorLastName';

  SessionStatus get status {
    final now = DateTime.now().toUtc();
    if (now.isAfter(startedAt) && now.isBefore(endedAt)) {
      return SessionStatus.now;
    } else if (now.isBefore(startedAt)) {
      return SessionStatus.upcoming;
    } else {
      return SessionStatus.recorded;
    }
  }

  bool get isLive => status == SessionStatus.now;

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
    
    final timeStr = '${localStartedAt.hour.toString().padLeft(2, '0')}:${localStartedAt.minute.toString().padLeft(2, '0')}';
    final endTimeStr = '${localEndedAt.hour.toString().padLeft(2, '0')}:${localEndedAt.minute.toString().padLeft(2, '0')}';
    
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
    } else {
      return '${minutes}m';
    }
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
      courseId: courseData?['id']?.toString(),
      courseTitle: courseData?['attributes']?['title']?.toString(),
      courseThumbnail: courseData?['attributes']?['thumbnail']?.toString(),
      startedAt: DateTime.tryParse(attributes['started_at']?.toString() ?? '')?.toUtc() ?? DateTime.now().toUtc(),
      endedAt: DateTime.tryParse(attributes['ended_at']?.toString() ?? '')?.toUtc() ?? DateTime.now().toUtc(),
      maxJoinTime: DateTime.tryParse(attributes['max_join_time']?.toString() ?? '')?.toUtc() ?? DateTime.now().toUtc(),
      maxStudents: int.tryParse(attributes['max_students']?.toString() ?? '0') ?? 0,
      createdAt: DateTime.tryParse(attributes['created_at']?.toString() ?? '')?.toUtc() ?? DateTime.now().toUtc(),
      updatedAt: DateTime.tryParse(attributes['updated_at']?.toString() ?? '')?.toUtc() ?? DateTime.now().toUtc(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': 'live-rooms',
      'attributes': {
        'title': title,
        'description': description,
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
