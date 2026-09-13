import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/exam_repository.dart';
import '../../domain/quiz_activation_lock.dart';
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

      if (result['success'] != true) {
        emit(ExamActivationError(
          result['message'] ?? 'Invalid activation code. Please try again.',
        ));
        return;
      }

      // A 200 is not proof the code was accepted: the endpoint answers
      // `{done: false, has_activation: false}` when it declines. Checking the
      // body is what stops a rejected code from opening a locked exam.
      if (!activateCodeUnlocksQuiz(result['data'])) {
        emit(ExamActivationError(
          result['message'] ?? 'Invalid activation code. Please try again.',
        ));
        return;
      }

      // Re-read the quiz so the unlocked state comes from the server rather
      // than a locally patched copy — attempts, visibility and questions all
      // change once activation lands.
      final refreshed = await _examRepository.getQuizById(quizId);
      final updatedQuiz = refreshed['success'] == true
          ? refreshed['data'] as Quiz
          : _optimisticallyUnlocked(currentQuiz);

      emit(ExamActivationSuccess(updatedQuiz));
    } catch (e) {
      emit(ExamActivationError('Connection error: $e'));
    }
  }

  /// Fallback when the post-activation refetch fails: mark the quiz activated
  /// locally so the student is not stuck behind a gate the server just opened.
  Quiz _optimisticallyUnlocked(Quiz quiz) {
    final attributes = Map<String, dynamic>.from(quiz.attributes)
      ..['has_activation'] = true
      ..['can_watch'] = true;

    return Quiz(
      id: quiz.id,
      quizId: quiz.quizId,
      title: quiz.title,
      maxAttempts: quiz.maxAttempts,
      currentAttempts: quiz.currentAttempts,
      remainingAttempts: quiz.remainingAttempts,
      type: quiz.type,
      startTime: quiz.startTime,
      endTime: quiz.endTime,
      duration: quiz.duration,
      chapterId: quiz.chapterId,
      chapter: quiz.chapter,
      courseId: quiz.courseId,
      createdAt: quiz.createdAt,
      visibility: quiz.visibility,
      hasActivation: true,
      courseIds: quiz.courseIds,
      attributes: attributes,
      canView: true,
      canWatch: true,
    );
  }

  /// Reset state to initial
  void reset() {
    emit(const ExamActivationInitial());
  }
}
