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

/// Normalize API booleans / 0–1 / numeric strings for preview flags.
///
/// Exact port of the web's `coercePreviewFlag`: explicit truthy / falsy forms
/// first, then JavaScript `Boolean(value)` semantics for anything else (so a
/// non-zero number or a non-empty unknown string counts as `true`).
bool coercePreviewFlag(dynamic value) {
  if (value == true || value == 1 || value == '1') return true;
  if (value == false || value == 0 || value == '0') return false;
  if (value is String) {
    final s = value.trim().toLowerCase();
    if (s == 'true' || s == 'yes') return true;
    if (s == 'false' || s == 'no' || s.isEmpty) return false;
    return true;
  }
  if (value == null) return false;
  if (value is num) return value != 0 && !value.isNaN;
  return true;
}

/// Reads the `attributes` map off a chapter, tolerating a bare attributes map,
/// or a JSON:API resource with `data.attributes`.
Map<String, dynamic> chapterAttributes(dynamic chapter) {
  if (chapter is! Map) return const {};
  if (chapter['data'] is Map) {
    final data = chapter['data'] as Map;
    if (data['attributes'] is Map) {
      return Map<String, dynamic>.from(data['attributes'] as Map);
    }
    return Map<String, dynamic>.from(data);
  }
  final attrs = chapter['attributes'];
  if (attrs is Map) {
    if (attrs['data'] is Map && (attrs['data'] as Map)['attributes'] is Map) {
      return Map<String, dynamic>.from(
        (attrs['data'] as Map)['attributes'] as Map,
      );
    }
    return Map<String, dynamic>.from(attrs);
  }
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
  if (coercePreviewFlag(attrs['is_free_preview'])) return true;
  return coerceCanWatchExplicitTrue(attrs['can_watch']);
}

/// Whether the video should show an activation prompt instead of the player.
bool chapterVideoRequiresActivation(dynamic chapter,
    {required bool courseLocked}) {
  if (isChapterFullyUnlocked(chapter, courseLocked: courseLocked)) return false;

  final attrs = chapterAttributes(chapter);
  if (coercePreviewFlag(attrs['is_free_preview'])) return false;
  if (coerceCanWatchExplicitTrue(attrs['can_watch'])) return false;
  return true;
}

/// Whether the attached PDF is visible.
///
/// Note this checks `is_free_preview_attachment` — **not** `is_free_preview`.
bool isChapterPdfVisible(dynamic chapter, {required bool courseLocked}) {
  if (isChapterFullyUnlocked(chapter, courseLocked: courseLocked)) return true;
  final attrs = chapterAttributes(chapter);
  return coercePreviewFlag(attrs['is_free_preview_attachment']);
}

