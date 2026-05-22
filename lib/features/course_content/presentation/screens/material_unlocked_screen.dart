import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'electronic_library_screen.dart';
import 'pdf_viewer_screen.dart';

class MaterialUnlockedScreen extends StatelessWidget {
  final dynamic library;

  const MaterialUnlockedScreen({
    super.key,
    required this.library,
  });

  String get _currentDate {
    final now = DateTime.now();
    final months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return '${months[now.month - 1]} ${now.day}, ${now.year}';
  }

  void _openPdf(BuildContext context) {
    final attributes = library['attributes'] ?? {};
    final title = attributes['title']?.toString() ?? 'Material';
    final pdfUrl = attributes['file_url']?.toString() ?? attributes['pdf_url']?.toString() ?? '';

    if (pdfUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PDF URL not available')),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PdfViewerScreen(
          pdfUrl: pdfUrl,
          title: title,
        ),
      ),
    );
  }

  void _backToLibrary(BuildContext context) {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const ElectronicLibraryScreen()),
      (route) => route.isFirst,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // Background Gradients
          Positioned(
            top: -100,
            left: -50,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFFFFE4E1).withValues(alpha: 0.4),
                    const Color(0xFFFFE4E1).withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -100,
            right: -100,
            child: Container(
              width: 400,
              height: 400,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFFFFFACD).withValues(alpha: 0.3),
                    const Color(0xFFFFFACD).withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  const SizedBox(height: 60),
                  // Success Icon
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      // Outer circle
                      Container(
                        width: 140,
                        height: 140,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F5E9).withValues(alpha: 0.5),
                          shape: BoxShape.circle,
                        ),
                      ),
                      // Middle circle
                      Container(
                        width: 100,
                        height: 100,
                        decoration: const BoxDecoration(
                          color: Color(0xFFC8E6C9),
                          shape: BoxShape.circle,
                        ),
                      ),
                      // Check icon
                      Container(
                        width: 60,
                        height: 60,
                        decoration: const BoxDecoration(
                          color: Color(0xFF81C784),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                      // Shield icon top right
                      Positioned(
                        top: 0,
                        right: 0,
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: const BoxDecoration(
                            color: Color(0xFF27AE60),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.shield,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 40),
                  // Title
                  const Text(
                    'Material Unlocked!',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1F2937),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Subtitle
                  Text(
                    'You can now access this material an anytime from your Electronic Library.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[500],
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 32),
                  // Material Details Card
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const FaIcon(
                              FontAwesomeIcons.book,
                              color: Color(0xFF5A75FF),
                              size: 24,
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    library['attributes']?['title']?.toString() ?? 'Untitled',
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF1F2937),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      const FaIcon(
                                        FontAwesomeIcons.book,
                                        color: Color(0xFF5A75FF),
                                        size: 12,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        library['attributes']?['material_type']?.toString() ?? 'Unknown',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[500],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 24),
                        Row(
                          children: [
                            FaIcon(
                              FontAwesomeIcons.calendar,
                              color: Colors.grey[400],
                              size: 14,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'Unlocked on',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey[500],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              _currentDate,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF1F2937),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  // Open PDF Button
                  // SizedBox(
                  //   width: double.infinity,
                  //   height: 52,
                  //   child: ElevatedButton.icon(
                  //     onPressed: () => _openPdf(context),
                  //     style: ElevatedButton.styleFrom(
                  //       backgroundColor: const Color(0xFF2137D6),
                  //       foregroundColor: Colors.white,
                  //       shape: RoundedRectangleBorder(
                  //         borderRadius: BorderRadius.circular(12),
                  //       ),
                  //       elevation: 0,
                  //     ),
                  //     icon: const FaIcon(FontAwesomeIcons.bookOpen, size: 18),
                  //     label: const Text(
                  //       'Open PDF',
                  //       style: TextStyle(
                  //         fontSize: 16,
                  //         fontWeight: FontWeight.w600,
                  //       ),
                  //     ),
                  //   ),
                  // ),
                  const SizedBox(height: 20),
                  // Back to Library Button
                  TextButton.icon(
                    onPressed: () => _backToLibrary(context),
                    icon: const FaIcon(
                      FontAwesomeIcons.arrowLeft,
                      size: 14,
                      color: Color(0xFF5A75FF),
                    ),
                    label: const Text(
                      'Back to Library',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF5A75FF),
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
