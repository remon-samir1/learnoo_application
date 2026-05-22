import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';
import '../../data/notes_repository.dart';
import 'summary_detail_screen.dart';

class SummariesListScreen extends StatefulWidget {
  const SummariesListScreen({super.key});

  @override
  State<SummariesListScreen> createState() => _SummariesListScreenState();
}

class _SummariesListScreenState extends State<SummariesListScreen> {
  final NotesRepository _notesRepository = NotesRepository();
  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = '';
  List<dynamic> _notes = [];

  @override
  void initState() {
    super.initState();
    _loadNotes();
  }

  Future<void> _loadNotes() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
      _errorMessage = '';
    });

    try {
      final result = await _notesRepository.getNotes();
      if (result['success'] && mounted) {
        setState(() {
          _notes = result['data'] ?? [];
          _isLoading = false;
        });
      } else if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = result['message'] ?? 'Failed to load notes';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = 'Connection error: $e';
          _isLoading = false;
        });
      }
    }
  }

  List<dynamic> get _filteredItems {
    return _notes.where((item) {
      final attributes = item['attributes'] ?? {};
      return attributes['type'] == 'summary';
    }).toList();
  }

  String _formatDate(String? dateString) {
    if (dateString == null) return '';
    try {
      final date = DateTime.parse(dateString);
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inDays == 0) {
        return 'Today';
      } else if (difference.inDays == 1) {
        return 'Yesterday';
      } else if (difference.inDays < 7) {
        return '${difference.inDays} days ago';
      } else if (difference.inDays < 30) {
        return '${(difference.inDays / 7).floor()} weeks ago';
      } else {
        return DateFormat('MMM d, yyyy').format(date);
      }
    } catch (e) {
      return '';
    }
  }

  Map<String, dynamic> _getTypeStyles(String? type) {
    switch (type) {
      case 'summary':
        return {
          'typeLabel': 'Summary',
          'typeColor': const Color(0xFFF2994A),
          'typeBgColor': const Color(0xFFFFF4E6),
          'icon': FontAwesomeIcons.fileLines,
          'iconColor': const Color(0xFFF2994A),
          'iconBgColor': const Color(0xFFFFF4E6),
        };
      case 'highlight':
      case 'key_point':
        return {
          'typeLabel': 'Highlight',
          'typeColor': const Color(0xFF10B981),
          'typeBgColor': const Color(0xFFE6F9F1),
          'icon': FontAwesomeIcons.highlighter,
          'iconColor': const Color(0xFF10B981),
          'iconBgColor': const Color(0xFFE6F9F1),
        };
      case 'important_notice':
        return {
          'typeLabel': 'Important',
          'typeColor': const Color(0xFFEF4444),
          'typeBgColor': const Color(0xFFFFE6E6),
          'icon': FontAwesomeIcons.circleExclamation,
          'iconColor': const Color(0xFFEF4444),
          'iconBgColor': const Color(0xFFFFE6E6),
        };
      case 'video_note':
        return {
          'typeLabel': 'Video Note',
          'typeColor': const Color(0xFF5A75FF),
          'typeBgColor': const Color(0xFFEEF0FF),
          'icon': FontAwesomeIcons.video,
          'iconColor': const Color(0xFF5A75FF),
          'iconBgColor': const Color(0xFFEEF0FF),
        };
      default:
        return {
          'typeLabel': 'Note',
          'typeColor': const Color(0xFF6B7280),
          'typeBgColor': const Color(0xFFF3F4F6),
          'icon': FontAwesomeIcons.noteSticky,
          'iconColor': const Color(0xFF6B7280),
          'iconBgColor': const Color(0xFFF3F4F6),
        };
    }
  }

  void _navigateToSummaryDetail(dynamic item) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SummaryDetailScreen(
          note: item,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadNotes,
              color: const Color(0xFF5A75FF),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    const SizedBox(height: 16),
                    _buildSearchBar(),
                    const SizedBox(height: 20),
                    _buildContent(),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF6B7BFF),
            Color(0xFF5A75FF),
          ],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.arrow_back,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
              const Expanded(
                child: Text(
                  'Summaries',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const SizedBox(width: 16),
          const Icon(
            Icons.search,
            color: Color(0xFF9CA3AF),
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search notes...',
                hintStyle: TextStyle(
                  color: const Color(0xFF9CA3AF).withValues(alpha: 0.8),
                  fontSize: 14,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return _buildSkeletonList();
    }

    if (_hasError) {
      return _buildErrorWidget();
    }

    if (_filteredItems.isEmpty) {
      return _buildEmptyWidget();
    }

    return _buildItemsList();
  }

  Widget _buildSkeletonList() {
    return Column(
      children: List.generate(4, (index) => _buildSkeletonCard()),
    );
  }

  Widget _buildSkeletonCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF1F1F1)),
      ),
      child: Shimmer.fromColors(
        baseColor: Colors.grey[300]!,
        highlightColor: Colors.grey[100]!,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        height: 14,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: 100,
                        height: 10,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              height: 12,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 6),
            Container(
              width: 200,
              height: 12,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.error_outline,
            color: Color(0xFFEF4444),
            size: 48,
          ),
          const SizedBox(height: 16),
          Text(
            _errorMessage,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _loadNotes,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF5A75FF),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyWidget() {
    return Container(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.folder_open_outlined,
            color: const Color(0xFF9CA3AF).withValues(alpha: 0.5),
            size: 64,
          ),
          const SizedBox(height: 16),
          const Text(
            'No summaries available',
            style: TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Pull down to refresh',
            style: TextStyle(
              color: Color(0xFF9CA3AF),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemsList() {
    return Column(
      children: _filteredItems.map((item) {
        return _buildItemCard(item);
      }).toList(),
    );
  }

  Widget _buildItemCard(dynamic item) {
    final attributes = item['attributes'] ?? {};
    final title = attributes['title']?.toString() ?? 'Untitled';
    final type = attributes['type']?.toString() ?? 'note';
    final content = attributes['content']?.toString() ?? '';
    final linkedLecture = attributes['linked_lecture']?.toString();
    final createdAt = attributes['created_at']?.toString();

    final styles = _getTypeStyles(type);
    final preview = content.length > 100 ? '${content.substring(0, 100)}...' : content;
    final date = _formatDate(createdAt);

    return GestureDetector(
      onTap: () => _navigateToSummaryDetail(item),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFF1F1F1)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: styles['iconBgColor'],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: FaIcon(
                      styles['icon'],
                      color: styles['iconColor'],
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1F2937),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: styles['typeBgColor'],
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              styles['typeLabel'],
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: styles['typeColor'],
                              ),
                            ),
                          ),
                          if (linkedLecture != null) ...[
                            const SizedBox(width: 8),
                            Text(
                              linkedLecture,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF9CA3AF),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (preview.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                preview,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF6B7280),
                  height: 1.4,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (date.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                date,
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF9CA3AF),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
