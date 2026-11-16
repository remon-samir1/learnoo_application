import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../domain/exam_review.dart';
import '../../models/quiz_models.dart';

/// A short answer: the text the student wrote, with the "awaiting grading"
/// chip while no verdict exists — as `ExamQuestionScreen.tsx` renders it.
class ReviewShortAnswerBox extends StatelessWidget {
  final ExamQuestionReview review;

  const ReviewShortAnswerBox({super.key, required this.review});

  @override
  Widget build(BuildContext context) {
    final text = review.shortText.trim();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text.isEmpty ? '—' : text,
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              fontStyle: text.isEmpty ? FontStyle.italic : FontStyle.normal,
              color: text.isEmpty
                  ? const Color(0xFF64748B)
                  : const Color(0xFF0F172A),
            ),
          ),
          if (review.isPending) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'exams.awaiting_grading'.tr(),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF92400E),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One option, coloured by the website's `reviewOptionContainerClass`:
/// chosen+correct green, chosen+wrong red, a missed correct option dashed green
/// (only while the question as a whole is wrong), otherwise neutral.
class ReviewOptionTile extends StatelessWidget {
  final QuizAnswer answer;
  final ExamQuestionReview review;

  /// Builds an image widget for a URL (zoomable, with loading/error states).
  final Widget Function(String url) imageBuilder;

  const ReviewOptionTile({
    super.key,
    required this.answer,
    required this.review,
    required this.imageBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final selected = review.selected.any((s) => s.id == answer.id);
    final isCorrect = answer.isCorrect;
    final questionCorrect = review.correct == true;
    final showFeedback =
        (answer.hasReason || answer.hasReasonImage) && (isCorrect || selected);

    var border = const Color(0xFFE2E8F0);
    var fill = Colors.white;
    var textColor = const Color(0xFF0F172A);
    var dashed = false;
    if (selected && isCorrect) {
      border = const Color(0xFF059669);
      fill = const Color(0xFFECFDF5);
      textColor = const Color(0xFF022C22);
    } else if (selected) {
      border = const Color(0xFFDC2626);
      fill = const Color(0xFFFEF2F2);
      textColor = const Color(0xFF450A0A);
    } else if (isCorrect) {
      textColor = const Color(0xFF064E3B);
      if (!questionCorrect) {
        border = const Color(0xFF10B981).withValues(alpha: 0.7);
        fill = const Color(0xFFECFDF5).withValues(alpha: 0.6);
        dashed = true;
      }
    }

    final box = Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(8),
        border: dashed
            ? null
            : Border.all(color: border, width: selected ? 1.5 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 18,
                height: 18,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0xFFCBD5E1)),
                ),
                child: Text(
                  selected ? '✓' : '',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF475569),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  answer.text.trim(),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    height: 1.5,
                    color: textColor,
                  ),
                ),
              ),
            ],
          ),
          if (showFeedback)
            Container(
              margin: const EdgeInsetsDirectional.only(top: 8, start: 28),
              padding: const EdgeInsetsDirectional.only(start: 12),
              decoration: const BoxDecoration(
                border: BorderDirectional(
                  start: BorderSide(color: Color(0xFFE2E8F0), width: 2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'exams.explanation'.tr(),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF334155),
                    ),
                  ),
                  if (answer.hasReason)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        answer.reason!,
                        style: const TextStyle(
                          fontSize: 13,
                          height: 1.5,
                          color: Color(0xFF475569),
                        ),
                      ),
                    ),
                  if (answer.hasReasonImage)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: imageBuilder(answer.reasonImage!),
                    ),
                ],
              ),
            ),
          if (answer.hasImage)
            Padding(
              padding: const EdgeInsetsDirectional.only(top: 8, start: 28),
              child: imageBuilder(answer.image!),
            ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: dashed
          ? CustomPaint(foregroundPainter: _DashedPainter(border), child: box)
          : box,
    );
  }
}

class _DashedPainter extends CustomPainter {
  final Color color;

  _DashedPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(8)),
      );
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(metric.extractPath(distance, distance + 5), paint);
        distance += 9;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedPainter old) => old.color != color;
}

/// Under the options: the student's choice marked right (green) or wrong (red)
/// and, when it is wrong, the right choice beneath it in green — what the
/// doctor asked for on 16 Nov. When the correct options are not known (the
/// server hides them while a newer attempt of the same exam is running) the
/// second box is left out rather than showing a placeholder.
class ReviewAnswerSummary extends StatelessWidget {
  final ExamQuestionReview review;

  const ReviewAnswerSummary({super.key, required this.review});

  static const _red = Color(0xFFDC2626);
  static const _green = Color(0xFF059669);

  @override
  Widget build(BuildContext context) {
    final isCorrect = review.correct == true;
    final chosen = review.selected.map((a) => a.text.trim()).where((t) => t.isNotEmpty).toList();
    final correct = review.correctAnswers.map((a) => a.text.trim()).where((t) => t.isNotEmpty).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _box(
          key: const ValueKey('review-your-answer'),
          icon: isCorrect ? Icons.check_circle_outline : Icons.highlight_off,
          label: isCorrect ? 'exams.your_answer_correct'.tr() : 'exams.your_answer'.tr(),
          lines: chosen.isEmpty ? ['exams.no_answer_provided'.tr()] : chosen,
          color: isCorrect ? _green : _red,
          fill: isCorrect ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
        ),
        if (!isCorrect && correct.isNotEmpty) ...[
          const SizedBox(height: 8),
          _box(
            key: const ValueKey('review-correct-answer'),
            icon: Icons.check_circle_outline,
            label: 'exams.correct_answer'.tr(),
            lines: correct,
            color: _green,
            fill: const Color(0xFFECFDF5),
          ),
        ],
      ],
    );
  }

  Widget _box({
    required Key key,
    required IconData icon,
    required String label,
    required List<String> lines,
    required Color color,
    required Color fill,
  }) {
    return Container(
      key: key,
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final line in lines)
            Text(
              line,
              style: TextStyle(fontSize: 14, height: 1.5, fontWeight: FontWeight.w600, color: color),
            ),
        ],
      ),
    );
  }
}
