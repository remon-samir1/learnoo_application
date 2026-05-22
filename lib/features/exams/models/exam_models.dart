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
