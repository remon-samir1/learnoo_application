import 'package:flutter_test/flutter_test.dart';
import 'package:learnoo/features/course_content/domain/chapter_access.dart';

/// Chapter record shaped like the course payload's `lectures[].chapters[]`.
Map<String, dynamic> chapter({
  Object? isActivated,
  Object? isFreePreview,
  Object? isFreePreviewAttachment,
  Object? canWatch,
  Object? isLocked = true,
  String? video,
  String? duration,
  bool withPdf = false,
  Object? maxViews,
  Object? currentViews,
}) {
  return {
    'id': '7',
    'attributes': {
      'title': 'Part',
      'is_locked': ?isLocked,
      'is_activated': ?isActivated,
      'is_free_preview': ?isFreePreview,
      'is_free_preview_attachment': ?isFreePreviewAttachment,
      'can_watch': ?canWatch,
      'video': video ?? 'https://api.learnoo.app/storage',
      'duration': ?duration,
      'max_views': ?maxViews,
      'current_user_views': ?currentViews,
      'attachments': withPdf
          ? [
              {
                'id': '1',
                'attributes': {
                  'name': 'file 1',
                  'extension': 'pdf',
                  'path': '/storage/chapters/file1.pdf',
                  // The API marks the attachment locked too; the web ignores it.
                  'is_locked': true,
                },
              },
            ]
          : <dynamic>[],
    },
  };
}

