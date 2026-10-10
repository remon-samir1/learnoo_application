import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../data/notes_repository.dart';
import '../widgets/note_attachment_preview.dart';

/// Note / summary detail — the web's `NoteDetailsClient`.
///
/// Shows the type badge, title, course title and lecture, the attachment
/// inline and the content. The web's student page offers no share or download
/// action, so neither does this screen.
class SummaryDetailScreen extends StatefulWidget {
  final dynamic note;

  const SummaryDetailScreen({
    super.key,
    required this.note,
  });

  @override
  State<SummaryDetailScreen> createState() => _SummaryDetailScreenState();
}

class _SummaryDetailScreenState extends State<SummaryDetailScreen> {
  late Map<String, dynamic> _attributes = _attributesOf(widget.note);

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  static Map<String, dynamic> _attributesOf(dynamic note) {
    if (note is! Map) return <String, dynamic>{};
    final attrs = note['attributes'];
    return attrs is Map
        ? Map<String, dynamic>.from(attrs)
        : Map<String, dynamic>.from(note);
  }

  /// The web page loads the note by id (`GET /v1/note/{id}`); a list row may
  /// lack fields such as `course_title`, so fill them in when that succeeds.
  Future<void> _refresh() async {
    final note = widget.note;
    final id = note is Map ? note['id']?.toString() : null;
    if (id == null || id.isEmpty) return;
    final result = await NotesRepository().getNoteById(id);
    if (!mounted || result['success'] != true) return;
    final fresh = _attributesOf(result['data']);
    if (fresh.isEmpty) return;
    setState(() => _attributes = {..._attributes, ...fresh});
  }

  static String? _text(dynamic value) {
    final s = value?.toString().trim();
    if (s == null || s.isEmpty || s == 'null') return null;
    return s;
  }

  static String? _courseTitle(Map<String, dynamic> attributes) {
    final direct = _text(attributes['course_title']);
    if (direct != null) return direct;
    final course = attributes['course'];
    if (course is! Map) return null;
    final data = course['data'] is Map ? course['data'] as Map : course;
    final attrs = data['attributes'] is Map ? data['attributes'] as Map : data;
    return _text(attrs['title']);
  }

  Map<String, dynamic> _getTypeStyles(String? type) {
    switch (type) {
      case 'summary':
        return {
          'typeLabel': 'notes.type_summary'.tr(),
          'typeColor': const Color(0xFFF2994A),
          'typeBgColor': const Color(0xFFFFF4E6),
          'icon': FontAwesomeIcons.fileLines,
        };
      case 'highlight':
      case 'highlights':
        return {
          'typeLabel': 'notes.type_highlight'.tr(),
          'typeColor': const Color(0xFF10B981),
          'typeBgColor': const Color(0xFFE6F9F1),
          'icon': FontAwesomeIcons.highlighter,
        };
      case 'key_point':
        return {
          'typeLabel': 'notes.type_key_point'.tr(),
          'typeColor': const Color(0xFF10B981),
          'typeBgColor': const Color(0xFFE6F9F1),
          'icon': FontAwesomeIcons.highlighter,
        };
      case 'important_notice':
        return {
          'typeLabel': 'notes.type_important'.tr(),
          'typeColor': const Color(0xFFEF4444),
          'typeBgColor': const Color(0xFFFFE6E6),
          'icon': FontAwesomeIcons.circleExclamation,
        };
      case 'video_note':
        return {
          'typeLabel': 'notes.type_video_note'.tr(),
          'typeColor': const Color(0xFF5A75FF),
          'typeBgColor': const Color(0xFFEEF0FF),
          'icon': FontAwesomeIcons.video,
        };
      default:
        return {
          'typeLabel': 'notes.type_note'.tr(),
          'typeColor': const Color(0xFF6B7280),
          'typeBgColor': const Color(0xFFF3F4F6),
          'icon': FontAwesomeIcons.noteSticky,
        };
    }
  }

  String _formatDate(String? dateString) {
    if (dateString == null) return '';
    final date = DateTime.tryParse(dateString);
    if (date == null) return '';
    return DateFormat.yMMMd(context.locale.toString()).format(date.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    final attributes = _attributes;
    final title = _text(attributes['title']) ?? 'notes.untitled'.tr();
    final type = _text(attributes['type']) ?? 'note';
    final content = _text(attributes['content']) ?? '';
    // Same fallbacks as the web: lecture_title, then linked_lecture.
    final lecture = _text(attributes['lecture_title']) ??
        _text(attributes['linked_lecture']);
    // The web shows the course title; the bare course id meant nothing to a
    // student, so it is no longer shown.
    final courseTitle = _courseTitle(attributes);
    final createdAt =
        _text(attributes['created_at'] ?? attributes['createdAt']);
    final updatedAt =
        _text(attributes['updated_at'] ?? attributes['updatedAt']);
    final attachment = attributes['attachment'];

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
                    if (courseTitle != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        '${'notes.course'.tr()}: $courseTitle',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF6B7280),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    if (lecture != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${'notes.lecture'.tr()}: $lecture',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF5A75FF),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    // Images and clips render inline above the text, like the
                    // web detail page.
                    if (NoteAttachmentPreview.hasAttachment(attachment)) ...[
                      NoteAttachmentPreview(attachment: attachment),
                      const SizedBox(height: 20),
                    ],
                    _buildContentSection(
                      content.isNotEmpty ? content : 'notes.no_content'.tr(),
                    ),
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

  /// Back button only. The share and download buttons had no action and the
  /// web offers neither for a student, so they are gone.
  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: Color(0xFFF5F5F5),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.arrow_back,
                color: Color(0xFF4B4B4B),
                size: 20,
              ),
            ),
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
            Text(
              'notes.content'.tr(),
              style: const TextStyle(
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
