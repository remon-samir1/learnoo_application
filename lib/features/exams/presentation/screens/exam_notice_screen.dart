import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../data/exam_repository.dart';
import '../../models/quiz_models.dart';
import 'quiz_screen.dart';

class ExamNoticeScreen extends StatelessWidget {
  final Quiz quiz;

  const ExamNoticeScreen({
    super.key,
    required this.quiz,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
              const SizedBox(height: 40),
              // Warning Icon
              Container(
                width: 80,
                height: 80,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF6B73FF), Color(0xFF5A6AF0)],
                  ),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: FaIcon(FontAwesomeIcons.triangleExclamation, color: Colors.white, size: 36),
                ),
              ),
              const SizedBox(height: 24),
              Text('exams.notice_title'.tr(), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Color(0xFF1F2937))),
              const SizedBox(height: 8),
              Text('exams.notice_subtitle'.tr(), style: const TextStyle(fontSize: 14, color: Color(0xFF9CA3AF))),
              const SizedBox(height: 32),
              // Quiz Details Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFF1F1F1)),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(quiz.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF1F2937))),
                    const SizedBox(height: 20),
                    _buildDetailRow('exams.label_type'.tr(), quiz.type.toUpperCase()),
                    const Divider(height: 16, color: Color(0xFFF1F1F1)),
                    _buildDetailRow('exams.label_duration'.tr(), 'course.duration_min'.tr(args: [quiz.duration.toString()])),
                    const Divider(height: 16, color: Color(0xFFF1F1F1)),
                    _buildDetailRow('exams.label_max_attempts'.tr(), '${quiz.maxAttempts}'),
                    if (quiz.chapter != null) ...[
                      const Divider(height: 16, color: Color(0xFFF1F1F1)),
                      _buildDetailRow('exams.label_chapter'.tr(), quiz.chapter!.title),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // Exam Rules Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFF1F1F1)),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('exams.rules_title'.tr(), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF1F2937))),
                    const SizedBox(height: 16),
                    _buildRuleItem(FontAwesomeIcons.eye, const Color(0xFFFF4B4B), 'exams.rule_no_leave'.tr()),
                    const SizedBox(height: 12),
                    _buildRuleItem(FontAwesomeIcons.ban, const Color(0xFFF2994A), 'exams.rule_no_switch'.tr()),
                    const SizedBox(height: 12),
                    _buildRuleItem(FontAwesomeIcons.clock, const Color(0xFF5A75FF), 'exams.rule_timer'.tr()),
                    const SizedBox(height: 12),
                    _buildRuleItem(FontAwesomeIcons.fileSignature, const Color(0xFF9B59B6), 'exams.rule_all_questions'.tr()),
                    const SizedBox(height: 12),
                    _buildRuleItem(FontAwesomeIcons.rotateRight, const Color(0xFF27AE60), 'exams.rule_counts'.tr()),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              // Start Exam Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => _startExam(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3343D6),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: Text('exams.btn_start_exam'.tr(), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 12),
              // Go Back Button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF6B7280),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: const BorderSide(color: Color(0xFFE5E7EB)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text('exams.btn_go_back'.tr(), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    ),
    );
  }

  Future<void> _startExam(BuildContext context) async {
    final examRepo = ExamRepository();

    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    // Verify access with server before starting (GET /quiz/{id} validates access)
    final accessResult = await examRepo.getQuizById(quiz.quizId);

    if (!accessResult['success']) {
      if (!context.mounted) return;
      Navigator.pop(context); // Remove loading

      // Access denied or error
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(accessResult['message'] ?? 'exams.access_denied'.tr()),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Verify quiz data and access flags
    final updatedQuiz = accessResult['data'] as Quiz;
    if (!updatedQuiz.isPublic && !updatedQuiz.canView && !updatedQuiz.canWatch) {
      if (!context.mounted) return;
      Navigator.pop(context); // Remove loading

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('exams.access_denied'.tr()),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Start the attempt
    final result = await examRepo.startQuizAttempt(quiz.quizId);

    if (!context.mounted) return;
    Navigator.pop(context); // Remove loading

    if (result['success']) {
      final attempt = result['data'] as QuizAttempt;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => QuizScreen(quiz: updatedQuiz, attempt: attempt),
        ),
      );
    } else {
      // Show error
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['message'] ?? 'exams.failed_start'.tr()), backgroundColor: Colors.red),
      );
    }
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 14, color: Color(0xFF9CA3AF))),
        Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1F2937))),
      ],
    );
  }

  Widget _buildRuleItem(dynamic icon, Color iconColor, String text) {
    return Row(
      children: [
        FaIcon(icon, size: 16, color: iconColor),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 13, color: Color(0xFF4B5563)))),
      ],
    );
  }
}
