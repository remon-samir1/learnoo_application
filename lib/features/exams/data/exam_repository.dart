import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_constants.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/session/session_manager.dart';
import '../../../core/utils/coerce.dart';
import '../models/quiz_models.dart';

/// Exams data access.
///
/// Rewritten on [ApiClient] and aligned with the web's exam flow. The two
/// behavioural changes:
///
///  * **Per-question answers are now sent to the server.** The old code
///    computed a score locally and submitted only that total, with a comment
///    saying individual answers are "NOT submitted to API anymore". That left
///    `short_answer` questions ungradable for app students, because the
///    instructor's review screen reads `/v1/quiz-user-answer` rows.
///  * Attempt payloads match the web exactly: `{quiz_id}` to start,
///    `{score, total_score}` to finish.
class ExamRepository {
  final ApiClient _api = ApiClient();

  Future<String?> getToken() => SessionManager().currentToken();

  Map<String, dynamic> _fail(Object error, String fallback) {
    if (error is ApiException) {
      return {
        'success': false,
        'message': error.display(fallback),
        'errors': error.errors,
        'statusCode': error.status,
      };
    }
    return {'success': false, 'message': fallback, 'statusCode': 0};
  }

  // ---------------------------------------------------------------------
  // Listing
  // ---------------------------------------------------------------------

  /// `GET /v1/quiz` with pagination, per_page, course_id and title/search.
  Future<Map<String, dynamic>> getQuizzes({
    int page = 1,
    int perPage = 500,
    String? title,
    int? courseId,
  }) async {
    try {
      final payload = await _api.get(
        ApiConstants.quiz,
        query: {
          'page': page,
          'per_page': perPage,
          if (courseId != null) 'course_id': courseId,
          if (title != null && title.trim().isNotEmpty) ...{
            'title': title.trim(),
            'search': title.trim(),
          },
        },
        fallback: 'Failed to fetch quizzes',
      );

      final quizzes = unwrapList(payload)
          .whereType<Map>()
          .map((q) => Quiz.fromJson(Map<String, dynamic>.from(q)))
          .toList();

      final meta = readMeta(payload);
      final hasNextPage = (payload is Map && payload['links']?['next'] != null) ||
          (meta != null &&
              (meta['current_page'] ?? 1) < (meta['last_page'] ?? 1)) ||
          (perPage < 500 && quizzes.length >= perPage);

      return {
        'success': true,
        'data': quizzes,
        'meta': meta,
        'hasNextPage': hasNextPage,
      };
    } catch (e) {
      return _fail(e, 'Failed to fetch quizzes');
    }
  }

  /// `GET /v1/quiz/{id}` — also the server-side access check.
  ///
  /// A 403 here is a business rule (exam not activated), so the session must
  /// not be dropped.
  Future<Map<String, dynamic>> getQuizById(int quizId) async {
    try {
      final payload = await _api.get(
        '${ApiConstants.quiz}/$quizId',
        skipAuthRedirect: true,
        fallback: 'Failed to fetch quiz',
      );

      final data = unwrapMap(payload);
      if (data == null) {
        return {'success': false, 'message': 'Quiz not found'};
      }
      return {'success': true, 'data': Quiz.fromJson(data)};
    } catch (e) {
      return _fail(e, 'Failed to fetch quiz');
    }
  }

  Future<Map<String, dynamic>> getQuizQuestions(int quizId) async {
    try {
      final payload = await _api.get(
        ApiConstants.quizQuestion,
        query: {'quiz_id': quizId},
        skipAuthRedirect: true,
        fallback: 'Failed to fetch quiz questions',
      );

      final questions = unwrapList(payload)
          .whereType<Map>()
          .map((q) => QuizQuestion.fromJson(Map<String, dynamic>.from(q)))
          .toList();

      return {'success': true, 'data': questions};
    } catch (e) {
      return _fail(e, 'Failed to fetch quiz questions');
    }
  }

  @Deprecated('Answers are now included in getQuizQuestions response')
  Future<Map<String, dynamic>> getQuizAnswers({int? questionId}) async {
    try {
      final payload = await _api.get(
        ApiConstants.quizAnswer,
        query: questionId == null ? null : {'quiz_question_id': questionId},
        fallback: 'Failed to fetch quiz answers',
      );

      final answers = unwrapList(payload)
          .whereType<Map>()
          .map((a) => QuizAnswer.fromJson(Map<String, dynamic>.from(a)))
          .toList();

      return {'success': true, 'data': answers};
    } catch (e) {
      return _fail(e, 'Failed to fetch quiz answers');
    }
  }

