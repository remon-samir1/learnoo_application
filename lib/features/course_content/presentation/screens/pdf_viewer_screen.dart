import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../../core/services/download_service.dart';
import '../../../../core/services/feature_manager.dart';
import '../../../auth/data/auth_repository.dart';
import '../models/pdf_annotation.dart';
import '../managers/pdf_annotation_manager.dart';
import '../../../../core/services/pdf_watermark_service.dart';


enum AnnotationMode { none, pen, highlighter, eraser }

class PdfViewerScreen extends StatefulWidget {
  final String pdfUrl;
  final String title;

  const PdfViewerScreen({
    super.key,
    required this.pdfUrl,
    required this.title,
  });

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  final PdfViewerController _pdfViewerController = PdfViewerController();
  final GlobalKey<SfPdfViewerState> _pdfViewerKey = GlobalKey();
  String? _localFilePath;
  bool _isLoading = true;
  bool _isInitializing = true;
  String? _initError;

  // Annotation manager
  final PdfAnnotationManager _annotationManager = PdfAnnotationManager();
  
  // Annotation state
  AnnotationMode _currentAnnotationMode = AnnotationMode.none;
  bool _showAnnotationToolbar = false;
  final FeatureManager _featureManager = FeatureManager();
  String _userId = '';
  String _studentCode = '';
  String _phoneNumber = '';

  // Current drawing state
  List<AnnotationPoint> _currentStrokePoints = [];

  // Available annotation colors
  final List<Color> _annotationColors = [
    Colors.red,
    Colors.blue,
    Colors.green,
    Colors.yellow,
    Colors.purple,
    Colors.orange,
    Colors.black,
  ];

