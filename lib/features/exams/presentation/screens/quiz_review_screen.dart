import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import '../../data/exam_repository.dart';
import '../../domain/exam_review.dart';
import '../../models/quiz_models.dart';
import '../widgets/review_option_widgets.dart';
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
    _ensureCorrectAnswers();
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
        _borrowGrading(question, previous);
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
    _ensureCorrectAnswers();
  }

  static bool _needsGrading(QuizQuestion q) =>
      !q.isShortAnswer && q.answers.isNotEmpty && !q.answers.any((a) => a.isCorrect);

  /// A payload question can come without options, or with options that carry no
  /// `is_correct` — then the review printed "n/a" for the right answer. Take the
  /// options (and their flags) from [source] when it has them.
  void _borrowGrading(QuizQuestion target, QuizQuestion source) {
    if (target.answers.isEmpty && source.answers.isNotEmpty) {
      target.answers = source.answers;
      return;
    }
    if (!_needsGrading(target) || !source.answers.any((a) => a.isCorrect)) {
      return;
    }
    final correctIds = {
      for (final a in source.answers)
        if (a.isCorrect) a.answerId,
    };
    final correctTexts = {
      for (final a in source.answers)
        if (a.isCorrect) a.text.trim(),
    };
    target.answers = [
      for (final a in target.answers)
        correctIds.contains(a.answerId) || correctTexts.contains(a.text.trim())
            ? QuizAnswer(
                id: a.id,
                answerId: a.answerId,
                quizQuestionId: a.quizQuestionId,
                text: a.text,
                image: a.image,
                reason: a.reason ??
                    source.answers
                        .where((s) => s.answerId == a.answerId)
                        .map((s) => s.reason)
                        .firstOrNull,
                reasonImage: a.reasonImage,
                isCorrect: true,
                createdAt: a.createdAt,
              )
            : a,
    ];
  }

  bool _fetchedQuiz = false;

  /// Last resort, the website's own source: `GET /v1/quiz/{id}` carries every
  /// option's `is_correct`. The exam-taking endpoints and the result payload
  /// may leave it out.
  Future<void> _ensureCorrectAnswers() async {
    if (_fetchedQuiz || !_questions.any(_needsGrading)) return;
    _fetchedQuiz = true;
    final quizId = int.tryParse(widget.result.quizId);
    if (quizId == null) return;
    final res = await _examRepository.getQuizById(quizId);
    if (!mounted || res['success'] != true) return;
    final quiz = res['data'];
    if (quiz is! Quiz) return;
    final graded = {
      for (final q in questionsFromQuizAttributes(quiz.attributes))
        q.questionId: q,
    };
    setState(() {
      for (final q in _questions) {
        final source = graded[q.questionId];
        if (source != null) _borrowGrading(q, source);
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

                // Same layout as the website's review: every option listed and
                // coloured (chosen/correct/missed), explanations under the
                // options they belong to.
                if (question.isShortAnswer) ...[
                  ReviewShortAnswerBox(review: review),
                  for (final url in server?.answerImages ?? const <String>[])
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: _ReviewImage(url: url),
                    ),
                ] else if (question.answers.isEmpty)
                  Text(
                    'exams.no_answer_provided'.tr(),
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF475569),
                    ),
                  )
                else ...[
                  for (final answer in question.answers)
                    ReviewOptionTile(
                      answer: answer,
                      review: review,
                      imageBuilder: (url) => _ReviewImage(url: url),
                    ),
                  if (question.isMultipleChoice)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'exams.type_multiple_choice'.tr(),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    ),
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
