import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:learnoo/features/course_content/presentation/widgets/pdf_navigation_bar.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('PdfNavigationBar tap page prompt', (tester) async {
    final controller = PdfViewerController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PdfNavigationBar(
            controller: controller,
            currentPage: 2,
            pageCount: 10,
          ),
        ),
      ),
    );

    // Find the page text: 'pdf.page_of'
    final pageFinder = find.text('pdf.page_of');
    expect(pageFinder, findsOneWidget);

    await tester.tap(pageFinder);
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);

    // Enter a number
    await tester.enterText(find.byType(TextField), '5');
    await tester.tap(find.text('pdf.go'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
  });
}
