import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../home/presentation/screens/main_screen.dart';
import '../../models/quiz_models.dart';
import 'quiz_review_screen.dart';
import '../../../../core/widgets/watermark_wrapper.dart';
import '../../../../core/services/feature_manager.dart';
import '../../../auth/data/auth_repository.dart';

class ExamResultsScreen extends StatefulWidget {
  final QuizResult result;
  final List<QuizQuestion>? questions;

  /// Attempt id, so the review can load graded rows from the server.
  final String? attemptId;

  const ExamResultsScreen({
    super.key,
    required this.result,
    this.questions,
    this.attemptId,
  });

  @override
  State<ExamResultsScreen> createState() => _ExamResultsScreenState();
}

class _ExamResultsScreenState extends State<ExamResultsScreen> {
  final FeatureManager _featureManager = FeatureManager();
  final AuthRepository _authRepository = AuthRepository();
  String _studentCode = '';
  String _phoneNumber = '';

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final result = await _authRepository.getProfile();
    if (result['success'] && mounted) {
      final attributes = result['data']['attributes'] ?? {};
      final studentCode = attributes['student_code']?.toString() ?? '';
      final phone = attributes['phone']?.toString() ?? attributes['phone_number']?.toString() ?? '';
      setState(() {
        _studentCode = studentCode;
        _phoneNumber = phone;
      });
    } else {
      final cachedData = _authRepository.getCachedWatermarkData();
      if (mounted) {
        setState(() {
          _studentCode = cachedData['student_code'] ?? '';
          _phoneNumber = cachedData['phone'] ?? '';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF13151B) : Colors.white,
      body: WatermarkWrapper(
        type: WatermarkType.exams,
        studentCode: _studentCode,
        phone: _phoneNumber,
        featureManager: _featureManager,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                const SizedBox(height: 40),
                // Trophy Icon
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: widget.result.passed ? const Color(0xFF27AE60) : const Color(0xFFF2994A),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: FaIcon(
                      widget.result.passed ? FontAwesomeIcons.trophy : FontAwesomeIcons.rotateRight,
                      color: Colors.white,
                      size: 44,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                // Congratulations Text
                Text(
                  widget.result.passed ? 'exams.congratulations'.tr() : 'exams.good_try'.tr(),
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF1F2937),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.result.passed ? 'exams.passed_exam'.tr() : 'exams.keep_practicing'.tr(),
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF9CA3AF),
                  ),
                ),
                const SizedBox(height: 32),
                // Score Card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E212B) : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDark ? const Color(0xFF2E3344) : const Color(0xFFE5E7EB),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Text(
                        '${widget.result.percentage.toInt()}%',
                        style: TextStyle(
                          fontSize: 48,
                          fontWeight: FontWeight.w700,
                          color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF1F2937),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'exams.out_of_correct'.tr(
                          args: ['${widget.result.correctAnswers}', '${widget.result.totalQuestions}'],
                        ),
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF9CA3AF),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'exams.score'.tr(
                          args: ['${widget.result.score}', '${widget.result.totalScore}'],
                        ),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF5A75FF),
                        ),
                      ),
                      const SizedBox(height: 24),
                      // Circular Progress
                      SizedBox(
                        width: 120,
                        height: 120,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            CircularProgressIndicator(
                              value: widget.result.percentage / 100,
                              strokeWidth: 10,
                              backgroundColor: isDark ? const Color(0xFF262A36) : const Color(0xFFE5E7EB),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                widget.result.passed ? const Color(0xFF27AE60) : const Color(0xFFF2994A),
                              ),
                            ),
                            Center(
                              child: Text(
                                '${widget.result.percentage.toInt()}%',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF1F2937),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                // Review Answers Button (if questions available)
                if (widget.questions != null && widget.questions!.isNotEmpty) ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => QuizReviewScreen(
                              questions: widget.questions!,
                              result: widget.result,
                              attemptId: widget.attemptId,
                            ),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF8B5CF6),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      icon: const FaIcon(FontAwesomeIcons.clipboardCheck, size: 16),
                      label: Text(
                        'exams.review_answers'.tr(),
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                // Back to Home Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(builder: (context) => const MainScreen()),
                        (route) => false,
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3343D6),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    icon: const FaIcon(FontAwesomeIcons.house, size: 16),
                    label: Text(
                      'exams.back_to_home'.tr(),
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Back to Exams Button
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF6B7280),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: BorderSide(
                        color: isDark ? const Color(0xFF383E52) : const Color(0xFFE5E7EB),
                      ),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(
                      'exams.back_to_exams'.tr(),
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                    ),
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
}
