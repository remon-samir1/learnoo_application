import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/pagination_bar.dart';
import '../../data/live_room_repository.dart';
import '../../data/models/live_room.dart' as lr;
import '../widgets/live_room_widgets.dart';
import 'course_detail_screen.dart';
import 'live_session_detail_screen.dart';

/// Student live sessions list — the website's
/// `app/[locale]/student/live-sessions/page.tsx`.
///
/// `GET /v1/live-room?page=N`, narrowed to the student's faculty course tree,
/// with each card's call to action decided by the room's access state:
/// activate a private room with a code, activate the course first for an
/// "included" room, or open the session (join / watch recording / view).
class LiveSessionsScreen extends StatefulWidget {
  const LiveSessionsScreen({super.key});

  @override
  State<LiveSessionsScreen> createState() => _LiveSessionsScreenState();
}

class _LiveSessionsScreenState extends State<LiveSessionsScreen> {
  final LiveRoomRepository _repository = LiveRoomRepository();
  final LiveRoomAccessService _accessService = LiveRoomAccessService();
  final ScrollController _scrollController = ScrollController();

  List<lr.LiveRoom> _rooms = [];
  LiveRoomAccessContext _access = const LiveRoomAccessContext.empty();
  bool _isLoading = true;
  String? _errorMessage;
  int _currentPage = 1;
  int _lastPage = 1;

  @override
  void initState() {
    super.initState();
    _loadAccess();
    _loadRooms(page: 1);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadAccess({bool forceRefresh = false}) async {
    final access = await _accessService.load(forceRefresh: forceRefresh);
    if (!mounted) return;
    setState(() => _access = access);
  }

  Future<void> _loadRooms({required int page}) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final result = await _repository.getLiveRooms(page: page, perPage: null);
    if (!mounted) return;

    if (result['success'] == true) {
      final meta = result['meta'] as Map<String, dynamic>?;
      setState(() {
        _rooms = result['data'] as List<lr.LiveRoom>;
        _currentPage = (meta?['current_page'] as num?)?.toInt() ?? page;
        _lastPage = (meta?['last_page'] as num?)?.toInt() ?? 1;
        _isLoading = false;
      });
      if (_scrollController.hasClients) _scrollController.jumpTo(0);
    } else {
      setState(() {
        final message = result['message'];
        _errorMessage = message is String && message.trim().isNotEmpty
            ? message
            : 'live.load_error'.tr();
        _isLoading = false;
      });
    }
  }

  Future<void> _refresh() async {
    await Future.wait([
      _loadAccess(forceRefresh: true),
      _loadRooms(page: _currentPage),
    ]);
  }

