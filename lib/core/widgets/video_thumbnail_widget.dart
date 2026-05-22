import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../services/video_thumbnail_service.dart';

/// A reusable widget for displaying video thumbnails from network URLs
/// Automatically generates and caches thumbnails using the VideoThumbnailService
class VideoThumbnailWidget extends StatefulWidget {
  final String videoUrl;
  final double width;
  final double height;
  final double borderRadius;
  final VoidCallback? onTap;
  final bool showPlayIcon;
  final bool isLocked;

  const VideoThumbnailWidget({
    super.key,
    required this.videoUrl,
    this.width = 80,
    this.height = 60,
    this.borderRadius = 12,
    this.onTap,
    this.showPlayIcon = true,
    this.isLocked = false,
  });

  @override
  State<VideoThumbnailWidget> createState() => _VideoThumbnailWidgetState();
}

class _VideoThumbnailWidgetState extends State<VideoThumbnailWidget>
    with AutomaticKeepAliveClientMixin {
  String? _thumbnailPath;
  bool _isLoading = true;
  bool _hasError = false;
  bool _generationStarted = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadThumbnail();
  }

  @override
  void didUpdateWidget(VideoThumbnailWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoUrl != widget.videoUrl) {
      _thumbnailPath = null;
      _isLoading = true;
      _hasError = false;
      _generationStarted = false;
      _loadThumbnail();
    }
  }

  Future<void> _loadThumbnail() async {
    if (widget.videoUrl.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
      return;
    }

    if (_generationStarted) return;
    _generationStarted = true;

    try {
      final service = VideoThumbnailService.instance;

      // Check if already cached
      if (await service.hasThumbnail(widget.videoUrl)) {
        final path = await service.generateThumbnail(widget.videoUrl);
        if (mounted && path != null) {
          setState(() {
            _thumbnailPath = path;
            _isLoading = false;
          });
          return;
        }
      }

      // Generate thumbnail
      final path = await service.generateThumbnail(widget.videoUrl);

      if (mounted) {
        setState(() {
          if (path != null && File(path).existsSync()) {
            _thumbnailPath = path;
            _hasError = false;
          } else {
            _hasError = true;
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _isLoading = false;
        });
      }
    }
  }

  Widget _buildLoadingWidget() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: Colors.grey[300],
          borderRadius: BorderRadius.circular(widget.borderRadius),
        ),
      ),
    );
  }

  Widget _buildFallbackWidget() {
    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: Colors.grey[300],
        borderRadius: BorderRadius.circular(widget.borderRadius),
      ),
      child: Icon(
        widget.isLocked ? Icons.lock : Icons.play_arrow,
        color: Colors.white,
        size: widget.width > 60 ? 32 : 24,
      ),
    );
  }

  Widget _buildThumbnailWidget() {
    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        image: DecorationImage(
          image: FileImage(File(_thumbnailPath!)),
          fit: BoxFit.cover,
        ),
      ),
      child: widget.showPlayIcon
          ? Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(widget.borderRadius),
                color: Colors.black.withValues(alpha: 0.2),
              ),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.8),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    widget.isLocked ? Icons.lock : Icons.play_arrow,
                    color: Colors.black,
                    size: widget.width > 60 ? 20 : 14,
                  ),
                ),
              ),
            )
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    Widget content;
    if (_isLoading) {
      content = _buildLoadingWidget();
    } else if (_hasError || _thumbnailPath == null) {
      content = _buildFallbackWidget();
    } else {
      content = _buildThumbnailWidget();
    }

    if (widget.onTap != null) {
      return InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: content,
      );
    }

    return content;
  }
}
