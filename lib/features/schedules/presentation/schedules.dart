import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../../../core/widgets/image_preview_screen.dart';
import '../../course_content/presentation/screens/pdf_viewer_screen.dart';
import '../data/schedule_repository.dart';

class ScheduleCard extends StatelessWidget {
  const ScheduleCard({super.key, required this.entry});
  final ScheduleEntry entry;

  @override
  Widget build(BuildContext context) {
    String date(DateTime value) => DateFormat.yMd(
      context.locale.toString(),
    ).add_jm().format(value.toLocal());
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              entry.title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              '${entry.start == null ? 'schedules.no_date'.tr() : date(entry.start!)}${entry.end == null ? '' : ' — ${date(entry.end!)}'}',
            ),
            for (final document in entry.documents)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  document.extension.toLowerCase() == 'pdf'
                      ? Icons.picture_as_pdf_outlined
                      : Icons.image_outlined,
                ),
                title: Text(document.name),
                trailing: const Icon(Icons.open_in_new, size: 20),
                enabled: document.path.isNotEmpty,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => document.extension.toLowerCase() == 'pdf'
                        ? PdfViewerScreen(
                            pdfUrl: document.path,
                            title: document.name,
                          )
                        : ImagePreviewScreen(imageUrl: document.path),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Shared student-only list for the home preview and the dedicated page.
class ScheduleList extends StatefulWidget {
  const ScheduleList({super.key, this.limit, this.search = ''});
  final int? limit;
  final String search;
  @override
  State<ScheduleList> createState() => ScheduleListState();
}

class ScheduleListState extends State<ScheduleList> {
  List<ScheduleEntry> _entries = const [];
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final entries = await ScheduleRepository().list();
      if (mounted) {
        setState(() {
          _entries = entries;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = true;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error) {
      return Column(
        children: [
          Text('schedules.load_error'.tr()),
          TextButton(onPressed: refresh, child: Text('schedules.retry'.tr())),
        ],
      );
    }
    final matches = _entries.where((entry) => entry.matches(widget.search));
    final entries = widget.limit == null
        ? matches
        : matches.take(widget.limit!);
    if (entries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text('schedules.empty'.tr()),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: entries.map((entry) => ScheduleCard(entry: entry)).toList(),
    );
  }
}

class SchedulesScreen extends StatefulWidget {
  const SchedulesScreen({super.key});
  @override
  State<SchedulesScreen> createState() => _SchedulesScreenState();
}

class _SchedulesScreenState extends State<SchedulesScreen> {
  final _listKey = GlobalKey<ScheduleListState>();
  String _search = '';
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('schedules.title'.tr())),
    body: RefreshIndicator(
      onRefresh: () async {
        await _listKey.currentState?.refresh();
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              decoration: InputDecoration(
                hintText: 'schedules.search'.tr(),
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
              ),
              onChanged: (value) => setState(() => _search = value),
            ),
            const SizedBox(height: 20),
            ScheduleList(key: _listKey, search: _search),
          ],
        ),
      ),
    ),
  );
}
