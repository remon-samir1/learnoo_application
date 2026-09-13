/// Whether a student may open a chapter's video and PDF.
///
/// Ported from `src/lib/student-chapter-access.ts`. The app used to inline this
/// logic three times — in `course_detail_screen`, `course_content_screen` and
/// `lecture_detail_screen` — with three different readings of the same flags,
/// and all three used `as bool?` casts that silently fail on the `1` / `"1"`
/// forms the API actually sends.
///
/// Three cases govern visibility:
///
///  1. **Free preview** — `is_free_preview` unlocks the **video only** and
///     `is_free_preview_attachment` unlocks the **PDF only**. The two flags are
///     completely independent; neither implies the other.
///  2. **Activated** — `is_activated == true`, or the owning course is not
///     locked, unlocks everything regardless of preview flags.
///  3. **Views exhausted** — `can_watch` comes back false and the student must
///     re-activate.
library;

import '../../../core/utils/coerce.dart';

/// Placeholder the API returns when a chapter has no video attached.
const String _noVideoPlaceholder = 'https://api.learnoo.app/storage';

/// Reads the `attributes` map off a chapter, tolerating a bare attributes map.
Map<String, dynamic> chapterAttributes(dynamic chapter) {
  if (chapter is! Map) return const {};
  final attrs = chapter['attributes'];
  if (attrs is Map) return Map<String, dynamic>.from(attrs);
  return Map<String, dynamic>.from(chapter);
}

/// Fully unlocked through purchase/activation rather than a preview flag.
///
/// `is_locked` alone is not trustworthy here: the API flips it to `false` when
/// the video happens to be a free preview, which would wrongly unlock the PDF.
bool isChapterFullyUnlocked(dynamic chapter, {required bool courseLocked}) {
  if (!courseLocked) return true;
  final attrs = chapterAttributes(chapter);
  return coerceFlagOrNull(attrs['is_activated']) == true;
}

/// Whether the video can play right now.
bool isChapterVideoPlayable(dynamic chapter, {required bool courseLocked}) {
  if (isChapterFullyUnlocked(chapter, courseLocked: courseLocked)) return true;

  final attrs = chapterAttributes(chapter);
  if (coerceFlag(attrs['is_free_preview'])) return true;
  return coerceCanWatchExplicitTrue(attrs['can_watch']);
}

/// Whether the video should show an activation prompt instead of the player.
bool chapterVideoRequiresActivation(dynamic chapter,
    {required bool courseLocked}) {
  if (isChapterFullyUnlocked(chapter, courseLocked: courseLocked)) return false;

  final attrs = chapterAttributes(chapter);
  if (coerceFlag(attrs['is_free_preview'])) return false;
  if (coerceCanWatchExplicitTrue(attrs['can_watch'])) return false;
  return true;
}

/// Whether the attached PDF is visible.
///
/// Note this checks `is_free_preview_attachment` — **not** `is_free_preview`.
bool isChapterPdfVisible(dynamic chapter, {required bool courseLocked}) {
  if (isChapterFullyUnlocked(chapter, courseLocked: courseLocked)) return true;
  final attrs = chapterAttributes(chapter);
  return coerceFlag(attrs['is_free_preview_attachment']);
}

/// Whether the PDF should show an activation prompt.
bool chapterPdfRequiresActivation(dynamic chapter,
    {required bool courseLocked}) {
  if (isChapterFullyUnlocked(chapter, courseLocked: courseLocked)) return false;
  final attrs = chapterAttributes(chapter);
  return !coerceFlag(attrs['is_free_preview_attachment']);
}

/// Views the student has already spent on this chapter.
int chapterCurrentViews(dynamic chapter) {
  final attrs = chapterAttributes(chapter);
  return coerceNonNegativeInt(attrs['current_user_views']) ??
      coerceNonNegativeInt(attrs['current_views']) ??
      0;
}

/// Total views allowed, or `null` when unlimited.
int? chapterMaxViews(dynamic chapter) {
  final attrs = chapterAttributes(chapter);
  return coercePositiveInt(attrs['max_views']);
}