  // ---------------------------------------------------------------------
  // Attempts
  // ---------------------------------------------------------------------

  Future<Map<String, dynamic>> getQuizAttempts(int quizId) async {
    try {
      final payload = await _api.get(
        ApiConstants.quizAttempt,
        query: {'quiz_id': quizId},
        fallback: 'Failed to fetch quiz attempts',
      );

      final attempts = unwrapList(payload)
          .whereType<Map>()
          .map((a) => QuizAttempt.fromJson(Map<String, dynamic>.from(a)))
          .toList();

      return {'success': true, 'data': attempts};
    } catch (e) {
      return _fail(e, 'Failed to fetch quiz attempts');
    }
  }

  Future<Map<String, dynamic>> getAllAttempts() async {
    try {
      final payload = await _api.get(
        ApiConstants.quizAttempt,
        fallback: 'Failed to fetch attempts',
      );

      final attempts = unwrapList(payload)
          .whereType<Map>()
          .map((a) => QuizAttempt.fromJson(Map<String, dynamic>.from(a)))
          .toList();

      return {'success': true, 'data': attempts};
    } catch (e) {
      return _fail(e, 'Failed to fetch attempts');
    }
  }

  /// `POST /v1/quiz-attempt` with `{quiz_id}` only.
  ///
  /// The server stamps `started_at` itself; sending a client clock let a
  /// tampered device extend its own exam window. A 403 here means "no attempts
  /// left" — a rule, not an auth failure.
  Future<Map<String, dynamic>> startQuizAttempt(int quizId) async {
    try {
      final payload = await _api.post(
        ApiConstants.quizAttempt,
        body: {'quiz_id': quizId},
        skipAuthRedirect: true,
        fallback: 'Failed to start quiz attempt',
      );

      final data = unwrapMap(payload);
      if (data == null) {
        return {'success': false, 'message': 'Failed to start quiz attempt'};
      }

      return {
        'success': true,
        'data': QuizAttempt.fromJson(data),
        'message': payload is Map ? payload['message'] : null,
      };
    } catch (e) {
      return _fail(e, 'Failed to start quiz attempt');
    }
  }

  /// `PUT /v1/quiz-attempt/{id}` with `{score, total_score}`.
  ///
  /// [answers] is accepted for call-site compatibility and ignored — answers
  /// are persisted one at a time through [saveAnswer] while the student works,
  /// which is what makes them visible to an instructor.
  Future<Map<String, dynamic>> submitQuizAttempt({
    required int attemptId,
    required int quizId,
    List<Map<String, dynamic>> answers = const [],
    required int score,
    required int totalScore,
  }) async {
    try {
      final payload = await _api.put(
        '${ApiConstants.quizAttempt}/$attemptId',
        body: {'score': score, 'total_score': totalScore},
        skipAuthRedirect: true,
        fallback: 'Failed to submit quiz',
      );

      final data = unwrapMap(payload);
      return {
        'success': true,
        'data': data == null ? null : QuizAttempt.fromJson(data),
        'raw': payload,
        'message': payload is Map ? payload['message'] : null,
      };
    } catch (e) {
      return _fail(e, 'Failed to submit quiz');
    }
  }

  // ---------------------------------------------------------------------
  // Per-question answers
  // ---------------------------------------------------------------------

  /// Creates or updates the answer row for one question.
  ///
  /// Mirrors the web's POST-then-PUT: the first save creates a row and returns
  /// its id, every later change updates that same row. Pass the id back in
  /// [existingAnswerId] to take the update path.
  ///
  /// Returns the row id so the caller can cache it. Failures are non-fatal —
  /// the student must never be blocked mid-exam by a flaky save.
  Future<Map<String, dynamic>> saveAnswer({
    required Object attemptId,
    required Object questionId,
    required String answerText,
    Object? existingAnswerId,
  }) async {
    final text = answerText.trim();
    if (text.isEmpty) {
      return {'success': false, 'message': 'Empty answer'};
    }

    try {
      if (existingAnswerId != null) {
        await _api.put(
          '${ApiConstants.quizUserAnswer}/$existingAnswerId',
          body: {'answer_text': text},
          skipAuthRedirect: true,
          fallback: 'Failed to update answer',
        );
        return {'success': true, 'id': existingAnswerId};
      }

      final payload = await _api.post(
        ApiConstants.quizUserAnswer,
        body: {
          'quiz_attempt_id': attemptId,
          'quiz_question_id': questionId,
          'answer_text': text,
        },
        skipAuthRedirect: true,
        fallback: 'Failed to save answer',
      );

      final data = unwrapMap(payload);
      final id = coerceId(data?['id']);
      return {'success': true, 'id': id};
    } catch (e) {
      debugPrint('[quiz-user-answer] save failed: $e');
      return _fail(e, 'Failed to save answer');
    }
  }

