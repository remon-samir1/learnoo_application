/// Exam score / percentage / pass-fail reading, ported field-for-field from
/// the website's `src/lib/student-exam-score.ts` and the precedence used by
/// `components/student/exams/ExamResultView.tsx`.
///
/// The app used to grade and judge the result entirely on the device: it
/// summed `question.score` for every locally-correct answer and called the
/// student passed at a hard-coded `percentage >= 60`. The website never does
/// that for display — it finishes the attempt, then re-reads
/// `GET /v1/quiz-attempts/{id}/result` and renders the server's numbers, with
/// the quiz's own `passing_marks` as the threshold and the server's `passed`
/// flag winning whenever it is a real boolean.
library;

import 'dart:math' as math;

/// JavaScript `Number(value)` for the shapes this payload can hold.
///
/// `ExamResultView` reads `results.percentage ?? undefined`, i.e. an absent or
/// `null` field means "unknown" (JS `Number(undefined)` is `NaN`), while an
/// empty string really does coerce to `0` there. Both are mirrored so the app
/// cannot disagree with the website on a malformed payload.
double? jsNumber(dynamic value) {
  if (value == null) return null;
  if (value is num) {
    final d = value.toDouble();
    return d.isFinite ? d : null;
  }
  if (value is bool) return value ? 1 : 0;
  if (value is String) {
    final s = value.trim();
    if (s.isEmpty) return 0;
    final d = double.tryParse(s);
    return (d != null && d.isFinite) ? d : null;
  }
  return null;
}

/// `clampPercentage` — finite values squeezed into 0..100, otherwise `null`.
double? clampPercentage(dynamic value) {
  final numeric = jsNumber(value);
  if (numeric == null) return null;
  return math.min(100.0, math.max(0.0, numeric));
}

/// `percentageFromScore` — `score / total * 100`, clamped. Needs `total > 0`.
double? percentageFromScore(dynamic score, dynamic total) {
  final numericScore = jsNumber(score);
  final numericTotal = jsNumber(total);
  if (numericScore == null || numericTotal == null || numericTotal <= 0) {
    return null;
  }
  return clampPercentage((numericScore / numericTotal) * 100);
}

/// `readPercentageWithScoreFallback` — the server's percentage wins; only when
/// it is unusable is `score / total` computed.
double? readPercentageWithScoreFallback(
  dynamic percentage,
  dynamic score,
  dynamic total,
) {
  return clampPercentage(percentage) ?? percentageFromScore(score, total);
}

/// `passingMarksPercentage` — the quiz's passing marks, read as a percentage.
double? passingMarksPercentage(dynamic passingMarks) {
  return clampPercentage(passingMarks);
}

/// `isExamPassed` — the backend's `passed` wins whenever it is a boolean; only
/// otherwise is the percentage compared against the threshold. With no
/// threshold (the quiz carries no numeric `passing_marks`) the website shows
/// "failed", and so does the app.
bool isExamPassed(dynamic passed, double? score, double? passingScore) {
  if (passed is bool) return passed;
  return score != null && passingScore != null && score >= passingScore;
}

/// `formatTimeTakenForDisplay` from `src/lib/quiz-finish-result-fields.ts`:
/// hide invalid or negative values.
double? formatTimeTakenForDisplay(dynamic raw) {
  final n = jsNumber(raw);
  if (n == null || n < 0) return null;
  return n;
}

Map? _asMap(dynamic value) => value is Map ? value : null;

/// The attempt-result payload read with `ExamResultView`'s exact precedence.
class ExamScoreSummary {
  /// `results.score ?? results.earned_marks ?? payload.data.score`
  final double? score;

  /// `results.total_score ?? quiz.total_marks ?? quiz.attributes.total_marks`
  final double? total;

  /// Clamped `results.percentage`, else `score / total * 100`.
  final double? percentage;

  /// Clamped quiz `passing_marks`, or `null` when the quiz carries none.
  final double? passingPercentage;

  /// Backend `passed` when boolean, else `percentage >= passingPercentage`.
  final bool passed;

  /// `results.time_taken`, in the unit the backend sends (minutes on the web).
  final double? timeTaken;

