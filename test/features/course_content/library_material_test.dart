import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learnoo/core/models/watermark_config.dart';
import 'package:learnoo/core/services/device_downloads.dart';
import 'package:learnoo/core/services/library_pdf_watermark.dart';
import 'package:learnoo/core/services/notification_service.dart';
import 'package:learnoo/features/course_content/domain/library_material.dart';
import 'package:learnoo/features/course_content/services/library_download_service.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

WatermarkConfig config({
  bool enabled = true,
  String text = 'Learnoo',
  bool useStudentCode = false,
  bool usePhoneNumber = false,
}) {
  return WatermarkConfig(
    enabled: enabled,
    text: text,
    useStudentCode: useStudentCode,
    usePhoneNumber: usePhoneNumber,
    position: WatermarkPosition.full,
    opacity: 0.3,
    rotation: 0,
    size: 'medium',
    dynamicPosition: false,
    dynamicInterval: 2,
    randomCoordinates: false,
    animationStyle: WatermarkAnimationStyle.glide,
    easingType: WatermarkEasingType.easeInOut,
    voiceEnabled: false,
    voiceInterval: 5,
    color: Colors.black,
  );
}

Map<String, dynamic> material({
  Object? codeActivation = false,
  Object? isLocked = false,
  Object? isPublish = true,
  List<Map<String, dynamic>> attachments = const [],
}) {
  return {
    'id': '17',
    'attributes': {
      'title': 'Anatomy Booklet',
      'description': 'Chapter one notes',
      'material_type': 'booklet',
      'course_ids': [240, 12],
      'price': '150',
      'code_activation': codeActivation,
      'is_locked': isLocked,
      'is_publish': isPublish,
      'attachments': attachments,
    },
  };
}

Map<String, dynamic> attachment({
  Object? downloadable = true,
  String path = 'https://api.learnoo.app/storage/book.pdf',
  String extension = 'pdf',
}) {
  return {
    'id': '3',
    'attributes': {
      'name': 'book.pdf',
      'path': path,
      'extension': extension,
      'size': '2048',
      'downloadable': downloadable,
    },
  };
}

