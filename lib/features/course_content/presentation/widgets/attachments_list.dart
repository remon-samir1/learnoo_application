import 'package:flutter/material.dart';

import '../../../../core/utils/coerce.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class AttachmentsList extends StatelessWidget {
  final List<dynamic> attachments;
  final Function(String path, String name) onOpenPdf;
  final Function(String path, String name)? onDownloadPdf;
  final Function(String path, String name)? onDownloadFile;
  // Chapter context for permission checking
  final bool chapterIsLocked;
  final bool chapterIsActivated;
  final bool chapterIsFreePreview;
  final bool chapterIsFreePreviewAttachment;

  const AttachmentsList({
    super.key,
    required this.attachments,
    required this.onOpenPdf,
    this.onDownloadPdf,
    this.onDownloadFile,
    this.chapterIsLocked = false,
    this.chapterIsActivated = false,
    this.chapterIsFreePreview = false,
    this.chapterIsFreePreviewAttachment = false,
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
          final isLocked = coerceFlagOrNull(attrs['is_locked']) == true;
          final path = attrs['path']?.toString() ?? '';

          // Determine effective lock state based on chapter context
          bool effectivelyLocked = isLocked;
          bool isFreePreview = false;

          if (!isLocked) {
            if (chapterIsLocked) {
              effectivelyLocked = true;
            } else if (chapterIsActivated) {
              effectivelyLocked = false;
            } else if (chapterIsFreePreview) {
              if (chapterIsFreePreviewAttachment) {
                effectivelyLocked = false;
                isFreePreview = true;
              } else {
                effectivelyLocked = true;
              }
            } else {
              effectivelyLocked = true;
            }
          }

          return _buildAttachmentItem(
            name,
            size,
            extension,
            effectivelyLocked,
            isFreePreview,
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
