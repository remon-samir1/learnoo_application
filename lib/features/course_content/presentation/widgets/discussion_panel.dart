import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:shimmer/shimmer.dart';
import 'package:intl/intl.dart';

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
  final VoidCallback onAddReply; // If needed

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
  });

  @override
  State<DiscussionPanel> createState() => _DiscussionPanelState();
}

class _DiscussionPanelState extends State<DiscussionPanel> {
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
                        Text(
                          'course.ask_about_moment_title'.tr(),
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1F2937),
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: widget.onClose,
                          icon: const Icon(
                            Icons.close,
                            color: Color(0xFF9CA3AF),
                          ),
                        ),
                      ],
                    ),
                  ),
                  _buildDiscussionTabs(),
                  if (widget.currentTab != 'all') _buildDiscussionInput(),
                  Expanded(
                    child: widget.isLoading
                        ? _buildDiscussionSkeleton()
                        : widget.discussions.isEmpty
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
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
    bool isSelected = widget.currentTab == tab;
    return Expanded(
      child: GestureDetector(
        onTap: () => widget.onTabChanged(tab),
        child: Container(
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
              color: isSelected
                  ? const Color(0xFF3451E5)
                  : const Color(0xFF6B7280),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDiscussionInput() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 20),
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
                child: const Icon(
                  Icons.close,
                  size: 18,
                  color: Color(0xFF9CA3AF),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (widget.currentTab == 'comment')
            TextField(
              controller: widget.commentController,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: 'course.write_comment_moment'.tr(),
                hintStyle: const TextStyle(
                  color: Color(0xFF9CA3AF),
                  fontSize: 14,
                ),
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
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
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
            color: widget.isRecording
                ? const Color(0xFF3451E5)
                : const Color(0xFF9CA3AF),
          ),
          const SizedBox(height: 12),
          Text(
            widget.isRecording
                ? 'course.recording'.tr()
                : 'course.tap_to_record'.tr(),
            style: TextStyle(
              color: widget.isRecording
                  ? const Color(0xFF3451E5)
                  : const Color(0xFF6B7280),
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
                  widget.currentlyPlayingUrl == 'recorded' // Using a special string for recorded player state
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
                              ? position.inMilliseconds /
                                    totalDuration.inMilliseconds
                              : 0.0,
                          backgroundColor: const Color(0xFFE5E7EB),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            Color(0xFF3451E5),
                          ),
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
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.red,
                  size: 28,
                ),
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
                    child: const Icon(
                      Icons.send_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
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
                    Container(
                      height: 10,
                      width: double.infinity,
                      color: Colors.white,
                    ),
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
          const Icon(
            Icons.chat_bubble_outline,
            size: 48,
            color: Color(0xFFD1D5DB),
          ),
          const SizedBox(height: 16),
          Text(
            'course.no_discussions_yet'.tr(),
            style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            'course.be_the_first_discussion'.tr(),
            style: const TextStyle(color: Color(0xFFD1D5DB), fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildDiscussionsList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      itemCount: widget.discussions.length,
      itemBuilder: (context, index) {
        final discussion = widget.discussions[index];
        final attributes = discussion['attributes'] ?? {};
        final user = attributes['user']?['data']?['attributes'] ?? {};
        final firstName = user['first_name'] ?? '';
        final lastName = user['last_name'] ?? '';

        final content = attributes['content'] ?? '';
        final type = attributes['type'] ?? 'text';
        final moment = attributes['moment'] ?? 0;
        final createdAt = attributes['created_at'] ?? '';
        final replies = attributes['replies'] as List? ?? [];

        return Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: const Color(0xFFE5E7EB),
                    child: Text(
                      firstName.isNotEmpty ? firstName[0].toUpperCase() : 'U',
                      style: const TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Row(
                      children: [
                        Text(
                          '$firstName $lastName',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: Color(0xFF1F2937),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _formatDate(createdAt),
                          style: const TextStyle(
                            color: Color(0xFF9CA3AF),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(left: 48),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RichText(
                      text: TextSpan(
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF4B5563),
                          height: 1.5,
                        ),
                        children: [
                          TextSpan(
                            text: '${_formatMoment(moment)} ',
                            style: const TextStyle(
                              color: Color(0xFF3451E5),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          TextSpan(
                            text: type == 'text'
                                ? content
                                : 'course.voice_question_linked'.tr(),
                          ),
                        ],
                      ),
                    ),
                    if (type == 'voice') ...[
                      const SizedBox(height: 12),
                      _buildAudioPlayer(content),
                    ],
                    if (replies.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      ...replies.map((reply) => _buildReplyItem(reply)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAudioPlayer(String url) {
    bool isPlaying = widget.currentlyPlayingUrl == url;
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
                          ? position.inMilliseconds /
                                totalDuration.inMilliseconds
                          : 0.0,
                      backgroundColor: Colors.white.withValues(alpha: 0.5),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Color(0xFF3451E5),
                      ),
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

  Widget _buildReplyItem(dynamic reply) {
    final attributes = reply['attributes'] ?? {};
    final user = attributes['user']?['data']?['attributes'] ?? {};
    final firstName = user['first_name'] ?? '';
    final lastName = user['last_name'] ?? '';
    final role = user['role'] ?? '';
    final content = attributes['content'] ?? '';
    bool isInstructor =
        role.toLowerCase() == 'admin' || role.toLowerCase() == 'instructor';

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4FF),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: const Color(0xFF3451E5),
                child: Text(
                  firstName.isNotEmpty ? firstName[0].toUpperCase() : 'I',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '$firstName $lastName',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: Color(0xFF3451E5),
                ),
              ),
              if (isInstructor) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3451E5),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'course.instructor'.tr(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            content,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF4B5563),
              height: 1.5,
            ),
          ),
        ],
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
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
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
