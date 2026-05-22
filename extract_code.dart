import 'dart:io';
import 'dart:convert';

void main() async {
  // Read the kernel blob
  final file = File('apk_extracted/app_debug/assets/flutter_assets/kernel_blob.bin');
  final bytes = await file.readAsBytes();
  
  // Decode as UTF-8, ignoring errors
  final content = utf8.decode(bytes, allowMalformed: true);
  
  // Extract class definitions, method signatures, and imports
  final patterns = [
    RegExp(r'class\s+\w+\s*(?:extends\s+\w+)?\s*(?:implements\s+[\w,\s]+)?\s*\{[^}]*\}'),
    RegExp(r'(?:String|int|double|bool|void|Future|List|Map|Widget)\s+\w+\s*\([^)]*\)\s*(?:async\s*)?[\{;]'),
    RegExp(r'''import\s+['"]\s*[^'"]+['"];'''),
    RegExp(r'@override'),
  ];
  
  final allMatches = <String>{};
  for (final pattern in patterns) {
    final matches = pattern.allMatches(content);
    for (final match in matches) {
      final text = match.group(0);
      if (text != null && text.length > 20 && text.length < 1000) {
        allMatches.add(text);
      }
    }
  }
  
  final sorted = allMatches.toList()..sort();
  print('Found ${sorted.length} code snippets');
  
  final output = File('restored/extracted_code_snippets.txt');
  await output.writeAsString(sorted.join('\n\n---\n\n'));
  print('Saved to restored/extracted_code_snippets.txt');
}
