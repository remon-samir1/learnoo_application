import 'dart:async';

import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart' as intl;

import '../../../../core/theme/app_colors.dart';
import '../../data/live_room_repository.dart';
import '../../data/models/live_room.dart';

/// Shared pieces of the student live-session UI, matching the website's
/// `app/[locale]/student/live-sessions` pages.
class LiveRoomUi {
  LiveRoomUi._();

  static const Color liveRed = Color(0xFFDC2626);

  /// `toLocaleString(locale, {dateStyle: "medium", timeStyle: "short"})`,
  /// in the device time zone.
  static String formatWhen(BuildContext context, DateTime? value) {
    if (value == null) return '';
    final local = value.toLocal();
    final locale = context.locale.languageCode;
    try {
      return intl.DateFormat.yMMMd(locale).add_jm().format(local);
    } catch (_) {
      return intl.DateFormat('yyyy-MM-dd HH:mm').format(local);
    }
  }
}

/// Status pill: "Live Now" / "Upcoming" / "Ended" / raw status.
class LiveStatusBadge extends StatelessWidget {
  const LiveStatusBadge({super.key, required this.room});

  final LiveRoom room;

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark(context);
    switch (room.status) {
      case SessionStatus.now:
        return _pill(
          bg: LiveRoomUi.liveRed,
          fg: Colors.white,
          label: 'live.status_live_now'.tr(),
          leading: Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
        );
      case SessionStatus.upcoming:
        return _pill(
          bg: isDark ? const Color(0xFF1E3A8A) : const Color(0xFFDBEAFE),
          fg: isDark ? const Color(0xFFBFDBFE) : const Color(0xFF1D4ED8),
          label: 'live.status_upcoming'.tr(),
          leading: Icon(
            Icons.schedule,
            size: 11,
            color: isDark ? const Color(0xFFBFDBFE) : const Color(0xFF1D4ED8),
          ),
        );
      case SessionStatus.recorded:
        return _pill(
          bg: isDark ? const Color(0xFF2E3344) : const Color(0xFFF1F5F9),
          fg: AppColors.subtext(context),
          label: 'live.status_ended'.tr(),
          leading: Icon(
            Icons.check_circle_outline,
            size: 11,
            color: AppColors.subtext(context),
          ),
        );
      case SessionStatus.unknown:
        return _pill(
          bg: isDark ? const Color(0xFF2E3344) : const Color(0xFFF1F5F9),
          fg: AppColors.subtext(context),
          label: room.rawStatus.isEmpty ? '—' : room.rawStatus,
        );
    }
  }

  Widget _pill({
    required Color bg,
    required Color fg,
    required String label,
    Widget? leading,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[leading, const SizedBox(width: 6)],
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Small amber/orange lock chip shown next to the status on locked rooms.
class LiveAccessChip extends StatelessWidget {
  const LiveAccessChip({super.key, required this.access});

  final LiveRoomAccess access;

  @override
  Widget build(BuildContext context) {
    if (access == LiveRoomAccess.available) return const SizedBox.shrink();
    final isDark = AppColors.isDark(context);
    final isPrivate = access == LiveRoomAccess.lockedPrivate;
    final fg = isPrivate
        ? (isDark ? const Color(0xFFFCD34D) : const Color(0xFFB45309))
        : (isDark ? const Color(0xFFFDBA74) : const Color(0xFFC2410C));
    final bg = isPrivate
        ? (isDark ? const Color(0x33F59E0B) : const Color(0xFFFFFBEB))
        : (isDark ? const Color(0x33F97316) : const Color(0xFFFFF7ED));
    final border = isPrivate
        ? (isDark ? const Color(0x66F59E0B) : const Color(0xFFFDE68A))
        : (isDark ? const Color(0x66F97316) : const Color(0xFFFED7AA));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock, size: 10, color: fg),
          const SizedBox(width: 4),
          Text(
            isPrivate
                ? 'live.private_session'.tr()
                : 'live.activate_course_first'.tr(),
            style: TextStyle(
              color: fg,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Leading square icon: lock / radio / check / calendar.
class LiveRoomLeadingIcon extends StatelessWidget {
  const LiveRoomLeadingIcon({
    super.key,
    required this.room,
    this.access = LiveRoomAccess.available,
  });

  final LiveRoom room;
  final LiveRoomAccess access;

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark(context);
    final neutralBg = isDark
        ? const Color(0xFF2E3344)
        : const Color(0xFFF1F5F9);
    Color bg;
    Widget icon;
    if (access != LiveRoomAccess.available) {
      bg = neutralBg;
      icon = const Icon(Icons.lock, size: 22, color: Color(0xFF94A3B8));
    } else if (room.isLive) {
      bg = LiveRoomUi.liveRed;
      icon = const Icon(Icons.sensors, size: 22, color: Colors.white);
    } else if (room.isEnded) {
      bg = neutralBg;
      icon = const Icon(
        Icons.check_circle_outline,
        size: 22,
        color: Color(0xFF94A3B8),
      );
    } else {
      bg = isDark ? const Color(0xFF26305E) : const Color(0xFFEEF2FF);
      icon = Icon(
        Icons.calendar_month,
        size: 22,
        color: isDark ? AppColors.lightBlue : AppColors.primaryBlue,
      );
    }
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(child: icon),
    );
  }
}

/// A live stopwatch/countdown banner displaying time remaining until a live session starts,
/// or elapsed time if the live session is currently ongoing.
class LiveRoomTimerBanner extends StatefulWidget {
  const LiveRoomTimerBanner({
    super.key,
    required this.startTime,
    required this.isLive,
    this.isEnded = false,
    this.onReached,
  });

  final DateTime startTime;
  final bool isLive;
  final bool isEnded;
  final VoidCallback? onReached;

  @override
  State<LiveRoomTimerBanner> createState() => _LiveRoomTimerBannerState();
}

class _LiveRoomTimerBannerState extends State<LiveRoomTimerBanner> {
  Timer? _timer;
  bool _reached = false;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void didUpdateWidget(covariant LiveRoomTimerBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.startTime != widget.startTime ||
        oldWidget.isLive != widget.isLive ||
        oldWidget.isEnded != widget.isEnded) {
      _startTimer();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = null;
    if (widget.isEnded) return;

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final nowUtc = DateTime.now().toUtc();
      final isUpcoming = widget.startTime.isAfter(nowUtc);
      if (!isUpcoming && !_reached) {
        _reached = true;
        widget.onReached?.call();
      }
      setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isEnded) return const SizedBox.shrink();

    final nowUtc = DateTime.now().toUtc();
    final difference = widget.startTime.difference(nowUtc);
    final isUpcoming = difference.inSeconds > 0;
    final isDark = AppColors.isDark(context);

    String pad(int n) => n.toString().padLeft(2, '0');
    final String timeStr;
    final String label;
    final Color bannerBg;
    final Color bannerBorder;
    final Color accentColor;
    final Color clockBg;
    final IconData icon;

    if (isUpcoming) {
      final days = difference.inDays;
      final hours = difference.inHours % 24;
      final minutes = difference.inMinutes % 60;
      final seconds = difference.inSeconds % 60;

      final clock = '${pad(hours)}:${pad(minutes)}:${pad(seconds)}';
      final dayLabel = 'live.day_short'.tr();
      timeStr = days > 0 ? '$days $dayLabel $clock' : clock;
      label = 'live.starts_in'.tr();
      icon = Icons.timer_outlined;

      if (isDark) {
        bannerBg = const Color(0xFF1E2648);
        bannerBorder = const Color(0xFF2E3A6E);
        accentColor = const Color(0xFF93C5FD);
        clockBg = const Color(0xFF141A33);
      } else {
        bannerBg = const Color(0xFFF0F4FF);
        bannerBorder = const Color(0xFFDBEAFE);
        accentColor = const Color(0xFF2563EB);
        clockBg = Colors.white;
      }
    } else {
      // Live stopwatch counting elapsed time from start
      final elapsed = nowUtc.difference(widget.startTime);
      final hours = elapsed.inHours;
      final minutes = elapsed.inMinutes % 60;
      final seconds = elapsed.inSeconds % 60;

      timeStr = hours > 0
          ? '${pad(hours)}:${pad(minutes)}:${pad(seconds)}'
          : '${pad(minutes)}:${pad(seconds)}';
      label = 'live.live_now'.tr();
      icon = Icons.sensors;

      if (isDark) {
        bannerBg = const Color(0xFF331616);
        bannerBorder = const Color(0xFF5C2222);
        accentColor = const Color(0xFFF87171);
        clockBg = const Color(0xFF241010);
      } else {
        bannerBg = const Color(0xFFFEF2F2);
        bannerBorder = const Color(0xFFFECACA);
        accentColor = const Color(0xFFDC2626);
        clockBg = Colors.white;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bannerBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: bannerBorder),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: accentColor),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: accentColor,
                ),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: clockBg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: bannerBorder),
              boxShadow: isDark
                  ? null
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 3,
                        offset: const Offset(0, 1),
                      ),
                    ],
            ),
            child: Text(
              timeStr,
              textDirection: TextDirection.ltr,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: accentColor,
                letterSpacing: 0.6,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A live-session card as shown in the website's course details "Live" tab:
/// status, title, instructor, start time, stopwatch timer, and "Join Now" (live) or "View".
class LiveRoomCourseCard extends StatefulWidget {
  const LiveRoomCourseCard({
    super.key,
    required this.room,
    required this.onOpen,
    required this.access,
  });

  final LiveRoom room;
  final LiveRoomAccess access;
  final VoidCallback onOpen;

  @override
  State<LiveRoomCourseCard> createState() => _LiveRoomCourseCardState();
}

class _LiveRoomCourseCardState extends State<LiveRoomCourseCard> {
  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    final start = room.startedAtValue;
    final nowUtc = DateTime.now().toUtc();
    final left = start?.difference(nowUtc);
    final isLiveByTime =
        start != null && left != null && left.inSeconds <= 0 && !room.isEnded;
    final isLive = room.isLive || isLiveByTime;
    final when = LiveRoomUi.formatWhen(context, start);
    final title = room.title.trim().isEmpty ? '—' : room.title.trim();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isLive ? const Color(0xFFFECACA) : AppColors.border(context),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LiveRoomLeadingIcon(room: room, access: widget.access),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (room.status != SessionStatus.unknown)
                      LiveStatusBadge(room: room),
                    LiveAccessChip(access: widget.access),
                    const SizedBox(height: 6),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text(context),
                      ),
                    ),
                    if (room.instructorName.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        room.instructorName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.subtext(context),
                        ),
                      ),
                    ],
                    if (when.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        when,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.muted(context),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (start != null && !room.isEnded) ...[
            const SizedBox(height: 12),
            LiveRoomTimerBanner(
              startTime: start,
              isLive: isLive,
              isEnded: room.isEnded,
              onReached: () {
                if (mounted) setState(() {});
              },
            ),
          ],
          const SizedBox(height: 14),
          widget.access != LiveRoomAccess.available
              ? LiveRoomLockedAction(
                  access: widget.access,
                  onPressed: widget.onOpen,
                )
              : isLive
              ? ElevatedButton.icon(
                  onPressed: widget.onOpen,
                  icon: const Icon(Icons.sensors, size: 16),
                  label: Text('live.join_now'.tr()),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: LiveRoomUi.liveRed,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    minimumSize: const Size.fromHeight(44),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              : OutlinedButton(
                  onPressed: widget.onOpen,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.subtext(context),
                    side: BorderSide(color: AppColors.border(context)),
                    minimumSize: const Size.fromHeight(44),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: Text('live.view'.tr()),
                ),
        ],
      ),
    );
  }
}

