import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../models/quiz_models.dart';
import '../../../../core/widgets/watermark_wrapper.dart';
import '../../../../core/widgets/image_preview_screen.dart';
import '../../../../core/services/feature_manager.dart';
import '../../../auth/data/auth_repository.dart';

class QuizReviewScreen extends StatefulWidget {
  final QuizResult result;
  final List<QuizQuestion> questions;

  const QuizReviewScreen({
    super.key,
    required this.result,
    required this.questions,
  });

  @override
  State<QuizReviewScreen> createState() => _QuizReviewScreenState();
}

class _QuizReviewScreenState extends State<QuizReviewScreen> {
  final FeatureManager _featureManager = FeatureManager();
  final AuthRepository _authRepository = AuthRepository();
  String _studentCode = '';
  String _phoneNumber = '';
  int _currentPage = 0;
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _loadUserData();
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

  String? get _watermarkText {
    final config = _featureManager.getWatermarkConfig('exams');
    final parts = <String>[];
    if (config.useStudentCode && _studentCode.isNotEmpty) {
      parts.add(_studentCode);
    }
    if (config.usePhoneNumber && _phoneNumber.isNotEmpty) {
      parts.add(_phoneNumber);
    }
    if (parts.isNotEmpty) return parts.join(' | ');
    return config.text.isNotEmpty ? config.text : null;
  }

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
          icon: const FaIcon(FontAwesomeIcons.chevronLeft, color: Color(0xFF1F2937)),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: WatermarkWrapper(
        type: WatermarkType.exams,
        studentCode: _watermarkText,
        featureManager: _featureManager,
        child: Column(
          children: [
            // Progress indicator
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: Colors.white,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Question ${_currentPage + 1} of ${widget.questions.length}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1F2937),
                    ),
                  ),
                  // Page indicator dots
                  Row(
                    children: List.generate(
                      widget.questions.length,
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
                itemCount: widget.questions.length,
                itemBuilder: (context, index) {
                  final question = widget.questions[index];
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
                      icon: const FaIcon(FontAwesomeIcons.chevronLeft, size: 16),
                      label: const Text('Previous', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _currentPage < widget.questions.length - 1
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
                      icon: const FaIcon(FontAwesomeIcons.chevronRight, size: 16),
                      label: const Text('Next', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
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
    final isCorrect = question.isUserAnswerCorrect;
    final userAnswerText = _getUserAnswerText(question);
    final correctAnswerText = _getCorrectAnswerText(question);

    return Container(
      margin: EdgeInsets.zero,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isCorrect ? const Color(0xFF10B981).withOpacity(0.3) : const Color(0xFFEF4444).withOpacity(0.3),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: (isCorrect ? const Color(0xFF10B981) : const Color(0xFFEF4444)).withOpacity(0.08),
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
              color: isCorrect ? const Color(0xFFF0FDF4) : const Color(0xFFFEF2F2),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: isCorrect ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: FaIcon(
                      isCorrect ? FontAwesomeIcons.check : FontAwesomeIcons.xmark,
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
                        'Question ${index + 1}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1F2937),
                        ),
                      ),
                      Text(
                        isCorrect ? 'Correct' : 'Incorrect',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: isCorrect ? const Color(0xFF059669) : const Color(0xFFDC2626),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isCorrect ? const Color(0xFF10B981).withOpacity(0.1) : const Color(0xFFEF4444).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${question.score} pts',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isCorrect ? const Color(0xFF059669) : const Color(0xFFDC2626),
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
                  _buildReviewImage(question.image!),
                ],

                const SizedBox(height: 20),

                // User's Answer
                _buildAnswerSection(
                  title: isCorrect ? 'Your Answer (Correct)' : 'Your Answer',
                  answerText: userAnswerText,
                  isCorrect: isCorrect,
                  question: question,
                  showUserAnswer: true,
                ),

                // Show correct answer if user was wrong
                if (!isCorrect) ...[
                  const SizedBox(height: 12),
                  _buildAnswerSection(
                    title: 'Correct Answer',
                    answerText: correctAnswerText,
                    isCorrect: true,
                    question: question,
                    showUserAnswer: false,
                  ),
                ],

                // Reason/Explanation
                if (_hasReason(question)) ...[
                  const SizedBox(height: 16),
                  _buildReasonSection(question),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewImage(String imageUrl) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ImagePreviewScreen(
              imageUrl: imageUrl,
              heroTag: 'review_image_$imageUrl',
            ),
          ),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: CachedNetworkImage(
          imageUrl: imageUrl,
          width: double.infinity,
          fit: BoxFit.contain,
          placeholder: (context, url) => Container(
            height: 150,
            color: const Color(0xFFF3F4F6),
            child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          errorWidget: (context, url, error) => Container(
            height: 150,
            color: const Color(0xFFF3F4F6),
            child: const Center(
              child: FaIcon(FontAwesomeIcons.image, color: Color(0xFF9CA3AF), size: 32),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAnswerSection({
    required String title,
    required String answerText,
    required bool isCorrect,
    required QuizQuestion question,
    required bool showUserAnswer,
  }) {
    final bgColor = isCorrect ? const Color(0xFFF0FDF4) : const Color(0xFFFEF2F2);
    final borderColor = isCorrect ? const Color(0xFF10B981) : const Color(0xFFEF4444);
    final textColor = isCorrect ? const Color(0xFF059669) : const Color(0xFFDC2626);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FaIcon(
                isCorrect ? FontAwesomeIcons.circleCheck : FontAwesomeIcons.circleXmark,
                size: 14,
                color: textColor,
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            answerText.isEmpty ? 'No answer provided' : answerText,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: answerText.isEmpty ? const Color(0xFF9CA3AF) : const Color(0xFF1F2937),
            ),
          ),
          // Show answer image if available
          if (showUserAnswer && _hasUserAnswerImage(question)) ...[
            const SizedBox(height: 10),
            _buildAnswerImage(question),
          ],
          if (!showUserAnswer && _hasCorrectAnswerImage(question)) ...[
            const SizedBox(height: 10),
            _buildCorrectAnswerImage(question),
          ],
        ],
      ),
    );
  }

  Widget _buildAnswerImage(QuizQuestion question) {
    QuizAnswer? answer;
    if (question.isSingleChoice || question.isTrueFalse) {
      answer = question.answers.firstWhere(
        (a) => a.answerId == question.selectedAnswerId,
        orElse: () => QuizAnswer(id: '', answerId: 0, quizQuestionId: 0, text: '', isCorrect: false, createdAt: DateTime.now()),
      );
    } else if (question.isMultipleChoice && question.selectedAnswerIds.isNotEmpty) {
      answer = question.answers.firstWhere(
        (a) => a.answerId == question.selectedAnswerIds.first,
        orElse: () => QuizAnswer(id: '', answerId: 0, quizQuestionId: 0, text: '', isCorrect: false, createdAt: DateTime.now()),
      );
    }

    if (answer != null && answer.hasImage) {
      final nonNullAnswer = answer;
      return GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ImagePreviewScreen(
                imageUrl: nonNullAnswer.image!,
                heroTag: 'answer_image_${nonNullAnswer.answerId}',
              ),
            ),
          );
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: CachedNetworkImage(
            imageUrl: nonNullAnswer.image!,
            width: 100,
            height: 80,
            fit: BoxFit.cover,
            placeholder: (context, url) => Container(
              width: 100,
              height: 80,
              color: const Color(0xFFF3F4F6),
              child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
            errorWidget: (context, url, error) => Container(
              width: 100,
              height: 80,
              color: const Color(0xFFF3F4F6),
              child: const Center(child: FaIcon(FontAwesomeIcons.image, color: Color(0xFF9CA3AF))),
            ),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildCorrectAnswerImage(QuizQuestion question) {
    final correctAnswers = question.correctAnswers;
    if (correctAnswers.isNotEmpty && correctAnswers.first.hasImage) {
      return GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ImagePreviewScreen(
                imageUrl: correctAnswers.first.image!,
                heroTag: 'correct_answer_image_${correctAnswers.first.answerId}',
              ),
            ),
          );
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: CachedNetworkImage(
            imageUrl: correctAnswers.first.image!,
            width: 100,
            height: 80,
            fit: BoxFit.cover,
            placeholder: (context, url) => Container(
              width: 100,
              height: 80,
              color: const Color(0xFFF3F4F6),
              child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
            errorWidget: (context, url, error) => Container(
              width: 100,
              height: 80,
              color: const Color(0xFFF3F4F6),
              child: const Center(child: FaIcon(FontAwesomeIcons.image, color: Color(0xFF9CA3AF))),
            ),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildReasonSection(QuizQuestion question) {
    final reasons = _getReasons(question);
    if (reasons.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const FaIcon(
                FontAwesomeIcons.lightbulb,
                size: 14,
                color: Color(0xFFD97706),
              ),
              const SizedBox(width: 8),
              const Text(
                'Explanation',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFD97706),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...reasons.map((reason) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              reason,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF92400E),
                height: 1.5,
              ),
            ),
          )),
        ],
      ),
    );
  }

  String _getUserAnswerText(QuizQuestion question) {
    if (question.isSingleChoice || question.isTrueFalse) {
      if (question.selectedAnswerId == null) return '';
      final answer = question.answers.firstWhere(
        (a) => a.answerId == question.selectedAnswerId,
        orElse: () => QuizAnswer(id: '', answerId: 0, quizQuestionId: 0, text: '', isCorrect: false, createdAt: DateTime.now()),
      );
      return answer.text;
    } else if (question.isMultipleChoice) {
      if (question.selectedAnswerIds.isEmpty) return '';
      final selectedTexts = question.answers
          .where((a) => question.selectedAnswerIds.contains(a.answerId))
          .map((a) => a.text)
          .toList();
      return selectedTexts.join(', ');
    } else if (question.isShortAnswer) {
      return question.textAnswer ?? '';
    }
    return '';
  }

  String _getCorrectAnswerText(QuizQuestion question) {
    final correctAnswers = question.correctAnswers;
    if (correctAnswers.isEmpty) return 'N/A';
    return correctAnswers.map((a) => a.text).join(', ');
  }

  bool _hasReason(QuizQuestion question) {
    if (question.isShortAnswer) return false;

    // Check if any answer has a reason
    if (question.isUserAnswerCorrect) {
      // Show reason from correct answer
      final userAnswer = question.answers.firstWhere(
        (a) => a.answerId == question.selectedAnswerId,
        orElse: () => QuizAnswer(id: '', answerId: 0, quizQuestionId: 0, text: '', isCorrect: false, createdAt: DateTime.now()),
      );
      return userAnswer.hasReason;
    } else {
      // Show reasons from correct answers
      return question.correctAnswers.any((a) => a.hasReason);
    }
  }

  List<String> _getReasons(QuizQuestion question) {
    final reasons = <String>[];

    if (question.isUserAnswerCorrect) {
      final userAnswer = question.answers.firstWhere(
        (a) => a.answerId == question.selectedAnswerId,
        orElse: () => QuizAnswer(id: '', answerId: 0, quizQuestionId: 0, text: '', isCorrect: false, createdAt: DateTime.now()),
      );
      if (userAnswer.hasReason) {
        reasons.add(userAnswer.reason!);
      }
    } else {
      for (final answer in question.correctAnswers) {
        if (answer.hasReason) {
          reasons.add(answer.reason!);
        }
      }
    }

    return reasons;
  }

  bool _hasUserAnswerImage(QuizQuestion question) {
    if (question.isShortAnswer) return false;
    if (question.isSingleChoice || question.isTrueFalse) {
      if (question.selectedAnswerId == null) return false;
      final answer = question.answers.firstWhere(
        (a) => a.answerId == question.selectedAnswerId,
        orElse: () => QuizAnswer(id: '', answerId: 0, quizQuestionId: 0, text: '', isCorrect: false, createdAt: DateTime.now()),
      );
      return answer.hasImage;
    } else if (question.isMultipleChoice) {
      if (question.selectedAnswerIds.isEmpty) return false;
      final firstSelected = question.answers.firstWhere(
        (a) => a.answerId == question.selectedAnswerIds.first,
        orElse: () => QuizAnswer(id: '', answerId: 0, quizQuestionId: 0, text: '', isCorrect: false, createdAt: DateTime.now()),
      );
      return firstSelected.hasImage;
    }
    return false;
  }

  bool _hasCorrectAnswerImage(QuizQuestion question) {
    return question.correctAnswers.any((a) => a.hasImage);
  }
}
