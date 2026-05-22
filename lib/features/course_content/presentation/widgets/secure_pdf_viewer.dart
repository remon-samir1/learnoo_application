import 'package:flutter/material.dart';
import 'package:learnoo/core/widgets/secure_wrapper.dart';
import 'package:learnoo/core/widgets/watermark_widget.dart';

/// A secure PDF viewer that renders pages as images fetched from the backend.
/// Raw PDF rendering is avoided to prevent extraction.
class SecurePDFViewer extends StatefulWidget {
  final List<String> pageImageUrls; // Expiring URLs to rendered PDF pages
  final String userId;
  final String userName;
  final String title;

  const SecurePDFViewer({
    super.key,
    required this.pageImageUrls,
    required this.userId,
    required this.userName,
    this.title = "Document Viewer",
  });

  @override
  State<SecurePDFViewer> createState() => _SecurePDFViewerState();
}

class _SecurePDFViewerState extends State<SecurePDFViewer> {
  late PageController _pageController;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 1. Wrap with SecureWrapper to ensure screen is hidden during recording
    return SecureWrapper(
      protectionMessage: "Document viewing protected",
      child: Scaffold(
        backgroundColor: Colors.grey[900],
        appBar: AppBar(
          backgroundColor: Colors.black,
          title: Text(
            "${widget.title} (${_currentPage + 1}/${widget.pageImageUrls.length})",
            style: const TextStyle(fontSize: 16),
          ),
          centerTitle: true,
        ),
        body: Stack(
          children: [
            // 2. Document Pages Layer (Images)
            PageView.builder(
              controller: _pageController,
              itemCount: widget.pageImageUrls.length,
              onPageChanged: (index) {
                setState(() {
                  _currentPage = index;
                });
              },
              itemBuilder: (context, index) {
                return InteractiveViewer(
                  panEnabled: true,
                  minScale: 1.0,
                  maxScale: 4.0,
                  child: Center(
                    child: Image.network(
                      widget.pageImageUrls[index],
                      fit: BoxFit.contain,
                      loadingBuilder: (context, child, loadingProgress) {
                         if (loadingProgress == null) return child;
                         return Center(
                           child: CircularProgressIndicator(
                             value: loadingProgress.expectedTotalBytes != null
                                 ? loadingProgress.cumulativeBytesLoaded /
                                     (loadingProgress.expectedTotalBytes ?? 1)
                                 : null,
                             color: Colors.white,
                           ),
                         );
                      },
                      errorBuilder: (context, error, stackTrace) {
                        return const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.broken_image, color: Colors.white54, size: 48),
                              SizedBox(height: 8),
                              Text("Failed to load page secure image.", style: TextStyle(color: Colors.white54)),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                );
              },
            ),

            // 3. Dynamic Watermark Layer
            Positioned.fill(
              child: IgnorePointer(
                child: WatermarkWidget(
                  userId: widget.userId,
                  userName: widget.userName,
                  style: const TextStyle(
                    color: Colors.black54, // Visible on both light and dark backgrounds
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
