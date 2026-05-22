import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:cached_network_image/cached_network_image.dart';

import '../../data/exam_repository.dart';
import '../../models/quiz_models.dart';
import 'exam_results_screen.dart';
import 'exams_list_screen.dart';
import 'quiz_review_screen.dart';
import '../../../../core/widgets/watermark_wrapper.dart';
import '../../../../core/widgets/image_preview_screen.dart';
import '../../../../core/services/feature_manager.dart';
import '../../../../core/services/screen_protection_service.dart';
import '../../../auth/data/auth_repository.dart';

class QuizScreen extends StatefulWidget {
  final Quiz quiz;
  final QuizAttempt attempt;

  const QuizScreen({super.key, required this.quiz, required this.attempt});

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> with WidgetsBindingObserver {
  final ExamRepository _examRepository = ExamRepository();
  final ScreenProtectionService _screenProtection = ScreenProtectionService();
  int _currentQuestionIndex = 0;
  int _remainingSeconds = 0;
  Timer? _timer;
  List<QuizQuestion> _questions = [];
  bool _isLoading = true;
  bool _isSubmitting = false;

  // User info for watermark
  String _userName = '';
  String _userId = '';
  String _studentCode = '';
  String _phoneNumber = '';
  bool _showWatermark = true;
  final FeatureManager _featureManager = FeatureManager();
  final AuthRepository _authRepository = AuthRepository();

  // Exam protection state
  bool _isAppPaused = false;
  int _pauseCount = 0;
  DateTime? _lastPauseTime;
  static const int maxAllowedPauses =
      1; // Maximum allowed app switches before auto-submit

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _remainingSeconds = widget.quiz.duration * 60;
    _initializeProtection();
    _loadQuestions();
    _loadUserData();
    _startTimer();
  }

  Future<void> _loadUserData() async {
    final result = await _authRepository.getProfile();
    if (result['success'] && mounted) {
      final attributes = result['data']['attributes'] ?? {};
      final firstName = attributes['first_name']?.toString() ?? '';
      final lastName = attributes['last_name']?.toString() ?? '';
      final userId = result['data']['id']?.toString() ?? '';
      final studentCode = attributes['student_code']?.toString() ?? '';
      final phoneNumber = attributes['phone']?.toString() ?? '';
      setState(() {
        _userName = '$firstName $lastName'.trim();
        _userId = userId;
        _studentCode = studentCode;
        _phoneNumber = phoneNumber;
      });
    } else {
      // API failed or offline - use cached watermark data
      final cachedData = _authRepository.getCachedWatermarkData();
      if (mounted) {
        setState(() {
          _studentCode = cachedData['student_code'] ?? '';
          _phoneNumber = cachedData['phone'] ?? '';
        });
        debugPrint(
          '[QuizScreen] Using cached watermark data: studentCode=$_studentCode, phone=$_phoneNumber',
        );
      }
    }
  }

  /// Get combined watermark text based on feature settings
  String? get _watermarkText {
    final config = _featureManager.getWatermarkConfig('exams');
    final parts = <String>[];

    if (config.useStudentCode && _studentCode.isNotEmpty) {
      parts.add(_studentCode);
    }
    if (config.usePhoneNumber && _phoneNumber.isNotEmpty) {
      parts.add(_phoneNumber);
    }

    return parts.isNotEmpty ? parts.join(' | ') : null;
  }

  Future<void> _initializeProtection() async {
    // Initialize screen protection service
    await _screenProtection.initialize();

    // Enable global protection only if feature flags are enabled
    final blockScreenshots = _featureManager.isBlockScreenshotsEnabled;
    final screenShareMaxRes = _featureManager.isScreenShareMaxResolutionEnabled;

    if (blockScreenshots || screenShareMaxRes) {
      // Enable global protection (FLAG_SECURE on Android, iOS protection)
      await _screenProtection.enableGlobalProtection();
    }
  }

