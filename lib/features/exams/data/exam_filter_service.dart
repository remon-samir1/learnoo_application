import '../models/quiz_models.dart';
import 'exam_repository.dart';

/// Service for filtering exams based on visible courses (NO department filtering)
/// 
/// Logic:
/// 1. Get the list of visible/allowed courses from the Home Screen filter
/// 2. Extract all course_ids from those courses
/// 3. Extract all chapter_ids related to those courses
/// 4. Filter exams where:
///    - exam.course_id exists in allowed course_ids
///    - OR exam.chapter_id exists in allowed chapter_ids
class ExamFilterService {
  static final ExamRepository _examRepository = ExamRepository();

  /// Cache for chapter to course resolution to avoid duplicate API calls
  static final Map<int, int> _chapterToCourseCache = {};

  /// Extract course ID from course data
  static int? _extractCourseId(dynamic course) {
    return int.tryParse(course['id']?.toString() ?? '');
  }

  /// Extract chapter's course ID from chapter data
  static int? _extractChapterCourseId(dynamic chapter) {
    final attributes = chapter['attributes'] as Map<String, dynamic>?;
    final courseId = attributes?['course_id'] ?? attributes?['course']?['data']?['id'];
    return courseId != null ? int.tryParse(courseId.toString()) : null;
  }

  /// Extract chapter ID from chapter data
  static int? _extractChapterId(dynamic chapter) {
    return int.tryParse(chapter['id']?.toString() ?? '');
  }

  /// Get all allowed course IDs from the already-filtered courses list
  /// 
  /// [allowedCourses] - The filtered courses from Home Screen (already filtered by user's access)
  static Set<int> getAllowedCourseIds(List<dynamic> allowedCourses) {
    final courseIds = <int>{};
    for (final course in allowedCourses) {
      final courseId = _extractCourseId(course);
      if (courseId != null) {
        courseIds.add(courseId);
      }
    }
    return courseIds;
  }

  /// Get all allowed chapter IDs from chapters related to allowed courses
  /// 
  /// [allowedCourses] - The filtered courses from Home Screen
  /// [allChapters] - All chapters data to find related chapters
  static Set<int> getAllowedChapterIds({
    required List<dynamic> allowedCourses,
    required List<dynamic> allChapters,
  }) {
    final allowedCourseIds = getAllowedCourseIds(allowedCourses);
    final chapterIds = <int>{};

    for (final chapter in allChapters) {
      final chapterCourseId = _extractChapterCourseId(chapter);
      if (chapterCourseId != null && allowedCourseIds.contains(chapterCourseId)) {
        final chapterId = _extractChapterId(chapter);
        if (chapterId != null) {
          chapterIds.add(chapterId);
        }
      }
    }

    return chapterIds;
  }

  /// Resolve chapter to its course ID using API or cache
  static Future<int?> resolveChapterToCourse(int chapterId) async {
    // Check cache first
    if (_chapterToCourseCache.containsKey(chapterId)) {
      return _chapterToCourseCache[chapterId];
    }

    // Fetch from API
    final result = await _examRepository.resolveChapterToCourse(chapterId);
    if (result['success'] && result['data'] != null) {
      final courseId = result['data'] as int;
      _chapterToCourseCache[chapterId] = courseId;
      return courseId;
    }

    return null;
  }

  /// Filter exams based on allowed courses and their chapters
  /// 
  /// [exams] - All exams from API
  /// [allowedCourses] - Filtered courses from Home Screen (source of truth)
  /// [allChapters] - All chapters to find related ones
  static Future<List<Quiz>> filterExams({
    required List<Quiz> exams,
    required List<dynamic> allowedCourses,
    required List<dynamic> allChapters,
  }) async {
    // Extract allowed IDs
    final allowedCourseIds = getAllowedCourseIds(allowedCourses);
    final allowedChapterIds = getAllowedChapterIds(
      allowedCourses: allowedCourses,
      allChapters: allChapters,
    );

    final filteredExams = <Quiz>{};

    for (final exam in exams) {
      // Check if exam has direct course match
      if (exam.courseId != null && 
          exam.courseId! > 0 && 
          allowedCourseIds.contains(exam.courseId)) {
        filteredExams.add(exam);
        continue;
      }

      // Check if any of exam.courseIds belongs to allowed courses
      if (exam.courseIds.any((cid) => allowedCourseIds.contains(int.tryParse(cid)))) {
        filteredExams.add(exam);
        continue;
      }

      // Check if exam has chapter match
      if (exam.chapterId != null && allowedChapterIds.contains(exam.chapterId)) {
        filteredExams.add(exam);
        continue;
      }

      // Handle edge case: chapter exam - resolve chapter to course
      if (exam.chapterId != null) {
        final resolvedCourseId = await resolveChapterToCourse(exam.chapterId!);
        if (resolvedCourseId != null && allowedCourseIds.contains(resolvedCourseId)) {
          filteredExams.add(exam);
        }
      }
    }

    return filteredExams.toList();
  }

