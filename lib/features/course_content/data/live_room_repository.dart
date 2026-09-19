import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_constants.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/services/student_scope.dart';
import '../../../core/utils/coerce.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/domain/student_profile.dart';
import 'models/live_room.dart';

class LiveRoomRepository {
  final _storage = const FlutterSecureStorage();

  Future<String?> getToken() async {
    return await _storage.read(key: 'auth_token');
  }

  /// `GET /v1/live-room`.
  ///
  /// The website's student list sends only `page`; pass `perPage: null` to do
  /// the same and let the backend page size apply.
  Future<Map<String, dynamic>> getLiveRooms({
    int page = 1,
    int? perPage = 500,
    String? search,
    int? courseId,
  }) async {
    final token = await getToken();
    if (token == null) return {'success': false, 'message': 'No token found'};

    final queryParams = <String, String>{
      'page': page.toString(),
      if (perPage != null) 'per_page': perPage.toString(),
      if (courseId != null) 'course_id': courseId.toString(),
      if (search != null && search.trim().isNotEmpty) ...{
        'title': search.trim(),
        'search': search.trim(),
      },
    };

    final url = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.liveRooms}')
        .replace(queryParameters: queryParams);

    try {
      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        final liveRooms = _extractRooms(data);
        final meta =
            data is Map && data['meta'] is Map ? Map<String, dynamic>.from(data['meta']) : null;
        final links =
            data is Map && data['links'] is Map ? Map<String, dynamic>.from(data['links']) : null;
        final hasNextPage = (links != null && links['next'] != null) ||
            (meta != null &&
                (meta['current_page'] ?? 1) < (meta['last_page'] ?? 1)) ||
            (perPage != null && perPage < 500 && liveRooms.length >= perPage);

        return {
          'success': true,
          'data': liveRooms,
          'meta': meta,
          'hasNextPage': hasNextPage,
        };
      } else {
        return {
          'success': false,
          'message': (data is Map ? data['message'] : null) ??
              'Failed to fetch live rooms',
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  /// Port of `extractLiveRoomsFromResponse`: `data` may be a list, a nested
  /// `{data: [...]}`, or a single room.
  List<LiveRoom> _extractRooms(dynamic payload) {
    if (payload is! Map) return [];
    final raw = payload['data'];
    List<dynamic> items = const [];
    if (raw is List) {
      items = raw;
    } else if (raw is Map) {
      if (raw['data'] is List) {
        items = raw['data'] as List;
      } else if (raw['id'] != null) {
        items = [raw];
      }
    }
    return items
        .whereType<Map>()
        .where((item) => item['id'] != null)
        .map((item) => LiveRoom.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<Map<String, dynamic>> getLiveRoomById(String roomId) async {
    final token = await getToken();
    if (token == null) return {'success': false, 'message': 'No token found'};

    final url = Uri.parse(
        '${ApiConstants.baseUrl}${ApiConstants.liveRooms}/${Uri.encodeComponent(roomId)}');

    try {
      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        final raw = data is Map ? data['data'] : null;
        Map? roomJson;
        if (raw is Map && raw['id'] != null) {
          roomJson = raw;
        } else if (raw is Map && raw['data'] is Map) {
          roomJson = raw['data'] as Map;
        }
        if (roomJson == null) {
          return {'success': false, 'message': 'Failed to fetch live room details'};
        }
        final liveRoom = LiveRoom.fromJson(Map<String, dynamic>.from(roomJson));
        return {'success': true, 'data': liveRoom};
      } else {
        return {
          'success': false,
          'message': (data is Map ? data['message'] : null) ??
              'Failed to fetch live room details',
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  /// Unlocks a private live room with a code, like the website's
  /// `StudentCourseActivationModal` with `activationItemType="live_room"`:
  /// `POST /v1/code/activate {code, item_id, item_type: "live_room"}`.
  Future<Map<String, dynamic>> activateLiveRoom({
    required String roomId,
    required String code,
  }) async {
    final itemId = int.tryParse(roomId.trim());
    if (itemId == null) {
      return {'success': false, 'invalidId': true};
    }
    try {
      final payload = await ApiClient().post(
        ApiConstants.codeActivate,
        body: {
          'code': code.trim(),
          'item_id': itemId,
          'item_type': 'live_room',
        },
        skipAuthRedirect: true,
        fallback: 'Activation failed',
      );
      return {'success': true, 'data': payload is Map ? payload['data'] : null};
    } on ApiException catch (e) {
      return {'success': false, 'message': e.display()};
    } catch (e) {
      return {'success': false};
    }
  }
}

/// What the website's live sessions page computes before rendering:
/// the student's faculty course tree and the unlocked course ids.
class LiveRoomAccessContext {
  const LiveRoomAccessContext({
    required this.facultyCourseIds,
    required this.enrolledCourseIds,
  });

  const LiveRoomAccessContext.empty()
      : facultyCourseIds = const {},
        enrolledCourseIds = const {};

  /// Every course in the student's faculty tree (`extractFacultyTreeCourses`).
  final Set<String> facultyCourseIds;

  /// Unlocked courses from `/v1/course?per_page=500` plus unlocked tree courses.
  final Set<String> enrolledCourseIds;

  /// Port of `filterLiveRoomsByFacultyCourses`.
  List<LiveRoom> filterVisible(List<LiveRoom> rooms) {
    if (facultyCourseIds.isEmpty) return rooms;
    return rooms.where((room) {
      if (room.courseIds.isEmpty) return true;
      return room.courseIds.any(facultyCourseIds.contains);
    }).toList();
  }

  LiveRoomAccess accessFor(LiveRoom room) => room.accessFor(enrolledCourseIds);
}

class LiveRoomAccessService {
  final ApiClient _api = ApiClient();
  final AuthRepository _authRepository = AuthRepository();

  Future<LiveRoomAccessContext> load({bool forceRefresh = false}) async {
    final results = await Future.wait<dynamic>([
      StudentScopeService().load(forceRefresh: forceRefresh),
      _loadFacultyId(),
      _loadDepartments(),
    ]);

    final scope = results[0] as StudentScope;
    final facultyId = results[1] as String?;
    final categories = results[2] as List<dynamic>;

    final tree = _extractFacultyTreeCourses(categories, facultyId);

    final enrolled = <String>{};
    for (final course in scope.courses) {
      if (course is! Map) continue;
      final id = coerceId(course['id']);
      if (id == null) continue;
      final attrs = course['attributes'];
      final source = attrs is Map ? attrs : course;
      if (source['is_locked'] != true) enrolled.add(id);
    }
    enrolled.addAll(tree.unlocked);

    return LiveRoomAccessContext(
      facultyCourseIds: tree.all,
      enrolledCourseIds: enrolled,
    );
  }

  Future<String?> _loadFacultyId() async {
    try {
      final result = await _authRepository.getProfile();
      final data = result['data'];
      if (result['success'] != true || data is! Map) return null;
      return StudentProfile.fromData(Map<String, dynamic>.from(data)).facultyId;
    } catch (e) {
      debugPrint('[LiveRoomAccess] profile load failed');
      return null;
    }
  }

  Future<List<dynamic>> _loadDepartments() async {
    try {
      final payload = await _api.get(
        ApiConstants.departments,
        fallback: 'Failed to load departments',
      );
      return unwrapList(payload);
    } catch (e) {
      debugPrint('[LiveRoomAccess] department load failed');
      return const [];
    }
  }

  /// Port of `extractFacultyTreeCourses`.
  ({Set<String> all, Set<String> unlocked}) _extractFacultyTreeCourses(
    List<dynamic> categories,
    String? facultyId,
  ) {
    final all = <String>{};
    final unlocked = <String>{};
    if (categories.isEmpty || facultyId == null) {
      return (all: all, unlocked: unlocked);
    }

    String? parentOf(Map cat) {
      final attrs = cat['attributes'];
      return coerceId((attrs is Map ? attrs['parent_id'] : null) ?? cat['parent_id']);
    }

    final byId = <String, Map>{};
    for (final c in categories) {
      if (c is Map && coerceId(c['id']) != null) byId[coerceId(c['id'])!] = c;
    }

    final found = <String>{};
    final queue = <Map>[];
    for (final cat in byId.values) {
      if (parentOf(cat) == facultyId) {
        found.add(coerceId(cat['id'])!);
        queue.add(cat);
      }
    }

    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      final currentId = coerceId(current['id']);
      final attrs = current['attributes'];
      final children = (attrs is Map ? (attrs['childrens'] ?? attrs['children']) : null) ??
          current['childrens'];
      if (children is List) {
        for (final child in children) {
          if (child is! Map) continue;
          final childId = coerceId(child['id']);
          if (childId == null) continue;
          if (found.add(childId)) queue.add(byId[childId] ?? child);
        }
      }
      for (final cat in byId.values) {
        final id = coerceId(cat['id'])!;
        if (currentId != null && parentOf(cat) == currentId && found.add(id)) {
          queue.add(cat);
        }
      }
    }

    for (final catId in found) {
      final cat = byId[catId];
      if (cat == null) continue;
      final attrs = cat['attributes'];
      final rawCourses = (attrs is Map ? attrs['courses'] : null) ?? cat['courses'];
      final list = rawCourses is List
          ? rawCourses
          : (rawCourses is Map && rawCourses['data'] is List
              ? rawCourses['data'] as List
              : const []);
      for (final c in list) {
        if (c is! Map) continue;
        final id = coerceId(c['id']);
        if (id == null) continue;
        all.add(id);
        final cAttrs = c['attributes'] is Map ? c['attributes'] as Map : c;
        if (cAttrs['is_locked'] != true) unlocked.add(id);
      }
    }

    return (all: all, unlocked: unlocked);
  }
}
