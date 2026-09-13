import 'dart:io';

import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:shimmer/shimmer.dart';

class DiscussionPanel extends StatefulWidget {
  final int currentPositionSeconds;
  final bool isLoading;
  final List<dynamic> discussions;
  final String currentTab;
  final bool isRecording;
  final String? recordedPath;
  final ValueNotifier<Duration> recordedPosition;
  final ValueNotifier<Duration> recordedTotalDuration;
  final String? currentlyPlayingUrl;
  final ValueNotifier<Duration> listAudioPosition;
  final ValueNotifier<Duration> listAudioDuration;
  final VoidCallback onClose;
  final Function(String tab) onTabChanged;
  final TextEditingController commentController;
  final VoidCallback onPost;
  final VoidCallback onStartRecording;
  final VoidCallback onStopRecording;
  final VoidCallback onDeleteRecorded;
  final Function(String url) onPlayPauseAudio;
  final Future<void> Function() onPlayRecorded;
  final VoidCallback onAddReply;
  
  /// Called when user submits a reply. [parentId] is the root discussion ID.
  final Future<void> Function(int parentId, String content) onPostReply;
  
  /// Frame snapshotted when the student tapped "ask about this moment".
  final File? momentFrame;
  
  /// True while the frame is being captured.
  final bool isCapturingFrame;
  
  /// Drops the attached frame; the comment then posts without an image.
  final VoidCallback? onDismissFrame;
  
  /// Base URL for resolving relative image paths returned by the API.
  final String apiBaseUrl;

  const DiscussionPanel({
    super.key,
    required this.currentPositionSeconds,
    required this.isLoading,
    required this.discussions,
    required this.currentTab,
    required this.isRecording,
    this.recordedPath,
    required this.recordedPosition,
    required this.recordedTotalDuration,
    this.currentlyPlayingUrl,
    required this.listAudioPosition,
    required this.listAudioDuration,
    required this.onClose,
    required this.onTabChanged,
    required this.commentController,
    required this.onPost,
    required this.onStartRecording,
    required this.onStopRecording,
    required this.onDeleteRecorded,
    required this.onPlayPauseAudio,
    required this.onPlayRecorded,
    required this.onAddReply,
    required this.onPostReply,
    this.momentFrame,
    this.isCapturingFrame = false,
    this.onDismissFrame,
    this.apiBaseUrl = 'https://api.learnoo.app',
  });

  @override
  State<DiscussionPanel> createState() => _DiscussionPanelState();
}

class _DiscussionPanelState extends State<DiscussionPanel> {
  final Set<String> _expandedReplies = {};
  final Set<String> _showReplyInput = {};
  final Map<String, TextEditingController> _replyControllers = {};
  final Set<String> _postingReply = {};

  @override
  void dispose() {
    for (final c in _replyControllers.values) c.dispose();
    super.dispose();
  }

  TextEditingController _getReplyController(String id) =>
      _replyControllers.putIfAbsent(id, () => TextEditingController());

  List<dynamic> _getRootDiscussions() => widget.discussions.where((d) {
        final parentId = (d['attributes'] ?? d)['parent_id'];
        return parentId == null;
      }).toList();

  List<dynamic> _getReplies(String discussionId) =>
      widget.discussions.where((d) {
        final parentId = (d['attributes'] ?? d)['parent_id'];
        return parentId != null && parentId.toString() == discussionId;
      }).toList();

