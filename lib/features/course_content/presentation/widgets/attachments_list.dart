import 'package:flutter/material.dart';

import 'package:easy_localization/easy_localization.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class AttachmentsList extends StatelessWidget {
  final List<dynamic> attachments;
  final Function(String path, String name) onOpenPdf;
  final Function(String path, String name)? onDownloadPdf;
  final Function(String path, String name)? onDownloadFile;
  /// Whether the chapter's attachments may be opened, computed by the caller
  /// with the website rule (`canOpenChapterPdf` in `chapter_access.dart`).
  final bool canOpen;

  /// Open only through `is_free_preview_attachment` (shows the free badge).
  final bool isFreePreview;

  const AttachmentsList({
    super.key,
    required this.attachments,
    required this.onOpenPdf,
    this.onDownloadPdf,
    this.onDownloadFile,
    this.canOpen = false,
    this.isFreePreview = false,
  });

  @override
  Widget build(BuildContext context) {
    if (attachments.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'course.attachments'.tr(),
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Color(0xFF374151),
          ),
        ),
        const SizedBox(height: 12),
        ...attachments.map((attachment) {
          final attrs = attachment['attributes'] ?? {};
          final name = attrs['name']?.toString() ?? 'course.attachment'.tr();
          final size = attrs['size']?.toString() ?? '0';
          final extension = attrs['extension']?.toString() ?? '';
          final path = attrs['path']?.toString() ?? '';

          // The website ignores the attachment's own `is_locked`: access is
          // decided per chapter (activation / `is_free_preview_attachment`).
          return _buildAttachmentItem(
            name,
            size,
            extension,
            !canOpen,
            canOpen && isFreePreview,
            path,
          );
        }),
      ],
    );
  }

  Widget _buildAttachmentItem(
    String name,
    String size,
    String extension,
    bool isLocked,
    bool isFreePreview,
    String? path,
  ) {
    final isPdf = extension.toLowerCase() == 'pdf';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isPdf ? const Color(0xFFFFE4E1) : const Color(0xFFEDEDFF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: FaIcon(
              isLocked
                  ? FontAwesomeIcons.lock
                  : (isPdf
                      ? FontAwesomeIcons.filePdf
                      : FontAwesomeIcons.paperclip),
              color: isPdf ? const Color(0xFFE74C3C) : const Color(0xFF3451E5),
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                    if (isFreePreview) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'course.free_preview'.tr(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'course.attachment_size_ext'.tr(args: [size, extension]),
                  style: const TextStyle(
                    color: Color(0xFF9CA3AF),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          if (!isLocked && isPdf && path != null && path.isNotEmpty)
            Row(
              children: [
                GestureDetector(
                  onTap: () => onOpenPdf(path, name),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3451E5),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const FaIcon(
                      FontAwesomeIcons.eye,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),
              ],
            )
          else if (!isLocked)
            Row(
              children: [
                // Non-PDF files could have download button here
              ],
            ),
        ],
      ),
    );
  }
}
