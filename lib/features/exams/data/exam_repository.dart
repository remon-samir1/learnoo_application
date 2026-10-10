import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
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
        // Transport failures carry an English client-side message
        // ("No internet connection"); show the localized one instead.
        'message': error.isNetwork
            ? 'exams.network_error'.tr()
            : error.display(fallback),
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
        fallback: 'exams.load_failed'.tr(),
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
      return _fail(e, 'exams.load_failed'.tr());
    }
  }

  /// Every quiz the API returns for this student, across all server pages.
  ///
  /// The exams list filters to the student's own courses on the client. Doing
  /// that per server page left whole pages empty (page 1 and 2 held only other
  /// courses' exams, so "no exams" showed until page 3). Collecting every page
  /// first lets the caller filter once and paginate the result locally.
  ///
  /// Asks for large pages ([perPage]) and walks `meta.last_page` /
  /// `links.next`; stops on an empty page, a page with nothing new, or after
  /// [maxPages] as a safety net against a backend that ignores `page`.
  Future<Map<String, dynamic>> getAllQuizzes({
    String? title,
    int? courseId,
    int perPage = 100,
    int maxPages = 30,
  }) async {
    final byId = <String, Quiz>{};
    final order = <String>[];

    for (var page = 1; page <= maxPages; page++) {
      final result = await getQuizzes(
        page: page,
        perPage: perPage,
        title: title,
        courseId: courseId,
      );
      if (result['success'] != true) {
        // The first page failing is a real failure; a later one just ends the
        // walk with what we already have.
        if (page == 1) return result;
        break;
      }

      final quizzes = (result['data'] as List<Quiz>?) ?? const <Quiz>[];
      var added = 0;
      for (final quiz in quizzes) {
        final key = quiz.id.isNotEmpty ? quiz.id : '${quiz.quizId}';
        if (byId.containsKey(key)) continue;
        byId[key] = quiz;
        order.add(key);
        added++;
      }

      final meta = result['meta'] as Map<String, dynamic>?;
      final current = coercePositiveInt(meta?['current_page']) ?? page;
      final last = coercePositiveInt(meta?['last_page']);

      if (quizzes.isEmpty || added == 0) break;
      if (last != null) {
        if (current >= last) break;
      } else if (result['hasNextPage'] != true) {
        break;
      }
    }

    return {
      'success': true,
      'data': [for (final key in order) byId[key]!],
    };
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
        fallback: 'exams.load_exam_failed'.tr(),
      );

      final data = unwrapMap(payload);
      if (data == null) {
        return {'success': false, 'message': 'exams.exam_not_found'.tr()};
      }
      return {'success': true, 'data': Quiz.fromJson(data)};
    } catch (e) {
      return _fail(e, 'exams.load_exam_failed'.tr());
    }
  }

  Future<Map<String, dynamic>> getQuizQuestions(int quizId) async {
    try {
      final payload = await _api.get(
        ApiConstants.quizQuestion,
        query: {'quiz_id': quizId},
        skipAuthRedirect: true,
        fallback: 'errors.failed_fetch_quiz_questions'.tr(),
      );

      final questions = unwrapList(payload)
          .whereType<Map>()
          .map((q) => QuizQuestion.fromJson(Map<String, dynamic>.from(q)))
          .toList();

      return {'success': true, 'data': questions};
    } catch (e) {
      return _fail(e, 'errors.failed_fetch_quiz_questions'.tr());
    }
  }

  @Deprecated('Answers are now included in getQuizQuestions response')
  Future<Map<String, dynamic>> getQuizAnswers({int? questionId}) async {
    try {
      final payload = await _api.get(
        ApiConstants.quizAnswer,
        query: questionId == null ? null : {'quiz_question_id': questionId},
        fallback: 'errors.failed_fetch_quiz_answers'.tr(),
      );

      final answers = unwrapList(payload)
          .whereType<Map>()
          .map((a) => QuizAnswer.fromJson(Map<String, dynamic>.from(a)))
          .toList();

      return {'success': true, 'data': answers};
    } catch (e) {
      return _fail(e, 'errors.failed_fetch_quiz_answers'.tr());
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
        fallback: 'errors.failed_fetch_quiz_attempts'.tr(),
      );

      final attempts = unwrapList(payload)
          .whereType<Map>()
          .map((a) => QuizAttempt.fromJson(Map<String, dynamic>.from(a)))
          .toList();

      return {'success': true, 'data': attempts};
    } catch (e) {
      return _fail(e, 'errors.failed_fetch_quiz_attempts'.tr());
    }
  }

  Future<Map<String, dynamic>> getAllAttempts() async {
    try {
      final payload = await _api.get(
        ApiConstants.quizAttempt,
        fallback: 'errors.failed_fetch_attempts'.tr(),
      );

      final attempts = unwrapList(payload)
          .whereType<Map>()
          .map((a) => QuizAttempt.fromJson(Map<String, dynamic>.from(a)))
          .toList();

      return {'success': true, 'data': attempts};
    } catch (e) {
      return _fail(e, 'errors.failed_fetch_attempts'.tr());
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
        fallback: 'exams.failed_start'.tr(),
      );

      final data = unwrapMap(payload);
      if (data == null) {
        return {'success': false, 'message': 'exams.failed_start'.tr()};
      }

      return {
        'success': true,
        'data': QuizAttempt.fromJson(data),
        'message': payload is Map ? payload['message'] : null,
      };
    } catch (e) {
      return _fail(e, 'exams.failed_start'.tr());
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
        fallback: 'exams.failed_submit_exam'.tr(),
      );

      final data = unwrapMap(payload);
      return {
        'success': true,
        'data': data == null ? null : QuizAttempt.fromJson(data),
        'raw': payload,
        'message': payload is Map ? payload['message'] : null,
      };
    } catch (e) {
      return _fail(e, 'exams.failed_submit_exam'.tr());
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
      return {'success': false, 'message': 'errors.empty_answer'.tr()};
    }

    try {
      if (existingAnswerId != null) {
        await _api.put(
          '${ApiConstants.quizUserAnswer}/$existingAnswerId',
          body: {'answer_text': text},
          skipAuthRedirect: true,
          fallback: 'errors.failed_update_answer'.tr(),
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
        fallback: 'errors.failed_save_answer'.tr(),
      );

      final data = unwrapMap(payload);
      final id = coerceId(data?['id']);
      return {'success': true, 'id': id};
    } catch (e) {
      debugPrint('[quiz-user-answer] save failed: $e');
      return _fail(e, 'errors.failed_save_answer'.tr());
    }
  }

  /// `GET /v1/quiz-attempts/{id}/result` — the graded review payload.
  Future<Map<String, dynamic>> getAttemptResult(Object attemptId) async {
    try {
      final payload = await _api.get(
        ApiConstants.quizAttemptResult(attemptId),
        skipAuthRedirect: true,
        fallback: 'exams.load_result_failed'.tr(),
      );
      return {'success': true, 'data': payload};
    } catch (e) {
      return _fail(e, 'exams.load_result_failed'.tr());
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
        fallback: 'errors.failed_resolve_chapter'.tr(),
      );

      final data = unwrapMap(payload);
      final attributes = data?['attributes'];
      final attrs = attributes is Map ? attributes : const {};

      final courseId = coercePositiveInt(attrs['course_id']) ??
          coercePositiveInt(attrs['course']?['data']?['id']);

      if (courseId == null) {
        return {
          'success': false,
          'message': 'errors.course_id_not_found'.tr(),
        };
      }
      return {'success': true, 'data': courseId};
    } catch (e) {
      return _fail(e, 'errors.failed_resolve_chapter'.tr());
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
        fallback: 'exams.invalid_activation_code'.tr(),
      );

      return {
        'success': true,
        'data': payload is Map ? payload['data'] : null,
        'message': payload is Map ? payload['message'] : null,
      };
    } catch (e) {
      return _fail(e, 'exams.invalid_activation_code'.tr());
    }
  }
}