  /// Filter exams for a specific course detail screen
  /// 
  /// Shows exams where:
  /// - exam.course_id == courseId
  /// - OR exam.courseIds contains courseId
  /// - OR exam.chapter_id belongs to this course
  static Future<List<Quiz>> filterExamsByCourse({
    required List<Quiz> exams,
    required int courseId,
    required List<dynamic> courseChapters,
  }) async {
    // Get chapter IDs for this course
    final chapterIds = <int>{};
    for (final chapter in courseChapters) {
      final chapterId = _extractChapterId(chapter);
      if (chapterId != null) {
        chapterIds.add(chapterId);
      }
    }

    final courseIdStr = courseId.toString();
    final filteredExams = <Quiz>{};

    for (final exam in exams) {
      // Check direct course match
      if (exam.courseId != null && exam.courseId == courseId) {
        filteredExams.add(exam);
        continue;
      }

      // Check courseIds list match
      if (exam.courseIds.contains(courseIdStr)) {
        filteredExams.add(exam);
        continue;
      }

      // Check chapter match (exam's chapter belongs to this course)
      if (exam.chapterId != null && chapterIds.contains(exam.chapterId)) {
        filteredExams.add(exam);
        continue;
      }

      // Resolve chapter to course and check if it matches
      if (exam.chapterId != null) {
        final resolvedCourseId = await resolveChapterToCourse(exam.chapterId!);
        if (resolvedCourseId == courseId) {
          filteredExams.add(exam);
        }
      }
    }

    return filteredExams.toList();
  }

  /// Filter exams for subject/department detail screen
  /// 
  /// Shows exams where:
  /// - exam.course_id is in the department's courses
  /// - OR exam.chapter_id belongs to those courses
  static Future<List<Quiz>> filterExamsByDepartment({
    required List<Quiz> exams,
    required String departmentId,
    required List<dynamic> departmentCourses,
    required List<dynamic> departmentChapters,
  }) async {
    // Get course IDs in this department
    final courseIds = <int>{};
    for (final course in departmentCourses) {
      final courseId = _extractCourseId(course);
      if (courseId != null) {
        courseIds.add(courseId);
      }
    }

    // Get chapter IDs for courses in this department
    final chapterIds = <int>{};
    for (final chapter in departmentChapters) {
      final chapterCourseId = _extractChapterCourseId(chapter);
      if (chapterCourseId != null && courseIds.contains(chapterCourseId)) {
        final chapterId = _extractChapterId(chapter);
        if (chapterId != null) {
          chapterIds.add(chapterId);
        }
      }
    }

    final filteredExams = <Quiz>{};

    for (final exam in exams) {
      // Check course match
      if (exam.courseId != null && 
          exam.courseId! > 0 && 
          courseIds.contains(exam.courseId)) {
        filteredExams.add(exam);
        continue;
      }

      // Check chapter match
      if (exam.chapterId != null && chapterIds.contains(exam.chapterId)) {
        filteredExams.add(exam);
        continue;
      }

      // Handle edge case: chapter-only exam
      if (exam.chapterId != null && exam.courseId == null) {
        final resolvedCourseId = await resolveChapterToCourse(exam.chapterId!);
        if (resolvedCourseId != null && courseIds.contains(resolvedCourseId)) {
          filteredExams.add(exam);
        }
      }
    }

    return filteredExams.toList();
  }

  /// Clear the chapter to course cache (useful for logout or refresh)
  static void clearCache() {
    _chapterToCourseCache.clear();
  }
}
