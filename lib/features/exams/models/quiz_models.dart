import '../../../core/utils/coerce.dart';
import '../domain/exam_media_url.dart';
import '../domain/quiz_activation_lock.dart';

// Quiz/Exam Model
enum QuizStatus { upcoming, available, expired, noAttempts }

class Quiz {
  final String id;
  final int quizId;
  final String title;
  final int maxAttempts;
  final int currentAttempts;
  final int remainingAttempts;
  final String type; // 'exam' or 'homework'
  final DateTime startTime;
  final DateTime endTime;
  final int duration; // in minutes
  final int? chapterId;
  final Chapter? chapter;
  final int? courseId;
  final DateTime createdAt;

  /// Three-way visibility. `is_public` is not a boolean: the API also sends
  /// the string `"included"`, which the old `bool` field could not hold — and
  /// assigning it threw at runtime.
  final QuizVisibility visibility;

  /// The backend already granted this student access to the exam.
  final bool hasActivation;

  /// Every course the exam belongs to (`courses_ids` / `courses` / `course_id`).
  final List<String> courseIds;

  /// Raw `attributes`, so the shared gate in `quiz_activation_lock.dart` can be
  /// applied without re-parsing.
  final Map<String, dynamic> attributes;

  final bool canView;
  final bool canWatch;

  Quiz({
    required this.id,
    required this.quizId,
    required this.title,
    required this.maxAttempts,
    this.currentAttempts = 0,
    this.remainingAttempts = 0,
    required this.type,
    required this.startTime,
    required this.endTime,
    required this.duration,
    this.chapterId,
    this.chapter,
    this.courseId,
    required this.createdAt,
    this.visibility = QuizVisibility.unknown,
    this.hasActivation = false,
    this.courseIds = const [],
    this.attributes = const {},
    this.canView = false,
    this.canWatch = false,
  });

  /// Open to everyone, no gate. Kept for call sites that only need the boolean.
  bool get isPublic => visibility == QuizVisibility.public;

  /// Bundled with a course: unlocks once that course is activated.
  bool get isIncluded => visibility == QuizVisibility.included;

  factory Quiz.fromJson(Map<String, dynamic> json) {
    final rawAttributes = json['attributes'];
    final nestedAttributes = rawAttributes is Map
        ? Map<String, dynamic>.from(rawAttributes)
        : <String, dynamic>{};

    // The course-detail endpoint nests each exam under `course.attributes.exams`
    // as a JSON:API resource, but some of its fields — `remaining_attempts`,
    // `current_attempts`, `max_attempts`/`maxAttempts`, `has_activation` — can
    // ride on the *top level* of that exam object instead of inside
    // `attributes`. The web's own `examAttrsForQuizPolicy` reads
    // `attributes.field ?? topLevel.field` for exactly this reason; this app
    // read only `attributes`, so an exam shaped that way parsed with a zero
    // quiz id and a locked-looking gate and effectively vanished from the tab.
    // `id`/`type` are excluded from the fallback because they mean something
    // different at the JSON:API envelope level (resource id/type) than inside
    // `attributes` (this quiz's numeric id / exam vs. homework).
    final topLevelFallback = Map<String, dynamic>.from(json)
      ..remove('id')
      ..remove('type')
      ..remove('attributes');
    final attributes = <String, dynamic>{
      ...topLevelFallback,
      ...nestedAttributes,
    };

    final chapterData = attributes['chapter']?['data'];

    return Quiz(
      id: json['id']?.toString() ?? '',
      quizId: coerceInt(attributes['id'] ?? json['id']),
      title: attributes['title']?.toString() ?? '',
      maxAttempts: coerceInt(attributes['max_attempts'], fallback: 1),
      currentAttempts: coerceInt(attributes['current_attempts']),
      remainingAttempts: readRemainingAttempts(attributes) ?? 0,
      type: attributes['type']?.toString() ?? 'exam',
      startTime:
          DateTime.tryParse(attributes['start_time']?.toString() ?? '') ??
              DateTime.now(),
      endTime: DateTime.tryParse(attributes['end_time']?.toString() ?? '') ??
          DateTime.now(),
      duration: coerceInt(attributes['duration']),
      chapterId: coercePositiveInt(attributes['chapter_id']),
      chapter: chapterData != null ? Chapter.fromJson(chapterData) : null,
      courseId: coercePositiveInt(attributes['course_id']),
      createdAt:
          DateTime.tryParse(attributes['created_at']?.toString() ?? '') ??
              DateTime.now(),
      visibility: readQuizVisibility(attributes),
      hasActivation: coerceFlagOrNull(attributes['has_activation']) == true,
      courseIds: readQuizCourseIds(attributes),
      attributes: attributes,
      canView: coerceFlag(attributes['can_view']),
      canWatch: coerceFlag(attributes['can_watch']),
    );
  }

