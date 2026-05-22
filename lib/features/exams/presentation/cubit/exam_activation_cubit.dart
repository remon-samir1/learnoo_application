import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/exam_repository.dart';
import '../../models/quiz_models.dart';

/// States for exam activation flow
abstract class ExamActivationState {
  const ExamActivationState();
}

class ExamActivationInitial extends ExamActivationState {
  const ExamActivationInitial();
}

class ExamActivationLoading extends ExamActivationState {
  const ExamActivationLoading();
}

class ExamActivationSuccess extends ExamActivationState {
  final Quiz updatedQuiz;
  const ExamActivationSuccess(this.updatedQuiz);
}

class ExamActivationError extends ExamActivationState {
  final String message;
  const ExamActivationError(this.message);
}

/// Cubit for managing exam activation code flow
class ExamActivationCubit extends Cubit<ExamActivationState> {
  final ExamRepository _examRepository;

  ExamActivationCubit({ExamRepository? examRepository})
      : _examRepository = examRepository ?? ExamRepository(),
        super(const ExamActivationInitial());

  /// Activate exam with provided code
  Future<void> activateExam({
    required String code,
    required int quizId,
    required Quiz currentQuiz,
  }) async {
    emit(const ExamActivationLoading());

    try {
      final result = await _examRepository.activateQuizCode(
        code: code,
        quizId: quizId,
      );

      if (result['success']) {
        // Create updated quiz with can_watch = true
        final updatedQuiz = Quiz(
          id: currentQuiz.id,
          quizId: currentQuiz.quizId,
          title: currentQuiz.title,
          maxAttempts: currentQuiz.maxAttempts,
          type: currentQuiz.type,
          startTime: currentQuiz.startTime,
          endTime: currentQuiz.endTime,
          duration: currentQuiz.duration,
          chapterId: currentQuiz.chapterId,
          chapter: currentQuiz.chapter,
          courseId: currentQuiz.courseId,
          createdAt: currentQuiz.createdAt,
          isPublic: currentQuiz.isPublic,
          canView: currentQuiz.canView,
          canWatch: true, // Activated!
        );

        emit(ExamActivationSuccess(updatedQuiz));
      } else {
        emit(ExamActivationError(
          result['message'] ?? 'Invalid activation code. Please try again.',
        ));
      }
    } catch (e) {
      emit(ExamActivationError('Connection error: $e'));
    }
  }

  /// Reset state to initial
  void reset() {
    emit(const ExamActivationInitial());
  }
}
