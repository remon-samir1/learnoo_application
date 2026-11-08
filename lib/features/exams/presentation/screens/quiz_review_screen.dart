import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import '../../data/exam_repository.dart';
import '../../domain/exam_review.dart';
import '../../models/quiz_models.dart';
import '../../../../core/widgets/watermark_wrapper.dart';
import '../../../../core/widgets/image_preview_screen.dart';
import '../../../../core/services/feature_manager.dart';
import '../../../auth/data/auth_repository.dart';

class QuizReviewScreen extends StatefulWidget {
  final QuizResult result;
  final List<QuizQuestion> questions;

  /// When set, `GET /v1/quiz-attempts/{id}/result` is loaded — the same
  /// request the website's review makes. It is the only source of the graded
  /// quiz (options with `is_correct`), the student's own rows (`answer_text`),
  /// the per-question verdict, teacher feedback and attached images.
  final String? attemptId;

  /// An already-fetched result payload, handed over by the result screen so the
  /// review does not repeat the request.
  final dynamic resultPayload;

  const QuizReviewScreen({
    super.key,
    required this.result,
    required this.questions,
    this.attemptId,
    this.resultPayload,
  });

  @override
  State<QuizReviewScreen> createState() => _QuizReviewScreenState();
}

class _QuizReviewScreenState extends State<QuizReviewScreen> {
  final FeatureManager _featureManager = FeatureManager();
  final AuthRepository _authRepository = AuthRepository();
  final ExamRepository _examRepository = ExamRepository();
  String _studentCode = '';
  String _phoneNumber = '';
  int _currentPage = 0;
  late PageController _pageController;
  Map<String, QuizAnswerReview> _serverAnswers = const {};
  late List<QuizQuestion> _questions;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _questions = widget.questions;
    _loadUserData();
    if (widget.resultPayload != null) {
      _applyResultPayload(widget.resultPayload);
    } else {
      _loadServerReview();
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    final result = await _authRepository.getProfile();
    if (result['success'] && mounted) {
      final attributes = result['data']['attributes'] ?? {};
      final studentCode = attributes['student_code']?.toString() ?? '';
      final phoneNumber = attributes['phone']?.toString() ?? '';
      setState(() {
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
      }
    }
  }

  /// The graded attempt, as the website's review reads it. The in-memory
  /// questions stay as the fallback for the case the request cannot be made or
  /// fails (right after finishing while offline).
  Future<void> _loadServerReview() async {
    final attemptId = widget.attemptId?.trim() ?? '';
    if (attemptId.isEmpty) return;
    final result = await _examRepository.getAttemptResult(attemptId);
    if (!mounted || result['success'] != true) return;
    _applyResultPayload(result['data']);
  }

  /// Swaps in the server's quiz and answer rows.
  ///
  /// The graded quiz is preferred over the one the exam was taken from, because
  /// only the graded copy carries each option's `is_correct` — without it the
  /// correct answer cannot be marked at all. The selections made on the device
  /// are carried across so they can still serve as a fallback for any question
  /// the server sent no row for.
  void _applyResultPayload(dynamic payload) {
    final serverQuestions = questionsFromResultPayload(payload);
    final answers = QuizAnswerReview.mapFromResultPayload(payload);
    if (serverQuestions.isEmpty && answers.isEmpty) return;

    if (serverQuestions.isNotEmpty) {
      final local = <String, QuizQuestion>{
        for (final q in widget.questions) q.questionId.toString(): q,
      };
      for (final question in serverQuestions) {
        final previous = local[question.questionId.toString()];
        if (previous == null) continue;
        question.selectedAnswerId = previous.selectedAnswerId;
        question.selectedAnswerIds = previous.selectedAnswerIds;
        question.textAnswer = previous.textAnswer;
      }
    }

    if (!mounted) return;
    setState(() {
      if (serverQuestions.isNotEmpty) _questions = serverQuestions;
      _serverAnswers = answers;
      if (_currentPage >= _questions.length) {
        _currentPage = _questions.isEmpty ? 0 : _questions.length - 1;
      }
    });
  }

  ExamQuestionReview _reviewFor(QuizQuestion question) => buildQuestionReview(
        question,
        _serverAnswers[question.questionId.toString()],
      );

  bool get _isRtl => Directionality.of(context) == TextDirection.rtl;

  /// Visual "back" / "forward" chevrons that follow the reading direction.
  FaIconData get _backChevron =>
      _isRtl ? FontAwesomeIcons.chevronRight : FontAwesomeIcons.chevronLeft;
  FaIconData get _forwardChevron =>
      _isRtl ? FontAwesomeIcons.chevronLeft : FontAwesomeIcons.chevronRight;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'exam.review_title'.tr(),
          style: const TextStyle(
            color: Color(0xFF1F2937),
            fontWeight: FontWeight.w600,
          ),
        ),
        leading: IconButton(
          icon: FaIcon(_backChevron, color: const Color(0xFF1F2937)),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: WatermarkWrapper(
        type: WatermarkType.exams,
        studentCode: _studentCode,
        phone: _phoneNumber,
        featureManager: _featureManager,
        child: Column(
          children: [
            // Progress indicator
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: Colors.white,
              child: Row(
                children: [
                  Text(
                    'exams.question_x_of_y'.tr(args: [
                      '${_currentPage + 1}',
                      '${_questions.length}',
                    ]),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1F2937),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Page indicator dots
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: List.generate(
                          _questions.length,
                          (index) => Container(
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: index == _currentPage
                                  ? const Color(0xFF8B5CF6)
                                  : const Color(0xFFE5E7EB),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // PageView for questions
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (index) {
                  setState(() {
                    _currentPage = index;
                  });
                },
                itemCount: _questions.length,
                itemBuilder: (context, index) {
                  final question = _questions[index];
                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: _buildQuestionReviewCard(context, question, index),
                  );
                },
              ),
            ),
            // Navigation buttons
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.white,
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _currentPage > 0
                          ? () {
                              _pageController.previousPage(
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeInOut,
                              );
                            }
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6B7280),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                        disabledBackgroundColor: const Color(0xFFE5E7EB),
                      ),
                      icon: FaIcon(_backChevron, size: 16),
                      label: Text(
                        'exams.previous'.tr(),
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _currentPage < _questions.length - 1
                          ? () {
                              _pageController.nextPage(
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeInOut,
                              );
                            }
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF8B5CF6),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                        disabledBackgroundColor: const Color(0xFFE5E7EB),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'exams.next'.tr(),
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(width: 8),
                          FaIcon(_forwardChevron, size: 16),
                        ],
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

  Widget _buildQuestionReviewCard(BuildContext context, QuizQuestion question, int index) {
    final review = _reviewFor(question);
    final isCorrect = review.correct == true;
    final isPending = review.isPending;
    final server = review.server;
    final userAnswerText = _userAnswerText(review);
    final correctAnswerText = _correctAnswerText(review);

    const pendingColor = Color(0xFFD97706);
    final statusColor = isPending
        ? pendingColor
        : (isCorrect ? const Color(0xFF10B981) : const Color(0xFFEF4444));
    final statusTextColor = isPending
        ? pendingColor
        : (isCorrect ? const Color(0xFF059669) : const Color(0xFFDC2626));
    final statusLabel = isPending
        ? 'exams.awaiting_grading'.tr()
        : (isCorrect ? 'exams.correct'.tr() : 'exams.incorrect'.tr());

    final selectedAnswers = review.selected;
    final feedbackAnswers = review.explanationAnswers;

    return Container(
      margin: EdgeInsets.zero,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: statusColor.withValues(alpha: 0.3),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: statusColor.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with status
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.08),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: statusColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: FaIcon(
                      isPending
                          ? FontAwesomeIcons.hourglassHalf
                          : (isCorrect ? FontAwesomeIcons.check : FontAwesomeIcons.xmark),
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'exams.review_question_n'.tr(args: ['${index + 1}']),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1F2937),
                        ),
                      ),
                      Text(
                        statusLabel,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: statusTextColor,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'exams.points_short'.tr(args: ['${question.score}']),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: statusTextColor,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Question content
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Question text
                Text(
                  question.text,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1F2937),
                    height: 1.5,
                  ),
                ),

