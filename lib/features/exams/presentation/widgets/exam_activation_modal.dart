import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../models/quiz_models.dart';
import '../cubit/exam_activation_cubit.dart';

/// Modal dialog for exam activation code input
class ExamActivationModal extends StatelessWidget {
  final Quiz quiz;
  final Function(Quiz updatedQuiz) onSuccess;
  final Function(String message)? onError;

  const ExamActivationModal({
    super.key,
    required this.quiz,
    required this.onSuccess,
    this.onError,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => ExamActivationCubit(),
      child: _ExamActivationModalContent(
        quiz: quiz,
        onSuccess: onSuccess,
        onError: onError,
      ),
    );
  }
}

class _ExamActivationModalContent extends StatefulWidget {
  final Quiz quiz;
  final Function(Quiz updatedQuiz) onSuccess;
  final Function(String message)? onError;

  const _ExamActivationModalContent({
    required this.quiz,
    required this.onSuccess,
    this.onError,
  });

  @override
  State<_ExamActivationModalContent> createState() =>
      _ExamActivationModalContentState();
}

class _ExamActivationModalContentState
    extends State<_ExamActivationModalContent> {
  final _codeController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<ExamActivationCubit, ExamActivationState>(
      listener: (context, state) {
        if (state is ExamActivationSuccess) {
          widget.onSuccess(state.updatedQuiz);
        } else if (state is ExamActivationError) {
          widget.onError?.call(state.message);
        }
      },
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Handle bar
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Icon
                  Center(
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(32),
                      ),
                      child: const Icon(
                        Icons.lock_outline,
                        color: Color(0xFF6366F1),
                        size: 32,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Title
                  Text(
                    'exams.activation_title'.tr(),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1F2937),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),

                  // Subtitle with exam name
                  Text(
                    '${'exams.activation_subtitle'.tr()}\n${widget.quiz.title}',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),

                  // Error message (if any)
                  BlocBuilder<ExamActivationCubit, ExamActivationState>(
                    builder: (context, state) {
                      if (state is ExamActivationError) {
                        return Container(
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red.shade200),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.error_outline,
                                color: Colors.red.shade600,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  state.message,
                                  style: TextStyle(
                                    color: Colors.red.shade600,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),

                  // Code input field
                  TextFormField(
                    controller: _codeController,
                    enabled: context.select<ExamActivationCubit, bool>(
                      (cubit) => cubit.state is! ExamActivationLoading,
                    ),
                    decoration: InputDecoration(
                      labelText: 'exams.activation_code_label'.tr(),
                      hintText: 'exams.activation_code_hint'.tr(),
                      prefixIcon: const Icon(Icons.vpn_key_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Color(0xFF6366F1),
                          width: 2,
                        ),
                      ),
                      errorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.red.shade300),
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'exams.activation_code_required'.tr();
                      }
                      if (value.trim().length < 4) {
                        return 'exams.activation_code_min_length'.tr();
                      }
                      return null;
                    },
                    textCapitalization: TextCapitalization.characters,
                    onFieldSubmitted: (_) => _submit(context),
                  ),
                  const SizedBox(height: 24),

                  // Submit button
                  BlocBuilder<ExamActivationCubit, ExamActivationState>(
                    builder: (context, state) {
                      final isLoading = state is ExamActivationLoading;

                      return ElevatedButton(
                        onPressed: isLoading ? null : () => _submit(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6366F1),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          disabledBackgroundColor: Colors.grey.shade300,
                        ),
                        child: isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              )
                            : Text(
                                'exams.activate_button'.tr(),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),

                  // Cancel button
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text(
                      'common.cancel'.tr(),
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _submit(BuildContext context) {
    // Hide keyboard
    FocusScope.of(context).unfocus();

    if (_formKey.currentState?.validate() ?? false) {
      final code = _codeController.text.trim();
      context.read<ExamActivationCubit>().activateExam(
            code: code,
            quizId: widget.quiz.quizId,
            currentQuiz: widget.quiz,
          );
    }
  }
}
