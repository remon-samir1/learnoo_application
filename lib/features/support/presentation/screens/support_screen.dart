import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../data/issue_repository.dart';

/// "Contact support" — the app-side counterpart of `/student/support`.
class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key});

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _repository = IssueRepository();

  File? _attachment;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickAttachment() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 70,
      );
      if (picked == null) return;
      setState(() => _attachment = File(picked.path));
    } catch (_) {
      _showMessage('support.attachment_failed'.tr(), isError: true);
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isSubmitting = true);

    final result = await _repository.createIssue(
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim(),
      attachment: _attachment,
    );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (result['success'] == true) {
      _showMessage(
        result['message']?.toString() ?? 'support.submitted'.tr(),
      );
      _formKey.currentState?.reset();
      _titleController.clear();
      _descriptionController.clear();
      setState(() => _attachment = null);
      Navigator.of(context).maybePop();
    } else {
      _showMessage(
        result['message']?.toString() ?? 'support.submit_failed'.tr(),
        isError: true,
      );
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : AppColors.joinLiveGreen,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundWhite,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'support.title'.tr(),
          style: const TextStyle(
            color: AppColors.textDark,
            fontWeight: FontWeight.bold,
          ),
        ),
        iconTheme: const IconThemeData(color: AppColors.textDark),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'support.subtitle'.tr(),
                style: const TextStyle(
                  color: AppColors.textGray,
                  fontSize: 14,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 24),
              _label('support.subject'.tr()),
              const SizedBox(height: 8),
              TextFormField(
                controller: _titleController,
                textInputAction: TextInputAction.next,
                decoration: _inputDecoration('support.subject_hint'.tr()),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'support.subject_required'.tr()
                    : null,
              ),
              const SizedBox(height: 20),
              _label('support.details'.tr()),
              const SizedBox(height: 8),
              TextFormField(
                controller: _descriptionController,
                maxLines: 6,
                decoration: _inputDecoration('support.details_hint'.tr()),
                validator: (value) =>
                    (value == null || value.trim().length < 10)
                        ? 'support.details_required'.tr()
                        : null,
              ),
              const SizedBox(height: 20),
              _buildAttachmentRow(),
              const SizedBox(height: 32),
              PrimaryButton(
                text: 'support.submit'.tr(),
                isLoading: _isSubmitting,
                onPressed: _isSubmitting ? null : _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Text(
        text,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: AppColors.labelGray,
        ),
      );

  InputDecoration _inputDecoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.inputHint),
        filled: true,
        fillColor: AppColors.inputFill,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.inputBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.inputBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primaryBlue, width: 2),
        ),
      );

  Widget _buildAttachmentRow() {
    return Row(
      children: [
        OutlinedButton.icon(
          onPressed: _isSubmitting ? null : _pickAttachment,
          icon: const Icon(Icons.attach_file, size: 18),
          label: Text('support.attach'.tr()),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primaryBlue,
            side: const BorderSide(color: AppColors.inputBorder),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        const SizedBox(width: 12),
        if (_attachment != null)
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _attachment!.path.split(Platform.pathSeparator).last,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textGray,
                      fontSize: 12,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  color: AppColors.textGray,
                  onPressed: () => setState(() => _attachment = null),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