/// Whether the PDF should show an activation prompt.
bool chapterPdfRequiresActivation(dynamic chapter,
    {required bool courseLocked}) {
  if (isChapterFullyUnlocked(chapter, courseLocked: courseLocked)) return false;
  final attrs = chapterAttributes(chapter);
  return !coercePreviewFlag(attrs['is_free_preview_attachment']);
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

/// Port of the web's `getFirstPdfUrl`: the `path` of the first PDF attachment,
/// or `null` when the chapter has none.
String? chapterFirstPdfPath(dynamic chapter) {
  for (final att in chapterPdfAttachments(chapter)) {
    final attributes = att['attributes'] is Map ? att['attributes'] as Map : att;
    final path = coerceString(attributes['path'])?.trim();
    if (path != null && path.isNotEmpty && path != 'null') return path;
  }
  return null;
}

/// Chapter `duration` in seconds (`"mm:ss"`, `"hh:mm:ss"` or a plain number),
/// or `0` when absent / unparseable.
int chapterDurationSeconds(dynamic chapter) {
  final raw = coerceString(chapterAttributes(chapter)['duration'])?.trim();
  if (raw == null || raw.isEmpty) return 0;
  final plain = num.tryParse(raw);
  if (plain != null) return plain > 0 ? plain.round() : 0;
  final parts = raw.split(':');
  if (parts.length < 2 || parts.length > 3) return 0;
  var total = 0;
  for (final part in parts) {
    final n = int.tryParse(part.trim());
    if (n == null || n < 0) return 0;
    total = total * 60 + n;
  }
  return total;
}

/// Whether the chapter has a video — including one the API withheld.
///
/// For a chapter whose video the student may not watch, the API strips the
/// stream URLs, so [chapterHasVideoContent] alone reads a locked
/// "video + PDF" chapter as PDF-only (client report #9). The dashboard fills
/// `duration` from the uploaded video, so a locked chapter with a non-zero
/// duration still has a video behind the lock.
bool chapterHasVideo(dynamic chapter, {required bool courseLocked}) {
  if (chapterHasVideoContent(chapter)) return true;
  if (isChapterVideoPlayable(chapter, courseLocked: courseLocked)) {
    // Playable yet no URL: the chapter really has no video.
    return false;
  }
  return chapterDurationSeconds(chapter) > 0;
}

/// Whether the student may open the chapter's PDF right now.
///
/// Mirrors the web row: once the view allowance is spent only the
/// re-activation button is offered; otherwise the PDF opens when the chapter
/// is fully unlocked or `is_free_preview_attachment` is set. Attachment-level
/// `is_locked` and chapter `is_locked` are **not** consulted — the web ignores
/// them (the API sets chapter `is_locked` for every non-activated chapter,
/// which used to hide free PDFs).
bool canOpenChapterPdf(dynamic chapter, {required bool courseLocked}) {
  if (chapterViewsExhausted(chapter)) return false;
  return isChapterPdfVisible(chapter, courseLocked: courseLocked);
}

/// [canOpenChapterPdf] for callers that hold the chapter flags rather than the
/// chapter record (file lists, the attachment permission service).
///
/// [maxViews] `<= 0` means unlimited, like a missing `max_views`.
bool canOpenChapterPdfFlags({
  required bool courseLocked,
  required bool chapterIsActivated,
  required bool chapterIsFreePreviewAttachment,
  int currentViews = 0,
  int maxViews = 0,
}) {
  return canOpenChapterPdf(
    {
      'attributes': {
        'is_activated': chapterIsActivated,
        'is_free_preview_attachment': chapterIsFreePreviewAttachment,
        'current_user_views': currentViews,
        'max_views': maxViews,
      },
    },
    courseLocked: courseLocked,
  );
}

/// Everything a chapter row, sheet or entry point needs to decide what to
/// show, computed once with the web's rules.
class ChapterAccessSummary {
  /// The chapter has a video (possibly withheld behind the lock).
  final bool hasVideo;

  /// The chapter has a PDF attachment.
  final bool hasPdf;

  /// The video may be played now.
  final bool videoOpen;

  /// The PDF may be opened now.
  final bool pdfOpen;

  /// The view allowance is used up; only re-activation is offered.
  final bool viewsExhausted;

  /// Unlocked through the course or an activation code.
  final bool fullyUnlocked;

  const ChapterAccessSummary({
    required this.hasVideo,
    required this.hasPdf,
    required this.videoOpen,
    required this.pdfOpen,
    required this.viewsExhausted,
    required this.fullyUnlocked,
  });

  /// A video exists but is locked.
  bool get videoLocked => hasVideo && !videoOpen;

  /// A PDF exists but is locked.
  bool get pdfLocked => hasPdf && !pdfOpen;

  /// Something in the chapter needs an activation code.
  bool get needsActivation => viewsExhausted || videoLocked || pdfLocked;

  /// The chapter should render as a PDF item (no video at all).
  bool get isPdfOnly => !hasVideo && hasPdf;
}

/// Summarises [chapter] access using the web's `ChapterRow` rules.
ChapterAccessSummary summarizeChapterAccess(
  dynamic chapter, {
  required bool courseLocked,
}) {
  final exhausted = chapterViewsExhausted(chapter);
  final hasVideo = chapterHasVideo(chapter, courseLocked: courseLocked);
  final hasPdf = chapterHasPdfAttachment(chapter);
  final videoPlayable =
      isChapterVideoPlayable(chapter, courseLocked: courseLocked) &&
          !chapterVideoRequiresActivation(chapter, courseLocked: courseLocked);
  final pdfVisible = isChapterPdfVisible(chapter, courseLocked: courseLocked) &&
      !chapterPdfRequiresActivation(chapter, courseLocked: courseLocked);
  return ChapterAccessSummary(
    hasVideo: hasVideo,
    hasPdf: hasPdf,
    videoOpen: !exhausted && hasVideo && videoPlayable,
    pdfOpen: !exhausted && hasPdf && pdfVisible,
    viewsExhausted: exhausted,
    fullyUnlocked: isChapterFullyUnlocked(chapter, courseLocked: courseLocked),
  );
}

/// True when the chapter is PDF-only: no video anywhere, but a PDF/attachment attached.
///
/// The web hides the watch button for these; the app opens the PDF reviewer
/// directly instead of a player with nothing to play. A locked chapter whose
/// stream URLs were withheld is **not** PDF-only when its `duration` shows a
/// video exists (see [chapterHasVideo]). [courseLocked] defaults to `true`,
/// the safe direction, for callers that do not know the course state.
bool chapterIsPdfOnly(dynamic chapter, {bool courseLocked = true}) {
  if (chapterHasVideo(chapter, courseLocked: courseLocked)) return false;
  if (chapterHasPdfAttachment(chapter)) return true;
  final attrs = chapterAttributes(chapter);
  final raw = attrs['attachments'];
  if (raw is List && raw.isNotEmpty) return true;
  if (raw is Map && raw['data'] is List && (raw['data'] as List).isNotEmpty) return true;
  return false;
}

/// Whether a chapter's `schedule` (release time) has passed.
///
/// Port of the web's `LecturesTab` filter: a chapter with no schedule, or an
/// unparseable one, is visible; a chapter scheduled in the future is hidden
/// until its release time. The API sends `YYYY-MM-DD HH:mm:ss` in local time.
bool isChapterScheduleReleased(dynamic chapter, {DateTime? now}) {
  final raw = coerceString(chapterAttributes(chapter)['schedule'])?.trim();
  if (raw == null || raw.isEmpty) return true;
  final parsed = DateTime.tryParse(raw.replaceFirst(' ', 'T'));
  if (parsed == null) return true;
  return !parsed.isAfter(now ?? DateTime.now());
}

/// The chapters a student sees under a lecture in the "Lectures & PDF" tab:
/// the lecture's own `chapters` in API order, minus those not yet released.
///
/// Exams and live rooms are separate course attributes (`exams`,
/// `live_rooms`) and never belong in this list.
List<dynamic> studentVisibleChapters(dynamic lecture, {DateTime? now}) {
  if (lecture is! Map) return const [];
  final attrs = lecture['attributes'] is Map
      ? lecture['attributes'] as Map
      : (lecture['data'] is Map && (lecture['data'] as Map)['attributes'] is Map
          ? (lecture['data'] as Map)['attributes'] as Map
          : lecture);
  final raw = attrs['chapters'];
  final list = raw is List
      ? raw
      : raw is Map && raw['data'] is List
          ? raw['data'] as List
          : const [];
  final reference = now ?? DateTime.now();
  return list
      .where((ch) => ch is Map && isChapterScheduleReleased(ch, now: reference))
      .toList();
}

/// Course lectures sorted by `attributes.order` ascending (missing = 0), the
/// same ordering as the web's `sortedLectures`. The sort is stable so lectures
/// sharing an order keep their API order.
List<dynamic> studentSortedLectures(dynamic rawLectures) {
  if (rawLectures is! List) return const [];
  int orderOf(Map lecture) {
    final attrs = lecture['attributes'] is Map
        ? lecture['attributes'] as Map
        : lecture;
    return coerceInt(attrs['order']);
  }

  final entries = <(int, Map)>[];
  for (final lecture in rawLectures) {
    if (lecture is Map) entries.add((entries.length, lecture));
  }
  entries.sort((a, b) {
    final byOrder = orderOf(a.$2).compareTo(orderOf(b.$2));
    return byOrder != 0 ? byOrder : a.$1.compareTo(b.$1);
  });
  return entries.map((e) => e.$2).toList();
}