void main() {
  group('lock follows code_activation, like the website', () {
    test('code_activation true locks even when is_locked is false', () {
      expect(libraryIsLocked(material(codeActivation: true)), isTrue);
    });

    test('is_locked alone no longer locks', () {
      expect(libraryIsLocked(material(isLocked: true)), isFalse);
    });

    test('the API forms 1 and "1" lock too', () {
      expect(libraryIsLocked(material(codeActivation: 1)), isTrue);
      expect(libraryIsLocked(material(codeActivation: '1')), isTrue);
    });
  });

  group('published filter', () {
    test('only an explicit false hides a material', () {
      expect(libraryIsPublished(material(isPublish: false)), isFalse);
      expect(libraryIsPublished(material(isPublish: 0)), isFalse);
      expect(libraryIsPublished(material(isPublish: null)), isTrue);
    });
  });

  group('downloadable', () {
    test('only an explicit true allows download', () {
      expect(attachmentIsDownloadable(attachment(downloadable: true)), isTrue);
      expect(attachmentIsDownloadable(attachment(downloadable: 1)), isTrue);
      expect(attachmentIsDownloadable(attachment(downloadable: false)), isFalse);
      expect(attachmentIsDownloadable(attachment(downloadable: null)), isFalse);
    });

    test('canDownload requires unlocked, a path and the downloadable flag', () {
      final open = material(attachments: [attachment()]);
      expect(LibraryDownloadService.canDownload(open, attachment()), isTrue);

      final locked = material(codeActivation: true);
      expect(LibraryDownloadService.canDownload(locked, attachment()), isFalse);

      expect(
        LibraryDownloadService.canDownload(
          open,
          attachment(downloadable: false),
        ),
        isFalse,
      );
      expect(
        LibraryDownloadService.canDownload(open, attachment(path: '')),
        isFalse,
      );
      expect(LibraryDownloadService.canDownload(open, null), isFalse);
    });
  });

  group('saving to the device', () {
    test('file name keeps Arabic letters and the extension', () {
      expect(
        LibraryDownloadService.fileNameFor(material(), attachment()),
        'book.pdf',
      );
      final arabic = {
        'attributes': {'name': 'ملزمة الفصل الأول.pdf', 'extension': 'pdf'},
      };
      expect(
        LibraryDownloadService.fileNameFor(material(), arabic),
        'ملزمة_الفصل_الأول.pdf',
      );
    });

    test('mime types match what the system viewer expects', () {
      expect(DeviceDownloads.mimeTypeFor('PDF'), 'application/pdf');
      expect(DeviceDownloads.mimeTypeFor('jpg'), 'image/jpeg');
      expect(DeviceDownloads.mimeTypeFor('weird'), 'application/octet-stream');
    });

    test('completion notification payload carries the saved file', () {
      const saved = SavedDownload(
        uri: 'content://media/external/downloads/42',
        fileName: 'book.pdf',
        mimeType: 'application/pdf',
      );
      expect(
        NotificationService.openDownloadPayload(saved),
        'open_download|application/pdf|content://media/external/downloads/42',
      );
    });
  });

  group('labels and search', () {
    test('course ids, price and size format like the website', () {
      final m = material();
      expect(libraryCourseIdsLabel(m), '240, 12');
      expect(libraryPriceLabel(m), '150.00');
      expect(formatLibraryAttachmentSize('2048'), '2.0 KB');
      expect(formatLibraryAttachmentSize('512'), '512 B');
      expect(formatLibraryAttachmentSize('x'), '—');
    });

    test('search covers title, description, course ids and type', () {
      final m = material();
      expect(libraryMatchesSearch(m, 'anatomy'), isTrue);
      expect(libraryMatchesSearch(m, 'chapter one'), isTrue);
      expect(libraryMatchesSearch(m, '240'), isTrue);
      expect(libraryMatchesSearch(m, 'booklet'), isTrue);
      expect(libraryMatchesSearch(m, 'physics'), isFalse);
      expect(libraryMatchesSearch(m, '   '), isTrue);
    });
  });

  group('download watermark text mirrors server-pdf-watermark.ts', () {
    test('code and phone joined with a middle dot', () {
      expect(
        buildDownloadWatermarkText(
          config: config(useStudentCode: true, usePhoneNumber: true),
          studentCode: 'STU-9',
          phone: '201001234567',
        ),
        'STU-9 · 201001234567',
      );
    });

    test('static text when neither toggle applies, code appended', () {
      expect(
        buildDownloadWatermarkText(
          config: config(text: 'Learnoo'),
          studentCode: 'STU-9',
          phone: '2010',
        ),
        'Learnoo · STU-9',
      );
    });

    test('phone only still appends the code for traceability', () {
      expect(
        buildDownloadWatermarkText(
          config: config(usePhoneNumber: true),
          studentCode: 'STU-9',
          phone: '2010',
        ),
        '2010 · STU-9',
      );
    });

    test('no code available leaves the static text alone', () {
      expect(
        buildDownloadWatermarkText(config: config(text: 'Learnoo')),
        'Learnoo',
      );
    });
  });

  group('LibraryPdfWatermarker', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('library_wm_test');
    });

    tearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    Future<File> makePdf(int pages) async {
      final document = PdfDocument();
      for (var i = 0; i < pages; i++) {
        document.pages.add().graphics.drawString(
              'Original page ${i + 1}',
              PdfStandardFont(PdfFontFamily.helvetica, 14),
              bounds: const Rect.fromLTWH(20, 20, 300, 40),
            );
      }
      final file = File('${dir.path}/source.pdf');
      await file.writeAsBytes(await document.save());
      document.dispose();
      return file;
    }

    test('stamps the text on every page and keeps the page count', () async {
      final source = await makePdf(3);
      final destination = File('${dir.path}/out.pdf');

      await const LibraryPdfWatermarker().apply(
        source: source,
        destination: destination,
        text: 'STU-9 · 201001234567',
        config: config(),
      );

      final result = PdfDocument(inputBytes: await destination.readAsBytes());
      try {
        expect(result.pages.count, 3);
        final extractor = PdfTextExtractor(result);
        for (var i = 0; i < 3; i++) {
          final text = extractor.extractText(startPageIndex: i, endPageIndex: i);
          expect(text, contains('STU-9'), reason: 'page ${i + 1} watermark');
          expect(text, contains('Original page ${i + 1}'),
              reason: 'page ${i + 1} content kept');
        }
      } finally {
        result.dispose();
      }
    });

    test('draws 12 copies per page, the website grid', () async {
      final source = await makePdf(1);
      final destination = File('${dir.path}/grid.pdf');

      await const LibraryPdfWatermarker().apply(
        source: source,
        destination: destination,
        text: 'GRIDMARK',
        config: config(),
      );

      final result = PdfDocument(inputBytes: await destination.readAsBytes());
      try {
        final text = PdfTextExtractor(result).extractText();
        expect('GRIDMARK'.allMatches(text).length, 12);
      } finally {
        result.dispose();
      }
    });

    test('non-Latin admin text falls back to the drawable part', () async {
      final source = await makePdf(1);
      final destination = File('${dir.path}/arabic.pdf');

      await const LibraryPdfWatermarker().apply(
        source: source,
        destination: destination,
        text: 'ليرنو · STU-9',
        config: config(),
      );

      final result = PdfDocument(inputBytes: await destination.readAsBytes());
      try {
        expect(PdfTextExtractor(result).extractText(), contains('STU-9'));
      } finally {
        result.dispose();
      }
    });

    test('a file that is not a PDF is rejected, never passed through',
        () async {
      final source = File('${dir.path}/fake.pdf');
      await source.writeAsString('not a pdf');
      final destination = File('${dir.path}/never.pdf');

      await expectLater(
        const LibraryPdfWatermarker().apply(
          source: source,
          destination: destination,
          text: 'STU-9',
          config: config(),
        ),
        throwsA(anything),
      );
      expect(await destination.exists(), isFalse);
    });
  });
}
