import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:shimmer/shimmer.dart';
import '../../data/live_room_repository.dart';
import '../../data/models/live_room.dart' as lr;
import 'widgets/session_detail_modal.dart';
import 'widgets/set_reminder_modal.dart';
import 'live_stream_screen.dart';

class LiveSessionsScreen extends StatefulWidget {
  const LiveSessionsScreen({super.key});

  @override
  State<LiveSessionsScreen> createState() => _LiveSessionsScreenState();
}

class _LiveSessionsScreenState extends State<LiveSessionsScreen> {
  String _selectedFilter = 'All';
  final LiveRoomRepository _liveRoomRepository = LiveRoomRepository();
  List<lr.LiveRoom> _sessions = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadLiveRooms();
  }

  Future<void> _loadLiveRooms() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await _liveRoomRepository.getLiveRooms();
      if (mounted) {
        if (result['success']) {
          setState(() {
            _sessions = result['data'] as List<lr.LiveRoom>;
            _isLoading = false;
          });
        } else {
          setState(() {
            _errorMessage = result['message'];
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'course.failed_load_live_rooms'.tr();
          _isLoading = false;
        });
      }
    }
  }

  List<lr.LiveRoom> get _filteredSessions {
    if (_selectedFilter == 'All') return _sessions;
    if (_selectedFilter == 'Live Now') {
      return _sessions.where((s) => s.status == lr.SessionStatus.now).toList();
    }
    if (_selectedFilter == 'Upcoming') {
      return _sessions.where((s) => s.status == lr.SessionStatus.upcoming).toList();
    }
    if (_selectedFilter == 'Recorded') {
      return _sessions.where((s) => s.status == lr.SessionStatus.recorded).toList();
    }
    return _sessions;
  }

  SessionStatus _mapToModalStatus(lr.SessionStatus status) {
    switch (status) {
      case lr.SessionStatus.now:
        return SessionStatus.now;
      case lr.SessionStatus.upcoming:
        return SessionStatus.upcoming;
      case lr.SessionStatus.recorded:
        return SessionStatus.recorded;
    }
  }

  void _showSessionDetail(lr.LiveRoom session) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SessionDetailModal(
        session: LiveSession(
          id: session.id,
          title: session.title,
          instructor: session.instructorName,
          time: session.formattedTime,
          duration: session.duration,
          status: _mapToModalStatus(session.status),
          category: session.courseTitle ?? 'course.general'.tr(),
          description: session.description,
        ),
        onSetReminder: () {
          Navigator.pop(context);
          _showSetReminder(session);
        },
        onJoinNow: () {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => LiveStreamScreen(liveRoom: session),
            ),
          );
        },
        onWatch: () {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => LiveStreamScreen(liveRoom: session),
            ),
          );
        },
      ),
    );
  }

  void _showSetReminder(lr.LiveRoom session) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SetReminderModal(
        sessionTitle: session.title,
        onSave: (minutes) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('course.reminder_set'.tr(args: [minutes.toString()])),
              backgroundColor: const Color(0xFF4A68F6),
            ),
          );
        },
        onCancel: () {
          Navigator.pop(context);
        },
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
          _buildFilterTabs(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadLiveRooms,
              color: const Color(0xFF4A68F6),
              backgroundColor: Colors.white,
              child: _isLoading
                  ? _buildSkeletonList()
                  : _errorMessage != null
                      ? _buildErrorWidget()
                      : _filteredSessions.isEmpty
                          ? _buildEmptyWidget()
                          : ListView.builder(
                              padding: const EdgeInsets.all(16),
                              physics: const AlwaysScrollableScrollPhysics(),
                              itemCount: _filteredSessions.length,
                              itemBuilder: (context, index) {
                                return _buildSessionCard(_filteredSessions[index]);
                              },
                            ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSkeletonList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 4,
      itemBuilder: (context, index) {
        return _buildSkeletonCard();
      },
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
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
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
                  width: 60,
                  height: 24,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const Spacer(),
                Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              height: 18,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: 150,
              height: 14,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 4),
            Container(
              width: 120,
              height: 12,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const FaIcon(
              FontAwesomeIcons.triangleExclamation,
              color: Color(0xFFF2994A),
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              _errorMessage ?? 'course.something_went_wrong'.tr(),
              style: const TextStyle(
                color: Color(0xFF6B7280),
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadLiveRooms,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4A68F6),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text('course.retry'.tr()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyWidget() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const FaIcon(
              FontAwesomeIcons.towerBroadcast,
              color: Color(0xFFD1D5DB),
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              'course.no_sessions_found'.tr(args: [_selectedFilter == 'All' ? 'course.all'.tr() : _selectedFilter == 'Live Now' ? 'course.live_now'.tr() : _selectedFilter == 'Upcoming' ? 'course.upcoming_filter'.tr() : 'course.recorded_filter'.tr()]),
              style: const TextStyle(
                color: Color(0xFF6B7280),
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3451E5), Color(0xFF5A75FF), Color(0xFF7B93FF)],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      child: Column(
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
             padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 50),
              child: Column(
                children: [
                  Text(
                    'course.live_sessions'.tr(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterTabs() {
    final filters = ['All', 'Live Now', 'Upcoming', 'Recorded'];
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: filters.map((filter) {
            final isSelected = _selectedFilter == filter;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => setState(() => _selectedFilter = filter),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFF4A68F6) : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected ? const Color(0xFF4A68F6) : const Color(0xFFE5E7EB),
                    ),
                  ),
                  child: Text(
                    filter == 'All' ? 'course.all'.tr() : filter == 'Live Now' ? 'course.live_now'.tr() : filter == 'Upcoming' ? 'course.upcoming_filter'.tr() : 'course.recorded_filter'.tr(),
                    style: TextStyle(
                      color: isSelected ? Colors.white : const Color(0xFF6B7280),
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildSessionCard(lr.LiveRoom session) {
    return GestureDetector(
      onTap: () => _showSessionDetail(session),
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
                _buildStatusBadge(_mapToModalStatus(session.status)),
                const Spacer(),
                const FaIcon(
                  FontAwesomeIcons.towerBroadcast,
                  color: Color(0xFF5A75FF),
                  size: 18,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              session.title,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: Color(0xFF1F2937),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              session.instructorName,
              style: const TextStyle(
                color: Color(0xFF6B7280),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${session.formattedTime} • ${session.duration}',
              style: TextStyle(
                color: const Color(0xFF9CA3AF),
                fontSize: 12,
                fontWeight: FontWeight.w400,
              ),
            ),
            const SizedBox(height: 16),
            _buildActionButtons(session),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(SessionStatus status) {
    final (bgColor, textColor, label, dotColor) = switch (status) {
      SessionStatus.now => (
          const Color(0xFFFFF0F0),
          const Color(0xFFFF4B4B),
          'course.live_uppercase'.tr(),
          const Color(0xFFFF4B4B)
        ),
      SessionStatus.upcoming => (
          const Color(0xFFFFF9F0),
          const Color(0xFFF2994A),
          'course.upcoming_uppercase'.tr(),
          const Color(0xFFF2994A)
        ),
      SessionStatus.recorded => (
          const Color(0xFFF0F2FF),
          const Color(0xFF5A75FF),
          'course.recorded_uppercase'.tr(),
          const Color(0xFF5A75FF)
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: textColor,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(lr.LiveRoom session) {
    if (session.status == lr.SessionStatus.now) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: () => _showSessionDetail(session),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2DBC77),
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 0,
          ),
          child: Text(
            'course.join_live'.tr(),
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ),
      );
    } else if (session.status == lr.SessionStatus.upcoming) {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => _showSessionDetail(session),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF6B7280),
                side: const BorderSide(color: Color(0xFFD1D5DB)),
                minimumSize: const Size(double.infinity, 44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(
                'course.view_details'.tr(),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton(
              onPressed: () => _showSetReminder(session),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF5A75FF),
                side: const BorderSide(color: Color(0xFF5A75FF)),
                minimumSize: const Size(double.infinity, 44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(
                'course.set_reminder'.tr(),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      );
    } else if (session.status == lr.SessionStatus.recorded) {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => _showSessionDetail(session),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF6B7280),
                side: const BorderSide(color: Color(0xFFD1D5DB)),
                minimumSize: const Size(double.infinity, 44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(
                'course.view_details'.tr(),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton(
              onPressed: () => _showSessionDetail(session),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF5A75FF),
                side: const BorderSide(color: Color(0xFF5A75FF)),
                minimumSize: const Size(double.infinity, 44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(
                'course.watch'.tr(),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      );
    }
    return const SizedBox.shrink();
  }
}
