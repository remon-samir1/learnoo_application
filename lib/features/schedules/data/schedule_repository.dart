import '../../../core/network/api_client.dart';
import '../../../core/network/api_constants.dart';
import '../../../core/utils/media_url.dart';

class ScheduleDocument {
  const ScheduleDocument({
    required this.id,
    required this.name,
    required this.path,
    required this.extension,
  });
  final String id;
  final String name;
  final String path;
  final String extension;

  factory ScheduleDocument.fromJson(Map<String, dynamic> json) {
    final attrs = json['attributes'] as Map? ?? const {};
    return ScheduleDocument(
      id: '${json['id'] ?? ''}',
      name: '${attrs['name'] ?? ''}',
      path: resolveMediaUrl(attrs['path']) ?? '',
      extension: '${attrs['extension'] ?? ''}',
    );
  }
}

class ScheduleEntry {
  const ScheduleEntry({
    required this.id,
    required this.title,
    this.start,
    this.end,
    required this.documents,
  });
  final String id;
  final String title;
  final DateTime? start;
  final DateTime? end;
  final List<ScheduleDocument> documents;

  factory ScheduleEntry.fromJson(Map<String, dynamic> json) => ScheduleEntry(
    id: '${json['id'] ?? ''}',
    title: '${json['title'] ?? ''}',
    start: DateTime.tryParse('${json['start'] ?? ''}'),
    end: DateTime.tryParse('${json['end'] ?? ''}'),
    documents: (json['documents'] as List? ?? const [])
        .whereType<Map>()
        .map((doc) => ScheduleDocument.fromJson(Map<String, dynamic>.from(doc)))
        .toList(),
  );

  bool matches(String search) =>
      '$title ${documents.map((doc) => doc.name).join(' ')}'
          .toLowerCase()
          .contains(search.trim().toLowerCase());
}

class ScheduleRepository {
  Future<List<ScheduleEntry>> list() async {
    final payload = unwrapMap(await ApiClient().get(ApiConstants.timetable));
    // The student website filters only by kind; access is scoped by the API.
    return (payload?['entries'] as List? ?? const [])
        .whereType<Map>()
        .where((entry) => entry['kind'] == 'course')
        .map(
          (entry) => ScheduleEntry.fromJson(Map<String, dynamic>.from(entry)),
        )
        .toList();
  }
}
