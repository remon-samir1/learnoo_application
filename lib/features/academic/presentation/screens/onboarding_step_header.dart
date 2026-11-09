import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/header_back_button.dart';

/// Gradient header with the step indicator shared by the onboarding screens.
///
/// Onboarding has three selections: university → center → faculty.
class OnboardingStepHeader extends StatelessWidget {
  const OnboardingStepHeader({
    super.key,
    required this.step,
    required this.title,
    this.totalSteps = 3,
  });

  /// 1-based position of the current step.
  final int step;
  final int totalSteps;
  final String title;

  @override
  Widget build(BuildContext context) {
    // The step that can be popped gets a back control: iOS has no hardware
    // back button, so the earlier step would otherwise be unreachable. The
    // first step is pushed as a replacement and has nothing to go back to, so
    // it keeps the header as it is.
    final canPop = Navigator.of(context).canPop();
    // Keep the original 60px top inset, but never let the content sit under a
    // notch / Dynamic Island that is taller than that.
    final topPadding = math.max(60.0, MediaQuery.paddingOf(context).top + 12);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.only(
        top: topPadding,
        bottom: 40,
        left: 24,
        right: 24,
      ),
      decoration: const BoxDecoration(
        gradient: AppColors.mainGradient,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(40),
          bottomRight: Radius.circular(40),
        ),
      ),
      child: Column(
        children: [
          if (canPop)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: HeaderBackButton(),
              ),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(totalSteps, (index) {
              final isDone = index < step;
              return Padding(
                padding: EdgeInsetsDirectional.only(
                  end: index == totalSteps - 1 ? 0 : 8,
                ),
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
            'academic.step_x_of_y'.tr(args: ['$step', '$totalSteps']),
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
