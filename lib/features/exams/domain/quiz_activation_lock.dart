/// The exam activation gate.
///
/// Ported from `src/lib/student-quiz-activation-lock.ts` and
/// `src/lib/student-exam-hub-quiz.ts`.
///
/// The critical difference from the old app logic: `is_public` is **not** a
/// boolean. It is a three-way value — `true`, `false`, `"included"` — and the
/// app read it as `attributes['is_public'] ?? false`, which throws away the
/// `"included"` case entirely. That case is the common one: an exam bundled
/// with a course, which unlocks as soon as the student activates that course.
///
///  * `true`      → open to everyone.
///  * `"included"` → open when the owning course is one the student activated.
///  * `false`     → private; needs an activation code, always.
library;

import '../../../core/utils/coerce.dart';

/// How the backend described this exam's visibility.
enum QuizVisibility {
  /// `is_public: true` — no gate.
  public,

  /// `is_public: "included"` — unlocked by activating the owning course.
  included,

  /// `is_public: false` — needs an activation code.
  private,

  /// Field absent or unparseable. Treated as open, matching the web's
  /// backward-compatible default.
  unknown,
}

/// Bucket an exam falls into on the exams list.
enum QuizBucket {
  available,
  upcoming,
  expired,

  /// Already sat and graded. The web shows these in their own section rather
  /// than lumping them in with locked exams.
  completed,

  /// Locked behind an activation code.
  locked,

  /// An `included` exam whose course the student has not activated.
  courseNotEnrolled,
}

/// Status tokens the backend uses for an exam the student already finished.
///
/// Matches the `completed` list in the web's `classifyExamBucket`.
const Set<String> _completedStatuses = {
  'completed',
  'complete',
  'finished',
  'done',
  'submitted',
  'graded',
  'passed',
  'failed',
};

/// Normalises a status the way the web does: trimmed, lower-cased, with
/// hyphens and spaces folded to underscores.
String normalizeQuizStatus(dynamic status) {
  return (status?.toString() ?? '')
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[-\s]+'), '_');
}

/// Reads `attributes` off a quiz row, tolerating a bare attributes map.
Map<String, dynamic> quizAttributes(dynamic quiz) {
  if (quiz is! Map) return const {};
  final attrs = quiz['attributes'];
  if (attrs is Map) return Map<String, dynamic>.from(attrs);
  return Map<String, dynamic>.from(quiz);
}

/// Parses the tri-state `is_public`.
QuizVisibility readQuizVisibility(Map<String, dynamic> attrs) {
  final value = attrs['is_public'];

  if (value is String) {
    final s = value.trim().toLowerCase();
    if (s == 'included') return QuizVisibility.included;
    if (s == 'true' || s == '1') return QuizVisibility.public;
    if (s == 'false' || s == '0') return QuizVisibility.private;
    return QuizVisibility.unknown;
  }

  if (value == true || (value is num && value == 1)) {
    return QuizVisibility.public;
  }
  if (value == false || (value is num && value == 0)) {
    return QuizVisibility.private;
  }

  return QuizVisibility.unknown;
}

/// Attempts the student has left, or `null` when the API does not say.
///
/// Prefers the explicit `remaining_attempts`, else derives it from
/// `max_attempts − current_attempts`.
int? readRemainingAttempts(Map<String, dynamic> attrs) {
  final direct = coerceNonNegativeInt(attrs['remaining_attempts']);
  if (direct != null) return direct;

  final max = coercePositiveInt(attrs['max_attempts']) ??
      coercePositiveInt(attrs['maxAttempts']);
  final current = coerceNonNegativeInt(attrs['current_attempts']);
  if (max != null && current != null) {
    final left = max - current;
    return left < 0 ? 0 : left;
  }
  return null;
}

/// Every course this exam belongs to.
///
/// Reads `courses_ids`, then the `courses` relation (bare list or JSON:API),
/// then the single `course_id`. The app only ever read `course_id`, so exams
/// attached to several courses never matched the student's enrolment.
List<String> readQuizCourseIds(Map<String, dynamic> attrs) {
  final ids = <String>{};

  final coursesIds = attrs['courses_ids'];
  if (coursesIds is List) {
    for (final id in coursesIds) {
      final s = coerceId(id);
      if (s != null) ids.add(s);
    }
  }

  final courses = attrs['courses'];
  final list = courses is List
      ? courses
      : (courses is Map && courses['data'] is List
          ? courses['data'] as List
          : null);
  if (list != null) {
    for (final course in list) {
      if (course is! Map) continue;
      final id = coerceId(course['id']) ??
          (course['data'] is Map
              ? coerceId((course['data'] as Map)['id'])
              : null);
      if (id != null) ids.add(id);
    }
  }

  final single = coerceId(attrs['course_id']);
  if (single != null) ids.add(single);

  return ids.toList();
}

