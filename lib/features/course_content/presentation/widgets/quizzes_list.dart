import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class QuizzesList extends StatelessWidget {
  final List<dynamic> quizzes;
  final Function(int quizId, dynamic quizData) onStartQuiz;

  const QuizzesList({
    super.key,
    required this.quizzes,
    required this.onStartQuiz,
  });

  @override
  Widget build(BuildContext context) {
    if (quizzes.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'course.linked_quizzes'.tr(),
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Color(0xFF374151),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'course.take_quiz_desc'.tr(),
          style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12),
        ),
        const SizedBox(height: 12),
        ...quizzes.map((quiz) {
          final attrs = quiz['attributes'] ?? {};
          final id = int.tryParse(quiz['id']?.toString() ?? '0') ?? 0;
          final title = attrs['title']?.toString() ?? 'course.quiz'.tr();
          final maxAttempts = attrs['max_attempts'] as int? ?? 0;
          final duration = attrs['duration'] as int? ?? 0;

          return _buildQuizItem(id, title, maxAttempts, duration, quiz);
        }),
      ],
    );
  }

  Widget _buildQuizItem(
    int quizId,
    String title,
    int maxAttempts,
    int duration,
    dynamic quizData,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F9F0),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF2DBC77).withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: Color(0xFF1F2937),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF2DBC77),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'course.available'.tr(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              FaIcon(
                FontAwesomeIcons.listCheck,
                size: 12,
                color: Colors.grey[600],
              ),
              const SizedBox(width: 6),
              Text(
                'course.attempts'.tr(args: [maxAttempts.toString()]),
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
              const SizedBox(width: 16),
              FaIcon(FontAwesomeIcons.clock, size: 12, color: Colors.grey[600]),
              const SizedBox(width: 6),
              Text(
                'course.duration_min'.tr(args: [duration.toString()]),
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => onStartQuiz(quizId, quizData),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2DBC77),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
                elevation: 0,
              ),
              child: Text(
                'course.start_quiz'.tr(),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
