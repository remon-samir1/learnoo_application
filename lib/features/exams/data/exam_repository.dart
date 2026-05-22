import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../core/network/api_constants.dart';
import '../models/quiz_models.dart';

class ExamRepository {
  final _storage = const FlutterSecureStorage();

  Future<String?> getToken() async {
    return await _storage.read(key: 'auth_token');
  }

  String _handleError(dynamic data, String defaultMessage) {
    if (data == null) return defaultMessage;

    if (data['message'] != null) {
      return data['message'].toString();
    }

    if (data['errors'] != null && data['errors'] is Map) {
      final errors = data['errors'] as Map<String, dynamic>;
      return errors.values
          .map((e) {
            if (e is List) return e.join(', ');
            return e.toString();
          })
          .join('\n');
    }

    return defaultMessage;
  }

  // Get all quizzes
  Future<Map<String, dynamic>> getQuizzes() async {
    final token = await getToken();
    if (token == null) return {'success': false, 'message': 'No token found'};

    final url = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.quiz}');
    try {
      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        final List<dynamic> quizData = data['data'] ?? [];
        final quizzes = quizData.map((q) => Quiz.fromJson(q)).toList();
        return {'success': true, 'data': quizzes};
      } else {
        return {
          'success': false,
          'message': _handleError(data, 'Failed to fetch quizzes'),
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  // Get quiz by ID
  Future<Map<String, dynamic>> getQuizById(int quizId) async {
    final token = await getToken();
    if (token == null) return {'success': false, 'message': 'No token found'};

    final url = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.quiz}/$quizId');
    try {
      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        final quiz = Quiz.fromJson(data['data']);
        return {'success': true, 'data': quiz};
      } else {
        return {
          'success': false,
          'message': _handleError(data, 'Failed to fetch quiz'),
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  // Get questions for a quiz
  Future<Map<String, dynamic>> getQuizQuestions(int quizId) async {
    final token = await getToken();
    if (token == null) return {'success': false, 'message': 'No token found'};

    final url = Uri.parse(
      '${ApiConstants.baseUrl}${ApiConstants.quizQuestion}?quiz_id=$quizId',
    );
    try {
      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        final List<dynamic> questionData = data['data'] ?? [];
        final questions = questionData.map((q) => QuizQuestion.fromJson(q)).toList();
        return {'success': true, 'data': questions};
      } else {
        return {
          'success': false,
          'message': _handleError(data, 'Failed to fetch quiz questions'),
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  // Get all answers (for a specific question or all)
  // DEPRECATED: Answers are now included in the questions API response
  // This method is kept for backward compatibility but should not be used
  @Deprecated('Answers are now included in getQuizQuestions response')
  Future<Map<String, dynamic>> getQuizAnswers({int? questionId}) async {
    final token = await getToken();
    if (token == null) return {'success': false, 'message': 'No token found'};

    var urlString = '${ApiConstants.baseUrl}${ApiConstants.quizAnswer}';
    if (questionId != null) {
      urlString += '?quiz_question_id=$questionId';
    }

    final url = Uri.parse(urlString);
    try {
      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        final List<dynamic> answerData = data['data'] ?? [];
        final answers = answerData.map((a) => QuizAnswer.fromJson(a)).toList();
        return {'success': true, 'data': answers};
      } else {
        return {
          'success': false,
          'message': _handleError(data, 'Failed to fetch quiz answers'),
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  // Get attempts for a specific quiz
  Future<Map<String, dynamic>> getQuizAttempts(int quizId) async {
    final token = await getToken();
    if (token == null) return {'success': false, 'message': 'No token found'};

    final url = Uri.parse(
      '${ApiConstants.baseUrl}${ApiConstants.quizAttempt}?quiz_id=$quizId',
    );
    try {
      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        final List<dynamic> attemptData = data['data'] ?? [];
        final attempts = attemptData.map((a) => QuizAttempt.fromJson(a)).toList();
        return {'success': true, 'data': attempts};
      } else {
        return {
          'success': false,
          'message': _handleError(data, 'Failed to fetch quiz attempts'),
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  // Get all attempts for current user
  Future<Map<String, dynamic>> getAllAttempts() async {
    final token = await getToken();
    if (token == null) return {'success': false, 'message': 'No token found'};

    final url = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.quizAttempt}');
    try {
      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        final List<dynamic> attemptData = data['data'] ?? [];
        final attempts = attemptData.map((a) => QuizAttempt.fromJson(a)).toList();
        return {'success': true, 'data': attempts};
      } else {
        return {
          'success': false,
          'message': _handleError(data, 'Failed to fetch attempts'),
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  // Start a new quiz attempt
  Future<Map<String, dynamic>> startQuizAttempt(int quizId) async {
    final token = await getToken();
    if (token == null) return {'success': false, 'message': 'No token found'};

    final url = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.quizAttempt}');
    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'quiz_id': quizId,
          'started_at': DateTime.now().toUtc().toIso8601String(),
        }),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 201 || response.statusCode == 200) {
        return {
          'success': true,
          'data': QuizAttempt.fromJson(data['data']),
          'message': data['message'] ?? 'Quiz attempt started',
        };
      } else {
        return {
          'success': false,
          'message': _handleError(data, 'Failed to start quiz attempt'),
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  // Submit quiz answers and complete attempt
  // Note: We calculate score client-side, so we only mark the attempt as finished
  // without submitting individual answers to the API
  Future<Map<String, dynamic>> submitQuizAttempt({
    required int attemptId,
    required int quizId,
    required List<Map<String, dynamic>> answers, // Not used - client-side scoring
    required int score,
    required int totalScore,
  }) async {
    final token = await getToken();
    if (token == null) return {'success': false, 'message': 'No token found'};

    // Note: Individual answers are NOT submitted to API anymore
    // We calculate score client-side based on correct answers in questions data
    // Just mark the attempt as finished with the calculated score

    final url = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.quizAttempt}/$attemptId');
    try {
      final response = await http.put(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'finished_at': DateTime.now().toUtc().toIso8601String(),
          'score': score,
          'total_score': totalScore,
        }),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {
          'success': true,
          'data': QuizAttempt.fromJson(data['data']),
          'message': data['message'] ?? 'Quiz submitted successfully',
        };
      } else {
        return {
          'success': false,
          'message': _handleError(data, 'Failed to submit quiz'),
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  // Calculate remaining attempts for a quiz (filtered by current user)
  Future<Map<String, dynamic>> getRemainingAttempts(int quizId, int maxAttempts, {Quiz? quiz}) async {
    // If we already have the quiz object with attempt data, use it
    if (quiz != null && quiz.quizId == quizId) {
      return {
        'success': true,
        'remainingAttempts': quiz.remainingAttempts,
        'currentAttempts': quiz.currentAttempts,
        'attempts': [], // We don't have the full list here, but usually not needed for simple check
      };
    }

    final result = await getQuizAttempts(quizId);
    if (!result['success']) {
      return {'success': false, 'message': result['message']};
    }

    // Get current user ID to filter attempts
    final token = await getToken();
    if (token == null) {
      return {'success': false, 'message': 'No token found'};
    }

    // Decode token to get user ID
    String? currentUserId;
    try {
      final parts = token.split('.');
      if (parts.length == 3) {
        final payload = jsonDecode(
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
        );
        currentUserId = payload['sub']?.toString();
      }
    } catch (e) {
      // Failed to decode token, will count all attempts as fallback
    }

    final allAttempts = result['data'] as List<QuizAttempt>;
    // Filter attempts by current user ID
    final userAttempts = currentUserId != null
        ? allAttempts.where((a) => a.userId == currentUserId).toList()
        : allAttempts;
    final remainingAttempts = maxAttempts - userAttempts.length;

    return {
      'success': true,
      'remainingAttempts': remainingAttempts > 0 ? remainingAttempts : 0,
      'attempts': userAttempts,
    };
  }

  /// Resolve chapter to its course ID
  /// Used when an exam has chapter_id but no course_id
  Future<Map<String, dynamic>> resolveChapterToCourse(int chapterId) async {
    final token = await getToken();
    if (token == null) return {'success': false, 'message': 'No token found'};

    final url = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.chapters}/$chapterId');
    try {
      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        final chapterData = data['data'];
        final attributes = chapterData?['attributes'] ?? {};
        final courseId = attributes['course_id'] ?? attributes['course']?['data']?['id'];

        if (courseId != null) {
          return {
            'success': true,
            'data': int.tryParse(courseId.toString()),
          };
        } else {
          return {
            'success': false,
            'message': 'Course ID not found for this chapter',
          };
        }
      } else {
        return {
          'success': false,
          'message': _handleError(data, 'Failed to resolve chapter'),
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  /// Activate quiz with activation code
  Future<Map<String, dynamic>> activateQuizCode({
    required String code,
    required int quizId,
  }) async {
    final token = await getToken();
    if (token == null) return {'success': false, 'message': 'No token found'};

    final url = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.codeActivate}');
    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'code': code,
          'item_type': 'quiz',
          'item_id': quizId,
        }),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {
          'success': true,
          'data': data['data'],
          'message': data['message'] ?? 'Activation successful',
        };
      } else {
        return {
          'success': false,
          'message': _handleError(data, 'Invalid activation code'),
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }
}