/// True when the view allowance is used up and re-activation is needed.
bool chapterViewsExhausted(dynamic chapter) {
  final max = chapterMaxViews(chapter);
  if (max == null) return false;
  return chapterCurrentViews(chapter) >= max;
}

/// Minutes of playback required before a view is counted.
///
/// `0` (or absent) means the view is registered as soon as playback starts.
int chapterViewByMinute(dynamic chapter) {
  final attrs = chapterAttributes(chapter);
  final value = coerceNonNegativeInt(attrs['view_by_minute']) ?? 0;
  return value < 0 ? 0 : value;
}

/// Detects the "no video attached" placeholder the API returns.
///
/// The API may send: actual `null`, an empty string, the literal string
/// `"null"`, `"0"`, the full placeholder URL, or a relative path (`/storage`,
/// `storage`) that would resolve to the placeholder once a base URL is
/// prepended.  All of these mean "no video".
bool isNoVideoUrl(String? url) {
  if (url == null) return true;
  final s = url.trim().replaceAll('\\', '/');
  if (s.isEmpty) return true;
  if (s == 'null' || s == '0') return true;
  if (s == _noVideoPlaceholder || s == '$_noVideoPlaceholder/') return true;
  // Relative variants that would resolve to the storage placeholder.
  if (s == '/storage' || s == '/storage/' || s == 'storage' || s == 'storage/') {
    return true;
  }
  return false;
}

/// A course is locked only when the API explicitly says so.
///
/// Mirrors `courseIsLocked`: a missing field means unlocked, not locked.
bool courseIsLocked(dynamic course) {
  if (course is! Map) return false;
  final attrs = course['attributes'];
  final source = attrs is Map ? attrs : course;
  return coerceFlagOrNull(source['is_locked']) == true;
}

/// Whether the chapter has any playable video at all.
///
/// Port of `hasVideoContent` in the web's chapter row: the API sends a
/// placeholder URL rather than `null` for a PDF-only chapter, and the stream can
/// live in any of four fields. Checking `attributes.video` alone — which the app
/// did — classified a chapter whose stream is under `playlist` as PDF-only, and
/// a placeholder-only chapter as having video.
bool chapterHasVideoContent(dynamic chapter) {
  final attrs = chapterAttributes(chapter);
  for (final key in const [
    'video',
    'playlist',
    'video_hls_url',
    'video_mp4_url',
    'main_video',
  ]) {
    if (!isNoVideoUrl(coerceString(attrs[key]))) return true;
  }
  return false;
}

/// Whether the chapter carries a PDF attachment.
bool chapterHasPdfAttachment(dynamic chapter) {
  return chapterPdfAttachments(chapter).isNotEmpty;
}

/// The chapter's PDF attachments, unwrapped from either envelope the API uses.
List<dynamic> chapterPdfAttachments(dynamic chapter) {
  final attrs = chapterAttributes(chapter);
  final raw = attrs['attachments'];
  final list = raw is List
      ? raw
      : raw is Map && raw['data'] is List
          ? raw['data'] as List
          : const [];

  return list.where((att) {
    if (att is! Map) return false;
    final attributes = att['attributes'] is Map ? att['attributes'] as Map : att;
    final extension =
        coerceString(attributes['extension'])?.toLowerCase().trim() ?? '';
    if (extension == 'pdf') return true;
    final path = coerceString(attributes['path'])?.toLowerCase() ?? '';
    if (path.endsWith('.pdf') || path.contains('.pdf')) return true;
    final name = coerceString(attributes['name'])?.toLowerCase() ?? '';
    return name.endsWith('.pdf');
  }).toList();
}

/// True when the chapter is PDF-only: no video anywhere, but a PDF/attachment attached.
///
/// The web hides the watch button for these; the app opens the PDF reviewer
/// directly instead of a player with nothing to play.
bool chapterIsPdfOnly(dynamic chapter) {
  if (chapterHasVideoContent(chapter)) return false;
  if (chapterHasPdfAttachment(chapter)) return true;
  final attrs = chapterAttributes(chapter);
  final raw = attrs['attachments'];
  if (raw is List && raw.isNotEmpty) return true;
  if (raw is Map && raw['data'] is List && (raw['data'] as List).isNotEmpty) return true;
  return false;
}