  // Download service for loading PDFs
  final DownloadService _downloadService = DownloadService();

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _downloadAndOpenPdf();
  }

  Future<void> _loadUserData() async {
    try {
      final authRepository = AuthRepository();
      final result = await authRepository.getProfile();
      if (result['success'] && mounted) {
        final data = result['data'] ?? {};
        final attributes = data['attributes'] ?? {};
        setState(() {
          _userId = data['id']?.toString() ?? '';
          _studentCode = attributes['student_code']?.toString() ?? '';
          _phoneNumber = attributes['phone']?.toString() ?? '';
        });
      } else {
        // API failed or offline - use cached watermark data
        final cachedData = authRepository.getCachedWatermarkData();
        if (mounted) {
          setState(() {
            _studentCode = cachedData['student_code'] ?? '';
            _phoneNumber = cachedData['phone'] ?? '';
          });
          debugPrint('[PDFViewer] Using cached watermark data: studentCode=$_studentCode, phone=$_phoneNumber');
        }
      }
    } catch (e) {
      debugPrint('Error loading user data for watermark: $e');
      // On error, try to use cached data
      try {
        final authRepository = AuthRepository();
        final cachedData = authRepository.getCachedWatermarkData();
        if (mounted) {
          setState(() {
            _studentCode = cachedData['student_code'] ?? '';
            _phoneNumber = cachedData['phone'] ?? '';
          });
          debugPrint('[PDFViewer] Using cached watermark data after error: studentCode=$_studentCode, phone=$_phoneNumber');
        }
      } catch (_) {
        // Ignore cache retrieval errors
      }
    }
  }

  /// Get combined watermark text based on feature settings
  String? get _watermarkText {
    final config = _featureManager.getWatermarkConfig('files');
    final parts = <String>[];
    
    if (config.useStudentCode && _studentCode.isNotEmpty) {
      parts.add(_studentCode);
    }
    if (config.usePhoneNumber && _phoneNumber.isNotEmpty) {
      parts.add(_phoneNumber);
    }
    
    return parts.isNotEmpty ? parts.join(' | ') : null;
  }

  Future<void> _initializePdf() async {
    try {
      setState(() {
        _isInitializing = true;
        _initError = null;
      });

      final fileName = '${widget.title.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}.pdf';
      final result = await _downloadService.downloadFile(
        url: widget.pdfUrl,
        fileName: fileName,
        subDirectory: 'temp',
      );

      if (mounted) {
        if (result.status == DownloadStatus.completed && result.localPath != null) {
          String finalPath = result.localPath!;

          // 1. Get watermark text
          final watermark = _watermarkText;
          final watermarkConfig = _featureManager.getWatermarkConfig('files');

          // 2. Apply built-in watermark if enabled
          if (watermark != null && watermarkConfig.enabled) {
            try {
              setState(() => _isLoading = true);
              final watermarkedPath = await PdfWatermarkService().embedWatermark(
                sourcePdfPath: finalPath,
                watermarkText: watermark,
                opacity: watermarkConfig.opacity,
                fontSize: watermarkConfig.fontSize,
                rotationDeg: watermarkConfig.rotation * (180.0 / pi), // Convert radians to degrees
                position: watermarkConfig.position,
                color: watermarkConfig.color,
              );
              finalPath = watermarkedPath;
            } catch (e) {
              debugPrint('Error applying built-in watermark: $e');
              // Fallback to original path if watermarking fails
            }
          }

          setState(() {
            _localFilePath = finalPath;
            _isInitializing = false;
            _isLoading = false;
          });
        } else if (result.status == DownloadStatus.failed) {
          setState(() {
            _initError = result.errorMessage ?? 'Failed to load PDF';
            _isInitializing = false;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _initError = 'Error loading PDF: $e';
          _isInitializing = false;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _downloadAndOpenPdf() async {
    await _initializePdf();
  }

  Future<void> _shareUrl() async {
    await Share.shareUri(Uri.parse(widget.pdfUrl));
  }

  void _setAnnotationMode(AnnotationMode mode) {
    setState(() {
      _currentAnnotationMode = mode;
      _currentStrokePoints.clear();
      
      // Update annotation manager settings
      if (mode == AnnotationMode.pen) {
        _annotationManager.isHighlighterMode = false;
      } else if (mode == AnnotationMode.highlighter) {
        _annotationManager.isHighlighterMode = true;
      }
    });
  }

  void _setAnnotationColor(Color color) {
    setState(() {
      _annotationManager.currentColor = color;
    });
  }

  void _setStrokeWidth(double width) {
    setState(() {
      _annotationManager.currentStrokeWidth = width;
    });
  }

  void _eraseNearbyPoints(Offset position) {
    final pageNumber = _pdfViewerController.pageNumber;
    if (pageNumber == 0) return;
    
    final eraseRadius = _annotationManager.currentStrokeWidth * 5;
    final annotations = _annotationManager.getAnnotationsForPage(pageNumber);
    
    setState(() {
      for (final stroke in annotations) {
        stroke.points.removeWhere((point) {
          return (point.offset - position).distance < eraseRadius;
        });
      }
      // Remove empty strokes
      annotations.removeWhere((stroke) => stroke.points.isEmpty);
    });
  }

  Future<void> _saveCurrentStroke() async {
    if (_currentStrokePoints.length < 2) {
      _currentStrokePoints.clear();
      return;
    }

    final pageNumber = _pdfViewerController.pageNumber;
    if (pageNumber == 0) return;

    // Create stroke from current points
    final stroke = InkStroke(
      points: List.from(_currentStrokePoints),
      color: _annotationManager.currentColor,
      strokeWidth: _annotationManager.currentStrokeWidth,
      isHighlighter: _annotationManager.isHighlighterMode,
    );

    // Add to annotation manager
    _annotationManager.addStroke(pageNumber, stroke);
    
    // Clear current stroke points
    _currentStrokePoints.clear();

    // Auto-save to PDF
    await _autoSaveToPdf();
  }

  Future<void> _autoSaveToPdf() async {
    if (_localFilePath == null) return;
    
    setState(() => _isLoading = true);
    
    try {
      final success = await _annotationManager.saveToPdf(_localFilePath!);
      
      if (mounted) {
        setState(() => _isLoading = false);
        if (success) {
          // Optionally show a subtle indicator that auto-save happened
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to save annotation')),
          );
        }
      }
    } catch (e) {
      debugPrint('Error auto-saving: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _discardChanges() async {
    if (_localFilePath == null) return;
    
    setState(() => _isLoading = true);
    
    try {
      // Discard all annotations
      _annotationManager.discardAll();
      _currentStrokePoints.clear();
      
      // Reload the original PDF
      await _initializePdf();
      
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Changes discarded')),
        );
      }
    } catch (e) {
      debugPrint('Error discarding changes: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<bool> _onWillPop() async {
    if (!_annotationManager.hasUnsavedChanges) {
      return true;
    }
    
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unsaved Changes'),
        content: const Text('You have unsaved annotations. What would you like to do?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await _discardChanges();
              Navigator.pop(context, true);
            },
            child: const Text('Discard'),
          ),
          TextButton(
            onPressed: () async {
              await _autoSaveToPdf();
              Navigator.pop(context, true);
            },
            child: const Text('Save & Close'),
          ),
        ],
      ),
    );
    
    return result ?? false;
  }

  void _undo() {
    final pageNumber = _pdfViewerController.pageNumber;
    if (pageNumber == 0) return;
    
    _annotationManager.undo(pageNumber);
    setState(() {});
    
    // Re-save after undo
    _autoSaveToPdf();
  }

  void _clearCurrentPage() {
    final pageNumber = _pdfViewerController.pageNumber;
    if (pageNumber == 0) return;
    
    _annotationManager.clearPage(pageNumber);
    setState(() {});
    
    // Re-save after clearing
    _autoSaveToPdf();
  }

  @override
  Widget build(BuildContext context) {
    // Show initialization loading
    if (_isInitializing) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: const Color(0xFF2137D6),
          foregroundColor: Colors.white,
          elevation: 0,
          title: Text(
            widget.title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Color(0xFF2137D6)),
              SizedBox(height: 16),
              Text('Loading PDF...'),
            ],
          ),
        ),
      );
    }

    // Show initialization error
    if (_initError != null) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: const Color(0xFF2137D6),
          foregroundColor: Colors.white,
          elevation: 0,
          title: Text(
            widget.title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text(_initError!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _initializePdf,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2137D6),
                  foregroundColor: Colors.white,
                ),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: const Color(0xFF2137D6),
          foregroundColor: Colors.white,
          elevation: 0,
          title: Text(
            widget.title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            // Undo button
            if (_showAnnotationToolbar)
              IconButton(
                icon: const FaIcon(FontAwesomeIcons.rotateLeft, size: 18),
                onPressed: _annotationManager.canUndo(_pdfViewerController.pageNumber)
                    ? _undo
                    : null,
                tooltip: 'Undo',
              ),
            // Annotation toggle button
            IconButton(
              onPressed: () {
                setState(() {
                  _showAnnotationToolbar = !_showAnnotationToolbar;
                  if (!_showAnnotationToolbar) {
                    _currentAnnotationMode = AnnotationMode.none;
                  }
                });
              },
              icon: FaIcon(
                _showAnnotationToolbar ? FontAwesomeIcons.penToSquare : FontAwesomeIcons.highlighter,
                size: 18,
                color: _showAnnotationToolbar ? Colors.orange : Colors.white,
              ),
              tooltip: 'pdf.annotation_tools'.tr(),
            ),
            // Discard button
            if (_showAnnotationToolbar && _annotationManager.hasUnsavedChanges)
              IconButton(
                icon: const FaIcon(FontAwesomeIcons.trash, size: 18),
                onPressed: _discardChanges,
                tooltip: 'Discard Changes',
              ),
            // Share URL button
            IconButton(
              onPressed: _shareUrl,
              icon: const FaIcon(FontAwesomeIcons.shareNodes, size: 18),
              tooltip: 'share.share_link'.tr(),
            ),
          ],
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Color(0xFF2137D6)),
            SizedBox(height: 16),
            Text(
              'Saving...',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    if (_localFilePath != null) {
      return Column(
        children: [
          // Annotation Toolbar
          if (_showAnnotationToolbar)
            Container(
              height: 120,
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Annotation Type Selection
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    child: Row(
                      children: [
                        _buildAnnotationModeButton(
                          FontAwesomeIcons.pen,
                          'Pen',
                          AnnotationMode.pen,
                          Colors.red,
                        ),
                        _buildAnnotationModeButton(
                          FontAwesomeIcons.highlighter,
                          'Highlighter',
                          AnnotationMode.highlighter,
                          Colors.yellow,
                        ),
                        _buildAnnotationModeButton(
                          FontAwesomeIcons.eraser,
                          'Eraser',
                          AnnotationMode.eraser,
                          Colors.grey,
                        ),
                        const VerticalDivider(width: 20),
                        // Clear all button
                        InkWell(
                          onTap: _clearCurrentPage,
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.red.withOpacity(0.3)),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                FaIcon(FontAwesomeIcons.trash, size: 20, color: Colors.red),
                                SizedBox(height: 4),
                                Text('Clear', style: TextStyle(fontSize: 10, color: Colors.red)),
                              ],
                            ),
                          ),
                        ),
                        const VerticalDivider(width: 20),
                        Text('Width', style: const TextStyle(fontSize: 12)),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 100,
                          child: Slider(
                            value: _annotationManager.currentStrokeWidth,
                            min: 1,
                            max: 10,
                            onChanged: _setStrokeWidth,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  // Color Selection
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: _annotationColors.map((color) {
                        final isSelected = _annotationManager.currentColor == color;
                        return Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: GestureDetector(
                            onTap: () => _setAnnotationColor(color),
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isSelected ? Colors.black : Colors.transparent,
                                  width: 3,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.2),
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                              child: isSelected
                                  ? const Icon(Icons.check, color: Colors.black, size: 18)
                                  : null,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
          // PDF with Drawing Overlay
          Expanded(
            child: Stack(
              children: [
                if (_localFilePath != null)
                  SfPdfViewer.file(
                    File(_localFilePath!),
                    controller: _pdfViewerController,
                    key: _pdfViewerKey,
                    enableTextSelection: _currentAnnotationMode == AnnotationMode.none,
                    enableDocumentLinkAnnotation: true,
                    enableHyperlinkNavigation: true,
                  )
                else
                  const Center(child: Text('PDF file not available')),
                // Drawing overlay
                if (_showAnnotationToolbar && _currentAnnotationMode != AnnotationMode.none)
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanStart: (details) {
                        if (_currentAnnotationMode == AnnotationMode.eraser) {
                          _eraseNearbyPoints(details.localPosition);
                        } else {
                          setState(() {
                            _currentStrokePoints.add(AnnotationPoint(
                              offset: details.localPosition,
                              color: _annotationManager.currentColor,
                              strokeWidth: _annotationManager.currentStrokeWidth,
                              isHighlighter: _annotationManager.isHighlighterMode,
                            ));
                          });
                        }
                      },
                      onPanUpdate: (details) {
                        if (_currentAnnotationMode == AnnotationMode.eraser) {
                          _eraseNearbyPoints(details.localPosition);
                        } else {
                          setState(() {
                            _currentStrokePoints.add(AnnotationPoint(
                              offset: details.localPosition,
                              color: _annotationManager.currentColor,
                              strokeWidth: _annotationManager.currentStrokeWidth,
                              isHighlighter: _annotationManager.isHighlighterMode,
                            ));
                          });
                        }
                      },
                      onPanEnd: (_) async {
                        if (_currentAnnotationMode != AnnotationMode.eraser) {
                          await _saveCurrentStroke();
                        }
                      },
                      child: CustomPaint(
                        size: Size.infinite,
                        painter: _AnnotationPainter(
                          currentStrokePoints: _currentStrokePoints,
                          pageAnnotations: _annotationManager.getAnnotationsForPage(_pdfViewerController.pageNumber),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      );
    }

    return Center(
      child: Text('course.unable_load_pdf'.tr()),
    );
  }

  Widget _buildAnnotationModeButton(
    FaIconData icon,
    String label,
    AnnotationMode mode,
    Color defaultColor,
  ) {
    final isSelected = _currentAnnotationMode == mode;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: InkWell(
        onTap: () => _setAnnotationMode(isSelected ? AnnotationMode.none : mode),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? defaultColor.withOpacity(0.2) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? defaultColor : Colors.grey.withOpacity(0.3),
              width: 2,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FaIcon(
                icon,
                size: 20,
                color: isSelected ? defaultColor : Colors.grey,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  color: isSelected ? defaultColor : Colors.grey,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnnotationPainter extends CustomPainter {
  final List<AnnotationPoint> currentStrokePoints;
  final List<InkStroke> pageAnnotations;

  _AnnotationPainter({
    required this.currentStrokePoints,
    required this.pageAnnotations,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw saved page annotations
    for (final stroke in pageAnnotations) {
      _drawStroke(canvas, stroke.points, stroke.color, stroke.strokeWidth, stroke.isHighlighter);
    }

    // Draw current stroke being drawn
    if (currentStrokePoints.isNotEmpty) {
      final isHighlighter = currentStrokePoints.first.isHighlighter;
      _drawStroke(canvas, currentStrokePoints, currentStrokePoints.first.color, currentStrokePoints.first.strokeWidth, isHighlighter);
    }
  }

  void _drawStroke(Canvas canvas, List<AnnotationPoint> points, Color color, double strokeWidth, bool isHighlighter) {
    if (points.isEmpty) return;

    for (int i = 0; i < points.length - 1; i++) {
      final point = points[i];
      final nextPoint = points[i + 1];

      // Skip if the points are too far apart (new stroke)
      if ((point.offset - nextPoint.offset).distance > 50) continue;

      final paint = Paint()
        ..color = isHighlighter ? color.withOpacity(0.3) : color
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;

      canvas.drawLine(point.offset, nextPoint.offset, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
