import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Gradient header with the step indicator shared by the onboarding screens.
///
/// Extracted so the progress dots stay consistent now that onboarding is four
/// steps (university → centre → faculty → department) instead of three.
class OnboardingStepHeader extends StatelessWidget {
  const OnboardingStepHeader({
    super.key,
    required this.step,
    required this.title,
    this.totalSteps = 4,
  });

  /// 1-based position of the current step.
  final int step;
  final int totalSteps;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(top: 60, bottom: 40, left: 24, right: 24),
      decoration: const BoxDecoration(
        gradient: AppColors.mainGradient,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(40),
          bottomRight: Radius.circular(40),
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(totalSteps, (index) {
              final isDone = index < step;
              return Padding(
                padding: EdgeInsets.only(right: index == totalSteps - 1 ? 0 : 8),
                child: Container(
                  width: isDone ? 40 : 20,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDone
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 12),
          Text(
            'Step $step of $totalSteps',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 24),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
