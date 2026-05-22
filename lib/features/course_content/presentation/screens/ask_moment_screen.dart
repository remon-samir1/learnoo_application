import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'dart:async';

class AskMomentScreen extends StatefulWidget {
  const AskMomentScreen({super.key});

  @override
  State<AskMomentScreen> createState() => _AskMomentScreenState();
}

class _AskMomentScreenState extends State<AskMomentScreen> {
  int _selectedTab = 0; // 0: All Discussions, 1: Comment, 2: Voice
  bool _isRecording = false;
  bool _hasRecorded = false;
  int _recordingSeconds = 0;
  double _playbackProgress = 0.3;
  bool _isPlaying = false;
  Timer? _recordingTimer;
  final TextEditingController _commentController = TextEditingController();

  final List<Map<String, dynamic>> _discussions = [
    {
      'name': 'Ahmed',
      'avatar': 'A',
      'time': '18:35',
      'timestamp': '4:45',
      'message': 'Great explanation! The merge sort example is much clearer now.',
      'isInstructor': false,
    },
    {
      'name': 'Dr. Sarah Ahmed',
      'avatar': 'D',
      'time': '1 hour ago',
      'timestamp': null,
      'message': 'Great question! Merge sort always has O(n log n) complexity, while quick sort has average O(n log n) but worst case O(n²). Merge sort is stable, quick sort is not.',
      'isInstructor': true,
    },
    {
      'name': 'Fatima',
      'avatar': 'F',
      'time': '18:36',
      'timestamp': '2:30',
      'message': 'Can you repeat the last part?',
      'isInstructor': false,
    },
    {
      'name': 'Noura',
      'avatar': 'N',
      'time': '18:36',
      'timestamp': '12:45',
      'message': 'I missed why the smaller branch moved first',
      'isInstructor': false,
    },
  ];