/// Empty state for a course's Live tab.
class LiveRoomsEmptyState extends StatelessWidget {
  const LiveRoomsEmptyState({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF26305E)
                    : const Color(0xFFEEF2FF),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.sensors,
                size: 28,
                color: isDark ? AppColors.lightBlue : const Color(0xFF2D43D1),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.subtext(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Code activation for a private live room — the website's
/// `StudentCourseActivationModal` with `activationItemType="live_room"`.
class LiveRoomActivationSheet extends StatefulWidget {
  const LiveRoomActivationSheet({
    super.key,
    required this.roomId,
    required this.title,
  });

  final String roomId;
  final String title;

  /// Returns `true` when the room was activated.
  static Future<bool> show(
    BuildContext context, {
    required String roomId,
    required String title,
  }) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => LiveRoomActivationSheet(roomId: roomId, title: title),
    );
    return result == true;
  }

  @override
  State<LiveRoomActivationSheet> createState() =>
      _LiveRoomActivationSheetState();
}

class _LiveRoomActivationSheetState extends State<LiveRoomActivationSheet> {
  final _controller = TextEditingController();
  final _repository = LiveRoomRepository();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _controller.text.trim();
    if (code.isEmpty) {
      setState(() => _error = 'live.enter_code'.tr());
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });

