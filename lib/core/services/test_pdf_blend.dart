import 'package:syncfusion_flutter_pdf/pdf.dart';
void main() {
  final document = PdfDocument();
  final page = document.pages.add();
  page.graphics.setTransparency(0.5, mode: PdfBlendMode.multiply);
  print('success');
}