  /// `GET /v1/quiz-attempts/{id}/result` — the graded review payload.
  Future<Map<String, dynamic>> getAttemptResult(Object attemptId) async {
    try {
      final payload = await _api.get(
        ApiConstants.quizAttemptResult(attemptId),
        skipAuthRedirect: true,
        fallback: 'Failed to load result',
      );
      return {'success': true, 'data': payload};
    } catch (e) {
      return _fail(e, 'Failed to load result');
    }
  }

  // ---------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------

  /// Attempts the student has left.
  ///
  /// Prefers the values the API attached to the quiz; only falls back to
  /// counting attempt rows when the quiz row is unavailable.
  Future<Map<String, dynamic>> getRemainingAttempts(
    int quizId,
    int maxAttempts, {
    Quiz? quiz,
  }) async {
    if (quiz != null && quiz.quizId == quizId) {
      return {
        'success': true,
        'remainingAttempts': quiz.remainingAttempts,
        'currentAttempts': quiz.currentAttempts,
        'attempts': const [],
      };
    }

    final result = await getQuizAttempts(quizId);
    if (result['success'] != true) {
      return {'success': false, 'message': result['message']};
    }

    final currentUserId = await _currentUserId();
    final allAttempts = result['data'] as List<QuizAttempt>;
    final userAttempts = currentUserId != null
        ? allAttempts.where((a) => a.userId == currentUserId).toList()
        : allAttempts;

    final remaining = maxAttempts - userAttempts.length;

    return {
      'success': true,
      'remainingAttempts': remaining > 0 ? remaining : 0,
      'attempts': userAttempts,
    };
  }

  Future<String?> _currentUserId() async {
    final token = await getToken();
    if (token == null) return null;
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      return payload['sub']?.toString();
    } catch (_) {
      return null;
    }
  }

  /// Resolve chapter to its course ID.
  /// Used when an exam has chapter_id but no course_id.
  Future<Map<String, dynamic>> resolveChapterToCourse(int chapterId) async {
    try {
      final payload = await _api.get(
        '${ApiConstants.chapters}/$chapterId',
        skipAuthRedirect: true,
        fallback: 'Failed to resolve chapter',
      );

      final data = unwrapMap(payload);
      final attributes = data?['attributes'];
      final attrs = attributes is Map ? attributes : const {};

      final courseId = coercePositiveInt(attrs['course_id']) ??
          coercePositiveInt(attrs['course']?['data']?['id']);

      if (courseId == null) {
        return {
          'success': false,
          'message': 'Course ID not found for this chapter',
        };
      }
      return {'success': true, 'data': courseId};
    } catch (e) {
      return _fail(e, 'Failed to resolve chapter');
    }
  }

  /// `POST /v1/code/activate` for an exam.
  ///
  /// The endpoint answers 200 even when it declines the code, so the caller
  /// must check `activateCodeUnlocksQuiz` on `data` before letting the student
  /// through. The raw body is returned for exactly that.
  Future<Map<String, dynamic>> activateQuizCode({
    required String code,
    required int quizId,
  }) async {
    try {
      final payload = await _api.post(
        ApiConstants.codeActivate,
        body: {
          'code': code,
          'item_type': 'quiz',
          'item_id': quizId,
        },
        skipAuthRedirect: true,
        fallback: 'Invalid activation code',
      );

      return {
        'success': true,
        'data': payload is Map ? payload['data'] : null,
        'message': payload is Map ? payload['message'] : null,
      };
    } catch (e) {
      return _fail(e, 'Invalid activation code');
    }
  }
}