  // Check if quiz is currently available based on start/end time
  bool get isAvailable {
    final now = DateTime.now().toUtc();
    return now.isAfter(startTime) && now.isBefore(endTime);
  }

  // Check if quiz has expired
  bool get isExpired {
    final now = DateTime.now().toUtc();
    return now.isAfter(endTime);
  }

  // Get current status of the quiz
  QuizStatus getStatus(int remainingAttempts) {
    if (isExpired) return QuizStatus.expired;
    if (remainingAttempts <= 0) return QuizStatus.noAttempts;
    if (isAvailable) return QuizStatus.available;
    return QuizStatus.upcoming;
  }

  // Helper for status translation keys
  String getStatusTextKey(QuizStatus status) {
    switch (status) {
      case QuizStatus.expired:
        return 'exams.status_expired';
      case QuizStatus.noAttempts:
        return 'exams.status_no_attempts';
      case QuizStatus.available:
        return 'exams.status_available';
      case QuizStatus.upcoming:
        return 'exams.status_upcoming';
    }
  }

  // Helper for button translation keys
  String getButtonTextKey(QuizStatus status) {
    switch (status) {
      case QuizStatus.expired:
        return 'exams.btn_exam_expired';
      case QuizStatus.noAttempts:
        return 'exams.btn_no_attempts';
      case QuizStatus.available:
        return 'exams.btn_start_exam';
      case QuizStatus.upcoming:
        return 'exams.btn_not_available';
    }
  }
}

// Chapter Model (nested in quiz response)
class Chapter {
  final String id;
  final int chapterId;
  final int lectureId;
  final String title;
  final String thumbnail;
  final String duration;
  final bool isFreePreview;
  final int maxViews;
  final int currentUserViews;
  final bool isActivated;
  final bool isLocked;
  final bool canWatch;
  final DateTime createdAt;
  final DateTime updatedAt;

