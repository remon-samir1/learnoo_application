import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../data/library_repository.dart';
import 'pdf_viewer_screen.dart';

class UnlockMaterialScreen extends StatefulWidget {
  final dynamic library;

  const UnlockMaterialScreen({
    super.key,
    required this.library,
  });

  @override
  State<UnlockMaterialScreen> createState() => _UnlockMaterialScreenState();
}

class _UnlockMaterialScreenState extends State<UnlockMaterialScreen> {
  final TextEditingController _codeController = TextEditingController();
  final LibraryRepository _libraryRepository = LibraryRepository();
  bool _isVerifying = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _verifyCode() async {
    final code = _codeController.text.trim();

    if (code.isEmpty) {
      _showError('Please enter an activation code');
      return;
    }

    setState(() {
      _isVerifying = true;
    });

    try {
      // Get library ID from the library data
      final libraryId = int.tryParse(widget.library['id'].toString()) ?? 0;

      if (libraryId == 0) {
        setState(() => _isVerifying = false);
        _showError('Invalid library ID');
        return;
      }

      final result = await _libraryRepository.activateCode(
        code: code,
        itemId: libraryId,
        itemType: 'library',
      );

      if (mounted) {
        setState(() {
          _isVerifying = false;
        });

        if (result['success']) {
          _openPdf();
        } else {
          _showError(result['message'] ?? 'Invalid activation code');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isVerifying = false;
        });
        _showError('Connection error. Please try again.');
      }
    }
  }

  void _openPdf() {
    final attributes = widget.library['attributes'] ?? {};
    final title = attributes['title']?.toString() ?? 'Material';
    final attachments = attributes['attachments'] as List<dynamic>? ?? [];

    final pdfAttachment = attachments.firstWhere(
      (attachment) {
        final ext = attachment['attributes']?['extension']?.toString().toLowerCase() ?? '';
        return ext == 'pdf';
      },
      orElse: () => null,
    );

    final pdfUrl = pdfAttachment?['attributes']?['path']?.toString() ?? '';

    if (pdfUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PDF not available')),
      );
      return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => PdfViewerScreen(
          pdfUrl: pdfUrl,
          title: title,
        ),
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final attributes = widget.library['attributes'] ?? {};
    final title = attributes['title']?.toString() ?? 'Untitled';
    final coverImage = attributes['cover_image']?.toString() ?? '';
    final materialType = attributes['material_type']?.toString() ?? 'Unknown';

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
            child: Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.arrow_back,
                            color: Colors.grey[700],
                            size: 20,
                          ),
                        ),
                      ),
                      const Expanded(
                        child: Text(
                          'Unlock Material',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1F2937),
                          ),
                        ),
                      ),
                      const SizedBox(width: 40),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      children: [
                        // Material Preview Card
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFF1F1F1)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.03),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.network(
                                  coverImage,
                                  width: 70,
                                  height: 90,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Container(
                                      width: 70,
                                      height: 90,
                                      color: const Color(0xFFF3F4F6),
                                      child: const Icon(Icons.book, color: Color(0xFF9CA3AF)),
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF1F2937),
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF0F2FF),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        materialType,
                                        style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w500,
                                          color: Color(0xFF5A75FF),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 32),
                        // Key Icon
                        Container(
                          width: 70,
                          height: 70,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0F2FF),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Center(
                            child: FaIcon(
                              FontAwesomeIcons.key,
                              color: Color(0xFF5A75FF),
                              size: 28,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        // Title
                        const Text(
                          'Enter Activation Code',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1F2937),
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Subtitle
                        Text(
                          'Enter the code you received to unlock this PDF material.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[500],
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 32),
                        // Code Input Label
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Activation Code',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Colors.grey[700],
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Code Input Field
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE5E7EB)),
                          ),
                          child: TextField(
                            controller: _codeController,
                            keyboardType: TextInputType.text,
                            textCapitalization: TextCapitalization.characters,
                            maxLength: 20,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 4,
                              color: Color(0xFF1F2937),
                            ),
                            decoration: InputDecoration(
                              counterText: '',
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 18,
                              ),
                              border: InputBorder.none,
                              hintText: 'ABCD-1234',
                              hintStyle: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 4,
                                color: Colors.grey[300],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        // Help Text
                        Row(
                          children: [
                            FaIcon(
                              FontAwesomeIcons.circleQuestion,
                              color: Colors.grey[400],
                              size: 14,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                "Didn't receive a code? Please contact support. Codes are provided after payment.",
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[400],
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 40),
                        // Verify Button
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton.icon(
                            onPressed: _isVerifying ? null : _verifyCode,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF5A75FF),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                            ),
                            icon: _isVerifying
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const FaIcon(FontAwesomeIcons.key, size: 16),
                            label: Text(
                              _isVerifying ? 'Verifying...' : 'Verify Code',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Cancel Button
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(
                            'Cancel',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Colors.grey[600],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
