import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/theme/app_colors.dart';

/// Renders a note's attachment inline.
///
/// Port of the attachment block in the web's `StudentNoteCard`: an image is
/// shown as an image, a video gets a player, and anything else falls back to a
/// download link. The app previously rendered every attachment as a bare link,
/// so a student never saw a note's picture or clip without leaving the app.
class NoteAttachmentPreview extends StatelessWidget {
  const NoteAttachmentPreview({super.key, required this.attachment});

  final Map<String, dynamic> attachment;

  static const _videoExtensions = {'mp4', 'webm', 'ogg', 'mov', 'avi', 'mkv'};
  static const _imageExtensions = {
    'jpg',
    'jpeg',
    'png',
    'gif',
    'webp',
    'svg',
    'bmp',
  };

  String get _url => attachment['url']?.toString() ?? '';

  String get _name => attachment['name']?.toString() ?? '';

  /// Extension from the explicit field, else from the URL's last dot segment —
  /// the same order the web uses.
  String get _extension {
    final explicit = attachment['extension']?.toString().trim();
    if (explicit != null && explicit.isNotEmpty) return explicit.toLowerCase();

    final path = Uri.tryParse(_url)?.path ?? _url;
    final dot = path.lastIndexOf('.');
    if (dot == -1 || dot == path.length - 1) return '';
    return path.substring(dot + 1).toLowerCase();
  }

  @override
  Widget build(BuildContext context) {
    final url = _url;
    if (url.isEmpty) return const SizedBox.shrink();

    final extension = _extension;

    Widget child;
    if (_videoExtensions.contains(extension)) {
      child = _NoteVideoPlayer(url: url);
    } else if (_imageExtensions.contains(extension)) {
      child = _NoteImage(url: url, name: _name);
    } else {
      child = _NoteFileLink(url: url, name: _name);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFF1F5F9)),
        ),
        child: child,
      ),
    );
  }
}

class _NoteImage extends StatelessWidget {
  const _NoteImage({required this.url, required this.name});

  final String url;
  final String name;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              title: Text(name, style: const TextStyle(fontSize: 15)),
            ),
            body: PhotoView(imageProvider: CachedNetworkImageProvider(url)),
          ),
        ),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 300),
        child: CachedNetworkImage(
          imageUrl: url,
          width: double.infinity,
          fit: BoxFit.contain,
          placeholder: (context, _) => const SizedBox(
            height: 160,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          errorWidget: (context, _, __) =>
              _NoteFileLink(url: url, name: name),
        ),
      ),
    );
  }
}

class _NoteVideoPlayer extends StatefulWidget {
  const _NoteVideoPlayer({required this.url});

  final String url;

  @override
  State<_NoteVideoPlayer> createState() => _NoteVideoPlayerState();
}

class _NoteVideoPlayerState extends State<_NoteVideoPlayer> {
  VideoPlayerController? _controller;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _initialise();
  }

  Future<void> _initialise() async {
    final controller =
        VideoPlayerController.networkUrl(Uri.parse(widget.url));
    try {
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } catch (_) {
      await controller.dispose();
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return _NoteFileLink(url: widget.url, name: '');
    }

    final controller = _controller;
    if (controller == null) {
      return const SizedBox(
        height: 180,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    return Column(
      children: [
        AspectRatio(
          aspectRatio: controller.value.aspectRatio == 0
              ? 16 / 9
              : controller.value.aspectRatio,
          child: Stack(
            alignment: Alignment.center,
            children: [
              VideoPlayer(controller),
              ValueListenableBuilder<VideoPlayerValue>(
                valueListenable: controller,
                builder: (context, value, _) => IconButton(
                  iconSize: 48,
                  icon: Icon(
                    value.isPlaying
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_fill,
                    color: Colors.white70,
                  ),
                  onPressed: () =>
                      value.isPlaying ? controller.pause() : controller.play(),
                ),
              ),
            ],
          ),
        ),
        VideoProgressIndicator(controller, allowScrubbing: true),
      ],
    );
  }
}

class _NoteFileLink extends StatelessWidget {
  const _NoteFileLink({required this.url, required this.name});

  final String url;
  final String name;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () =>
          launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            const Icon(
              Icons.download_outlined,
              size: 16,
              color: AppColors.primaryBlue,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                name.isEmpty ? 'notes.download_attachment'.tr() : name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.primaryBlue,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
