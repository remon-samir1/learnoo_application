import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../auth/presentation/screens/login_screen.dart';
import '../../data/parent_repository.dart';
import 'link_student_screen.dart';

/// Parent home — the app's counterpart to the web's `/parent/dashboard`.
///
/// Same data as the web: the linked children in a picker, the four quick
/// overview tiles, recent activity and alerts for the selected child. The
/// payload readers below accept the same alternative key names the web page
/// falls back through, because the API is inconsistent across those endpoints.
class ParentDashboardScreen extends StatefulWidget {
  const ParentDashboardScreen({super.key});

  @override
  State<ParentDashboardScreen> createState() => _ParentDashboardScreenState();
}

class _ParentDashboardScreenState extends State<ParentDashboardScreen> {
  final _parentRepository = ParentRepository();
  final _authRepository = AuthRepository();

  List<_LinkedChild> _children = const [];
  String? _selectedId;

  Map<String, dynamic> _overview = const {};
  List<dynamic> _activity = const [];
  List<dynamic> _alerts = const [];

  bool _loadingChildren = true;
  bool _loadingDetail = false;
  String? _error;
  String _parentName = '';

  @override
  void initState() {
    super.initState();
    _loadChildren();
    _loadParentName();
  }

  Future<void> _loadParentName() async {
    final result = await _authRepository.getProfile();
    if (!mounted || result['success'] != true) return;
    final data = result['data'];
    final attrs = data is Map ? data['attributes'] : null;
    if (attrs is Map) {
      setState(() => _parentName = (attrs['first_name'] ?? '').toString());
    }
  }

  Future<void> _loadChildren() async {
    setState(() {
      _loadingChildren = true;
      _error = null;
    });

    final result = await _parentRepository.linkedStudents();

    if (!mounted) return;

    if (result['success'] != true) {
      setState(() {
        _loadingChildren = false;
        _error = result['message']?.toString();
      });
      return;
    }

    final children = ((result['data'] as List?) ?? const [])
        .map(_LinkedChild.fromJson)
        .where((c) => c.id.isNotEmpty)
        .toList();

    setState(() {
      _loadingChildren = false;
      _children = children;
      _selectedId = children.isEmpty ? null : children.first.id;
    });

    if (_selectedId != null) {
      await _loadDetail(_selectedId!);
    }
  }

  Future<void> _loadDetail(String studentId) async {
    setState(() {
      _loadingDetail = true;
      _error = null;
    });

    final dashboard = await _parentRepository.studentDashboard(studentId);
    final activity = await _parentRepository.studentActivity(studentId);
    final alerts = await _parentRepository.studentAlerts(studentId);

    if (!mounted) return;

    final data = (dashboard['data'] as Map?) ?? const {};
    final overview = data['quick_overview'] ?? data['overview'];

    setState(() {
      _loadingDetail = false;
      _overview = overview is Map ? Map<String, dynamic>.from(overview) : const {};
      _activity = (data['recent_activity'] as List?) ??
          (activity['data'] as List?) ??
          const [];
      _alerts = (data['alerts'] as List?) ?? (alerts['data'] as List?) ?? const [];
      if (dashboard['success'] != true) {
        _error = dashboard['message']?.toString();
      }
    });
  }

  /// First non-empty value among [keys], following the same fallback chain the
  /// web's `StatCard` props walk (`overview.x.value`, then the flat aliases).
  String _stat(String nested, List<String> flat) {
    final node = _overview[nested];
    if (node is Map && node['value'] != null) return node['value'].toString();
    for (final key in flat) {
      final value = _overview[key];
      if (value != null && value.toString().isNotEmpty) return value.toString();
    }
    return '—';
  }

