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
  final bool isPublic;
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
    this.isPublic = false,
    this.canView = false,
    this.canWatch = false,
  });

  factory Quiz.fromJson(Map<String, dynamic> json) {
    final attributes = json['attributes'] ?? {};
    final chapterData = attributes['chapter']?['data'];

    return Quiz(
      id: json['id']?.toString() ?? '',
      quizId: attributes['id'] ?? 0,
      title: attributes['title'] ?? '',
      maxAttempts: attributes['max_attempts'] ?? 1,
      currentAttempts: attributes['current_attempts'] ?? 0,
      remainingAttempts: attributes['remaining_attempts'] ?? 0,
      type: attributes['type'] ?? 'exam',
      startTime: DateTime.tryParse(attributes['start_time'] ?? '') ?? DateTime.now(),
      endTime: DateTime.tryParse(attributes['end_time'] ?? '') ?? DateTime.now(),
      duration: attributes['duration'] ?? 0,

      chapterId: attributes['chapter_id'],
      chapter: chapterData != null ? Chapter.fromJson(chapterData) : null,
      courseId: attributes['course_id'] != null ? int.tryParse(attributes['course_id'].toString()) : null,
      createdAt: DateTime.tryParse(attributes['created_at'] ?? '') ?? DateTime.now(),
      isPublic: attributes['is_public'] ?? false,
      canView: attributes['can_view'] ?? false,
      canWatch: attributes['can_watch'] ?? false,
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
    final attributes = json['attributes'] ?? {};
    final List<dynamic> answersData = attributes['answers'] ?? [];
    final answers = answersData.map((a) => QuizAnswer.fromJson(a)).toList();

    return QuizQuestion(
      id: json['id']?.toString() ?? '',
      questionId: int.tryParse(json['id']?.toString() ?? '0') ?? 0,
      quizId: attributes['quiz_id'] ?? 0,
      text: attributes['text'] ?? '',
      image: attributes['image'],
      score: attributes['score'] ?? 0,
      type: attributes['type'] ?? 'single_choice',
      autoCorrect: attributes['auto_correct'] ?? true,
      createdAt: DateTime.tryParse(attributes['created_at'] ?? '') ?? DateTime.now(),
      answers: answers,
    );
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
  final bool isCorrect;
  final DateTime createdAt;

  QuizAnswer({
    required this.id,
    required this.answerId,
    required this.quizQuestionId,
    required this.text,
    this.image,
    this.reason,
    required this.isCorrect,
    required this.createdAt,
  });

  factory QuizAnswer.fromJson(Map<String, dynamic> json) {
    final attributes = json['attributes'] ?? {};

    return QuizAnswer(
      id: json['id']?.toString() ?? '',
      answerId: int.tryParse(attributes['id']?.toString() ?? '0') ?? 0,
      quizQuestionId: attributes['quiz_question_id'] ?? 0,
      text: attributes['text'] ?? '',
      image: attributes['image'],
      reason: attributes['reason'],
      isCorrect: attributes['is_correct'] ?? false,
      createdAt: DateTime.tryParse(attributes['created_at'] ?? '') ?? DateTime.now(),
    );
  }

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
