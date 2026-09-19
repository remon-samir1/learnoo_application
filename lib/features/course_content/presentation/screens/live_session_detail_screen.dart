import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/live_room_repository.dart';
import '../../data/models/live_room.dart';
import '../widgets/live_room_widgets.dart';
import 'live_stream_screen.dart';

/// Student live session page — the website's
/// `app/[locale]/student/live-sessions/[id]` (`LiveSessionRoomClient`).
///
/// Always re-fetches `GET /v1/live-room/{id}` so the status is current, then
/// shows the header card and one of: join (live), "not started yet"
/// (upcoming), recording / no recording (ended), or the description (unknown
/// status).
class LiveSessionDetailScreen extends StatefulWidget {
  const LiveSessionDetailScreen({
    super.key,
    required this.roomId,
    this.initialRoom,
  });

  final String roomId;

  /// Shown immediately while the fresh copy loads.
  final LiveRoom? initialRoom;

  @override
  State<LiveSessionDetailScreen> createState() =>
      _LiveSessionDetailScreenState();
}

class _LiveSessionDetailScreenState extends State<LiveSessionDetailScreen> {
  final _repository = LiveRoomRepository();

  LiveRoom? _room;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _room = widget.initialRoom;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final result = await _repository.getLiveRoomById(widget.roomId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (result['success'] == true && result['data'] is LiveRoom) {
        _room = result['data'] as LiveRoom;
      }
    });
  }

  Future<void> _join(LiveRoom room) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => LiveStreamScreen(liveRoom: room)),
    );
    if (mounted) _load();
  }

  Future<void> _openRecording(String url) async {
    final uri = Uri.tryParse(url);
    var opened = false;
    if (uri != null) {
      try {
        opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {
        opened = false;
      }
    }
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('live.recording_open_failed'.tr())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final room = _room;
    return Scaffold(
      backgroundColor: AppColors.surface(context),
      appBar: AppBar(
        backgroundColor: AppColors.surface(context),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.text(context),
        title: Text(
          'live.back_to_list'.tr(),
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppColors.subtext(context),
          ),
        ),
      ),
      body: room == null
          ? (_loading
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.primaryBlue),
                )
              : _buildNotFound())
          : RefreshIndicator(
              onRefresh: _load,
              color: AppColors.primaryBlue,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: LinearProgressIndicator(
                        minHeight: 2,
                        color: AppColors.primaryBlue,
                      ),
                    ),
                  _buildHeader(room),
                  const SizedBox(height: 16),
                  _buildBody(room),
                ],
              ),
            ),
    );
  }

  Widget _buildNotFound() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.videocam_off_outlined,
                size: 48, color: AppColors.muted(context)),
            const SizedBox(height: 12),
            Text(
              'live.session_not_found'.tr(),
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.subtext(context), fontSize: 14),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _load,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
                foregroundColor: Colors.white,
              ),
              child: Text('live.retry'.tr()),
            ),
          ],
        ),
      ),
    );
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: AppColors.card(context),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.border(context)),
    );
  }

  Widget _buildHeader(LiveRoom room) {
    final title =
        room.title.trim().isEmpty ? 'live.live_session'.tr() : room.title.trim();
    final instructor = room.instructorName.isEmpty
        ? 'live.unknown_instructor'.tr()
        : room.instructorName;
    final course = room.courseTitlesLabel.isEmpty
        ? 'live.course_not_available'.tr()
        : room.courseTitlesLabel;
    final thumb = room.courseThumbnail;
    final started = LiveRoomUi.formatWhen(context, room.startedAtValue);

    final String statusLabel;
    switch (room.status) {
      case SessionStatus.now:
        statusLabel = 'live.live_badge'.tr();
      case SessionStatus.upcoming:
        statusLabel = 'live.status_upcoming'.tr();
      case SessionStatus.recorded:
        statusLabel = 'live.status_ended'.tr();
      case SessionStatus.unknown:
        statusLabel =
            room.rawStatus.isEmpty ? 'live.unknown'.tr() : room.rawStatus;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (room.isLive)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: LiveRoomUi.liveRed,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'live.live_badge'.tr(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.isDark(context)
                      ? const Color(0xFF2E3344)
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    color: AppColors.subtext(context),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              height: 1.3,
              color: AppColors.text(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(instructor,
              style:
                  TextStyle(fontSize: 13, color: AppColors.subtext(context))),
          const SizedBox(height: 4),
          Text(course,
              style:
                  TextStyle(fontSize: 13, color: AppColors.subtext(context))),
          if (thumb != null) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CachedNetworkImage(
                imageUrl: thumb,
                height: 110,
                width: double.infinity,
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          ],
          if (started.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(started,
                style:
                    TextStyle(fontSize: 12, color: AppColors.muted(context))),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.people_outline,
                  size: 18,
                  color: AppColors.isDark(context)
                      ? AppColors.lightBlue
                      : AppColors.primaryBlue),
              const SizedBox(width: 6),
              Text(
                room.maxStudentsValue != null
                    ? '${room.maxStudentsValue} ${'live.max_students_label'.tr()}'
                    : '—',
                style:
                    TextStyle(fontSize: 13, color: AppColors.subtext(context)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBody(LiveRoom room) {
    switch (room.status) {
      case SessionStatus.now:
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: _cardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: Color(0xFF10B981),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'live.join_description'.tr(),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text(context),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => _join(room),
                icon: const Icon(Icons.videocam, size: 18),
                label: Text('live.join_now'.tr()),
                style: ElevatedButton.styleFrom(
                  backgroundColor: LiveRoomUi.liveRed,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  textStyle: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        );
      case SessionStatus.upcoming:
        final started = LiveRoomUi.formatWhen(context, room.startedAtValue);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          decoration: _cardDecoration(),
          child: Column(
            children: [
              Icon(Icons.sensors,
                  size: 48,
                  color: AppColors.isDark(context)
                      ? AppColors.lightBlue
                      : AppColors.primaryBlue),
              const SizedBox(height: 14),
              Text(
                'live.upcoming_message'.tr(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.text(context),
                ),
              ),
              if (started.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(started,
                    style: TextStyle(
                        fontSize: 12, color: AppColors.subtext(context))),
              ],
            ],
          ),
        );
      case SessionStatus.recorded:
        final url = room.recordingUrl;
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: _cardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'live.session_ended'.tr(),
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text(context),
                ),
              ),
              const SizedBox(height: 14),
              if (url != null)
                ElevatedButton(
                  onPressed: () => _openRecording(url),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text('live.watch_recording'.tr()),
                )
              else
                Text(
                  'live.ended_no_recording'.tr(),
                  style: TextStyle(
                      fontSize: 14, color: AppColors.subtext(context)),
                ),
            ],
          ),
        );
      case SessionStatus.unknown:
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: _cardDecoration(),
          child: Text(
            room.description.trim().isEmpty
                ? 'live.not_available'.tr()
                : room.description.trim(),
            style: TextStyle(fontSize: 14, color: AppColors.subtext(context)),
          ),
        );
    }
  }
}
