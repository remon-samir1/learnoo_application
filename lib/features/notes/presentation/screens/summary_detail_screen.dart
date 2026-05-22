import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';

class SummaryDetailScreen extends StatelessWidget {
  final dynamic note;

  const SummaryDetailScreen({
    super.key,
    required this.note,
  });

  Map<String, dynamic> _getTypeStyles(String? type) {
    switch (type) {
      case 'summary':
        return {
          'typeLabel': 'Summary',
          'typeColor': const Color(0xFFF2994A),
          'typeBgColor': const Color(0xFFFFF4E6),
          'icon': FontAwesomeIcons.fileLines,
        };
      case 'highlight':
      case 'key_point':
        return {
          'typeLabel': 'Highlight',
          'typeColor': const Color(0xFF10B981),
          'typeBgColor': const Color(0xFFE6F9F1),
          'icon': FontAwesomeIcons.highlighter,
        };
      case 'important_notice':
        return {
          'typeLabel': 'Important',
          'typeColor': const Color(0xFFEF4444),
          'typeBgColor': const Color(0xFFFFE6E6),
          'icon': FontAwesomeIcons.circleExclamation,
        };
      case 'video_note':
        return {
          'typeLabel': 'Video Note',
          'typeColor': const Color(0xFF5A75FF),
          'typeBgColor': const Color(0xFFEEF0FF),
          'icon': FontAwesomeIcons.video,
        };
      default:
        return {
          'typeLabel': 'Note',
          'typeColor': const Color(0xFF6B7280),
          'typeBgColor': const Color(0xFFF3F4F6),
          'icon': FontAwesomeIcons.noteSticky,
        };
    }
  }

  String _formatDate(String? dateString) {
    if (dateString == null) return '';
    try {
      final date = DateTime.parse(dateString);
      return DateFormat('MMM d, yyyy').format(date);
    } catch (e) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final attributes = note['attributes'] ?? {};
    final title = attributes['title']?.toString() ?? 'Untitled';
    final type = attributes['type']?.toString() ?? 'note';
    final content = attributes['content']?.toString() ?? '';
    final linkedLecture = attributes['linked_lecture']?.toString();
    final createdAt = attributes['created_at']?.toString();
    final updatedAt = attributes['updated_at']?.toString();
    final courseId = attributes['course_id']?.toString();

    final styles = _getTypeStyles(type);
    final displayDate = _formatDate(updatedAt ?? createdAt);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 20),
                    _buildTypeBadge(styles, displayDate),
                    const SizedBox(height: 16),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                    if (linkedLecture != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Lecture: $linkedLecture',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF5A75FF),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    if (courseId != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Course ID: $courseId',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF9CA3AF),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    if (content.isNotEmpty)
                      _buildContentSection(content)
                    else
                      _buildContentSection('No content available'),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.arrow_back,
                color: Color(0xFF4B4B4B),
                size: 20,
              ),
            ),
          ),
          Row(
            children: [
              GestureDetector(
                onTap: () {},
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F5F5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.share_outlined,
                    color: Color(0xFF4B4B4B),
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () {},
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F5F5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.download_outlined,
                    color: Color(0xFF4B4B4B),
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTypeBadge(Map<String, dynamic> styles, String date) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: styles['typeBgColor'],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FaIcon(
                styles['icon'],
                color: styles['typeColor'],
                size: 14,
              ),
              const SizedBox(width: 6),
              Text(
                styles['typeLabel'],
                style: TextStyle(
                  color: styles['typeColor'],
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        if (date.isNotEmpty) ...[
          const SizedBox(width: 12),
          Text(
            date,
            style: TextStyle(
              color: const Color(0xFF9CA3AF).withValues(alpha: 0.8),
              fontSize: 12,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildContentSection(String content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Color(0xFF5A75FF),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'Content',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF374151),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF9FAFB),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFF1F1F1)),
          ),
          child: Text(
            content,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF4B5563),
              height: 1.6,
            ),
          ),
        ),
      ],
    );
  }
}
