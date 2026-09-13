import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:learnoo/features/category_tree/data/models/category_tree_model.dart';
import 'package:learnoo/features/category_tree/presentation/widgets/category_card.dart';
import 'package:learnoo/features/category_tree/presentation/widgets/course_card.dart';

void main() {
  group('CategoryCard & CourseCard Widget Tests', () {
    testWidgets('CategoryCard renders category name and counts', (tester) async {
      const category = Category(
        id: '123',
        name: 'Computer Engineering',
        stats: CategoryStats(coursesCount: 5, studentsCount: 140),
      );

      bool tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CategoryCard(
              category: category,
              onTap: () => tapped = true,
            ),
          ),
        ),
      );

      expect(find.text('Computer Engineering'), findsOneWidget);
      expect(find.text('5 Courses'), findsOneWidget);
      expect(find.text('140'), findsOneWidget);

      await tester.tap(find.byType(CategoryCard));
      expect(tapped, isTrue);
    });

    testWidgets('CourseCard renders course info, lock badge when locked, and triggers callbacks', (tester) async {
      const lockedCourse = CourseItem(
        id: 'c1',
        title: 'Microprocessors & Embedded Systems',
        subTitle: 'Hardware Architecture and Assembly',
        isLocked: true,
        stats: CourseStats(lecturesCount: 12, notesCount: 4, studentsCount: 85),
      );

      bool tapCalled = false;
      bool activateCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CourseCard(
              course: lockedCourse,
              onTap: () => tapCalled = true,
              onActivate: () => activateCalled = true,
            ),
          ),
        ),
      );

      expect(find.text('Microprocessors & Embedded Systems'), findsNWidgets(2));
      expect(find.text('Hardware Architecture and Assembly'), findsOneWidget);
      expect(find.text('12 Lectures'), findsOneWidget);
      expect(find.text('4 Notes'), findsOneWidget);
      expect(find.text('Course Details'), findsOneWidget);
      expect(find.text('Unlock'), findsOneWidget);

      // Tapping Course Details triggers onTap
      await tester.tap(find.text('Course Details'));
      expect(tapCalled, isTrue);

      // Tapping Unlock triggers onActivate
      await tester.tap(find.text('Unlock'));
      expect(activateCalled, isTrue);
    });
  });
}