  Chapter({
    required this.id,
    required this.chapterId,
    required this.lectureId,
    required this.title,
    required this.thumbnail,
    required this.duration,
    required this.isFreePreview,
    required this.maxViews,
    required this.currentUserViews,
    required this.isActivated,
    required this.isLocked,
    required this.canWatch,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Chapter.fromJson(Map<String, dynamic> json) {
    final attributes = json['attributes'] ?? {};

    return Chapter(
      id: json['id']?.toString() ?? '',
      chapterId: int.tryParse(json['id']?.toString() ?? '0') ?? 0,
      lectureId: attributes['lecture_id'] ?? 0,
      title: attributes['title'] ?? '',
      thumbnail: attributes['thumbnail'] ?? '',
      duration: attributes['duration'] ?? '',
      isFreePreview: attributes['is_free_preview'] ?? false,
      maxViews: attributes['max_views'] ?? 0,
      currentUserViews: attributes['current_user_views'] ?? 0,
      isActivated: attributes['is_activated'] ?? false,
      isLocked: attributes['is_locked'] ?? false,
      canWatch: attributes['can_watch'] ?? false,
      createdAt: DateTime.tryParse(attributes['created_at'] ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(attributes['updated_at'] ?? '') ?? DateTime.now(),
    );
  }
}

// Quiz Question Model
class QuizQuestion {
  final String id;
  final int questionId;
  final int quizId;
  final String text;
  final String? image; // URL for question image
  final int score;
  final String type; // 'single_choice', 'multiple_choice', 'true_false', 'short_answer'
  final bool autoCorrect;
  final DateTime createdAt;
  List<QuizAnswer> answers;
  int? selectedAnswerId; // For single choice
  List<int> selectedAnswerIds; // For multiple choice
  String? textAnswer; // For short_answer

  QuizQuestion({
    required this.id,
    required this.questionId,
    required this.quizId,
    required this.text,
    this.image,
    required this.score,
    required this.type,
    required this.autoCorrect,
    required this.createdAt,
    this.answers = const [],
    this.selectedAnswerId,
    this.selectedAnswerIds = const [],
    this.textAnswer,
  });

  factory QuizQuestion.fromJson(Map<String, dynamic> json) {
    final rawAttributes = json['attributes'];
    final Map attributes = rawAttributes is Map ? rawAttributes : json;
    final rawAnswers = attributes['answers'];
    final List<dynamic> answersData = rawAnswers is List
        ? rawAnswers
        : (rawAnswers is Map && rawAnswers['data'] is List)
            ? rawAnswers['data'] as List
            : const [];
    final answers = answersData
        .whereType<Map>()
        .map((a) => QuizAnswer.fromJson(Map<String, dynamic>.from(a)))
        .toList();

    return QuizQuestion(
      id: json['id']?.toString() ?? '',
      questionId: coerceInt(json['id'] ?? attributes['id']),
      quizId: coerceInt(attributes['quiz_id']),
      text: attributes['text']?.toString() ?? '',
      // Same field the website reads (`attributes.image`); the attempt-result
      // payload names it `image_url`. Relative paths are made absolute.
      image: readExamMediaUrl(attributes, const ['image', 'image_url']),
      score: _coerceScore(attributes['score']),
      type: attributes['type']?.toString() ?? 'single_choice',
      autoCorrect: coerceFlagOrNull(attributes['auto_correct']) ?? true,
      createdAt:
          DateTime.tryParse(attributes['created_at']?.toString() ?? '') ??
              DateTime.now(),
      answers: answers,
    );
  }

  static int _coerceScore(dynamic value) {
    if (value is num) return value.round();
    if (value is String) {
      final n = num.tryParse(value.trim());
      if (n != null) return n.round();
    }
    return 0;
  }

  // Helper methods for question types
  bool get isSingleChoice => type == 'single_choice';
  bool get isMultipleChoice => type == 'multiple_choice';
  bool get isTrueFalse => type == 'true_false';
  bool get isShortAnswer => type == 'short_answer';

  // Check if question has an image
  bool get hasImage => image != null && image!.isNotEmpty;

  // Get correct answers (for review)
  List<QuizAnswer> get correctAnswers => answers.where((a) => a.isCorrect).toList();

  // Check if user's answer is correct
  bool get isUserAnswerCorrect {
    if (isSingleChoice || isTrueFalse) {
      final selected = answers.firstWhere(
        (a) => a.answerId == selectedAnswerId,
        orElse: () => QuizAnswer(id: '', answerId: 0, quizQuestionId: 0, text: '', isCorrect: false, createdAt: DateTime.now()),
      );
      return selected.isCorrect;
    } else if (isMultipleChoice) {
      if (selectedAnswerIds.isEmpty) return false;
      final correctIds = correctAnswers.map((a) => a.answerId).toSet();
      final selectedIds = selectedAnswerIds.toSet();
      return correctIds.length == selectedIds.length && correctIds.containsAll(selectedIds);
    }
    return false;
  }
}

// Quiz Answer Model
class QuizAnswer {
  final String id;
  final int answerId;
  final int quizQuestionId;
  final String text;
  final String? image; // URL for answer image
  final String? reason; // Explanation for why this answer is correct/incorrect
  final String? reasonImage; // Explanation image (`reason_image`)
  final bool isCorrect;
  final DateTime createdAt;

  QuizAnswer({
    required this.id,
    required this.answerId,
    required this.quizQuestionId,
    required this.text,
    this.image,
    this.reason,
    this.reasonImage,
    required this.isCorrect,
    required this.createdAt,
  });

  factory QuizAnswer.fromJson(Map<String, dynamic> json) {
    final rawAttributes = json['attributes'];
    final Map attributes = rawAttributes is Map ? rawAttributes : json;
    final reason = attributes['reason']?.toString().trim();

    return QuizAnswer(
      id: json['id']?.toString() ?? '',
      // The website keys answers by the resource `id`; `attributes.id` is not
      // always present, and defaulting every answer to 0 made every choice
      // match the first one (wrong selection, wrong review image).
      answerId: coerceInt(attributes['id'] ?? json['id']),
      quizQuestionId: coerceInt(attributes['quiz_question_id']),
      text: attributes['text']?.toString() ?? '',
      image: readExamMediaUrl(attributes, const ['image', 'image_url']),
      reason:
          (reason == null || reason.isEmpty || reason == 'null') ? null : reason,
      reasonImage: readExamMediaUrl(
        attributes,
        const ['reason_image', 'reason_image_url'],
      ),
      isCorrect: coerceFlag(attributes['is_correct']),
      createdAt:
          DateTime.tryParse(attributes['created_at']?.toString() ?? '') ??
              DateTime.now(),
    );
  }

  // Check if the explanation has an image (`reason_image`)
  bool get hasReasonImage => reasonImage != null && reasonImage!.isNotEmpty;

  // Check if answer has an image
  bool get hasImage => image != null && image!.isNotEmpty;

  // Check if answer has a reason
  bool get hasReason => reason != null && reason!.isNotEmpty;
}

// Quiz Attempt Model
class QuizAttempt {
  final String id;
  final String userId;
  final int quizId;
  final int score;
  final int totalScore;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final DateTime createdAt;

  QuizAttempt({
    required this.id,
    required this.userId,
    required this.quizId,
    required this.score,
    required this.totalScore,
    required this.startedAt,
    this.finishedAt,
    required this.createdAt,
  });

  factory QuizAttempt.fromJson(Map<String, dynamic> json) {
    final attributes = json['attributes'] ?? {};

    return QuizAttempt(
      id: json['id']?.toString() ?? '',
      userId: attributes['user_id']?.toString() ?? '',
      quizId: attributes['quiz_id'] ?? 0,
      score: attributes['score'] ?? 0,
      totalScore: attributes['total_score'] ?? 0,
      startedAt: DateTime.tryParse(attributes['started_at'] ?? '') ?? DateTime.now(),
      finishedAt: DateTime.tryParse(attributes['finished_at'] ?? ''),
      createdAt: DateTime.tryParse(attributes['created_at'] ?? '') ?? DateTime.now(),
    );
  }

  double get percentage => totalScore > 0 ? (score / totalScore) * 100 : 0;
  bool get isCompleted => finishedAt != null;
}

/// One graded answer row from `GET /v1/quiz-attempts/{id}/result`
/// (`data.answers[]` or `answers[]`, JSON:API or flat — the website accepts
/// both, see `ExamAnswersReview.tsx`).
class QuizAnswerReview {
  final String questionId;
  final String answerText;
  final bool? isCorrect;
  final num? scoreEarned;
  final String? feedback;

  /// Images the student attached to the answer (essay questions).
  final List<String> answerImages;

  /// Correction images the teacher attached while grading.
  final List<String> feedbackImages;

  const QuizAnswerReview({
    required this.questionId,
    this.answerText = '',
    this.isCorrect,
    this.scoreEarned,
    this.feedback,
    this.answerImages = const [],
    this.feedbackImages = const [],
  });

  static const _answerImageKeys = [
    'answer_image',
    'answer_image_url',
    'answer_images',
    'image',
    'image_url',
    'images',
    'attachment',
    'attachments',
    'file',
    'files',
  ];

  static const _feedbackImageKeys = [
    'feedback_image',
    'feedback_image_url',
    'feedback_images',
    'correction_image',
    'correction_image_url',
    'correction_images',
    'teacher_image',
    'teacher_images',
    'reviewer_image',
  ];

  static List<String> _images(Map attributes, List<String> keys) {
    final out = <String>[];
    void add(dynamic value) {
      if (value is List) {
        for (final item in value) {
          add(item);
        }
        return;
      }
      if (value is Map && value['data'] != null) {
        add(value['data']);
        return;
      }
      if (value is Map && value['attributes'] is Map) {
        add(value['attributes']);
        return;
      }
      final url = resolveExamMediaUrl(value);
      if (url == null || out.contains(url)) return;
      final path = url.split('?').first.toLowerCase();
      const nonImage = ['.pdf', '.doc', '.docx', '.mp3', '.mp4', '.m4a', '.zip'];
      if (nonImage.any(path.endsWith)) return;
      out.add(url);
    }

    for (final key in keys) {
      add(attributes[key]);
    }
    return out;
  }

  static QuizAnswerReview? fromJson(dynamic json) {
    if (json is! Map) return null;
    final rawAttributes = json['attributes'];
    final Map attributes = rawAttributes is Map ? rawAttributes : json;
    final nestedQuestion = attributes['quiz_question'];
    final questionId = coerceId(attributes['quiz_question_id']) ??
        coerceId(attributes['question_id']) ??
        (nestedQuestion is Map ? coerceId(nestedQuestion['id']) : null);
    if (questionId == null) return null;

    final rawScore = attributes['score_earned'];
    return QuizAnswerReview(
      questionId: questionId,
      answerText: attributes['answer_text']?.toString() ?? '',
      isCorrect: coerceFlagOrNull(attributes['is_correct']),
      scoreEarned: rawScore is num
          ? rawScore
          : num.tryParse(rawScore?.toString() ?? ''),
      feedback: coerceString(attributes['feedback']),
      answerImages: _images(attributes, _answerImageKeys),
      feedbackImages: _images(attributes, _feedbackImageKeys),
    );
  }

  /// Answer rows keyed by question id, from the whole result payload.
  static Map<String, QuizAnswerReview> mapFromResultPayload(dynamic payload) {
    final result = <String, QuizAnswerReview>{};
    if (payload is! Map) return result;
    final data = payload['data'];
    dynamic answers = data is Map ? data['answers'] : null;
    answers ??= payload['answers'];
    if (answers is Map && answers['data'] is List) answers = answers['data'];
    if (answers is! List) return result;
    for (final row in answers) {
      final parsed = QuizAnswerReview.fromJson(row);
      if (parsed != null) result[parsed.questionId] = parsed;
    }
    return result;
  }
}

// Quiz Result for local use
class QuizResult {
  final String quizId;
  final String quizTitle;
  final int score;
  final int totalScore;
  final double percentage;
  final int correctAnswers;
  final int totalQuestions;
  final bool passed;
  final DateTime completedAt;

  QuizResult({
    required this.quizId,
    required this.quizTitle,
    required this.score,
    required this.totalScore,
    required this.percentage,
    required this.correctAnswers,
    required this.totalQuestions,
    required this.passed,
    required this.completedAt,
  });
}

// Legacy classes for backward compatibility
class Exam {
  final String id;
  final String title;
  final String subject;
  final int questionCount;
  final int durationMinutes;
  final DateTime date;
  final String startTime;
  final ExamStatus status;
  final List<Question> questions;
  final String? description;

  Exam({
    required this.id,
    required this.title,
    required this.subject,
    required this.questionCount,
    required this.durationMinutes,
    required this.date,
    required this.startTime,
    required this.status,
    required this.questions,
    this.description,
  });
}

enum ExamStatus { upcoming, available, completed, notAvailable }

class Question {
  final String id;
  final int number;
  final String text;
  final List<String> options;
  final int correctAnswerIndex;
  String? selectedAnswer;

  Question({
    required this.id,
    required this.number,
    required this.text,
    required this.options,
    required this.correctAnswerIndex,
    this.selectedAnswer,
  });
}

class ExamResult {
  final String examId;
  final String examTitle;
  final double percentage;
  final int correctAnswers;
  final int totalQuestions;
  final int score;
  final int totalScore;
  final bool passed;
  final List<ChapterPerformance> chapterPerformance;

  ExamResult({
    required this.examId,
    required this.examTitle,
    required this.percentage,
    required this.correctAnswers,
    required this.totalQuestions,
    required this.score,
    required this.totalScore,
    required this.passed,
    required this.chapterPerformance,
  });
}

class ChapterPerformance {
  final String chapterName;
  final double percentage;
  final bool needsImprovement;

  ChapterPerformance({
    required this.chapterName,
    required this.percentage,
    this.needsImprovement = false,
  });
}