  String _resolveUrl(String? url) {
    if (url == null || url.trim().isEmpty) return '';
    final clean = url.trim().replaceAll('\\', '/');
    if (clean.startsWith('http://') || clean.startsWith('https://')) return clean;
    final normalized = clean.replaceAll(RegExp(r'^/+'), '');
    if (normalized.startsWith('storage/')) {
      return '${widget.apiBaseUrl}/$normalized';
    }
    return '${widget.apiBaseUrl}/storage/$normalized';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.5),
      child: Column(
        children: [
          GestureDetector(
            onTap: widget.onClose,
            child: Container(
              height: MediaQuery.of(context).size.height * 0.15,
              color: Colors.transparent,
            ),
          ),
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 8, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'course.ask_about_moment_title'.tr(),
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1F2937),
                                ),
                              ),
                              if (widget.currentPositionSeconds > 0) ...[
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEEF2FF),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    _formatMoment(widget.currentPositionSeconds),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF3451E5),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: widget.onClose,
                          icon: const Icon(Icons.close, color: Color(0xFF9CA3AF)),
                        ),
                      ],
                    ),
                  ),
                  _buildDiscussionTabs(),
                  if (widget.currentTab != 'all') _buildDiscussionInput(),
                  Expanded(
                    child: widget.isLoading
                        ? _buildDiscussionSkeleton()
                        : _getRootDiscussions().isEmpty
                            ? _buildEmptyDiscussions()
                            : _buildDiscussionsList(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiscussionTabs() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _buildTabItem('course.all_discussions'.tr(), 'all'),
          _buildTabItem('course.comment'.tr(), 'comment'),
          _buildTabItem('course.voice'.tr(), 'voice'),
        ],
      ),
    );
  }

  Widget _buildTabItem(String label, String tab) {
    final isSelected = widget.currentTab == tab;
    return Expanded(
      child: GestureDetector(
        onTap: () => widget.onTabChanged(tab),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              color: isSelected ? const Color(0xFF3451E5) : const Color(0xFF6B7280),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDiscussionInput() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF3F4F6)),
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
              Text(
                'course.about_moment'.tr(args: [_formatMoment(widget.currentPositionSeconds)]),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Color(0xFF1F2937),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  widget.currentTab == 'comment' ? 'comment' : 'voice',
                  style: const TextStyle(
                    color: Color(0xFF3451E5),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => widget.onTabChanged('all'),
                child: const Icon(Icons.close, size: 18, color: Color(0xFF9CA3AF)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildMomentFramePreview(),
          if (widget.currentTab == 'comment')
            TextField(
              controller: widget.commentController,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: 'course.write_comment_moment'.tr(),
                hintStyle: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
                filled: true,
                fillColor: const Color(0xFFF9FAFB),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.all(16),
              ),
            )
          else
            _buildVoiceRecorderUI(),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: widget.onPost,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3451E5),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: Text(
                widget.currentTab == 'comment'
                    ? 'course.post_comment'.tr()
                    : 'course.post_voice_note'.tr(),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMomentFramePreview() {
    if (widget.isCapturingFrame) {
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF3451E5)),
            ),
            const SizedBox(width: 12),
            Text(
              'course.capturing_moment'.tr(),
              style: const TextStyle(color: Color(0xFF6B7280), fontSize: 13),
            ),
          ],
        ),
      );
    }

    final frame = widget.momentFrame;
    if (frame == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              frame,
              width: 84,
              height: 52,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 84,
                height: 52,
                color: const Color(0xFFE5E7EB),
                child: const Icon(
                  Icons.image_not_supported_outlined,
                  size: 18,
                  color: Color(0xFF9CA3AF),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'course.frame_attached'.tr(),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _formatMoment(widget.currentPositionSeconds),
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ],
            ),
          ),
          if (widget.onDismissFrame != null)
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              color: const Color(0xFF9CA3AF),
              tooltip: 'course.remove_frame'.tr(),
              onPressed: widget.onDismissFrame,
            ),
        ],
      ),
    );
  }

  Widget _buildVoiceRecorderUI() {
    if (widget.recordedPath != null) return _buildRecordedPreview();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(
            widget.isRecording ? Icons.mic : Icons.mic_none,
            size: 48,
            color: widget.isRecording ? const Color(0xFF3451E5) : const Color(0xFF9CA3AF),
          ),
          const SizedBox(height: 12),
          Text(
            widget.isRecording ? 'course.recording'.tr() : 'course.tap_to_record'.tr(),
            style: TextStyle(
              color: widget.isRecording ? const Color(0xFF3451E5) : const Color(0xFF6B7280),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  if (widget.isRecording) {
                    widget.onStopRecording();
                  } else {
                    widget.onStartRecording();
                  }
                },
                borderRadius: BorderRadius.circular(32),
                child: Container(
                  height: 64,
                  width: 64,
                  decoration: BoxDecoration(
                    color: const Color(0xFF3451E5),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF3451E5).withValues(alpha: 0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(
                    widget.isRecording ? Icons.stop : Icons.mic,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordedPreview() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: widget.onPlayRecorded,
                child: Icon(
                  widget.currentlyPlayingUrl == 'recorded'
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  color: const Color(0xFF3451E5),
                  size: 32,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ValueListenableBuilder<Duration>(
                  valueListenable: widget.recordedTotalDuration,
                  builder: (context, totalDuration, child) {
                    return ValueListenableBuilder<Duration>(
                      valueListenable: widget.recordedPosition,
                      builder: (context, position, child) {
                        return LinearProgressIndicator(
                          value: totalDuration.inMilliseconds > 0
                              ? position.inMilliseconds / totalDuration.inMilliseconds
                              : 0.0,
                          backgroundColor: const Color(0xFFE5E7EB),
                          valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF3451E5)),
                          borderRadius: BorderRadius.circular(4),
                        );
                      },
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              ValueListenableBuilder<Duration>(
                valueListenable: widget.recordedTotalDuration,
                builder: (context, totalDuration, child) {
                  return Text(
                    _formatDuration(totalDuration),
                    style: const TextStyle(
                      color: Color(0xFF6B7280),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              IconButton(
                onPressed: widget.onDeleteRecorded,
                icon: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 28),
              ),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: widget.onStartRecording,
                  borderRadius: BorderRadius.circular(28),
                  child: Container(
                    height: 56,
                    width: 56,
                    decoration: const BoxDecoration(
                      color: Color(0xFF3451E5),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.mic, color: Colors.white, size: 28),
                  ),
                ),
              ),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: widget.onPost,
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    height: 56,
                    width: 56,
                    decoration: BoxDecoration(
                      color: const Color(0xFF3451E5),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.send_rounded, color: Colors.white, size: 24),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDiscussionSkeleton() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: 5,
      itemBuilder: (context, index) => Shimmer.fromColors(
        baseColor: Colors.grey[200]!,
        highlightColor: Colors.grey[50]!,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CircleAvatar(radius: 20, backgroundColor: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(height: 12, width: 100, color: Colors.white),
                    const SizedBox(height: 8),
                    Container(height: 10, width: double.infinity, color: Colors.white),
                    const SizedBox(height: 4),
                    Container(height: 10, width: 150, color: Colors.white),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyDiscussions() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.chat_bubble_outline, size: 48, color: Color(0xFFD1D5DB)),
          const SizedBox(height: 16),
          Text('course.no_discussions_yet'.tr(),
              style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 16)),
          const SizedBox(height: 8),
          Text('course.be_the_first_discussion'.tr(),
              style: const TextStyle(color: Color(0xFFD1D5DB), fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildDiscussionsList() {
    final roots = _getRootDiscussions();
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      itemCount: roots.length,
      itemBuilder: (context, index) => _buildRootDiscussionItem(roots[index]),
    );
  }

  Widget _buildRootDiscussionItem(dynamic discussion) {
    final id = discussion['id']?.toString() ?? '';
    final attrs = discussion['attributes'] ?? {};
    final user = attrs['user']?['data']?['attributes'] ?? {};
    final firstName = (user['first_name'] ?? '').toString();
    final lastName = (user['last_name'] ?? '').toString();
    final content = (attrs['content'] ?? '').toString();
    final type = (attrs['type'] ?? 'text').toString();
    final momentRaw = attrs['moment'] ?? 0;
    final moment = momentRaw is int ? momentRaw : int.tryParse(momentRaw.toString()) ?? 0;
    final createdAt = (attrs['created_at'] ?? '').toString();
    final imageUrl = _resolveUrl(attrs['image']?.toString());

    final fromList = _getReplies(id);
    final fromAttrs = (attrs['replies'] as List? ?? []);
    final allReplies = [
      ...fromList,
      ...fromAttrs.where((r) {
        final rId = r['id']?.toString() ?? '';
        return !fromList.any((lr) => lr['id']?.toString() == rId);
      }),
    ];

    final replyCount = allReplies.length;
    final isExpanded = _expandedReplies.contains(id);
    final showReplyInput = _showReplyInput.contains(id);

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDiscussionCard(
            firstName: firstName,
            lastName: lastName,
            content: content,
            type: type,
            moment: moment,
            createdAt: createdAt,
            imageUrl: imageUrl,
          ),
          Padding(
            padding: const EdgeInsets.only(left: 48, top: 8),
            child: Wrap(
              spacing: 8,
              children: [
                _buildActionChip(
                  icon: Icons.reply,
                  label: 'course.reply'.tr(),
                  onTap: () => setState(() {
                    if (showReplyInput) {
                      _showReplyInput.remove(id);
                    } else {
                      _showReplyInput.add(id);
                    }
                  }),
                  active: showReplyInput,
                ),
                if (replyCount > 0)
                  _buildActionChip(
                    icon: isExpanded ? Icons.expand_less : Icons.expand_more,
                    label: isExpanded
                        ? 'course.hide_replies'.tr()
                        : 'course.show_replies'.tr(args: [replyCount.toString()]),
                    onTap: () => setState(() {
                      if (isExpanded) {
                        _expandedReplies.remove(id);
                      } else {
                        _expandedReplies.add(id);
                      }
                    }),
                    active: false,
                  ),
              ],
            ),
          ),
          if (showReplyInput) _buildReplyComposer(id),
          if (isExpanded && allReplies.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 56, top: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 2,
                    margin: const EdgeInsets.only(right: 12, top: 4),
                    color: const Color(0xFFE5E7EB),
                  ),
                  Expanded(
                    child: Column(
                      children: allReplies.map((r) => _buildReplyCard(r)).toList(),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDiscussionCard({
    required String firstName,
    required String lastName,
    required String content,
    required String type,
    required int moment,
    required String createdAt,
    required String imageUrl,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: const Color(0xFFE5E7EB),
          child: Text(
            firstName.isNotEmpty ? firstName[0].toUpperCase() : 'U',
            style: const TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '$firstName $lastName'.trim().isEmpty
                          ? 'User'
                          : '$firstName $lastName'.trim(),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                  ),
                  Text(
                    _formatDate(createdAt),
                    style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 11),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _formatMoment(moment),
                  style: const TextStyle(
                    color: Color(0xFF3451E5),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (type == 'text' && content.isNotEmpty)
                Text(content,
                    style: const TextStyle(
                        fontSize: 14, color: Color(0xFF4B5563), height: 1.5)),
              if (type == 'voice' && content.isNotEmpty) _buildAudioPlayer(content),
              if (type == 'voice' && content.isEmpty)
                Text('course.voice_question_linked'.tr(),
                    style: const TextStyle(color: Color(0xFF6B7280), fontSize: 13)),
              if (imageUrl.isNotEmpty) ...[
                const SizedBox(height: 10),
                _buildNetworkImage(imageUrl, height: 160),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildReplyCard(dynamic reply) {
    final attrs = reply['attributes'] ?? reply;
    final user = attrs['user']?['data']?['attributes'] ?? {};
    final firstName = (user['first_name'] ?? '').toString();
    final lastName = (user['last_name'] ?? '').toString();
    final role = (user['role'] ?? '').toString();
    final content = (attrs['content'] ?? '').toString();
    final type = (attrs['type'] ?? 'text').toString();
    final createdAt = (attrs['created_at'] ?? '').toString();
    final imageUrl = _resolveUrl(attrs['image']?.toString());
    final isInstructor =
        role.toLowerCase() == 'admin' || role.toLowerCase() == 'instructor';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F9FF),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor:
                      isInstructor ? const Color(0xFF3451E5) : const Color(0xFFE5E7EB),
                  child: Text(
                    firstName.isNotEmpty ? firstName[0].toUpperCase() : 'U',
                    style: TextStyle(
                      color: isInstructor ? Colors.white : const Color(0xFF6B7280),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$firstName $lastName'.trim().isEmpty
                        ? 'User'
                        : '$firstName $lastName'.trim(),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: isInstructor ? const Color(0xFF3451E5) : const Color(0xFF1F2937),
                    ),
                  ),
                ),
                if (isInstructor)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3451E5),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('course.instructor'.tr(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        )),
                  ),
                const SizedBox(width: 6),
                Text(_formatDate(createdAt),
                    style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 10)),
              ],
            ),
            const SizedBox(height: 8),
            if (type == 'text' && content.isNotEmpty)
              Text(content,
                  style: const TextStyle(
                      fontSize: 13, color: Color(0xFF4B5563), height: 1.5)),
            if (type == 'voice' && content.isNotEmpty) _buildAudioPlayer(content),
            if (imageUrl.isNotEmpty) ...[
              const SizedBox(height: 8),
              _buildNetworkImage(imageUrl, height: 120),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildReplyComposer(String discussionId) {
    final controller = _getReplyController(discussionId);
    final isPosting = _postingReply.contains(discussionId);
    final parentIdInt = int.tryParse(discussionId);

    return Padding(
      padding: const EdgeInsets.only(left: 48, top: 10, bottom: 4),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            TextField(
              controller: controller,
              maxLines: 3,
              minLines: 1,
              decoration: InputDecoration(
                hintText: 'course.write_reply'.tr(),
                hintStyle: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFF3451E5), width: 1.5),
                ),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () {
                    controller.clear();
                    setState(() => _showReplyInput.remove(discussionId));
                  },
                  child: Text('course.cancel_reply'.tr(),
                      style: const TextStyle(color: Color(0xFF6B7280))),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: (isPosting || parentIdInt == null)
                      ? null
                      : () async {
                          final text = controller.text.trim();
                          if (text.isEmpty) return;
                          setState(() => _postingReply.add(discussionId));
                          await widget.onPostReply(parentIdInt, text);
                          controller.clear();
                          if (!mounted) return;
                          setState(() {
                            _postingReply.remove(discussionId);
                            _showReplyInput.remove(discussionId);
                            _expandedReplies.add(discussionId);
                          });
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3451E5),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                  child: isPosting
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text('course.post_reply'.tr(),
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAudioPlayer(String url) {
    final isPlaying = widget.currentlyPlayingUrl == url;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF2FF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => widget.onPlayPauseAudio(url),
            child: Container(
              height: 32,
              width: 32,
              decoration: const BoxDecoration(
                color: Color(0xFF3451E5),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isPlaying ? Icons.pause : Icons.play_arrow,
                color: Colors.white,
                size: 18,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ValueListenableBuilder<Duration>(
              valueListenable: widget.listAudioDuration,
              builder: (context, totalDuration, child) {
                return ValueListenableBuilder<Duration>(
                  valueListenable: widget.listAudioPosition,
                  builder: (context, position, child) {
                    return LinearProgressIndicator(
                      value: isPlaying && totalDuration.inMilliseconds > 0
                          ? position.inMilliseconds / totalDuration.inMilliseconds
                          : 0.0,
                      backgroundColor: Colors.white.withValues(alpha: 0.5),
                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF3451E5)),
                      borderRadius: BorderRadius.circular(4),
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(width: 12),
          ValueListenableBuilder<Duration>(
            valueListenable: widget.listAudioDuration,
            builder: (context, totalDuration, child) {
              return Text(
                _formatDuration(totalDuration),
                style: const TextStyle(
                  color: Color(0xFF3451E5),
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildNetworkImage(String url, {required double height}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.network(
        url,
        height: height,
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        loadingBuilder: (_, child, progress) {
          if (progress == null) return child;
          return Container(
            height: height,
            width: double.infinity,
            color: const Color(0xFFF3F4F6),
            child: const Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFF3451E5),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildActionChip({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required bool active,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF3451E5) : const Color(0xFFEEF2FF),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: active ? Colors.white : const Color(0xFF3451E5)),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: active ? Colors.white : const Color(0xFF3451E5),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  String _formatMoment(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String _formatDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      return DateFormat('dd/MM/yyyy HH:mm').format(date);
    } catch (_) {
      return dateStr;
    }
  }
}
