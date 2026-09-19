import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learnoo/core/utils/media_url.dart';
import 'package:learnoo/core/widgets/cover_image.dart';

void main() {
  group('resolveMediaUrl', () {
    test('absolute URLs pass through', () {
      expect(
        resolveMediaUrl('https://api.learnoo.app/storage/courses/a.png'),
        'https://api.learnoo.app/storage/courses/a.png',
      );
    });

    test('server-relative paths get the API origin', () {
      expect(
        resolveMediaUrl('/storage/categories/b.jpg'),
        'https://api.learnoo.app/storage/categories/b.jpg',
      );
      expect(
        resolveMediaUrl('storage/categories/b.jpg'),
        'https://api.learnoo.app/storage/categories/b.jpg',
      );
    });

    test('empty, "null" and missing values mean no image', () {
      expect(resolveMediaUrl(null), isNull);
      expect(resolveMediaUrl(''), isNull);
      expect(resolveMediaUrl('  '), isNull);
      expect(resolveMediaUrl('null'), isNull);
    });

    test('objects and lists are unwrapped', () {
      expect(
        resolveMediaUrl({'url': '/storage/x.png'}),
        'https://api.learnoo.app/storage/x.png',
      );
      expect(
        resolveMediaUrl([null, '', '/storage/y.png']),
        'https://api.learnoo.app/storage/y.png',
      );
    });

    test('readMediaUrl takes the first usable key', () {
      expect(
        readMediaUrl(
          {'thumbnail': 'null', 'image': '/storage/z.png'},
          const ['thumbnail', 'image'],
        ),
        'https://api.learnoo.app/storage/z.png',
      );
    });
  });

  test('fallback gradient matches the website hash', () {
    // Indices computed with the website's getGradientStyle.
    expect(CoverImage.gradientFor('Anatomy'), CoverImage.gradients[3]);
    expect(CoverImage.gradientFor('كورس تجربة'), CoverImage.gradients[6]);
    expect(CoverImage.gradientFor('Physics 101'), CoverImage.gradients[1]);
  });

  testWidgets('no image shows the gradient with the title', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 240,
            height: 160,
            child: CoverImage(url: 'null', title: 'Anatomy', height: 160),
          ),
        ),
      ),
    );
    expect(find.text('Anatomy'), findsOneWidget);
    expect(find.byIcon(Icons.school_rounded), findsOneWidget);
  });
}
