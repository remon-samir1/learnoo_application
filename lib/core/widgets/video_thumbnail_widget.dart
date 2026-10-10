import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../services/video_thumbnail_service.dart';

/// Preview frame for a video, used only when the API has no picture for it.
///
/// Renders a light placeholder immediately. A disk-cached frame replaces it
/// straight away; otherwise extraction is requested **lazily** — only once the
/// widget has been on screen for a moment (rows scrolled past quickly never
/// queue work) — through [VideoThumbnailService], which runs at most two
/// extractions at a time. The list itself never waits on any of this.
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

class _VideoThumbnailWidgetState extends State<VideoThumbnailWidget> {
  /// How long a row must stay visible before extraction is requested.
  static const Duration _settleDelay = Duration(milliseconds: 350);

  String? _thumbnailPath;
  bool _requested = false;
  Timer? _settleTimer;
  ScrollPosition? _scrollPosition;

  @override
  void initState() {
    super.initState();
    _loadCachedThenMaybeExtract();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final position = Scrollable.maybeOf(context)?.position;
    if (!identical(position, _scrollPosition)) {
      _scrollPosition?.removeListener(_onScroll);
      _scrollPosition = position;
      _scrollPosition?.addListener(_onScroll);
    }
  }

  @override
  void didUpdateWidget(VideoThumbnailWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoUrl != widget.videoUrl) {
      _settleTimer?.cancel();
      _thumbnailPath = null;
      _requested = false;
      _loadCachedThenMaybeExtract();
    }
  }

  @override
  void dispose() {
    _settleTimer?.cancel();
    _scrollPosition?.removeListener(_onScroll);
    super.dispose();
  }

  Future<void> _loadCachedThenMaybeExtract() async {
    final url = widget.videoUrl;
    if (!VideoThumbnailService.isExtractable(url)) return;
    final cached = await VideoThumbnailService.instance.cachedThumbnail(url);
    if (!mounted || url != widget.videoUrl) return;
    if (cached != null) {
      setState(() => _thumbnailPath = cached);
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _scheduleIfVisible());
  }

  void _onScroll() {
    if (_thumbnailPath == null && !_requested) _scheduleIfVisible();
  }

  bool _isVisible() {
    if (!mounted || !TickerMode.valuesOf(context).enabled) return false;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return false;
    final topLeft = box.localToGlobal(Offset.zero);
    final screen = MediaQuery.sizeOf(context);
    return topLeft.dy < screen.height &&
        topLeft.dy + box.size.height > 0 &&
        topLeft.dx < screen.width &&
        topLeft.dx + box.size.width > 0;
  }

  void _scheduleIfVisible() {
    if (_requested || _thumbnailPath != null || !_isVisible()) return;
    _settleTimer?.cancel();
    _settleTimer = Timer(_settleDelay, _requestExtraction);
  }

  Future<void> _requestExtraction() async {
    if (_requested || !_isVisible()) return;
    _requested = true;
    final url = widget.videoUrl;
    final path = await VideoThumbnailService.instance.generateThumbnail(
      url,
      stillNeeded: () => mounted && url == widget.videoUrl,
    );
    if (!mounted || url != widget.videoUrl) return;
    if (path != null && File(path).existsSync()) {
      setState(() => _thumbnailPath = path);
    }
  }

  Widget _buildPlaceholder() {
    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: const Color(0xFFE5E7EB),
        borderRadius: BorderRadius.circular(widget.borderRadius),
      ),
      child: Icon(
        widget.isLocked ? Icons.lock : Icons.play_arrow,
        color: Colors.white,
        size: widget.width > 60 ? 28 : 22,
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
          image: ResizeImage(
            FileImage(File(_thumbnailPath!)),
            width: (widget.width * 2).round(),
          ),
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
    final content = _thumbnailPath == null
        ? _buildPlaceholder()
        : _buildThumbnailWidget();

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