  /// Raw `results.finished_at`.
  final String? finishedAt;

  /// `quiz.title` / `quiz.attributes.title`, trimmed.
  final String? quizTitle;

  const ExamScoreSummary({
    this.score,
    this.total,
    this.percentage,
    this.passingPercentage,
    this.passed = false,
    this.timeTaken,
    this.finishedAt,
    this.quizTitle,
  });

  /// `true` once there is at least one figure worth showing instead of the
  /// device's own tally.
  bool get hasServerFigures =>
      score != null || total != null || percentage != null;

  /// Reads `GET /v1/quiz-attempts/{id}/result`.
  ///
  /// Returns `null` when the payload carries neither an attempt nor a quiz, so
  /// the caller can keep the locally computed result (straight after a finish
  /// that could not reach the server, for instance).
  ///
  /// [fallbackPassingMarks] / [fallbackTotalMarks] come from the `Quiz` the app
  /// already has in memory; they are consulted only when the payload itself
  /// carries no such field, which is the one place the app has to go beyond the
  /// website — the website's result page always has `quiz_info` from the same
  /// request, the app can be showing a result it finished while offline.
  static ExamScoreSummary? fromResultPayload(
    dynamic payload, {
    dynamic fallbackPassingMarks,
    dynamic fallbackTotalMarks,
  }) {
    final root = _asMap(payload);
    if (root == null) return null;
    final data = _asMap(root['data']);

    // `payload.results ?? payload.data.attempt ?? payload.attempt.data ?? payload.attempt`
    final attemptHolder = _asMap(root['attempt']);
    final results = _asMap(root['results']) ??
        _asMap(data?['attempt']) ??
        _asMap(attemptHolder?['data']) ??
        attemptHolder;

    // `payload.quiz_info ?? payload.data.quiz ?? payload.quiz`
    final quizInfo =
        _asMap(root['quiz_info']) ?? _asMap(data?['quiz']) ?? _asMap(root['quiz']);

    if (results == null && quizInfo == null) return null;

    // A JSON:API resource keeps its fields under `attributes`. The website only
    // ever reads the flat shape, so this fallback can add a figure where the
    // website would render a dash, never change one it does render.
    dynamic readResult(String key) {
      if (results == null) return null;
      if (results.containsKey(key)) return results[key];
      final attributes = _asMap(results['attributes']);
      return attributes == null ? null : attributes[key];
    }

    dynamic readQuiz(String key) {
      if (quizInfo == null) return null;
      if (quizInfo.containsKey(key)) return quizInfo[key];
      final attributes = _asMap(quizInfo['attributes']);
      return attributes == null ? null : attributes[key];
    }

    final score =
        readResult('score') ?? readResult('earned_marks') ?? data?['score'];
    final total = readResult('total_score') ?? readQuiz('total_marks') ?? fallbackTotalMarks;

    final percentage =
        readPercentageWithScoreFallback(readResult('percentage'), score, total);

    // The website only takes a threshold from a *numeric* `passing_marks`; a
    // missing or non-numeric one leaves `passPct` null.
    final rawPassingMarks = readQuiz('passing_marks');
    final passingMarks =
        rawPassingMarks is num ? rawPassingMarks : (fallbackPassingMarks is num ? fallbackPassingMarks : null);
    final passingPercentage =
        passingMarks == null ? null : passingMarksPercentage(passingMarks);

    final title = readQuiz('title')?.toString().trim();

    return ExamScoreSummary(
      score: jsNumber(score),
      total: jsNumber(total),
      percentage: percentage,
      passingPercentage: passingPercentage,
      passed: isExamPassed(readResult('passed'), percentage, passingPercentage),
      timeTaken: formatTimeTakenForDisplay(readResult('time_taken')),
      finishedAt: readResult('finished_at')?.toString().trim(),
      quizTitle: (title == null || title.isEmpty) ? null : title,
    );
  }
}

/// Marks rendered the way the website prints `${a} / ${b}`: whole numbers stay
/// whole, fractions keep their digits.
String formatMarks(double? value) {
  if (value == null) return '—';
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value.toString();
}
