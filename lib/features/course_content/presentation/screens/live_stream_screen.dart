import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:jitsi_meet_flutter_sdk/jitsi_meet_flutter_sdk.dart';

import '../../../../core/network/api_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../auth/domain/student_profile.dart';
import '../../data/models/live_room.dart';

/// Live session, hosted on Jitsi.
///
/// This replaces the PeerJS/WebRTC implementation. The web dashboard moved to
/// Jitsi (`components/student/live-sessions/LiveSessionRoomClient.tsx`) and its
/// PeerJS config is now dead code, so an app student on PeerJS could never see
/// or be seen by a web student. Both clients now derive the room name the same
/// way — `learnooroom{id}` — which is what puts them in the same conference.
///
/// Students join muted with the camera off; the instructor drives the session.
class LiveStreamScreen extends StatefulWidget {
  const LiveStreamScreen({
    super.key,
    required this.liveRoom,
    this.isHost = false,
  });

  final LiveRoom liveRoom;

  /// Reserved for instructor builds; students are always viewers.
  final bool isHost;

  @override
  State<LiveStreamScreen> createState() => _LiveStreamScreenState();
}

class _LiveStreamScreenState extends State<LiveStreamScreen> {
  final _jitsi = JitsiMeet();
  final _authRepository = AuthRepository();

  bool _isJoining = true;
  bool _hasLeft = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _join());
  }

  Future<void> _join() async {
    setState(() {
      _isJoining = true;
      _error = null;
    });

    try {
      final profile = await _loadProfile();

      final options = JitsiMeetConferenceOptions(
        serverURL: ApiConstants.jitsiServerUrl,
        room: ApiConstants.jitsiRoomName(widget.liveRoom.id),
        configOverrides: {
          // Students are viewers: no mic, no camera, and no pre-join gate to
          // fumble with — same defaults the web embed uses.
          'startWithAudioMuted': !widget.isHost,
          'startWithVideoMuted': !widget.isHost,
          'prejoinPageEnabled': false,
          'disableDeepLinking': true,
          'subject': widget.liveRoom.title,
          'requireDisplayName': false,
          // Whiteboard is collaborative for host, but view-only / read-only for students
          'whiteboard': {
            'enabled': true,
            'collaborative': widget.isHost,
            'readOnly': !widget.isHost,
          },
          if (!widget.isHost)
            'toolbarButtons': [
              'raisehand',
              'chat',
              'tileview',
              'hangup',
              'microphone',
              'camera',
              'desktop',
              'fullscreen',
              'pip',
            ],
        },
        featureFlags: {
          'invite.enabled': false,
          'meeting-name.enabled': true,
          'live-streaming.enabled': false,
          'recording.enabled': false,
          'kick-out.enabled': false,
          'raise-hand.enabled': true,
          'chat.enabled': true,
          'tile-view.enabled': true,
          'pip.enabled': true,
          'toolbox.alwaysVisible': false,
          // Only host can initiate whiteboard; student cannot edit or trigger it
          'whiteboard.enabled': widget.isHost,
          // A student must not be able to hand out moderator rights.
          'security-options.enabled': false,
          'add-people.enabled': false,
          'calendar.enabled': false,
          'call-integration.enabled': false,
        },
        userInfo: JitsiMeetUserInfo(
          displayName: profile?.fullName.isNotEmpty == true
              ? profile!.fullName
              : 'Student',
          email: profile?.email,
          avatar: profile?.imageUrl,
        ),
      );

      final listener = JitsiMeetEventListener(
        conferenceJoined: (url) {
          if (!mounted) return;
          setState(() => _isJoining = false);
        },
        conferenceTerminated: (url, error) {
          _handleLeave();
        },
        readyToClose: () {
          _handleLeave();
        },
      );

      await _jitsi.join(options, listener);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isJoining = false;
        _error = e.toString();
      });
    }
  }

  Future<StudentProfile?> _loadProfile() async {
    try {
      final result = await _authRepository.getProfile();
      if (result['success'] != true) return null;
      final data = result['data'];
      if (data is! Map) return null;
      return StudentProfile.fromData(Map<String, dynamic>.from(data));
    } catch (_) {
      return null;
    }
  }

  /// Jitsi runs in its own activity; once it closes we pop back to the list.
  void _handleLeave() {
    if (_hasLeft) return;
    _hasLeft = true;
    if (!mounted) return;
    Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    if (!_hasLeft) {
      _jitsi.hangUp();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundWhite,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          widget.liveRoom.title,
          style: const TextStyle(color: AppColors.textDark, fontSize: 16),
        ),
        iconTheme: const IconThemeData(color: AppColors.textDark),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: _error != null
              ? _buildError()
              : (_isJoining ? _buildJoining() : _buildInSession()),
        ),
      ),
    );
  }

  /// Shown behind the Jitsi window once the conference is live, so returning
  /// to the app mid-session offers a way back in rather than a blank spinner.
  Widget _buildInSession() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.podcasts, size: 56, color: AppColors.primaryBlue),
        const SizedBox(height: 16),
        Text(
          'course.live_in_progress'.tr(),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.textDark,
          ),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _join,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primaryBlue,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
          ),
          child: Text('course.rejoin_live'.tr()),
        ),
      ],
    );
  }

  Widget _buildJoining() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(color: AppColors.primaryBlue),
        const SizedBox(height: 24),
        Text(
          'course.joining_live'.tr(),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.textDark,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          widget.liveRoom.instructorName,
          style: const TextStyle(color: AppColors.textGray, fontSize: 13),
        ),
      ],
    );
  }

  Widget _buildError() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.videocam_off_outlined,
            size: 56, color: AppColors.textGray),
        const SizedBox(height: 16),
        Text(
          'course.live_join_failed'.tr(),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.textDark,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _error ?? '',
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textGray, fontSize: 12),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _join,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primaryBlue,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
          ),
          child: Text('course.retry'.tr()),
        ),
      ],
    );
  }
}
