import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../core/network/api_constants.dart';
import '../../../core/offline/offline_first_repository.dart';
import '../../../core/local/hive_boxes.dart';

/// Model class for course file/attachment
class CourseFile {
  final int id;
  final String title;
  final String filePath;
  final String extension;
  final bool isLocked;
  final bool downloadable;
  final int? size;
  final String? mimeType;
  final DateTime? createdAt;
  final String? courseName;
  final String? lectureName;
  final String? chapterName;
  final int? chapterId;
  final bool chapterIsLocked;
  final bool chapterIsFreePreviewAttachment;
  final bool chapterIsActivated;
  final bool chapterIsFreePreview;
  final int currentViews;
  final int maxViews;
  final String? courseId;

  CourseFile({
    required this.id,
    required this.title,
    required this.filePath,
    required this.extension,
    required this.isLocked,
    required this.downloadable,
    this.size,
    this.mimeType,
    this.createdAt,
    this.courseName,
    this.lectureName,
    this.chapterName,
    this.chapterId,
    this.chapterIsLocked = false,
    this.chapterIsFreePreviewAttachment = false,
    this.chapterIsActivated = false,
    this.chapterIsFreePreview = false,
    this.currentViews = 0,
    this.maxViews = 5,
    this.courseId,
  });

  factory CourseFile.fromJson(
    Map<String, dynamic> json, {
    String? courseName,
    String? lectureName,
    String? chapterName,
    int? chapterId,
    bool chapterIsLocked = false,
    bool chapterIsFreePreviewAttachment = false,
    bool chapterIsActivated = false,
    bool chapterIsFreePreview = false,
    int currentViews = 0,
    int maxViews = 5,
    String? courseId,
  }) {
    final attributes = json['attributes'] ?? {};
    return CourseFile(
      id: int.tryParse(json['id']?.toString() ?? '0') ?? 0,
      title: attributes['title']?.toString() ??
          attributes['name']?.toString() ??
          'Unnamed File',
      filePath: attributes['path']?.toString() ??
          attributes['file_path']?.toString() ??
          attributes['url']?.toString() ??
          '',
      extension: attributes['extension']?.toString().toLowerCase() ??
          attributes['file_type']?.toString().toLowerCase() ??
          'pdf',
      isLocked: attributes['is_locked'] == true,
      downloadable: attributes['downloadable'] == true,
      size: int.tryParse(attributes['size']?.toString() ?? '0'),
      mimeType: attributes['mime_type']?.toString(),
      createdAt: attributes['created_at'] != null
          ? DateTime.tryParse(attributes['created_at'].toString())
          : null,
      courseName: courseName,
      lectureName: lectureName,
      chapterName: chapterName,
      chapterId: chapterId,
      chapterIsLocked: chapterIsLocked,
      chapterIsFreePreviewAttachment: chapterIsFreePreviewAttachment,
      chapterIsActivated: chapterIsActivated,
      chapterIsFreePreview: chapterIsFreePreview,
      currentViews: currentViews,
      maxViews: maxViews,
      courseId: courseId,
    );
  }

  /// Get file type category (pdf, image, video, audio, document, other)
  String get fileType {
    switch (extension.toLowerCase()) {
      case 'pdf':
        return 'pdf';
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'webp':
      case 'bmp':
        return 'image';
      case 'mp4':
      case 'mov':
      case 'avi':
      case 'mkv':
      case 'webm':
        return 'video';
      case 'mp3':
      case 'wav':
      case 'aac':
      case 'ogg':
      case 'm4a':
        return 'audio';
      case 'doc':
      case 'docx':
      case 'xls':
      case 'xlsx':
      case 'ppt':
      case 'pptx':
      case 'txt':
      case 'rtf':
        return 'document';
      default:
        return 'other';
    }
  }

  /// Get formatted file size string
  String get formattedSize {
    if (size == null || size == 0) return '';
    if (size! < 1024) return '${size}B';
    if (size! < 1024 * 1024) return '${(size! / 1024).toStringAsFixed(1)}KB';
    if (size! < 1024 * 1024 * 1024) {
      return '${(size! / (1024 * 1024)).toStringAsFixed(1)}MB';
    }
    return '${(size! / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
  }

  /// Check if file is a PDF
  bool get isPdf => extension.toLowerCase() == 'pdf';

  /// Check if file can be previewed
  bool get canPreview => isPdf || ['image', 'video'].contains(fileType);
}

/// Repository for course files/attachments with offline-first support
class CourseFilesRepository with OfflineFirstRepository {
  final _storage = const FlutterSecureStorage();

  Future<String?> getToken() async {
    return await _storage.read(key: 'auth_token');
  }