  Future<void> _logout() async {
    await _authRepository.logout();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          _parentName.isEmpty
              ? 'parent.dashboard_title'.tr()
              : 'parent.welcome'.tr(args: [_parentName]),
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Color(0xFF0F172A),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'parent.add_child'.tr(),
            icon: const Icon(Icons.person_add_alt, color: Color(0xFF334155)),
            onPressed: () async {
              final added = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (_) => const LinkStudentScreen(isOnboarding: false),
                ),
              );
              if (added == true) _loadChildren();
            },
          ),
          IconButton(
            tooltip: 'profile.logout'.tr(),
            icon: const Icon(Icons.logout, color: Color(0xFF334155)),
            onPressed: _logout,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadChildren,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_loadingChildren)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_children.isEmpty)
              _emptyState()
            else ...[
              _childPicker(),
              const SizedBox(height: 16),
              if (_error != null) _errorBanner(),
              if (_loadingDetail)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...[
                _statsGrid(),
                const SizedBox(height: 16),
                _section(
                  title: 'parent.recent_activity'.tr(),
                  emptyText: 'parent.no_recent_activity'.tr(),
                  items: _activity,
                  builder: (item) => _activityTile(item),
                ),
                const SizedBox(height: 16),
                _section(
                  title: 'parent.alerts'.tr(),
                  emptyText: 'parent.no_alerts'.tr(),
                  items: _alerts,
                  builder: (item) => _alertTile(item),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 16),
      child: Column(
        children: [
          const Icon(Icons.family_restroom, size: 56, color: Color(0xFF94A3B8)),
          const SizedBox(height: 16),
          Text(
            'parent.no_children'.tr(),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15, color: Color(0xFF475569)),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryBlue,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.add),
            label: Text('parent.add_child'.tr()),
            onPressed: () async {
              final added = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (_) => const LinkStudentScreen(isOnboarding: false),
                ),
              );
              if (added == true) _loadChildren();
            },
          ),
        ],
      ),
    );
  }

  Widget _errorBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _error!,
              style: const TextStyle(color: Color(0xFFB91C1C), fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: () {
              final id = _selectedId;
              if (id != null) _loadDetail(id);
            },
            child: Text('profile.retry'.tr()),
          ),
        ],
      ),
    );
  }

  Widget _childPicker() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF262A36) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF383E52) : const Color(0xFFE2E8F0),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: _selectedId,
          dropdownColor: isDark ? const Color(0xFF1E212B) : Colors.white,
          iconEnabledColor: isDark ? const Color(0xFFCBD5E1) : Colors.grey[700],
          items: _children
              .map(
                (child) => DropdownMenuItem(
                  value: child.id,
                  child: Text(
                    child.label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A),
                    ),
                  ),
                ),
              )
              .toList(),
          onChanged: (value) {
            if (value == null) return;
            setState(() => _selectedId = value);
            _loadDetail(value);
          },
        ),
      ),
    );
  }

  Widget _statsGrid() {
    final tiles = <Widget>[
      _statCard(
        'parent.attendance'.tr(),
        _stat('attendance', const ['attendance_rate', 'attendance']),
        Icons.schedule,
        const Color(0xFFE0E7FF),
        const Color(0xFF4F46E5),
      ),
      _statCard(
        'parent.course_progress'.tr(),
        _stat('progress', const ['course_progress', 'progress']),
        Icons.menu_book_outlined,
        const Color(0xFFD1FAE5),
        const Color(0xFF059669),
      ),
      _statCard(
        'parent.exam_average'.tr(),
        _stat('exam_avg', const ['exam_average', 'average_score']),
        Icons.emoji_events_outlined,
        const Color(0xFFFEF3C7),
        const Color(0xFFD97706),
      ),
      _statCard(
        'parent.engagement'.tr(),
        _stat('engagement', const ['engagement_level', 'engagement']),
        Icons.trending_up,
        const Color(0xFFEDE9FE),
        const Color(0xFF7C3AED),
      ),
    ];

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.35,
      children: tiles,
    );
  }

  Widget _statCard(
    String title,
    String value,
    IconData icon,
    Color background,
    Color foreground,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 18, color: foreground),
          ),
          const Spacer(),
          Text(
            title,
            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0F172A),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section({
    required String title,
    required String emptyText,
    required List<dynamic> items,
    required Widget Function(Map<String, dynamic>) builder,
  }) {
    final rows = items
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .take(5)
        .toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 12),
          if (rows.isEmpty)
            Text(
              emptyText,
              style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
            )
          else
            ...rows.map(builder),
        ],
      ),
    );
  }

  Widget _activityTile(Map<String, dynamic> item) {
    final title = (item['title'] ?? item['name'] ?? item['subject'] ?? '').toString();
    final time = (item['time'] ?? item['date'] ?? '').toString();
    final description =
        (item['description'] ?? item['detail'] ?? item['summary'] ?? '').toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle_outline,
                  size: 18, color: Color(0xFF059669)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
              Text(
                time,
                style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
              ),
            ],
          ),
          if (description.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              description,
              style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _alertTile(Map<String, dynamic> item) {
    final title = (item['title'] ?? item['subject'] ?? '').toString();
    final message = (item['message'] ?? item['description'] ?? '').toString();
    final category = (item['category'] ?? item['type'] ?? '').toString();
    final date = (item['date'] ?? item['time'] ?? '').toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF0F172A),
            ),
          ),
          if (message.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              message,
              style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                category,
                style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
              ),
              Text(
                date,
                style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One row of `GET /v1/parent/students`, flattened out of the JSON:API-ish
/// envelope the endpoint uses.
class _LinkedChild {
  const _LinkedChild({required this.id, required this.label});

  final String id;
  final String label;

  factory _LinkedChild.fromJson(dynamic raw) {
    if (raw is! Map) return const _LinkedChild(id: '', label: '');
    final attrs = raw['attributes'] is Map ? raw['attributes'] as Map : raw;

    final id = (raw['id'] ?? attrs['id'] ?? '').toString();

    final fullName = (attrs['full_name'] ??
            '${attrs['first_name'] ?? ''} ${attrs['last_name'] ?? ''}'.trim())
        .toString()
        .trim();
    final name = fullName.isNotEmpty
        ? fullName
        : (attrs['name'] ?? attrs['label'] ?? '').toString();

    final relationship = (attrs['grade'] ?? attrs['relationship'] ?? '').toString();

    return _LinkedChild(
      id: id,
      label: relationship.isEmpty ? name : '$name ($relationship)',
    );
  }
}
