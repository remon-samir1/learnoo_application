import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../data/exam_repository.dart';
import '../../models/quiz_models.dart';
import '../../presentation/screens/exam_notice_screen.dart';
import '../../presentation/widgets/exam_activation_modal.dart';
import '../quiz_activation_lock.dart';

/// Why an exam can or cannot be opened.
enum ExamAccessStatus {
  /// Open to everyone (`is_public: true`).
  public,

  /// Gate satisfied — activated, or bundled with a course the student has.
  viewable,

  /// Bundled with a course the student has not activated yet.
  courseNotEnrolled,

  /// Private exam, or attempts exhausted: needs an activation code.
  needsActivation,

  /// Every attempt used on an exam the student had already activated.
  attemptsExhausted,

  error,
}

/// Decides what happens when a student taps an exam.
///
/// Rewritten on the shared gate in `quiz_activation_lock.dart` so the app and
/// the web reach the same verdict. The old version had only three states and
/// keyed off `can_view` / `can_watch`, which meant a course-bundled exam looked
/// identical to a private one — the student was asked for a code they had no
/// way to obtain.
class ExamAccessUseCase {
  ExamAccessUseCase({ExamRepository? examRepository})
      : _examRepository = examRepository ?? ExamRepository();

  final ExamRepository _examRepository;

  /// [enrolledCourseIds] are the courses the student has activated. Pass the
  /// same set the exams list built, so an `included` exam resolves identically
  /// in the list and on tap.
  ExamAccessStatus checkExamAccess(
    Quiz quiz, {
    Set<String> enrolledCourseIds = const {},
  }) {
    final attrs = quiz.attributes;

    if (quizNeedsReactivation(attrs)) {
      return ExamAccessStatus.attemptsExhausted;
    }

    if (quizRequiresActivationWithEnrolled(attrs, enrolledCourseIds)) {
      return readQuizVisibility(attrs) == QuizVisibility.included
          ? ExamAccessStatus.courseNotEnrolled
          : ExamAccessStatus.needsActivation;
    }

    return quiz.isPublic
        ? ExamAccessStatus.public
        : ExamAccessStatus.viewable;
  }

  bool canOpenExam(Quiz quiz, {Set<String> enrolledCourseIds = const {}}) {
    final status = checkExamAccess(quiz, enrolledCourseIds: enrolledCourseIds);
    return status == ExamAccessStatus.public ||
        status == ExamAccessStatus.viewable;
  }

  /// Entry point for a tap on an exam card.
  Future<void> handleExamAccess({
    required BuildContext context,
    required Quiz quiz,
    Set<String> enrolledCourseIds = const {},
    QuizAttempt? existingAttempt,
  }) async {
    final status = checkExamAccess(quiz, enrolledCourseIds: enrolledCourseIds);

    switch (status) {
      case ExamAccessStatus.public:
      case ExamAccessStatus.viewable:
        await _navigateToExamNotice(context, quiz);
        break;

      case ExamAccessStatus.courseNotEnrolled:
        // No code will help here — the student needs to activate the course.
        _showMessage(context, 'exams.activate_course_first'.tr());
        break;

      case ExamAccessStatus.needsActivation:
        await _showActivationModal(context, quiz);
        break;

      case ExamAccessStatus.attemptsExhausted:
        await _showActivationModal(
          context,
          quiz,
          title: 'exams.reactivate_attempts_title'.tr(),
          body: 'exams.reactivate_attempts_body'.tr(),
        );
        break;

      case ExamAccessStatus.error:
        _showMessage(context, 'exams.access_denied'.tr());
        break;
    }
  }

  Future<void> _navigateToExamNotice(BuildContext context, Quiz quiz) async {
    if (!context.mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => ExamNoticeScreen(quiz: quiz)),
    );
  }

  Future<void> _showActivationModal(
    BuildContext context,
    Quiz quiz, {
    String? title,
    String? body,
  }) async {
    if (!context.mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => ExamActivationModal(
        quiz: quiz,
        headline: title,
        message: body,
        onSuccess: (updatedQuiz) {
          Navigator.pop(sheetContext);
          _navigateToExamNotice(context, updatedQuiz);
        },
        onError: (message) {
          // Surfaced inside the modal.
        },
      ),
    );
  }

  void _showMessage(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  /// Re-checks access against the server before opening.
  ///
  /// `GET /v1/quiz/{id}` both validates access and returns the questions, so a
  /// stale list row cannot be used to slip into a locked exam.
  Future<Map<String, dynamic>> verifyExamAccess(
    int quizId, {
    Set<String> enrolledCourseIds = const {},
  }) async {
    final result = await _examRepository.getQuizById(quizId);

    if (result['success'] != true) {
      return {
        'success': false,
        'accessStatus': ExamAccessStatus.error,
        'message': result['message'] ?? 'Failed to access exam',
      };
    }

    final quiz = result['data'] as Quiz;
    final status = checkExamAccess(quiz, enrolledCourseIds: enrolledCourseIds);

    return {
      'success': true,
      'quiz': quiz,
      'accessStatus': status,
      'canProceed': status == ExamAccessStatus.public ||
          status == ExamAccessStatus.viewable,
    };
  }
}

/// Convenience checks on a quiz row.
extension QuizAccessExtension on Quiz {
  bool isAccessibleFor(Set<String> enrolledCourseIds) =>
      !quizMustActivate(attributes, enrolledCourseIds);

  bool requiresActivationFor(Set<String> enrolledCourseIds) =>
      quizMustActivate(attributes, enrolledCourseIds);

  QuizBucket bucketFor(Set<String> enrolledCourseIds) =>
      classifyQuiz({'attributes': attributes}, enrolledCourseIds);
}
