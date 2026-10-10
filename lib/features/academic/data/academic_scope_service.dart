import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../../core/local/hive_boxes.dart';
import '../../../core/services/student_scope.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/domain/student_profile.dart';
import '../../exams/data/exam_filter_service.dart';

/// The student's academic selection: university, centre, faculty, department.
///
/// Nearly everything the student sees — the course catalogue, the subject
/// tree, live sessions, exams, library, notes — is scoped by it on the server.
/// The web never caches those reads (`cache: "no-store"`) and calls
/// `router.refresh()` after the profile form saves, so a new selection shows
/// up immediately. The app memoises and persists several of them, so after a
/// change they have to be dropped explicitly: that is what [applyScopeChange]
/// does.
class AcademicSelection {
  const AcademicSelection({
    this.universityId,
    this.centerId,
    this.facultyId,
    this.departmentId,
  });

  factory AcademicSelection.fromProfile(StudentProfile profile) {
    return AcademicSelection(
      universityId: profile.universityId,
      centerId: profile.centerId,
      facultyId: profile.facultyId,
      departmentId: profile.departmentId,
    );
  }

  final String? universityId;
  final String? centerId;
  final String? facultyId;
  final String? departmentId;

  static String? _norm(String? id) {
    final trimmed = id?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  /// True when any of the four ids differs from [other].
  bool differsFrom(AcademicSelection other) {
    return _norm(universityId) != _norm(other.universityId) ||
        _norm(centerId) != _norm(other.centerId) ||
        _norm(facultyId) != _norm(other.facultyId) ||
        _norm(departmentId) != _norm(other.departmentId);
  }
}

class AcademicScopeService {
  AcademicScopeService({AuthRepository? authRepository})
      : _authRepository = authRepository ?? AuthRepository();

  final AuthRepository _authRepository;

  /// Hive boxes whose content depends on the academic selection: the course
  /// catalogue (`courses_all`, `courses_activated`, per-category lists,
  /// library files) and the chapter / lecture lists derived from it.
  ///
  /// Not cleared: `pending_actions` (unsynced offline work), `user_profile`
  /// (watermark data and the OTA acknowledgement), `app_state`, `comments` and
  /// `progress`, none of which are keyed on the selection.
  static const List<String> scopedBoxes = [
    HiveBoxes.courses,
    HiveBoxes.chapters,
    HiveBoxes.lectures,
  ];

  /// Drops every in-memory and on-disk cache built for the previous selection.
  Future<void> invalidateCaches() async {
    StudentScopeService().invalidate();
    ExamFilterService.clearCache();

    for (final name in scopedBoxes) {
      try {
        if (Hive.isBoxOpen(name)) {
          await Hive.box<dynamic>(name).clear();
        }
      } catch (e) {
        debugPrint('[AcademicScope] could not clear box "$name": $e');
      }
    }
  }

  /// Runs after `PUT /v1/auth/update` succeeded with a new selection.
  ///
  /// Clears the stale caches, then re-reads `/v1/auth/me` so the caller gets
  /// the profile exactly as the server stored it. Returns that `data` node, or
  /// `null` when the refresh failed (the caches are cleared either way, so the
  /// next screen load fetches fresh data).
  Future<Map<String, dynamic>?> applyScopeChange() async {
    await invalidateCaches();

    final result = await _authRepository.getProfile();
    final data = result['success'] == true ? result['data'] : null;
    if (data is! Map) return null;

    // Start loading the course scope for the new selection; the rebuilt home
    // screen joins this in-flight request instead of starting its own.
    unawaited(StudentScopeService().load(forceRefresh: true));

    return Map<String, dynamic>.from(data);
  }
}
