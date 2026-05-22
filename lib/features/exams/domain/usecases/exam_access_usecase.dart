import 'package:flutter/material.dart';
import '../../data/exam_repository.dart';
import '../../models/quiz_models.dart';
import '../../presentation/widgets/exam_activation_modal.dart';
import '../../presentation/screens/quiz_screen.dart';
import '../../presentation/screens/exam_notice_screen.dart';

/// Enum representing exam access status
enum ExamAccessStatus {
  public,        // is_public == true, open directly
  viewable,      // can_view == true, show notice then open
  needsActivation, // can_view == false, show activation modal
  error,         // API error occurred
}

/// Use case for handling exam access control logic
class ExamAccessUseCase {
  final ExamRepository _examRepository;

  ExamAccessUseCase({ExamRepository? examRepository})
      : _examRepository = examRepository ?? ExamRepository();

  /// Check if exam can be opened based on access properties
  ExamAccessStatus checkExamAccess(Quiz quiz) {
    // Step 1: Check if public
    if (quiz.isPublic) {
      return ExamAccessStatus.public;
    }

    // Step 2: Check if user has view permission
    if (quiz.canView) {
      return ExamAccessStatus.viewable;
    }

    // Step 3: User needs activation
    return ExamAccessStatus.needsActivation;
  }

  /// Quick check if exam can be opened without activation
  bool canOpenExam(Quiz quiz) {
    return quiz.isPublic || quiz.canView;
  }

  /// Handle exam access - main entry point with navigation logic
  /// This should be called when user clicks on an exam
  Future<void> handleExamAccess({
    required BuildContext context,
    required Quiz quiz,
    QuizAttempt? existingAttempt,
  }) async {
    final accessStatus = checkExamAccess(quiz);

    switch (accessStatus) {
      case ExamAccessStatus.public:
        // Open exam directly - no need for notice
        await _navigateToExamNotice(context, quiz, existingAttempt);
        break;

      case ExamAccessStatus.viewable:
        // User can view, show notice screen
        await _navigateToExamNotice(context, quiz, existingAttempt);
        break;

      case ExamAccessStatus.needsActivation:
        // Show activation modal
        await _showActivationModal(context, quiz);
        break;

      case ExamAccessStatus.error:
        // Show error
        _showAccessDeniedMessage(context);
        break;
    }
  }

  /// Navigate to exam notice screen
  Future<void> _navigateToExamNotice(
    BuildContext context,
    Quiz quiz,
    QuizAttempt? existingAttempt,
  ) async {
    if (!context.mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ExamNoticeScreen(
          quiz: quiz,
        ),
      ),
    );
  }

  /// Show activation code modal
  Future<void> _showActivationModal(BuildContext context, Quiz quiz) async {
    if (!context.mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ExamActivationModal(
        quiz: quiz,
        onSuccess: (updatedQuiz) {
          // After successful activation, navigate to exam notice
          Navigator.pop(context); // Close modal
          _navigateToExamNotice(context, updatedQuiz, null);
        },
        onError: (message) {
          // Error is handled within the modal
        },
      ),
    );
  }

  /// Show access denied message
  void _showAccessDeniedMessage(BuildContext context) {
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('You do not have access to this quiz.'),
        backgroundColor: Colors.red,
      ),
    );
  }

  /// Verify exam access with server before opening
  /// This calls GET /quiz/{id} which validates access and returns questions
  Future<Map<String, dynamic>> verifyExamAccess(int quizId) async {
    final result = await _examRepository.getQuizById(quizId);

    if (!result['success']) {
      return {
        'success': false,
        'accessStatus': ExamAccessStatus.error,
        'message': result['message'] ?? 'Failed to access exam',
      };
    }

    final quiz = result['data'] as Quiz;
    final accessStatus = checkExamAccess(quiz);

    return {
      'success': true,
      'quiz': quiz,
      'accessStatus': accessStatus,
      'canProceed': accessStatus == ExamAccessStatus.public ||
                    accessStatus == ExamAccessStatus.viewable,
    };
  }
}

/// Extension on Quiz for quick access checks
extension QuizAccessExtension on Quiz {
  /// Check if exam is accessible without activation
  bool get isAccessible => isPublic || canView || canWatch;

  /// Check if exam requires activation code
  bool get requiresActivation => !isPublic && !canView && !canWatch;
}