  void _startRecording() {
    setState(() {
      _isRecording = true;
      _recordingSeconds = 0;
    });
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _recordingSeconds++;
      });
    });
  }

  void _stopRecording() {
    _recordingTimer?.cancel();
    setState(() {
      _isRecording = false;
      _hasRecorded = true;
    });
  }

  void _cancelRecording() {
    _recordingTimer?.cancel();
    setState(() {
      _isRecording = false;
      _hasRecorded = false;
      _recordingSeconds = 0;
    });
  }

  String _formatTime(int seconds) {
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const FaIcon(FontAwesomeIcons.arrowLeft, size: 20),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Text(
                      'Ask about this moment',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Tabs
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _buildTab('All Discussions', 0),
                  const SizedBox(width: 8),
                  _buildTab('Comment', 1),
                  const SizedBox(width: 8),
                  _buildTab('Voice', 2),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Content
            Expanded(
              child: _selectedTab == 0
                  ? _buildDiscussionsList()
                  : _selectedTab == 1
                      ? _buildCommentInput()
                      : _buildVoiceRecorder(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTab(String label, int index) {
    final isSelected = _selectedTab == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedTab = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFF0F2FF) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFF3451E5) : const Color(0xFFE5E7EB),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            color: isSelected ? const Color(0xFF3451E5) : const Color(0xFF6B7280),
          ),
        ),
      ),
    );
  }

  Widget _buildDiscussionsList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _discussions.length,
      itemBuilder: (context, index) {
        final discussion = _discussions[index];
        return _buildDiscussionItem(
          name: discussion['name'],
          avatar: discussion['avatar'],
          time: discussion['time'],
          timestamp: discussion['timestamp'],
          message: discussion['message'],
          isInstructor: discussion['isInstructor'],
        );
      },
    );
  }

  Widget _buildDiscussionItem({
    required String name,
    required String avatar,
    required String time,
    String? timestamp,
    required String message,
    required bool isInstructor,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isInstructor ? const Color(0xFF3451E5) : const Color(0xFFE5E7EB),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                avatar,
                style: TextStyle(
                  color: isInstructor ? Colors.white : const Color(0xFF6B7280),
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Content
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
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      time,
                      style: const TextStyle(
                        color: Color(0xFF9CA3AF),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                if (isInstructor) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3451E5),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'Instructor',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                if (timestamp != null)
                  Text(
                    timestamp,
                    style: const TextStyle(
                      color: Color(0xFF3451E5),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isInstructor ? const Color(0xFFF0F2FF) : const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    message,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF374151),
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommentInput() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          // Info bar
          Row(
            children: [
              const Text(
                'About',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F2FF),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  '12:45',
                  style: TextStyle(
                    color: Color(0xFF3451E5),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () {},
                child: const FaIcon(FontAwesomeIcons.xmark, size: 16, color: Color(0xFF9CA3AF)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Tabs
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Center(
                    child: Text(
                      'All Discussions',
                      style: TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F2FF),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Center(
                    child: Text(
                      'Comment',
                      style: TextStyle(
                        color: Color(0xFF3451E5),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _selectedTab = 2),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF9FAFB),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Center(
                      child: Text(
                        'Voice',
                        style: TextStyle(
                          color: Color(0xFF6B7280),
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Text Field
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFE5E7EB)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TextField(
              controller: _commentController,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'Write a comment about this moment...',
                hintStyle: TextStyle(
                  color: Color(0xFF9CA3AF),
                  fontSize: 14,
                ),
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Post Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {},
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3451E5),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: const Text(
                'Post Comment',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVoiceRecorder() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          // Header
          Row(
            children: [
              const Text(
                'Ask about 12:45',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: _cancelRecording,
                child: const Text(
                  'Cancel',
                  style: TextStyle(
                    color: Color(0xFF9CA3AF),
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Recording Options
          if (!_isRecording && !_hasRecorded) ...[
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () {},
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Column(
                        children: [
                          FaIcon(FontAwesomeIcons.solidCommentDots, color: Color(0xFF3451E5), size: 24),
                          SizedBox(height: 8),
                          Text(
                            'Text Comment',
                            style: TextStyle(
                              color: Color(0xFF3451E5),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: _startRecording,
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFF3451E5)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Column(
                        children: [
                          FaIcon(FontAwesomeIcons.microphone, color: Color(0xFF3451E5), size: 24),
                          SizedBox(height: 8),
                          Text(
                            'Voice Note',
                            style: TextStyle(
                              color: Color(0xFF3451E5),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ] else if (_isRecording) ...[
            // Recording in progress
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFE5E7EB)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  const FaIcon(FontAwesomeIcons.microphone, color: Color(0xFF9CA3AF), size: 32),
                  const SizedBox(height: 12),
                  Text(
                    'Tap to record voice note',
                    style: TextStyle(
                      color: const Color(0xFF9CA3AF),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // Record button
            GestureDetector(
              onTap: _stopRecording,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF3451E5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const FaIcon(FontAwesomeIcons.microphone, color: Colors.white, size: 18),
                    const SizedBox(width: 10),
                    Text(
                      'Recording ${_formatTime(_recordingSeconds)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ] else if (_hasRecorded) ...[
            // Recorded voice with player
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFE5E7EB)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  // Waveform visualization
                  Container(
                    height: 60,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(20, (index) {
                        return Container(
                          width: 3,
                          height: 20 + (index % 5) * 8.0,
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          decoration: BoxDecoration(
                            color: index < _playbackProgress * 20
                                ? const Color(0xFF3451E5)
                                : const Color(0xFFE5E7EB),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        );
                      }),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // Playback controls
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: _cancelRecording,
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFEBEE),
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: FaIcon(FontAwesomeIcons.trash, color: Color(0xFFFF4B4B), size: 20),
                    ),
                  ),
                ),
                const SizedBox(width: 24),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _isPlaying = !_isPlaying;
                    });
                  },
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: const BoxDecoration(
                      color: Color(0xFF3451E5),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: FaIcon(
                        _isPlaying ? FontAwesomeIcons.pause : FontAwesomeIcons.play,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 24),
                GestureDetector(
                  onTap: () {},
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F5E9),
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: FaIcon(FontAwesomeIcons.paperPlane, color: Color(0xFF2DBC77), size: 20),
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 32),
          // Previous voice notes list
          if (!_isRecording)
            Expanded(
              child: ListView(
                children: [
                  _buildVoiceNoteItem(
                    name: 'Ahmed',
                    avatar: 'A',
                    time: '18:35',
                    timestamp: '12:45',
                    duration: '00:21',
                    progress: 0.4,
                  ),
                  const SizedBox(height: 16),
                  _buildVoiceNoteItem(
                    name: 'Beatrice',
                    avatar: 'B',
                    time: '19:00',
                    timestamp: '12:45',
                    duration: '00:25',
                    progress: 0.6,
                  ),
                  const SizedBox(height: 16),
                  _buildVoiceNoteItem(
                    name: 'Carlos',
                    avatar: 'C',
                    time: '19:15',
                    timestamp: '12:45',
                    duration: '00:30',
                    progress: 0.8,
                    isPlaying: true,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildVoiceNoteItem({
    required String name,
    required String avatar,
    required String time,
    required String timestamp,
    required String duration,
    required double progress,
    bool isPlaying = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: const BoxDecoration(
            color: Color(0xFFE5E7EB),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              avatar,
              style: const TextStyle(
                color: Color(0xFF6B7280),
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
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
                  Text(
                    name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    time,
                    style: const TextStyle(
                      color: Color(0xFF9CA3AF),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Short voice question linked to $timestamp in the live explanation.',
                style: const TextStyle(
                  color: Color(0xFF6B7280),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F2FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () {},
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: const BoxDecoration(
                          color: Color(0xFF3451E5),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: FaIcon(
                            isPlaying ? FontAwesomeIcons.pause : FontAwesomeIcons.play,
                            color: Colors.white,
                            size: 12,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        children: [
                          // Progress bar
                          Container(
                            height: 4,
                            decoration: BoxDecoration(
                              color: const Color(0xFFE5E7EB),
                              borderRadius: BorderRadius.circular(2),
                            ),
                            child: FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: progress,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: const Color(0xFF3451E5),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                isPlaying ? '00:12 / $duration' : duration,
                                style: const TextStyle(
                                  color: Color(0xFF9CA3AF),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
