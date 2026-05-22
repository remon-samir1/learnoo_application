import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../data/chapter_repository.dart';

enum AttachmentAccessState {
  locked,
  freePreview,
  unlocked,
}

class AttachmentPermissionService {
  final ChapterRepository _chapterRepository = ChapterRepository();

  /// Check if attachment can be opened based on multiple permission layers
  /// Priority order (highest to lowest):
  /// 1. File is_locked == true → BLOCK always
  /// 2. Chapter is_locked == true → BLOCK all content
  /// 3. Chapter is_activated == true → ALLOW (subject to view limit)
  /// 4. Chapter is_free_preview == true + chapter is_free_preview_attachment == true → ALLOW
  /// 5. Chapter is_free_preview == true + chapter is_free_preview_attachment == false → BLOCK
  /// 6. View limit exceeded → BLOCK
  bool canOpenAttachment({
    required bool fileIsLocked,
    required bool chapterIsLocked,
    required bool chapterIsActivated,
    required bool chapterIsFreePreview,
    required bool chapterIsFreePreviewAttachment,
    required int currentViews,
    required int maxViews,
  }) {
    // Priority 1: File-level lock (highest priority)
    if (fileIsLocked) {
      return false;
    }

    // Priority 2: Chapter-level lock
    if (chapterIsLocked) {
      return false;
    }

    // Priority 3: Chapter is activated (allow subject to view limit)
    if (chapterIsActivated) {
      // Check view limit
      if (maxViews > 0 && currentViews >= maxViews) {
        return false;
      }
      return true;
    }

    // Priority 4: Attachment allows free preview (independent of chapter free preview flag)
    if (chapterIsFreePreviewAttachment) {
      return true;
    }

    // Default: Block if none of the above conditions are met
    return false;
  }

  /// Get the access state of an attachment for UI display
  AttachmentAccessState getAttachmentAccessState({
    required bool fileIsLocked,
    required bool chapterIsLocked,
    required bool chapterIsActivated,
    required bool chapterIsFreePreview,
    required bool chapterIsFreePreviewAttachment,
    required int currentViews,
    required int maxViews,
  }) {
    // Priority 1: File-level lock
    if (fileIsLocked) {
      return AttachmentAccessState.locked;
    }

    // Priority 2: Chapter-level lock
    if (chapterIsLocked) {
      return AttachmentAccessState.locked;
    }

    // Priority 3: Chapter is activated
    if (chapterIsActivated) {
      // Check view limit
      if (maxViews > 0 && currentViews >= maxViews) {
        return AttachmentAccessState.locked;
      }
      return AttachmentAccessState.unlocked;
    }

    // Priority 4: Attachment allows free preview (independent of chapter free preview flag)
    if (chapterIsFreePreviewAttachment) {
      return AttachmentAccessState.freePreview;
    }

    // Default: Locked
    return AttachmentAccessState.locked;
  }

  /// Show dialog for locked attachment with activation option
  Future<void> showLockedAttachmentDialog({
    required BuildContext context,
    required int chapterId,
    required String? courseId,
    required VoidCallback onRefresh,
  }) async {
    final codeController = TextEditingController();
    bool isVerifying = false;
    String selectedType = 'chapter'; // 'chapter' or 'course'
    int? courseIdValue;

    // If courseId is provided, parse it
    if (courseId != null) {
      courseIdValue = int.tryParse(courseId);
    }

    await showDialog(
      context: context,
      barrierDismissible: !isVerifying,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Column(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F2FF),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Center(
                  child: FaIcon(
                    FontAwesomeIcons.lock,
                    color: Color(0xFF5A75FF),
                    size: 24,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'course.attachment_locked'.tr(),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1F2937),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'course.unlock_to_access_attachment'.tr(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 20),
              // Type selector (chapter or course)
              if (courseIdValue != null)
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setDialogState(() => selectedType = 'chapter'),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: selectedType == 'chapter'
                                  ? const Color(0xFF5A75FF)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'course.chapter'.tr(),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: selectedType == 'chapter'
                                    ? Colors.white
                                    : const Color(0xFF6B7280),
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setDialogState(() => selectedType = 'course'),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: selectedType == 'course'
                                  ? const Color(0xFF5A75FF)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'course.full_course'.tr(),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: selectedType == 'course'
                                    ? Colors.white
                                    : const Color(0xFF6B7280),
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              TextField(
                controller: codeController,
                enabled: !isVerifying,
                keyboardType: TextInputType.text,
                textCapitalization: TextCapitalization.characters,
                maxLength: 20,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 2,
                  color: Color(0xFF1F2937),
                ),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: 'ABCD-1234',
                  hintStyle: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 2,
                    color: Colors.grey[400],
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF5A75FF)),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isVerifying ? null : () => Navigator.pop(context),
              child: Text(
                'course.cancel'.tr(),
                style: TextStyle(color: Colors.grey[600]),
              ),
            ),
            ElevatedButton(
              onPressed: isVerifying
                  ? null
                  : () async {
                      final code = codeController.text.trim();
                      if (code.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('course.please_enter_code'.tr()),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }

                      setDialogState(() => isVerifying = true);

                      final itemId = selectedType == 'chapter'
                          ? chapterId
                          : (courseIdValue ?? 0);

                      if (itemId == 0) {
                        setDialogState(() => isVerifying = false);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('course.invalid_selection'.tr()),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }

                      final result = await _chapterRepository.activateCode(
                        code: code,
                        itemId: itemId,
                        itemType: selectedType,
                      );

                      setDialogState(() => isVerifying = false);

                      if (result['success']) {
                        Navigator.pop(context);
                        // Refresh the data to reflect unlocked status
                        onRefresh();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('course.chapter_unlocked_success'.tr()),
                            backgroundColor: const Color(0xFF2DBC77),
                          ),
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              result['message'] ?? 'course.invalid_code'.tr(),
                            ),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF5A75FF),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: isVerifying
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Text('course.unlock_now'.tr()),
            ),
          ],
        ),
      ),
    );
  }
}