/// True when one of the exam's courses is in the student's activated set.
bool quizCourseIsEnrolled(
  Map<String, dynamic> attrs,
  Set<String> enrolledCourseIds,
) {
  if (enrolledCourseIds.isEmpty) return false;
  final ids = readQuizCourseIds(attrs);
  if (ids.isEmpty) return false;
  return ids.any(enrolledCourseIds.contains);
}

/// Does this exam need an activation code before it can be opened?
///
/// Ignores enrolment — see [quizRequiresActivationWithEnrolled] for the
/// enrolment-aware variant used by the list and detail screens.
bool quizRequiresActivation(Map<String, dynamic> attrs) {
  final visibility = readQuizVisibility(attrs);
  if (visibility == QuizVisibility.public) return false;
  if (coerceFlagOrNull(attrs['has_activation']) == true) return false;

  if (visibility == QuizVisibility.included ||
      visibility == QuizVisibility.private) {
    return true;
  }

  // Unknown visibility → do not lock (backward compatible with older payloads).
  return false;
}

/// Enrolment-aware gate.
///
/// An `included` exam stops being locked once the student has activated the
/// owning course. A `private` exam never unlocks this way — it always needs a
/// code of its own.
bool quizRequiresActivationWithEnrolled(
  Map<String, dynamic> attrs,
  Set<String> enrolledCourseIds,
) {
  if (!quizRequiresActivation(attrs)) return false;

  if (readQuizVisibility(attrs) == QuizVisibility.included &&
      quizCourseIsEnrolled(attrs, enrolledCourseIds)) {
    return false;
  }

  return true;
}

/// The student activated this exam once but has used every attempt, so a new
/// code is required to try again.
bool quizNeedsReactivation(Map<String, dynamic> attrs) {
  final visibility = readQuizVisibility(attrs);
  if (visibility == QuizVisibility.public) return false;
  if (visibility == QuizVisibility.unknown) return false;
  if (coerceFlagOrNull(attrs['has_activation']) != true) return false;
  return readRemainingAttempts(attrs) == 0;
}

/// First-time activation or re-activation after attempts ran out.
bool quizMustActivate(
  Map<String, dynamic> attrs,
  Set<String> enrolledCourseIds,
) {
  return quizRequiresActivationWithEnrolled(attrs, enrolledCourseIds) ||
      quizNeedsReactivation(attrs);
}

/// Sorts an exam into the bucket the list screen renders it in.
///
/// Order matters and matches `classifyHubQuizRow`: the activation gate is
/// checked before timing, so a locked exam never shows as "available".
QuizBucket classifyQuiz(
  dynamic quiz,
  Set<String> enrolledCourseIds, {
  DateTime? now,
}) {
  final attrs = quizAttributes(quiz);
  final nowMs = (now ?? DateTime.now()).millisecondsSinceEpoch;

  if (quizRequiresActivationWithEnrolled(attrs, enrolledCourseIds)) {
    // An `included` exam can be unlocked by activating the course; a private
    // one strictly needs a code, so they get different prompts.
    return readQuizVisibility(attrs) == QuizVisibility.included
        ? QuizBucket.courseNotEnrolled
        : QuizBucket.locked;
  }

  final status = normalizeQuizStatus(attrs['status']);
  final start = _parseMs(attrs['start_time']);
  final end = _parseMs(attrs['end_time']);

  // Same order as the web: a finished exam is reported as finished even after
  // its window closes, and an expired window beats any other status.
  if (_completedStatuses.contains(status) ||
      status.contains('complete') ||
      status.contains('finish') ||
      status.contains('graded')) {
    return QuizBucket.completed;
  }

  if (end != null && end < nowMs) return QuizBucket.expired;

  if (status.isNotEmpty && status != 'active' && status != 'draft') {
    return QuizBucket.locked;
  }

  if (start != null && start > nowMs) return QuizBucket.upcoming;

  if (readRemainingAttempts(attrs) == 0) return QuizBucket.locked;

  return QuizBucket.available;
}

int? _parseMs(dynamic value) {
  final s = coerceString(value);
  if (s == null) return null;
  return DateTime.tryParse(s)?.millisecondsSinceEpoch;
}

/// Did `POST /v1/code/activate` actually unlock the exam?
///
/// The endpoint answers 200 even when it declines, with `done: false` and
/// `has_activation: false`. The app used to treat any 200 as success and let
/// the student through to a locked exam.
bool activateCodeUnlocksQuiz(dynamic data) {
  if (data is! Map) return true;
  if (data['done'] == true) return true;
  if (coerceFlagOrNull(data['has_activation']) == true) return true;
  if (data['done'] == false &&
      coerceFlagOrNull(data['has_activation']) == false) {
    return false;
  }
  return true;
}
