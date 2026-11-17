import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learnoo/core/services/share_link_service.dart';

void main() {
  group('ShareLinkTarget.parse', () {
    ShareLinkTarget? parse(String url) => ShareLinkTarget.parse(Uri.parse(url));

    test('reads the exam and live session links copied from the dashboard', () {
      expect(parse('https://learnoo.app/ar/student/exams/start-exam/42'), const ExamLinkTarget('42'));
      expect(parse('https://learnoo.app/en/student/exams/start-exam/42?course=3'), const ExamLinkTarget('42'));
      expect(parse('https://learnoo.app/ar/student/live-sessions/7'), const LiveSessionLinkTarget('7'));
      expect(parse('https://learnoo.app/en/student/live-sessions/7/'), const LiveSessionLinkTarget('7'));
      expect(parse('https://www.learnoo.app/ar/student/live-sessions/7'), const LiveSessionLinkTarget('7'));
    });

    test('ignores anything else', () {
      for (final url in [
        'https://evil.example/ar/student/exams/start-exam/42',
        'https://learnoo.app/ar/student/exams',
        'https://learnoo.app/ar/student/live-sessions',
        'https://learnoo.app/fr/student/live-sessions/7',
        'https://learnoo.app/ar/student/exams/start-exam/abc',
        'https://learnoo.app/ar/student/exams/take/42',
        'https://learnoo.app/ar/student/live-sessions/7/room',
        'learnoo://ar/student/live-sessions/7',
      ]) {
        expect(parse(url), isNull, reason: url);
      }
    });
  });

  group('ShareLinkService', () {
    late List<ShareLinkTarget> opened;
    late ShareLinkService service;

    setUp(() {
      opened = [];
      service = ShareLinkService.test(open: (_, target) async => opened.add(target));
    });

    Future<BuildContext> home(WidgetTester tester) async {
      late BuildContext context;
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (c) {
        context = c;
        return const SizedBox();
      })));
      return context;
    }

    testWidgets('a link that started the app (or came before sign-in) waits for the home screen',
        (tester) async {
      service.receive(Uri.parse('https://learnoo.app/ar/student/exams/start-exam/42'));
      expect(opened, isEmpty);
      expect(service.pending, const ExamLinkTarget('42'));

      service.attachHome(await home(tester));
      expect(opened, [const ExamLinkTarget('42')]);
      expect(service.pending, isNull);
    });

    testWidgets('a link that arrives while the home screen shows opens at once, only once',
        (tester) async {
      final context = await home(tester);
      service.attachHome(context);
      service.receive(Uri.parse('https://learnoo.app/en/student/live-sessions/7'));
      service.attachHome(context);
      expect(opened, [const LiveSessionLinkTarget('7')]);
    });

    testWidgets('after the home screen leaves (signed out) the next link waits again', (tester) async {
      final context = await home(tester);
      service.attachHome(context);
      service.detachHome(context);
      service.receive(Uri.parse('https://learnoo.app/ar/student/live-sessions/7'));
      expect(opened, isEmpty);
      expect(service.pending, const LiveSessionLinkTarget('7'));
    });

    testWidgets('other links are left alone', (tester) async {
      service.attachHome(await home(tester));
      service.receive(Uri.parse('https://learnoo.app/ar/student/courses'));
      expect(opened, isEmpty);
      expect(service.pending, isNull);
    });
  });
}