                // Question image
                if (question.hasImage) ...[
                  const SizedBox(height: 12),
                  _ReviewImage(url: question.image!, maxHeight: 260),
                ],

                const SizedBox(height: 20),

                // User's Answer
                _buildAnswerSection(
                  title: isCorrect ? 'exams.your_answer_correct'.tr() : 'exams.your_answer'.tr(),
                  answerText: userAnswerText,
                  isCorrect: isCorrect,
                  isPending: isPending,
                  images: [
                    for (final a in selectedAnswers)
                      if (a.hasImage) a.image!,
                    ...?server?.answerImages,
                  ],
                ),

                // Show correct answer if user was wrong
                if (!isCorrect && !isPending && !question.isShortAnswer) ...[
                  const SizedBox(height: 12),
                  _buildAnswerSection(
                    title: 'exams.correct_answer'.tr(),
                    answerText: correctAnswerText,
                    isCorrect: true,
                    isPending: false,
                    images: [
                      for (final a in review.correctAnswers)
                        if (a.hasImage) a.image!,
                    ],
                  ),
                ],

                // Reason/Explanation (text and image), as on the website:
                // shown for answers that are correct or were selected.
                if (feedbackAnswers.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _buildReasonSection(feedbackAnswers),
                ],

                // Teacher feedback / correction images from grading.
                if (server != null &&
                    (server.feedback != null || server.feedbackImages.isNotEmpty)) ...[
                  const SizedBox(height: 16),
                  _buildTeacherFeedbackSection(server),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnswerSection({
    required String title,
    required String answerText,
    required bool isCorrect,
    required bool isPending,
    List<String> images = const [],
  }) {
    final Color bgColor;
    final Color borderColor;
    final Color textColor;
    if (isPending) {
      bgColor = const Color(0xFFFFFBEB);
      borderColor = const Color(0xFFF59E0B);
      textColor = const Color(0xFFD97706);
    } else if (isCorrect) {
      bgColor = const Color(0xFFF0FDF4);
      borderColor = const Color(0xFF10B981);
      textColor = const Color(0xFF059669);
    } else {
      bgColor = const Color(0xFFFEF2F2);
      borderColor = const Color(0xFFEF4444);
      textColor = const Color(0xFFDC2626);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FaIcon(
                isPending
                    ? FontAwesomeIcons.hourglassHalf
                    : (isCorrect ? FontAwesomeIcons.circleCheck : FontAwesomeIcons.circleXmark),
                size: 14,
                color: textColor,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            answerText.isEmpty ? 'exams.no_answer_provided'.tr() : answerText,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: answerText.isEmpty ? const Color(0xFF9CA3AF) : const Color(0xFF1F2937),
            ),
          ),
          for (final url in images) ...[
            const SizedBox(height: 10),
            _ReviewImage(url: url),
          ],
        ],
      ),
    );
  }

  Widget _buildReasonSection(List<QuizAnswer> answers) {
    return _buildNoteSection(
      icon: FontAwesomeIcons.lightbulb,
      title: 'exams.explanation'.tr(),
      background: const Color(0xFFFEF3C7),
      accent: const Color(0xFFD97706),
      textColor: const Color(0xFF92400E),
      children: [
        for (final answer in answers) ...[
          if (answer.hasReason)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                answer.reason!,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF92400E),
                  height: 1.5,
                ),
              ),
            ),
          if (answer.hasReasonImage)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: _ReviewImage(url: answer.reasonImage!),
            ),
        ],
      ],
    );
  }

  Widget _buildTeacherFeedbackSection(QuizAnswerReview server) {
    return _buildNoteSection(
      icon: FontAwesomeIcons.chalkboardUser,
      title: 'exams.teacher_feedback'.tr(),
      background: const Color(0xFFEEF2FF),
      accent: const Color(0xFF4F46E5),
      textColor: const Color(0xFF312E81),
      children: [
        if (server.feedback != null)
          Text(
            server.feedback!,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF312E81),
              height: 1.5,
            ),
          ),
        for (final url in server.feedbackImages)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _ReviewImage(url: url),
          ),
      ],
    );
  }

  Widget _buildNoteSection({
    required FaIconData icon,
    required String title,
    required Color background,
    required Color accent,
    required Color textColor,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FaIcon(icon, size: 14, color: accent),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }

  /// The student's answer as text: a short answer verbatim, otherwise the
  /// options resolved from the server's `answer_text`.
  String _userAnswerText(ExamQuestionReview review) {
    if (review.question.isShortAnswer) return review.shortText;
    if (review.selected.isEmpty) {
      // The row exists but none of its texts matched an option — show what the
      // server recorded rather than nothing.
      return review.server?.answerText.trim() ?? '';
    }
    return review.selected.map((a) => a.text).join(', ');
  }

  String _correctAnswerText(ExamQuestionReview review) {
    final correctAnswers = review.correctAnswers;
    if (correctAnswers.isEmpty) return 'exams.not_available_short'.tr();
    return correctAnswers.map((a) => a.text).join(', ');
  }
}

/// Network image for the review screen: loading and error states, tap to zoom.
class _ReviewImage extends StatelessWidget {
  final String url;
  final double maxHeight;

  const _ReviewImage({required this.url, this.maxHeight = 220});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ImagePreviewScreen(imageUrl: url),
          ),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          constraints: BoxConstraints(maxHeight: maxHeight),
          color: const Color(0xFFF3F4F6),
          child: CachedNetworkImage(
            imageUrl: url,
            width: double.infinity,
            fit: BoxFit.contain,
            placeholder: (context, url) => const SizedBox(
              height: 150,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
            errorWidget: (context, url, error) => SizedBox(
              height: 120,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const FaIcon(FontAwesomeIcons.image, color: Color(0xFF9CA3AF), size: 28),
                    const SizedBox(height: 8),
                    Text(
                      'exams.failed_load_image'.tr(),
                      style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