  void _openRoom(lr.LiveRoom room) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            LiveSessionDetailScreen(roomId: room.id, initialRoom: room),
      ),
    );
  }

  Future<void> _activateRoom(lr.LiveRoom room) async {
    final activated = await LiveRoomActivationSheet.show(
      context,
      roomId: room.id,
      title: room.title.trim().isEmpty ? '—' : room.title.trim(),
    );
    if (activated && mounted) _loadRooms(page: _currentPage);
  }

  void _openCourse(lr.LiveRoom room) {
    if (room.courseIds.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CourseDetailScreen(
          courseId: room.courseIds.first,
          title: room.courseTitles.isNotEmpty ? room.courseTitles.first : '',
          thumbnail: room.courseThumbnail ?? '',
          price: '',
          description: '',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = _access.filterVisible(_rooms);

    return Scaffold(
      backgroundColor: AppColors.surface(context),
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              color: AppColors.primaryBlue,
              child: _isLoading
                  ? _buildMessage(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(
                              color: AppColors.primaryBlue),
                          const SizedBox(height: 16),
                          Text('live.loading'.tr(),
                              style: TextStyle(
                                  fontSize: 13,
                                  color: AppColors.muted(context))),
                        ],
                      ),
                    )
                  : _errorMessage != null
                      ? _buildError()
                      : visible.isEmpty
                          ? _buildEmpty()
                          : ListView.builder(
                              controller: _scrollController,
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.all(16),
                              itemCount: visible.length,
                              itemBuilder: (context, index) =>
                                  _buildCard(visible[index]),
                            ),
            ),
          ),
          if (!_isLoading && _lastPage > 1)
            PaginationBar(
              currentPage: _currentPage,
              lastPage: _lastPage,
              isLoading: _isLoading,
              onPageChanged: (page) => _loadRooms(page: page),
              primaryColor: AppColors.primaryBlue,
            ),
        ],
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
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          child: Row(
            children: [
              if (Navigator.of(context).canPop())
                IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const BackButtonIcon(),
                  color: Colors.white,
                ),
              Expanded(
                child: Text(
                  'live.title'.tr(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (Navigator.of(context).canPop()) const SizedBox(width: 48),
            ],
          ),
        ),
      ),
    );
  }

  /// A scrollable, centered message so pull-to-refresh still works.
  Widget _buildMessage({required Widget child}) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildError() {
    final isDark = AppColors.isDark(context);
    return _buildMessage(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? const Color(0x33EF4444) : const Color(0xFFFEF2F2),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? const Color(0x66EF4444) : const Color(0xFFFECACA),
          ),
        ),
        child: Column(
          children: [
            Text(
              _errorMessage ?? 'live.load_error'.tr(),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: isDark ? const Color(0xFFFCA5A5) : const Color(0xFFB91C1C),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => _loadRooms(page: _currentPage),
              child: Text('live.retry'.tr()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return _buildMessage(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.videocam_outlined,
            size: 48,
            color: AppColors.primaryBlue.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'live.no_sessions'.tr(),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: AppColors.subtext(context)),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(lr.LiveRoom room) {
    final access = _access.accessFor(room);
    final available = access == lr.LiveRoomAccess.available;
    final live = room.isLive;
    final title = room.title.trim().isEmpty ? '—' : room.title.trim();
    final instructor = room.instructorName.isEmpty
        ? 'live.unknown_instructor'.tr()
        : room.instructorName;
    final course = room.courseTitlesLabel.isEmpty
        ? 'live.no_course'.tr()
        : room.courseTitlesLabel;
    final when = LiveRoomUi.formatWhen(context, room.startedAtValue);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: live && available
              ? const Color(0xFFFECACA)
              : AppColors.border(context),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LiveRoomLeadingIcon(room: room, access: access),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        LiveStatusBadge(room: room),
                        LiveAccessChip(access: access),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$instructor · $course',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.subtext(context),
                      ),
                    ),
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
          const SizedBox(height: 14),
          _buildAction(room, access),
        ],
      ),
    );
  }

  Widget _buildAction(lr.LiveRoom room, lr.LiveRoomAccess access) {
    final isDark = AppColors.isDark(context);
    const shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(12)),
    );
    const minSize = Size.fromHeight(44);

    switch (access) {
      case lr.LiveRoomAccess.lockedPrivate:
        return ElevatedButton.icon(
          onPressed: () => _activateRoom(room),
          icon: const Icon(Icons.lock, size: 16),
          label: Text('live.activate_session'.tr()),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryBlue,
            foregroundColor: Colors.white,
            elevation: 0,
            minimumSize: minSize,
            shape: shape,
            textStyle:
                const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
        );
      case lr.LiveRoomAccess.courseNotEnrolled:
        final fg = isDark ? const Color(0xFFFDBA74) : const Color(0xFFC2410C);
        return OutlinedButton.icon(
          onPressed: room.courseIds.isEmpty ? null : () => _openCourse(room),
          icon: const Icon(Icons.lock, size: 16),
          label: Text('live.activate_course_first'.tr()),
          style: OutlinedButton.styleFrom(
            foregroundColor: fg,
            backgroundColor:
                isDark ? const Color(0x33F97316) : const Color(0xFFFFF7ED),
            side: BorderSide(
              color: isDark ? const Color(0x66F97316) : const Color(0xFFFED7AA),
            ),
            minimumSize: minSize,
            shape: shape,
            textStyle:
                const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
        );
      case lr.LiveRoomAccess.available:
        if (room.isLive) {
          return ElevatedButton.icon(
            onPressed: () => _openRoom(room),
            icon: const Icon(Icons.videocam, size: 16),
            label: Text('live.join_now'.tr()),
            style: ElevatedButton.styleFrom(
              backgroundColor: LiveRoomUi.liveRed,
              foregroundColor: Colors.white,
              elevation: 0,
              minimumSize: minSize,
              shape: shape,
              textStyle:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          );
        }
        final watch = room.isEnded && room.hasRecording;
        return OutlinedButton(
          onPressed: () => _openRoom(room),
          style: OutlinedButton.styleFrom(
            foregroundColor:
                watch ? AppColors.text(context) : AppColors.subtext(context),
            side: BorderSide(color: AppColors.border(context)),
            minimumSize: minSize,
            shape: shape,
            textStyle:
                const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          child: Text(watch ? 'live.watch_recording'.tr() : 'live.view'.tr()),
        );
    }
  }
}
