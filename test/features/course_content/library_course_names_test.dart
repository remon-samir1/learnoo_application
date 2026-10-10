import 'package:flutter_test/flutter_test.dart';
import 'package:learnoo/features/course_content/domain/library_material.dart';

void main() {
  test('resolves multiple course IDs to names without displaying IDs', () {
    final book = {'attributes': {'course_ids': [174, 240]}};
    expect(libraryCourseNamesLabel(book, resolvedNames: {'174': 'Accounting', '240': 'Finance'}), 'Accounting، Finance');
    expect(libraryCourseNamesLabel(book), isEmpty);
  });
  test('uses embedded course names and removes duplicate names', () {
    final book = {'attributes': {
      'course_ids': [174, 240],
      'courses': {'data': [
        {'id': '174', 'attributes': {'title': 'Accounting'}},
        {'id': '240', 'attributes': {'title': 'Finance'}},
      ]},
      'course': {'data': {'id': '174', 'attributes': {'title': 'Accounting'}}},
    }};
    expect(libraryCourseNamesLabel(book, resolvedNames: {'174': 'Old name'}), 'Accounting، Finance');
  });
  test('supports a bare course relation', () {
    expect(libraryCourseNamesLabel({'course': {'id': 1, 'title': 'Math'}}), 'Math');
  });
}