    final result = await _repository.activateLiveRoom(
      roomId: widget.roomId,
      code: code,
    );
    if (!mounted) return;

    if (result['success'] == true) {
      final messenger = ScaffoldMessenger.maybeOf(context);
      Navigator.of(context).pop(true);
      messenger?.showSnackBar(
        SnackBar(
          content: Text('live.activation_success'.tr()),
          backgroundColor: const Color(0xFF10B981),
        ),
      );
      return;
    }

    final message = result['invalidId'] == true
        ? 'live.activation_invalid_id'.tr()
        : ((result['message'] as String?)?.trim().isNotEmpty == true
              ? result['message'] as String
              : 'live.activation_failed'.tr());
    setState(() {
      _submitting = false;
      _error = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + keyboard),
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.divider(context),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                const Icon(
                  Icons.power_settings_new,
                  size: 18,
                  color: AppColors.primaryBlue,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'live.activate_session'.tr(),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text(context),
                    ),
                  ),
                ),
              ],
            ),
            if (widget.title.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                widget.title.trim(),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.subtext(context),
                ),
              ),
            ],
            const SizedBox(height: 6),
            Text(
              'live.activation_description'.tr(),
              style: TextStyle(fontSize: 12, color: AppColors.muted(context)),
            ),
            const SizedBox(height: 18),
            Text(
              'live.activation_code'.tr(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.subtext(context),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              enabled: !_submitting,
              autofocus: true,
              autocorrect: false,
              enableSuggestions: false,
              style: TextStyle(color: AppColors.text(context), fontSize: 15),
              decoration: InputDecoration(
                hintText: 'live.activation_code_hint'.tr(),
                hintStyle: TextStyle(color: AppColors.muted(context)),
                filled: true,
                fillColor: AppColors.input(context),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.border(context)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.border(context)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: AppColors.primaryBlue,
                    width: 2,
                  ),
                ),
              ),
              onSubmitted: (_) => _submit(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: const TextStyle(
                  color: Color(0xFFEF4444),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _submitting
                        ? null
                        : () => Navigator.of(context).pop(false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.subtext(context),
                      side: BorderSide(color: AppColors.border(context)),
                      minimumSize: const Size.fromHeight(46),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text('live.cancel'.tr()),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _submitting ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryBlue,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      minimumSize: const Size.fromHeight(46),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _submitting
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Flexible(child: Text('live.activating'.tr())),
                            ],
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const FaIcon(FontAwesomeIcons.unlock, size: 13),
                              const SizedBox(width: 8),
                              Flexible(child: Text('live.activate'.tr())),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Home "Upcoming Live Classes" card — the website's
/// `src/components/student/home/LiveSessions.tsx`: title, instructor, start
/// (weekday + time), course, and a button that counts down to `started_at`
/// and turns into "Live Now (Join)" once that time has passed.
class LiveHomeCard extends StatefulWidget {
  const LiveHomeCard({
    super.key,
    required this.room,
    required this.onOpen,
    required this.access,
  });

  final LiveRoom room;
  final LiveRoomAccess access;
  final VoidCallback onOpen;

  @override
  State<LiveHomeCard> createState() => _LiveHomeCardState();
}

class _LiveHomeCardState extends State<LiveHomeCard> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final start = widget.room.startedAtValue;
      if (start == null || !DateTime.now().toUtc().isBefore(start)) {
        _timer?.cancel();
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _countdown(Duration left) {
    String pad(int n) => n.toString().padLeft(2, '0');
    final days = left.inDays;
    final hours = left.inHours % 24;
    final minutes = left.inMinutes % 60;
    final seconds = left.inSeconds % 60;
    final hms = '${pad(hours)}:${pad(minutes)}:${pad(seconds)}';
    if (days <= 0) return hms;
    return '$days ${'live.day_short'.tr()} $hms';
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    final title = room.title.trim().isEmpty
        ? 'live.home_fallback_title'.tr()
        : room.title.trim();
    final instructor = room.instructorName.isEmpty
        ? 'live.unknown_instructor'.tr()
        : room.instructorName;
    final course = room.courseTitlesLabel.isEmpty
        ? 'live.course_not_available'.tr()
        : room.courseTitlesLabel;

    final start = room.startedAtValue;
    String when;
    if (start == null) {
      when = 'live.time_not_available'.tr();
    } else {
      try {
        when = intl.DateFormat(
          'EEEE',
          context.locale.languageCode,
        ).add_jm().format(start.toLocal());
      } catch (_) {
        when = LiveRoomUi.formatWhen(context, start);
      }
    }

    final left = start?.difference(DateTime.now().toUtc());
    final isLive = start != null && (left == null || left.inSeconds <= 0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            onTap: widget.onOpen,
            child: Text(
              title,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.text(context),
              ),
            ),
          ),
          if (widget.access != LiveRoomAccess.available)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: LiveAccessChip(access: widget.access),
            ),
          const SizedBox(height: 10),
          _row(context, Icons.people_outline, instructor),
          const SizedBox(height: 6),
          _row(context, Icons.calendar_month_outlined, when),
          const SizedBox(height: 6),
          Text(
            course,
            style: TextStyle(fontSize: 12, color: AppColors.muted(context)),
          ),
          const SizedBox(height: 14),
          if (widget.access != LiveRoomAccess.available)
            LiveRoomLockedAction(
              access: widget.access,
              onPressed: widget.onOpen,
            )
          else
            ElevatedButton(
              onPressed: widget.onOpen,
              style: ElevatedButton.styleFrom(
                backgroundColor: isLive
                    ? const Color(0xFF059669)
                    : AppColors.primaryBlue,
                foregroundColor: Colors.white,
                elevation: 0,
                minimumSize: const Size.fromHeight(44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(isLive ? Icons.sensors : Icons.timer_outlined, size: 16),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      isLive
                          ? 'live.home_live_join'.tr()
                          : _countdown(left ?? Duration.zero),
                      textDirection: isLive ? null : TextDirection.ltr,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        fontFeatures: isLive
                            ? null
                            : const [FontFeature.tabularFigures()],
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

  Widget _row(BuildContext context, IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.subtext(context)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 13, color: AppColors.subtext(context)),
          ),
        ),
      ],
    );
  }
}

class LiveRoomLockedAction extends StatelessWidget {
  const LiveRoomLockedAction({
    super.key,
    required this.access,
    required this.onPressed,
  });
  final LiveRoomAccess access;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => ElevatedButton.icon(
    onPressed: onPressed,
    icon: const Icon(Icons.lock, size: 16),
    label: Text(
      (access == LiveRoomAccess.lockedPrivate
              ? 'live.activate_session'
              : 'live.activate_course_first')
          .tr(),
    ),
    style: ElevatedButton.styleFrom(
      backgroundColor: AppColors.primaryBlue,
      foregroundColor: Colors.white,
      minimumSize: const Size.fromHeight(44),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}