  Future<void> _loadQuestions() async {
    // Load questions (answers are now included in the question response)
    final questionResult = await _examRepository.getQuizQuestions(
      widget.quiz.quizId,
    );
    if (!mounted) return;

    if (questionResult['success']) {
      setState(() {
        _questions = questionResult['data'] as List<QuizQuestion>;
        _isLoading = false;
      });
    } else {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    // Disable global protection when leaving exam
    _screenProtection.disableGlobalProtection();
    super.dispose();
  }

  // Handle app lifecycle changes for exam protection
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.inactive) {
      // User attempted to leave the app
      _handleAppPause();
    } else if (state == AppLifecycleState.resumed) {
      // User returned to the app
      _handleAppResume();
    }
  }

  void _handleAppPause() {
    if (_isSubmitting) return;

    _pauseCount++;
    _lastPauseTime = DateTime.now();

    setState(() {
      _isAppPaused = true;
    });

    // Auto-submit if user has paused too many times
    if (_pauseCount > maxAllowedPauses) {
      _showViolationAndSubmit('exam.violation_multiple_leaves'.tr());
      return;
    }

    // Show warning overlay but don't auto-submit immediately on first pause
    // This gives user a chance to return immediately
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _isAppPaused && !_isSubmitting) {
        // If still paused after 3 seconds, auto-submit
        _showViolationAndSubmit('exam.violation_auto_submit'.tr());
      }
    });
  }

  void _handleAppResume() {
    if (_isSubmitting) return;

    setState(() {
      _isAppPaused = false;
    });

    // If user returned quickly (within 3 seconds), show warning but continue
    if (_lastPauseTime != null) {
      final pauseDuration = DateTime.now().difference(_lastPauseTime!);
      if (pauseDuration.inSeconds < 3 && _pauseCount <= maxAllowedPauses) {
        _showWarningDialog();
      }
    }
  }

  void _showWarningDialog() {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const FaIcon(
              FontAwesomeIcons.triangleExclamation,
              color: Colors.orange,
              size: 24,
            ),
            const SizedBox(width: 8),
            Text('exam.warning_title'.tr()),
          ],
        ),
        content: Text(
          'exam.leave_warning'.tr(
            namedArgs: {
              'count': _pauseCount.toString(),
              'max': maxAllowedPauses.toString(),
            },
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3343D6),
            ),
            child: Text('exam.continue_exam'.tr()),
          ),
        ],
      ),
    );
  }

  void _showViolationAndSubmit(String message) {
    if (!mounted || _isSubmitting) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const FaIcon(
              FontAwesomeIcons.circleExclamation,
              color: Colors.red,
              size: 24,
            ),
            const SizedBox(width: 8),
            Text('exam.violation_title'.tr()),
          ],
        ),
        content: Text(message),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _autoSubmit();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('exam.ok'.tr()),
          ),
        ],
      ),
    );
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        if (_remainingSeconds > 0) {
          _remainingSeconds--;
        } else {
          _timer?.cancel();
          _submitExam();
        }
      });
    });
  }

  String get _formattedTime {
    final minutes = _remainingSeconds ~/ 60;
    final seconds = _remainingSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  // Handle single choice and true/false answer selection
  void _selectAnswer(int answerId) {
    final currentQuestion = _questions[_currentQuestionIndex];
    if (currentQuestion.isMultipleChoice)
      return; // Don't use for multiple choice

    setState(() {
      _questions[_currentQuestionIndex].selectedAnswerId = answerId;
    });
  }

  // Handle multiple choice answer selection
  void _toggleMultipleAnswer(int answerId) {
    final currentQuestion = _questions[_currentQuestionIndex];
    if (!currentQuestion.isMultipleChoice) return;

    setState(() {
      final selectedIds = currentQuestion.selectedAnswerIds.toList();
      if (selectedIds.contains(answerId)) {
        selectedIds.remove(answerId);
      } else {
        selectedIds.add(answerId);
      }
      _questions[_currentQuestionIndex].selectedAnswerIds = selectedIds;
    });
  }

  // Handle short answer text input
  void _updateTextAnswer(String text) {
    final currentQuestion = _questions[_currentQuestionIndex];
    if (!currentQuestion.isShortAnswer) return;

    setState(() {
      _questions[_currentQuestionIndex].textAnswer = text;
    });
  }

  // Check if current question has been answered
  bool _isCurrentQuestionAnswered() {
    final currentQuestion = _questions[_currentQuestionIndex];
    if (currentQuestion.isSingleChoice || currentQuestion.isTrueFalse) {
      return currentQuestion.selectedAnswerId != null;
    } else if (currentQuestion.isMultipleChoice) {
      return currentQuestion.selectedAnswerIds.isNotEmpty;
    } else if (currentQuestion.isShortAnswer) {
      return currentQuestion.textAnswer != null &&
          currentQuestion.textAnswer!.trim().isNotEmpty;
    }
    return false;
  }

  // Get count of answered questions
  int _getAnsweredCount() {
    int count = 0;
    for (final question in _questions) {
      if (question.isSingleChoice || question.isTrueFalse) {
        if (question.selectedAnswerId != null) count++;
      } else if (question.isMultipleChoice) {
        if (question.selectedAnswerIds.isNotEmpty) count++;
      } else if (question.isShortAnswer) {
        if (question.textAnswer != null &&
            question.textAnswer!.trim().isNotEmpty)
          count++;
      }
    }
    return count;
  }

  void _goToNextQuestion() {
    if (_currentQuestionIndex < _questions.length - 1) {
      setState(() {
        _currentQuestionIndex++;
      });
    } else {
      _showSubmitConfirmation();
    }
  }

  void _goToPreviousQuestion() {
    if (_currentQuestionIndex > 0) {
      setState(() {
        _currentQuestionIndex--;
      });
    }
  }

  void _showSubmitConfirmation() {
    // Check if all questions are answered
    final answeredCount = _getAnsweredCount();
    final unanswered = _questions.length - answeredCount;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('exam.submit_title'.tr()),
        content: unanswered > 0
            ? Text(
                'exam.unanswered_questions'.tr(
                  namedArgs: {'count': unanswered.toString()},
                ),
              )
            : Text('exam.confirm_submit'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('exam.cancel'.tr()),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _submitExam();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3343D6),
            ),
            child: Text('exam.submit'.tr()),
          ),
        ],
      ),
    );
  }

  void _autoSubmit() {
    if (_isSubmitting) return;
    _submitExam(isAutoSubmit: true, navigateToList: true);
  }

  Future<void> _submitExam({bool isAutoSubmit = false, bool navigateToList = false}) async {
    if (_isSubmitting) return;

    setState(() {
      _isSubmitting = true;
    });
    _timer?.cancel();

    // Prepare answers based on question type
    final answers = <Map<String, dynamic>>[];
    for (final question in _questions) {
      if (question.isSingleChoice || question.isTrueFalse) {
        if (question.selectedAnswerId != null) {
          answers.add({
            'question_id': question.questionId,
            'answer_id': question.selectedAnswerId,
          });
        }
      } else if (question.isMultipleChoice) {
        // Submit each selected answer for multiple choice
        for (final answerId in question.selectedAnswerIds) {
          answers.add({
            'question_id': question.questionId,
            'answer_id': answerId,
          });
        }
      } else if (question.isShortAnswer) {
        // Short answer - text submission
        if (question.textAnswer != null &&
            question.textAnswer!.trim().isNotEmpty) {
          answers.add({
            'question_id': question.questionId,
            'text_answer': question.textAnswer,
          });
        }
      }
    }

    // Calculate score client-side based on correct answers
    int correctAnswers = 0;
    int totalScore = 0;
    int userScore = 0;
    for (final question in _questions) {
      if (question.isUserAnswerCorrect) {
        correctAnswers++;
        userScore += question.score;
      }
      totalScore += question.score;
    }

    final percentage = totalScore > 0 ? (userScore / totalScore) * 100 : 0;

    // Submit to API with calculated score
    final result = await _examRepository.submitQuizAttempt(
      attemptId: int.parse(widget.attempt.id),
      quizId: widget.quiz.quizId,
      answers: [], // Not used anymore - client-side scoring
      score: userScore,
      totalScore: totalScore,
    );

    if (!mounted) return;

    if (result['success']) {
      final quizResult = QuizResult(
        quizId: widget.quiz.id,
        quizTitle: widget.quiz.title,
        score: userScore,
        totalScore: totalScore,
        percentage: percentage.toDouble(),
        correctAnswers: correctAnswers,
        totalQuestions: _questions.length,
        passed: percentage >= 60,
        completedAt: DateTime.now(),
      );

      if (navigateToList) {
        // Show notification and navigate to exams list
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('exam.auto_submitted_message'.tr()),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 3),
          ),
        );
        
        // Navigate to exams list screen
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (context) => const ExamsListScreen(),
          ),
          (route) => false,
        );
      } else {
        // Navigate to results screen with questions for review
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) =>
                ExamResultsScreen(result: quizResult, questions: _questions),
          ),
        );
      }
    } else {
      // Even if API fails, still show results to user
      final quizResult = QuizResult(
        quizId: widget.quiz.id,
        quizTitle: widget.quiz.title,
        score: userScore,
        totalScore: totalScore,
        percentage: percentage.toDouble(),
        correctAnswers: correctAnswers,
        totalQuestions: _questions.length,
        passed: percentage >= 60,
        completedAt: DateTime.now(),
      );

      if (navigateToList) {
        // Show notification and navigate to exams list
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('exam.auto_submitted_message'.tr()),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 3),
          ),
        );
        
        // Navigate to exams list screen
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (context) => const ExamsListScreen(),
          ),
          (route) => false,
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) =>
                ExamResultsScreen(result: quizResult, questions: _questions),
          ),
        );
      }
    }
  }

  Future<bool> _onWillPop() async {
    if (_isSubmitting) return false;

    // Prevent back button - show warning instead
    final shouldExit = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const FaIcon(
              FontAwesomeIcons.triangleExclamation,
              color: Colors.orange,
              size: 24,
            ),
            const SizedBox(width: 8),
            Text('exam.exit_title'.tr()),
          ],
        ),
        content: Text('exam.exit_warning'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('exam.stay'.tr()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('exam.leave_submit'.tr()),
          ),
        ],
      ),
    );

    if (shouldExit == true) {
      _autoSubmit();
      return false; // Let the submission handle navigation
    }
    return false; // Always return false to prevent immediate pop
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                'Loading questions...',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      );
    }

    if (_questions.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: const Text('Exam'),
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF1F2937),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const FaIcon(
                FontAwesomeIcons.circleExclamation,
                size: 48,
                color: Colors.orange,
              ),
              const SizedBox(height: 16),
              const Text(
                'No questions available',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Go Back'),
              ),
            ],
          ),
        ),
      );
    }

    final currentQuestion = _questions[_currentQuestionIndex];
    final progress = (_currentQuestionIndex + 1) / _questions.length;
    final answers = currentQuestion.answers;

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Stack(
        children: [
          Scaffold(
            backgroundColor: Colors.white,
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),
                    // Header Row
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.quiz.title,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF1F2937),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Question ${_currentQuestionIndex + 1} of ${_questions.length}',
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Color(0xFF9CA3AF),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Timer
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: _remainingSeconds < 60
                                ? const Color(0xFFFFF0F0)
                                : const Color(0xFFFFF4E6),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            children: [
                              FaIcon(
                                FontAwesomeIcons.clock,
                                size: 14,
                                color: _remainingSeconds < 60
                                    ? const Color(0xFFFF4B4B)
                                    : const Color(0xFFF2994A),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _formattedTime,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: _remainingSeconds < 60
                                      ? const Color(0xFFFF4B4B)
                                      : const Color(0xFFF2994A),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    // Progress Bar
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: LinearProgressIndicator(
                        value: progress,
                        backgroundColor: const Color(0xFFE5E7EB),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFF3343D6),
                        ),
                        minHeight: 6,
                      ),
                    ),
                    const SizedBox(height: 32),
                    // Scrollable content - Question Card + Options
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            // Question Card - Modern Design
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: const Color(0xFFE5E7EB)),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.04),
                                    blurRadius: 20,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Question Number & Type Badge
                                  Row(
                                    children: [
                                      Container(
                                        width: 36,
                                        height: 36,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF3343D6),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Center(
                                          child: Text(
                                            '${_currentQuestionIndex + 1}',
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      _buildQuestionTypeBadge(currentQuestion.type),
                                      const Spacer(),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF3F4F6),
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                        child: Text(
                                          '${currentQuestion.score} pts',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF6B7280),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  // Question Text
                                  Text(
                                    currentQuestion.text,
                                    style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF1F2937),
                                      height: 1.6,
                                    ),
                                  ),
                                  // Question Image - Modern Display
                                  if (currentQuestion.hasImage) ...[
                                    const SizedBox(height: 16),
                                    _buildImageCard(
                                      currentQuestion.image!,
                                      'Question Image',
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),
                            // Options - Answer choices
                            if (currentQuestion.isShortAnswer)
                              _buildShortAnswerInput()
                            else if (currentQuestion.isTrueFalse)
                              _buildTrueFalseButtons()
                            else if (answers.isEmpty)
                              const Center(
                                child: Text(
                                  'No answers available',
                                  style: TextStyle(
                                    color: Color(0xFF9CA3AF),
                                    fontSize: 14,
                                  ),
                                ),
                              )
                            else
                              ...answers.map((answer) {
                                if (currentQuestion.isMultipleChoice) {
                                  final isSelected = currentQuestion
                                      .selectedAnswerIds
                                      .contains(answer.answerId);
                                  return _buildMultipleChoiceCard(
                                    answer,
                                    isSelected,
                                  );
                                } else {
                                  final isSelected =
                                      currentQuestion.selectedAnswerId ==
                                      answer.answerId;
                                  return _buildSingleChoiceCard(
                                    answer,
                                    isSelected,
                                  );
                                }
                              }),
                            const SizedBox(height: 24),
                            // Navigation Row
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: const Color(0xFFE5E7EB),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  _buildNavButton(
                                    icon: FontAwesomeIcons.chevronLeft,
                                    onTap: _currentQuestionIndex > 0
                                        ? _goToPreviousQuestion
                                        : null,
                                  ),
                                  const SizedBox(width: 16),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF3F4F6),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      '${_currentQuestionIndex + 1}',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF1F2937),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  _buildNavButton(
                                    icon: FontAwesomeIcons.chevronRight,
                                    onTap: _goToNextQuestion,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Bottom Buttons
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _currentQuestionIndex > 0
                                ? _goToPreviousQuestion
                                : null,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _currentQuestionIndex > 0
                                  ? const Color(0xFF9CA3AF)
                                  : const Color(0xFFD1D5DB),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              side: BorderSide(
                                color: _currentQuestionIndex > 0
                                    ? const Color(0xFFE5E7EB)
                                    : const Color(0xFFF3F4F6),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                FaIcon(FontAwesomeIcons.chevronLeft, size: 14),
                                SizedBox(width: 8),
                                Text(
                                  'Previous',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _isSubmitting ? null : _goToNextQuestion,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF3343D6),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  _currentQuestionIndex < _questions.length - 1
                                      ? 'Next'
                                      : 'Submit',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const FaIcon(
                                  FontAwesomeIcons.chevronRight,
                                  size: 14,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
          // Watermark overlay for exam protection - controlled by API
          WatermarkWrapper(
            type: WatermarkType.exams,
            studentCode: _watermarkText,
            featureManager: _featureManager,
            child:
                Container(), // Empty child as the watermark is positioned fill
          ),
          // Pause blocking overlay - prevents viewing content when app is paused
          if (_isAppPaused)
            Positioned.fill(
              child: Container(
                color: Colors.black,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const FaIcon(
                        FontAwesomeIcons.circlePause,
                        color: Colors.white,
                        size: 64,
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'exam.paused_title'.tr(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Text(
                          'exam.paused_message'.tr(),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 16,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (_pauseCount > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.red.withOpacity(0.5),
                            ),
                          ),
                          child: Text(
                            'exam.warning_count'.tr(
                              namedArgs: {
                                'count': _pauseCount.toString(),
                                'max': maxAllowedPauses.toString(),
                              },
                            ),
                            style: const TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          // Submitting overlay - shows loading indicator when submitting exam
          if (_isSubmitting)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.7),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF3343D6)),
                        strokeWidth: 3,
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'exam.submitting'.tr(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // Modern Question Type Badge
  Widget _buildQuestionTypeBadge(String type) {
    String label;
    dynamic icon;
    Color color;

    switch (type) {
      case 'single_choice':
        label = 'Single Choice';
        icon = FontAwesomeIcons.circleDot;
        color = const Color(0xFF3343D6);
        break;
      case 'multiple_choice':
        label = 'Multiple Choice';
        icon = FontAwesomeIcons.squareCheck;
        color = const Color(0xFF10B981);
        break;
      case 'true_false':
        label = 'True / False';
        icon = FontAwesomeIcons.checkDouble;
        color = const Color(0xFFF2994A);
        break;
      case 'short_answer':
        label = 'Short Answer';
        icon = FontAwesomeIcons.penToSquare;
        color = const Color(0xFF8B5CF6);
        break;
      default:
        label = 'Question';
        icon = FontAwesomeIcons.question;
        color = const Color(0xFF6B7280);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FaIcon(icon, size: 12, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // Modern Image Card Display
  Widget _buildImageCard(String imageUrl, String? caption) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ImagePreviewScreen(
                    imageUrl: imageUrl,
                    heroTag: 'question_image_$_currentQuestionIndex',
                  ),
                ),
              );
            },
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                width: double.infinity,
                fit: BoxFit.contain,
                placeholder: (context, url) => Container(
                  height: 150,
                  color: const Color(0xFFF3F4F6),
                  child: const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
                errorWidget: (context, url, error) => Container(
                  height: 150,
                  color: const Color(0xFFF3F4F6),
                  child: const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        FaIcon(
                          FontAwesomeIcons.image,
                          color: Color(0xFF9CA3AF),
                          size: 32,
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Failed to load image',
                          style: TextStyle(
                            color: Color(0xFF9CA3AF),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (caption != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const FaIcon(
                    FontAwesomeIcons.image,
                    size: 12,
                    color: Color(0xFF9CA3AF),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    caption,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF6B7280),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // Modern Single Choice Card with optional image
  Widget _buildSingleChoiceCard(QuizAnswer answer, bool isSelected) {
    return GestureDetector(
      onTap: _isSubmitting ? null : () => _selectAnswer(answer.answerId),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFF0F2FF) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF3343D6)
                : const Color(0xFFE5E7EB),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFF3343D6).withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (answer.hasImage)
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ImagePreviewScreen(
                        imageUrl: answer.image!,
                        heroTag: 'answer_image_${answer.answerId}',
                      ),
                    ),
                  );
                },
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(14),
                  ),
                  child: CachedNetworkImage(
                    imageUrl: answer.image!,
                    width: double.infinity,
                    height: 120,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      height: 120,
                      color: const Color(0xFFF3F4F6),
                      child: const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                    errorWidget: (context, url, error) => Container(
                      height: 120,
                      color: const Color(0xFFF3F4F6),
                      child: const Center(
                        child: FaIcon(
                          FontAwesomeIcons.image,
                          color: Color(0xFF9CA3AF),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFF3343D6)
                            : const Color(0xFFD1D5DB),
                        width: 2,
                      ),
                      color: isSelected
                          ? const Color(0xFF3343D6)
                          : Colors.transparent,
                    ),
                    child: isSelected
                        ? const Center(
                            child: FaIcon(
                              FontAwesomeIcons.check,
                              size: 12,
                              color: Colors.white,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      answer.text,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: isSelected
                            ? const Color(0xFF3343D6)
                            : const Color(0xFF4B5563),
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Modern Multiple Choice Card with checkbox
  Widget _buildMultipleChoiceCard(QuizAnswer answer, bool isSelected) {
    return GestureDetector(
      onTap: _isSubmitting
          ? null
          : () => _toggleMultipleAnswer(answer.answerId),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFF0FDF4) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF10B981)
                : const Color(0xFFE5E7EB),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFF10B981).withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (answer.hasImage)
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ImagePreviewScreen(
                        imageUrl: answer.image!,
                        heroTag: 'answer_image_${answer.answerId}',
                      ),
                    ),
                  );
                },
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(14),
                  ),
                  child: CachedNetworkImage(
                    imageUrl: answer.image!,
                    width: double.infinity,
                    height: 120,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      height: 120,
                      color: const Color(0xFFF3F4F6),
                      child: const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                    errorWidget: (context, url, error) => Container(
                      height: 120,
                      color: const Color(0xFFF3F4F6),
                      child: const Center(
                        child: FaIcon(
                          FontAwesomeIcons.image,
                          color: Color(0xFF9CA3AF),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFF10B981)
                            : const Color(0xFFD1D5DB),
                        width: 2,
                      ),
                      color: isSelected
                          ? const Color(0xFF10B981)
                          : Colors.transparent,
                    ),
                    child: isSelected
                        ? const Center(
                            child: FaIcon(
                              FontAwesomeIcons.check,
                              size: 12,
                              color: Colors.white,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      answer.text,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: isSelected
                            ? const Color(0xFF059669)
                            : const Color(0xFF4B5563),
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // True/False Buttons - Modern Design
  Widget _buildTrueFalseButtons() {
    final currentQuestion = _questions[_currentQuestionIndex];
    final answers = currentQuestion.answers;

    // For true/false, we expect exactly 2 answers
    if (answers.length < 2) {
      return const Center(child: Text('Invalid true/false question'));
    }

    final trueAnswer = answers.firstWhere(
      (a) =>
          a.text.toLowerCase().contains('true') || a.text.toLowerCase() == 'صح',
      orElse: () => answers[0],
    );
    final falseAnswer = answers.firstWhere(
      (a) =>
          a.text.toLowerCase().contains('false') ||
          a.text.toLowerCase() == 'خطأ',
      orElse: () => answers[1],
    );

    final trueSelected =
        currentQuestion.selectedAnswerId == trueAnswer.answerId;
    final falseSelected =
        currentQuestion.selectedAnswerId == falseAnswer.answerId;

    return Column(
      children: [
        _buildTrueFalseButton(
          label: 'True',
          icon: FontAwesomeIcons.check,
          isSelected: trueSelected,
          color: const Color(0xFF10B981),
          onTap: () => _selectAnswer(trueAnswer.answerId),
        ),
        const SizedBox(height: 12),
        _buildTrueFalseButton(
          label: 'False',
          icon: FontAwesomeIcons.xmark,
          isSelected: falseSelected,
          color: const Color(0xFFEF4444),
          onTap: () => _selectAnswer(falseAnswer.answerId),
        ),
      ],
    );
  }

  Widget _buildTrueFalseButton({
    required String label,
    required dynamic icon,
    required bool isSelected,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: _isSubmitting ? null : onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.1) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? color : const Color(0xFFE5E7EB),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: color.withOpacity(0.15),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: isSelected ? color : const Color(0xFFF3F4F6),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: FaIcon(
                  icon,
                  size: 20,
                  color: isSelected ? Colors.white : const Color(0xFF6B7280),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? color : const Color(0xFF4B5563),
                ),
              ),
            ),
            if (isSelected)
              FaIcon(FontAwesomeIcons.circleCheck, color: color, size: 24),
          ],
        ),
      ),
    );
  }

  // Short Answer Input - Modern Design
  Widget _buildShortAnswerInput() {
    final currentQuestion = _questions[_currentQuestionIndex];

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: TextField(
        onChanged: _updateTextAnswer,
        enabled: !_isSubmitting,
        maxLines: 5,
        minLines: 3,
        textAlign: TextAlign.start,
        textDirection: TextDirection.rtl,
        decoration: InputDecoration(
          hintText: 'Type your answer here...',
          hintStyle: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 15),
          contentPadding: const EdgeInsets.all(20),
          border: InputBorder.none,
          suffixIcon:
              currentQuestion.textAnswer != null &&
                  currentQuestion.textAnswer!.isNotEmpty
              ? Container(
                  margin: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(
                    color: Color(0xFF8B5CF6),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: FaIcon(
                      FontAwesomeIcons.check,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                )
              : null,
        ),
      ),
    );
  }

  Widget _buildNavButton({
    required dynamic icon,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: onTap != null
              ? const Color(0xFFF3F4F6)
              : const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: FaIcon(
            icon,
            size: 16,
            color: onTap != null
                ? const Color(0xFF6B7280)
                : const Color(0xFFD1D5DB),
          ),
        ),
      ),
    );
  }
}