  /// Get files by category/subject ID with offline-first support
  /// Returns cached data if offline or API fails
  Future<Map<String, dynamic>> getFilesByCategory(int categoryId) async {
    final token = await getToken();
    if (token == null) return {'success': false, 'message': 'No token found'};

    return offlineFirstFetch(
      apiFetcher: () async {
        var url = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.courses}');
        url = url.replace(queryParameters: {
          ...url.queryParameters,
          'category_id': categoryId.toString(),
          'include': 'attachments',
        });

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
          final courses = data['data'] as List<dynamic>? ?? [];
          final files = _extractFilesFromCourses(courses);
          return {'success': true, 'data': files};
        } else {
          return {
            'success': false,
            'message': data['message'] ?? 'Failed to fetch files',
          };
        }
      },
      boxName: HiveBoxes.courses,
      cacheKey: 'files_category_$categoryId',
      maxCacheAge: const Duration(hours: 6),
    );
  }

  /// Get files by course IDs with offline-first support
  Future<Map<String, dynamic>> getFilesByCourseIds(List<int> courseIds) async {
    final token = await getToken();
    if (token == null) return {'success': false, 'message': 'No token found'};

    if (courseIds.isEmpty) {
      return {'success': true, 'data': <CourseFile>[]};
    }

    return offlineFirstFetch(
      apiFetcher: () async {
        // Build query with multiple course IDs
        final queryParams = <String, String>{
          'include': 'attachments',
        };
        for (var i = 0; i < courseIds.length; i++) {
          queryParams['course_ids[$i]'] = courseIds[i].toString();
        }

        var url = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.courses}');
        url = url.replace(queryParameters: queryParams);

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
          final courses = data['data'] as List<dynamic>? ?? [];
          final files = _extractFilesFromCourses(courses);
          return {'success': true, 'data': files};
        } else {
          return {
            'success': false,
            'message': data['message'] ?? 'Failed to fetch files',
          };
        }
      },
      boxName: HiveBoxes.courses,
      cacheKey: 'files_courses_${courseIds.join('_')}',
      maxCacheAge: const Duration(hours: 6),
    );
  }

  /// Get files by library with offline-first support
  Future<Map<String, dynamic>> getLibraryFiles() async {
    final token = await getToken();
    if (token == null) return {'success': false, 'message': 'No token found'};

    return offlineFirstFetch(
      apiFetcher: () async {
        final url = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.libraries}');
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
          final libraries = data['data'] as List<dynamic>? ?? [];
          final files = _extractFilesFromLibraries(libraries);
          return {'success': true, 'data': files};
        } else {
          return {
            'success': false,
            'message': data['message'] ?? 'Failed to fetch library files',
          };
        }
      },
      boxName: HiveBoxes.courses,
      cacheKey: 'library_files',
      maxCacheAge: const Duration(hours: 6),
    );
  }

  /// Extract files from course data
  /// Files are in chapter_attachments at course level
  List<CourseFile> _extractFilesFromCourses(List<dynamic> courses) {
    final files = <CourseFile>[];

    for (final course in courses) {
      final courseAttributes = course['attributes'] ?? {};

      // Get chapter_attachments from course level
      final chapterAttachments = courseAttributes['chapter_attachments'] as List<dynamic>? ?? [];

      for (final attachment in chapterAttachments) {
        try {
          final file = CourseFile.fromJson(attachment);
          if (file.filePath.isNotEmpty) {
            files.add(file);
          }
        } catch (e) {
          // Skip invalid attachments
          continue;
        }
      }

      // Also check attachments nested in lectures > chapters
      final lectures = courseAttributes['lectures'] as List<dynamic>? ?? [];
      for (final lecture in lectures) {
        final lectureAttrs = lecture['attributes'] ?? {};
        final chapters = lectureAttrs['chapters'] as List<dynamic>? ?? [];
        for (final chapter in chapters) {
          final chapterAttrs = chapter['attributes'] ?? {};
          final chapterId = int.tryParse(chapter['id']?.toString() ?? '');
          final chapterIsLocked = chapterAttrs['is_locked'] == true;
          final attachments = chapterAttrs['attachments'] as List<dynamic>? ?? [];
          for (final attachment in attachments) {
            try {
              final file = CourseFile.fromJson(
                attachment,
                chapterId: chapterId,
                chapterIsLocked: chapterIsLocked,
              );
              if (file.filePath.isNotEmpty) {
                files.add(file);
              }
            } catch (e) {
              continue;
            }
          }
        }
      }
    }

    return files;
  }

  /// Extract files from library data
  List<CourseFile> _extractFilesFromLibraries(List<dynamic> libraries) {
    final files = <CourseFile>[];

    for (final library in libraries) {
      final libraryAttributes = library['attributes'] ?? {};
      final attachments = libraryAttributes['attachments'] as List<dynamic>? ?? [];

      for (final attachment in attachments) {
        try {
          final file = CourseFile.fromJson(attachment);
          if (file.filePath.isNotEmpty) {
            files.add(file);
          }
        } catch (e) {
          // Skip invalid attachments
          continue;
        }
      }
    }

    return files;
  }

  /// Get cached files for a category
  List<CourseFile> getCachedFiles(int categoryId) {
    final cached = getCached(HiveBoxes.courses, 'files_category_$categoryId');
    if (cached == null) return [];

    if (cached is List) {
      return cached
          .whereType<Map<String, dynamic>>()
          .map((f) => CourseFile.fromJson(f))
          .where((f) => f.filePath.isNotEmpty)
          .toList();
    }
    return [];
  }

  /// Get cached files by course IDs
  List<CourseFile> getCachedFilesByCourseIds(List<int> courseIds) {
    if (courseIds.isEmpty) return [];

    final cached = getCached(HiveBoxes.courses, 'files_courses_${courseIds.join('_')}');
    if (cached == null) return [];

    if (cached is List) {
      return cached
          .whereType<Map<String, dynamic>>()
          .map((f) => CourseFile.fromJson(f))
          .where((f) => f.filePath.isNotEmpty)
          .toList();
    }
    return [];
  }

  /// Get all cached library files
  List<CourseFile> getCachedLibraryFiles() {
    final cached = getCached(HiveBoxes.courses, 'library_files');
    if (cached == null) return [];

    if (cached is List) {
      return cached
          .whereType<Map<String, dynamic>>()
          .map((f) => CourseFile.fromJson(f))
          .where((f) => f.filePath.isNotEmpty)
          .toList();
    }
    return [];
  }
}
