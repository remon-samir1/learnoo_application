/// Resolving a graded attempt into "what the student picked" and "was it
/// right", ported from the website's
/// `components/student/exams/ExamAnswersReview.tsx` and
/// `src/lib/student-exam-question-utils.ts`.
///
/// The app used to render the review from `QuizQuestion.selectedAnswerId` /
/// `selectedAnswerIds` — the in-memory selections made while taking the exam.
/// Those are also the only source for the local correctness tally, and the
/// options' `is_correct` flags come from whatever the question endpoint
/// returned while the exam was being taken. The website instead rebuilds the
/// whole review from the attempt-result payload: the quiz (with graded
/// options), the student's rows, and the server's per-question `is_correct`.
library;

import '../models/quiz_models.dart';

/// The student's own options, resolved from the server's `answer_text`.
///
/// This is the website's rule verbatim: the text is split on commas, each part
/// is trimmed, and an option counts as chosen when its own trimmed text is one
/// of those parts. Matching is on **text**, not on answer ids — the backend's
/// `quiz-user-answer` rows only carry the text.
///
/// Two consequences are inherited deliberately rather than "fixed", so that the
/// app and the website always agree:
///  * an option whose own text contains a comma can never match, because the
///    split tears it in two;
///  * two options with identical text are both marked as chosen.
List<QuizAnswer> selectedAnswersFromAnswerText(
  String answerText,
  List<QuizAnswer> answers, {
  bool isShortAnswer = false,
}) {
  if (answerText.isEmpty || isShortAnswer) return const [];
  final texts = answerText.split(',').map((t) => t.trim()).toList();
  return answers.where((a) => texts.contains(a.text.trim())).toList();
}

/// `isQuestionCorrect` — the local verdict, used only when the backend sends no
/// `is_correct` for the row.
///
/// `null` means "cannot be judged here": a short answer with text in it is
/// graded by a human, so the review shows "awaiting grading" instead of
/// painting it red or green.
bool? localQuestionCorrect(
  QuizQuestion question,
  List<QuizAnswer> selected, {
  String shortText = '',
}) {
  if (question.isShortAnswer) {
    return shortText.trim().isEmpty ? false : null;
  }

  final answers = question.answers;
  if (answers.isEmpty) return false;

  if (question.isMultipleChoice) {
    final correct = answers.where((a) => a.isCorrect).map((a) => a.id).toSet();
    final chosen = selected.map((a) => a.id).toSet();
    if (chosen.length != correct.length) return false;
    return correct.containsAll(chosen);
  }

  if (selected.length != 1) return false;
  return selected.first.isCorrect;
}

/// One question's review state, with the website's precedence applied.
class ExamQuestionReview {
  final QuizQuestion question;

  /// The options the student chose.
  final List<QuizAnswer> selected;

  /// The text of a short answer (server's `answer_text`, else what was typed).
  final String shortText;

  /// `true` / `false`, or `null` while a short answer awaits manual grading.
  final bool? correct;

  /// `true` when [selected] came from the student's in-memory picks because the
  /// server payload had no row for this question.
  final bool usedLocalSelection;

  /// The graded row, when the server sent one.
  final QuizAnswerReview? server;

  const ExamQuestionReview({
    required this.question,
    required this.selected,
    required this.shortText,
    required this.correct,
    required this.usedLocalSelection,
    this.server,
  });

  bool get isPending => correct == null;

  /// The options whose explanation is shown: exactly the website's rule —
  /// an option that is correct, or one the student chose.
  List<QuizAnswer> get explanationAnswers => question.answers
      .where((a) =>
          (a.hasReason || a.hasReasonImage) &&
          (a.isCorrect || selected.any((s) => s.id == a.id)))
      .toList();

  /// The correct option(s), from each option's own `is_correct`.
  List<QuizAnswer> get correctAnswers =>
      question.answers.where((a) => a.isCorrect).toList();
}

/// The student's local picks for a question, as answer objects.
List<QuizAnswer> localSelectedAnswers(QuizQuestion question) {
  if (question.isShortAnswer) return const [];
  if (question.isMultipleChoice) {
    return question.answers
        .where((a) => question.selectedAnswerIds.contains(a.answerId))
        .toList();
  }
  if (question.selectedAnswerId == null) return const [];
  return question.answers
      .where((a) => a.answerId == question.selectedAnswerId)
      .take(1)
      .toList();
}

/// Builds the review state for one question.
///
/// The server's row drives everything it can: the chosen options come from its
/// `answer_text`, and its `is_correct` is final. The in-memory selections are
/// consulted only when the server sent no row for this question — straight
/// after a submit that never reached the API, for instance. A locally computed
/// verdict can therefore never override the server's.
ExamQuestionReview buildQuestionReview(
  QuizQuestion question,
  QuizAnswerReview? server,
) {
  final serverText = server?.answerText.trim() ?? '';
  final hasServerRow = server != null;

  // The website's order (ExamAnswersReview.tsx): the picks made on this device
  // when there are any, otherwise the options resolved from `answer_text`.
  var selected = localSelectedAnswers(question);
  var usedLocal = true;
  if (selected.isEmpty && hasServerRow) {
    selected = selectedAnswersFromAnswerText(
      serverText,
      question.answers,
      isShortAnswer: question.isShortAnswer,
    );
    usedLocal = false;
  }

  final typed = question.textAnswer?.trim() ?? '';
  final shortText = question.isShortAnswer
      ? (hasServerRow && serverText.isNotEmpty ? serverText : typed)
      : '';

  final bool? correct = server?.isCorrect ??
      localQuestionCorrect(question, selected, shortText: shortText);

  return ExamQuestionReview(
    question: question,
    selected: selected,
    shortText: shortText,
    correct: correct,
    usedLocalSelection: usedLocal,
    server: server,
  );
}

Map? _asMap(dynamic value) => value is Map ? value : null;

/// `normalizeQuestions` — a raw question list parsed, with blank-text entries
/// dropped exactly as the website drops them.
List<QuizQuestion> parseQuestionList(dynamic raw) {
  var list = raw;
  if (list is Map && list['data'] is List) list = list['data'];
  if (list is! List) return const [];

  return list
      .whereType<Map>()
      .map((q) => QuizQuestion.fromJson(Map<String, dynamic>.from(q)))
      .where((q) => q.text.trim().isNotEmpty)
      .toList();
}

/// The questions carried by a quiz's own `attributes.questions`.
///
/// This is the website's single source for taking *and* reviewing an exam: the
/// quiz resource (`GET /v1/quiz/{id}`) is what carries each option's
/// `is_correct` and `reason`.
List<QuizQuestion> questionsFromQuizAttributes(Map? attributes) {
  if (attributes == null) return const [];
  return parseQuestionList(attributes['questions']);
}

/// The quiz's questions as the attempt-result payload carries them
/// (`payload.data.quiz ?? payload.quiz`), with the graded options attached.
///
/// This is what makes the correct answer appear at all: a review built from the
/// payload the exam was taken from can only mark the right option if that
/// payload happened to expose `is_correct`.
List<QuizQuestion> questionsFromResultPayload(dynamic payload) {
  final root = _asMap(payload);
  if (root == null) return const [];
  final data = _asMap(root['data']);
  final quiz = _asMap(data?['quiz']) ?? _asMap(root['quiz']);
  if (quiz == null) return const [];

  final fromAttributes = questionsFromQuizAttributes(_asMap(quiz['attributes']));
  if (fromAttributes.isNotEmpty) return fromAttributes;
  return parseQuestionList(quiz['questions']);
}
