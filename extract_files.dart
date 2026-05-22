import 'dart:io';
import 'dart:convert';

void main() async {
  // Read the kernel blob
  final file = File('apk_extracted/app_debug/assets/flutter_assets/kernel_blob.bin');
  final bytes = await file.readAsBytes();
  
  // Decode as UTF-8, ignoring errors
  final content = utf8.decode(bytes, allowMalformed: true);
  
  // Find all Dart file references
  final pattern = RegExp(r'file:///D:/projects/Remon/Learnoo/([^\s"<>|]+\.dart)');
  final matches = pattern.allMatches(content);
  
  final uniqueFiles = <String>{};
  for (final match in matches) {
    final filePath = match.group(1);
    if (filePath != null) {
      uniqueFiles.add(filePath);
    }
  }
  
  final sortedFiles = uniqueFiles.toList()..sort();
  
  print('Found ${sortedFiles.length} Dart source files');
  
  // Save file list
  await Directory('restored').create(recursive: true);
  final listFile = File('restored/dart_source_file_list.txt');
  await listFile.writeAsString(sortedFiles.join('\n'));
  
  // Print the files
  for (final file in sortedFiles) {
    print(file);
  }
}