void main() {
  group('coercePreviewFlag (port of the web helper)', () {
    test('explicit forms', () {
      for (final v in [true, 1, '1', 'true', 'TRUE', ' yes ']) {
        expect(coercePreviewFlag(v), isTrue, reason: '$v');
      }
      for (final v in [false, 0, '0', 'false', 'no', '', null]) {
        expect(coercePreviewFlag(v), isFalse, reason: '$v');
      }
    });

    test('falls back to JavaScript Boolean()', () {
      expect(coercePreviewFlag(2), isTrue);
      expect(coercePreviewFlag('on'), isTrue);
      expect(coercePreviewFlag(double.nan), isFalse);
    });
  });

  group('web rule: preview flags are independent', () {
    test('is_free_preview unlocks the video only', () {
      final ch = chapter(isFreePreview: 1);
      expect(isChapterVideoPlayable(ch, courseLocked: true), isTrue);
      expect(chapterVideoRequiresActivation(ch, courseLocked: true), isFalse);
      expect(isChapterPdfVisible(ch, courseLocked: true), isFalse);
      expect(chapterPdfRequiresActivation(ch, courseLocked: true), isTrue);
    });

    test('is_free_preview_attachment unlocks the PDF only', () {
      final ch = chapter(isFreePreviewAttachment: '1');
      expect(isChapterVideoPlayable(ch, courseLocked: true), isFalse);
      expect(isChapterPdfVisible(ch, courseLocked: true), isTrue);
      expect(chapterPdfRequiresActivation(ch, courseLocked: true), isFalse);
    });

    test('activation or an unlocked course unlocks both', () {
      final activated = chapter(isActivated: true);
      expect(isChapterVideoPlayable(activated, courseLocked: true), isTrue);
      expect(isChapterPdfVisible(activated, courseLocked: true), isTrue);

      final inUnlockedCourse = chapter();
      expect(
        isChapterVideoPlayable(inUnlockedCourse, courseLocked: false),
        isTrue,
      );
      expect(isChapterPdfVisible(inUnlockedCourse, courseLocked: false), isTrue);
    });

    test('is_locked on its own never decides', () {
      final ch = chapter(isLocked: false);
      expect(isChapterFullyUnlocked(ch, courseLocked: true), isFalse);
      expect(isChapterPdfVisible(ch, courseLocked: true), isFalse);
    });

    test('can_watch only counts when explicitly true', () {
      expect(
        isChapterVideoPlayable(chapter(canWatch: 'true'), courseLocked: true),
        isTrue,
      );
      expect(
        isChapterVideoPlayable(chapter(canWatch: 'yes'), courseLocked: true),
        isFalse,
      );
    });
  });

  group('client cases (#9 / #19)', () {
    test('(a) video + PDF both locked: listed as video + PDF, both locked', () {
      // The API withholds the stream URL, but the duration shows a video.
      final ch = chapter(duration: '03:27', withPdf: true);
      final access = summarizeChapterAccess(ch, courseLocked: true);
      expect(access.hasVideo, isTrue);
      expect(access.hasPdf, isTrue);
      expect(access.isPdfOnly, isFalse);
      expect(access.videoLocked, isTrue);
      expect(access.pdfLocked, isTrue);
      expect(access.needsActivation, isTrue);
      expect(chapterIsPdfOnly(ch, courseLocked: true), isFalse);
    });

    test('(b) PDF-only chapter with a free PDF opens', () {
      final ch = chapter(isFreePreviewAttachment: true, withPdf: true);
      final access = summarizeChapterAccess(ch, courseLocked: true);
      expect(access.isPdfOnly, isTrue);
      expect(access.pdfOpen, isTrue);
      expect(access.needsActivation, isFalse);
      expect(canOpenChapterPdf(ch, courseLocked: true), isTrue);
    });

    test('(c) locked video + free PDF: PDF opens, video stays locked', () {
      final ch = chapter(
        isFreePreviewAttachment: 1,
        duration: '1:02:03',
        withPdf: true,
      );
      final access = summarizeChapterAccess(ch, courseLocked: true);
      expect(access.hasVideo, isTrue);
      expect(access.videoOpen, isFalse);
      expect(access.pdfOpen, isTrue);
      expect(access.needsActivation, isTrue);
    });

    test('free video + locked PDF', () {
      final ch = chapter(
        isFreePreview: true,
        video: 'https://api.learnoo.app/storage/v.mp4',
        withPdf: true,
      );
      final access = summarizeChapterAccess(ch, courseLocked: true);
      expect(access.videoOpen, isTrue);
      expect(access.pdfOpen, isFalse);
    });

    test('views exhausted blocks both, like the web re-activate branch', () {
      final ch = chapter(
        isActivated: true,
        withPdf: true,
        maxViews: '3',
        currentViews: 3,
      );
      final access = summarizeChapterAccess(ch, courseLocked: true);
      expect(access.viewsExhausted, isTrue);
      expect(access.videoOpen, isFalse);
      expect(access.pdfOpen, isFalse);
      expect(canOpenChapterPdf(ch, courseLocked: true), isFalse);
    });
  });

  group('chapterHasVideo', () {
    test('a playable chapter without a URL has no video', () {
      final ch = chapter(isActivated: true, duration: '05:00', withPdf: true);
      expect(chapterHasVideo(ch, courseLocked: true), isFalse);
      expect(chapterIsPdfOnly(ch, courseLocked: true), isTrue);
    });

    test('a locked chapter with a zero / missing duration is PDF-only', () {
      for (final d in [null, '', '00:00', '0', '--:--']) {
        final ch = chapter(duration: d, withPdf: true);
        expect(chapterHasVideo(ch, courseLocked: true), isFalse, reason: d);
      }
    });

    test('a real stream URL always counts', () {
      final ch = chapter(video: '/storage/chapters/v.mp4');
      expect(chapterHasVideo(ch, courseLocked: false), isTrue);
    });
  });

  test('chapterDurationSeconds parses the dashboard formats', () {
    expect(chapterDurationSeconds(chapter(duration: '3:27')), 207);
    expect(chapterDurationSeconds(chapter(duration: '01:00:05')), 3605);
    expect(chapterDurationSeconds(chapter(duration: '90')), 90);
    expect(chapterDurationSeconds(chapter(duration: 'abc')), 0);
  });

  test('chapterFirstPdfPath mirrors getFirstPdfUrl', () {
    expect(
      chapterFirstPdfPath(chapter(withPdf: true)),
      '/storage/chapters/file1.pdf',
    );
    expect(chapterFirstPdfPath(chapter()), isNull);
  });

  group('canOpenChapterPdfFlags', () {
    test('free attachment on a locked course opens', () {
      expect(
        canOpenChapterPdfFlags(
          courseLocked: true,
          chapterIsActivated: false,
          chapterIsFreePreviewAttachment: true,
        ),
        isTrue,
      );
    });

    test('maxViews 0 means unlimited', () {
      expect(
        canOpenChapterPdfFlags(
          courseLocked: false,
          chapterIsActivated: false,
          chapterIsFreePreviewAttachment: false,
          currentViews: 10,
        ),
        isTrue,
      );
    });

    test('locked course, nothing free, is blocked', () {
      expect(
        canOpenChapterPdfFlags(
          courseLocked: true,
          chapterIsActivated: false,
          chapterIsFreePreviewAttachment: false,
        ),
        isFalse,
      );
    });
  });
}
