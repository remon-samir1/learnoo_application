import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learnoo/features/community/data/comment_order.dart';
import 'package:learnoo/features/community/data/models/post_model.dart';
import 'package:learnoo/features/community/data/repositories/community_repository.dart';
import 'package:learnoo/features/community/presentation/widgets/post_comments_section.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Doctor's list, platform point 10 (14 Nov): the doctor's answer to Marwa's
/// question showed above her comment. Comments under a post read oldest
/// first, and a new one lands at the end without the list jumping.
Post comment(String id, String content, String createdAt, {String parentId = '90'}) =>
    Post.fromJson({
      'id': id,
      'type': 'posts',
      'attributes': {
        'content': content,
        'title': content,
        'status': 'published',
        'type': 'post',
        'parent_id': int.parse(parentId),
        'created_at': createdAt,
        'user': {
          'data': {
            'id': 'u$id',
            'attributes': {'full_name': 'Author $id', 'role': 'Student'},
          },
        },
      },
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('commentsOldestFirst', () {
    test("the doctor's answer sits under the question even when sent first", () {
      final rows = [
        comment('41', 'answer', '2026-11-13T10:00:00+02:00'),
        comment('40', 'question', '2026-11-12T10:00:00+02:00'),
      ];
      expect(commentsOldestFirst(rows, '90').map((c) => c.id), ['40', '41']);
    });

    test('same-second comments keep the order they were saved in, by id', () {
      final rows = [
        comment('12', 'b', '2026-11-14T10:00:00Z'),
        comment('9', 'a', '2026-11-14T10:00:00Z'),
        comment('3', 'first', '2026-11-12T08:00:00Z'),
        comment('100', 'c', '2026-11-14T10:00:00Z'),
      ];
      expect(commentsOldestFirst(rows, '90').map((c) => c.id), ['3', '9', '12', '100']);
    });

    test('time zones are compared as instants', () {
      final rows = [
        comment('2', 'utc nine', '2026-11-14T09:00:00Z'),
        comment('1', 'cairo ten', '2026-11-14T10:00:00+02:00'),
      ];
      expect(commentsOldestFirst(rows, '90').map((c) => c.id), ['1', '2']);
    });

    test('rows of another post are dropped', () {
      final rows = [
        comment('1', 'mine', '2026-11-14T09:00:00Z'),
        comment('2', 'other', '2026-11-14T08:00:00Z', parentId: '91'),
      ];
      expect(commentsOldestFirst(rows, '90').map((c) => c.id), ['1']);
    });
  });

  testWidgets('comments read oldest first and a new one lands last without a spinner', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = _FakeRepository([
      // Newest first, as the old backend sent them.
      comment('43', 'LATER', '2026-11-14T09:00:00Z'),
      comment('41', 'ANSWER', '2026-11-13T10:00:00Z'),
      comment('40', 'QUESTION', '2026-11-12T10:00:00Z'),
    ]);
    final post = Post.fromJson({
      'id': '90',
      'type': 'posts',
      'attributes': {
        'content': 'News',
        'title': 'News',
        'status': 'published',
        'comments_count': 3,
        'created_at': '2026-11-11T10:00:00Z',
      },
    });

    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en'), Locale('ar')],
        startLocale: const Locale('ar'),
        saveLocale: false,
        path: 'assets/translations',
        assetLoader: const _TestTranslations(),
        child: Builder(
          builder: (context) => MaterialApp(
            locale: context.locale,
            supportedLocales: context.supportedLocales,
            localizationsDelegates: context.localizationDelegates,
            home: Scaffold(
              body: SingleChildScrollView(
                child: PostCommentsSection(
                  post: post,
                  currentUserId: 'u1',
                  repository: repository,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.chat_bubble_outline));
    await tester.pumpAndSettle();

    double y(String text) => tester.getTopLeft(find.text(text)).dy;
    expect(y('QUESTION'), lessThan(y('ANSWER')));
    expect(y('ANSWER'), lessThan(y('LATER')));

    // Post a comment; hold the reload open to look at the list meanwhile.
    repository.holdNextLoad();
    await tester.enterText(find.byType(TextField), 'THANKS');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();
    await tester.pump();

    expect(find.text('QUESTION'), findsOneWidget, reason: 'list stays while reloading');
    expect(find.text('LATER'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    repository.releaseLoad();
    await tester.pumpAndSettle();

    expect(find.text('THANKS'), findsOneWidget);
    expect(y('LATER'), lessThan(y('THANKS')), reason: 'the new comment lands last');
    expect(y('QUESTION'), lessThan(y('ANSWER')));
  });
}

class _FakeRepository extends CommunityRepository {
  _FakeRepository(this._rows);

  final List<Post> _rows;
  Completer<void>? _hold;

  void holdNextLoad() => _hold = Completer<void>();
  void releaseLoad() => _hold?.complete();

  @override
  Future<Map<String, dynamic>> getComments(String postId) async {
    final hold = _hold;
    if (hold != null) {
      await hold.future;
      _hold = null;
    }
    return {'success': true, 'data': List<Post>.of(_rows)};
  }

  @override
  Future<Map<String, dynamic>> addComment({
    required String postId,
    required String content,
  }) async {
    _rows.insert(0, comment('44', content, '2026-11-15T09:00:00Z'));
    return {'success': true};
  }
}

class _TestTranslations extends AssetLoader {
  const _TestTranslations();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async {
    return jsonDecode(
          File('$path/${locale.languageCode}.json').readAsStringSync(),
        )
        as Map<String, dynamic>;
  }
}
