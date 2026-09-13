import '../models/watermark_config.dart';

/// Fallback when the platform has not set a watermark text.
const String _defaultWatermarkText = 'Learnoo';

/// The line drawn over protected content.
///
/// Port of `src/lib/watermark-text.ts`. Two rules the app was missing:
///
///  * `usePhoneNumber` appends the student's phone after the code, separated by
///    a middle dot — the app ignored the flag entirely;
///  * the student code is appended for traceability even when the watermark is
///    showing custom text, unless the line already contains it.
String buildWatermarkText({
  required WatermarkConfig config,
  String? studentCode,
  String? phone,
}) {
  final code = studentCode?.trim() ?? '';
  final phoneNumber = phone?.trim() ?? '';

  String line;
  if (config.useStudentCode) {
    final primary = code.isEmpty ? '—' : code;
    line = config.usePhoneNumber && phoneNumber.isNotEmpty
        ? '$primary · $phoneNumber'
        : primary;
  } else {
    final custom = config.text.trim();
    line = custom.isEmpty ? _defaultWatermarkText : custom;
  }

  return _appendStudentCode(line, code);
}

String _appendStudentCode(String line, String code) {
  if (code.isEmpty) return line;
  final trimmed = line.trim();
  if (trimmed.isEmpty) return code;
  if (trimmed.contains(code)) return trimmed;
  return '$trimmed · $code';
}
