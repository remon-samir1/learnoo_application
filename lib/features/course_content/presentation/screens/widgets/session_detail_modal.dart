import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

enum SessionStatus { now, upcoming, recorded }

class LiveSession {
  final String id;
  final String title;
  final String instructor;
  final String time;
  final String duration;
  final SessionStatus status;
  final String category;
  final String? description;
  final String? sessionInfo;

  LiveSession({
    required this.id,
    required this.title,
    required this.instructor,
    required this.time,
    required this.duration,
    required this.status,
    required this.category,
    this.description,
    this.sessionInfo,
  });
}

class SessionDetailModal extends StatelessWidget {
  final LiveSession session;
  final VoidCallback onSetReminder;
  final VoidCallback onJoinNow;
  final VoidCallback onWatch;

  const SessionDetailModal({
    super.key,
    required this.session,
    required this.onSetReminder,
    required this.onJoinNow,
    required this.onWatch,
  });

  Color get _statusColor {
    switch (session.status) {
      case SessionStatus.now:
        return const Color(0xFFFF4B4B);
      case SessionStatus.upcoming:
        return const Color(0xFFF2994A);
      case SessionStatus.recorded:
        return const Color(0xFF5A75FF);
    }
  }

  String get _statusLabel {
    switch (session.status) {
      case SessionStatus.now:
        return 'NOW';
      case SessionStatus.upcoming:
        return 'Today';
      case SessionStatus.recorded:
        return 'Recorded';
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isLive = session.status == SessionStatus.now;
    final bool isRecorded = session.status == SessionStatus.recorded;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle bar
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE5E7EB),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Status Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _statusLabel,
                    style: TextStyle(
                      color: _statusColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Title
                Text(
                  session.title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 4),
                // Category
                Text(
                  session.category,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF9CA3AF),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 20),
                // Info Cards
                Row(
                  children: [
                    Expanded(
                      child: _buildInfoCard(
                        icon: FontAwesomeIcons.user,
                        label: session.instructor,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildInfoCard(
                        icon: FontAwesomeIcons.clock,
                        label: isRecorded ? '${session.duration} recording' : session.time,
                        sublabel: isRecorded ? null : session.duration,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                // Description
                if (session.description != null) ...[
                  Text(
                    session.description!,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF6B7280),
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                // Session Info Box
                if (session.sessionInfo != null) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF9FAFB),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: Text(
                      session.sessionInfo!,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF6B7280),
                        height: 1.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ] else ...[
                  const SizedBox(height: 8),
                ],
                // Action Buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF374151),
                          side: const BorderSide(color: Color(0xFFD1D5DB)),
                          minimumSize: const Size(double.infinity, 52),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Close',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: isLive
                            ? onJoinNow
                            : isRecorded
                                ? onWatch
                                : onSetReminder,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isLive || isRecorded
                              ? const Color(0xFFE60000)
                              : const Color(0xFF4A68F6),
                          foregroundColor: Colors.white,
                          minimumSize: const Size(double.infinity, 52),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          isLive
                              ? 'Join Now'
                              : isRecorded
                                  ? 'Watch'
                                  : 'Set Reminder',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Bottom safe area padding
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }

  Widget _buildInfoCard({
    required FaIconData icon,
    required String label,
    String? sublabel,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        children: [
          FaIcon(
            icon,
            color: const Color(0xFF9CA3AF),
            size: 24,
          ),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Color(0xFF374151),
            ),
          ),
          if (sublabel != null) ...[
            const SizedBox(height: 2),
            Text(
              sublabel,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF9CA3AF),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
