import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/services/capture_media_guard.dart';
import '../../../../core/utils/media_url.dart';
import '../../../course_content/presentation/screens/pdf_viewer_screen.dart';

/// What a note attachment is, decided from the API fields rather than
/// guessed from how the link looks.
enum NoteAttachmentKind { image, video, pdf, file, unknown }

/// A note's `attachment`, normalised from every shape the API sends it in.
///
/// The web reads `attachment.url` and `attachment.extension` (falling back to
/// the URL's last dot segment). Records reach the app as a `{url, name,
/// extension}` map, a JSON:API `{attributes: {...}}` wrapper, a map keyed by
/// `path`/`file`, or a bare URL string; the extension is sometimes a mime type
/// (`image/jpeg`), carries a leading dot, or is missing while `name` still
/// ends in `.jfif`. Each of those previously fell through to a download link.
class NoteAttachment {
  NoteAttachment._({
    required this.url,
    required this.name,
    required this.kind,
  });

  final String url;
  final String name;
  final NoteAttachmentKind kind;

  static const _imageExtensions = {
    'jpg',
    'jpeg',
    'jfif',
    'pjpeg',
    'pjp',
    'png',
    'gif',
    'webp',
    'bmp',
    'heic',
    'heif',
    'avif',
    'svg',
  };

  static const _videoExtensions = {
    'mp4',
    'm4v',
    'mov',
    'webm',
    'm3u8',
    'ogg',
    'ogv',
    'avi',
    'mkv',
    '3gp',
  };

  static const _fileExtensions = {
    'pdf',
    'doc',
    'docx',
    'xls',
    'xlsx',
    'csv',
    'ppt',
    'pptx',
    'txt',
    'rtf',
    'zip',
    'rar',
    'mp3',
    'wav',
    'm4a',
  };

  /// Parses [raw]; `null` when there is no usable URL.
  static NoteAttachment? parse(dynamic raw) {
    if (raw == null) return null;

    Map<String, dynamic> fields;
    if (raw is String) {
      fields = {'url': raw};
    } else if (raw is Map) {
      fields = Map<String, dynamic>.from(raw);
      if (fields['data'] is Map) {
        fields = {...fields, ...Map<String, dynamic>.from(fields['data'] as Map)};
      }
      final attrs = fields['attributes'];
      if (attrs is Map) {
        fields = {...fields, ...Map<String, dynamic>.from(attrs)};
      }
    } else if (raw is List) {
      for (final item in raw) {
        final parsed = parse(item);
        if (parsed != null) return parsed;
      }
      return null;
    } else {
      return null;
    }

    final url = readMediaUrl(fields, const [
      'url',
      'original_url',
      'full_url',
      'path',
      'file',
      'file_url',
      'src',
      'link',
    ]);
    if (url == null) return null;

    final name = _firstString(fields, const [
      'name',
      'file_name',
      'filename',
      'original_name',
    ]);

    return NoteAttachment._(
      url: url,
      name: name,
      kind: _detectKind(fields, url, name),
    );
  }

  static String _firstString(Map<String, dynamic> fields, List<String> keys) {
    for (final key in keys) {
      final value = fields[key]?.toString().trim() ?? '';
      if (value.isNotEmpty && value != 'null') return value;
    }
    return '';
  }

  static NoteAttachmentKind _detectKind(
    Map<String, dynamic> fields,
    String url,
    String name,
  ) {
    // Specific media MIME types win; generic binary metadata must not hide
    // a recognised image extension.
    NoteAttachmentKind? fallbackKind;
    for (final key in const [
      'mime_type',
      'mime',
      'mimetype',
      'content_type',
      'file_type',
      'media_type',
      'type',
      'extension',
    ]) {
      final kind = _kindFromMime(fields[key]?.toString());
      if (kind == NoteAttachmentKind.file) {
        fallbackKind = kind;
      } else if (kind != null) {
        return kind;
      }
    }

    // 2. The explicit extension, then the file name, then the URL path —
    //    the web's order, with the name added for records lacking both.
    final candidates = [
      _normaliseExtension(fields['extension']?.toString()),
      _extensionOf(name),
      _extensionOf(Uri.tryParse(url)?.path ?? url),
    ];
    for (final ext in candidates) {
      if (ext.isEmpty) continue;
      if (_imageExtensions.contains(ext)) return NoteAttachmentKind.image;
      if (_videoExtensions.contains(ext)) return NoteAttachmentKind.video;
      if (ext == 'pdf') return NoteAttachmentKind.pdf;
      if (_fileExtensions.contains(ext)) return NoteAttachmentKind.file;
    }
    return fallbackKind ?? NoteAttachmentKind.unknown;
  }

  static NoteAttachmentKind? _kindFromMime(String? raw) {
    final value = raw?.trim().toLowerCase() ?? '';
    if (value.isEmpty) return null;
    if (value == 'image' || value.startsWith('image/')) {
      return NoteAttachmentKind.image;
    }
    if (value == 'video' ||
        value.startsWith('video/') ||
        value.contains('mpegurl')) {
      return NoteAttachmentKind.video;
    }
    if (value == 'application/pdf') return NoteAttachmentKind.pdf;
    if (value == 'application/octet-stream' || value == 'binary/octet-stream') {
      return null;
    }
    if (value.startsWith('application/') ||
        value.startsWith('text/') ||
        value.startsWith('audio/')) {
      return NoteAttachmentKind.file;
    }
    return null;
  }

  static String _normaliseExtension(String? raw) {
    var value = raw?.trim().toLowerCase() ?? '';
    if (value.contains('/')) return '';
    while (value.startsWith('.')) {
      value = value.substring(1);
    }
    return value;
  }

  static String _extensionOf(String path) {
    final clean = path.split('?').first.split('#').first;
    final slash = clean.lastIndexOf('/');
    final last = slash == -1 ? clean : clean.substring(slash + 1);
    final dot = last.lastIndexOf('.');
    if (dot == -1 || dot == last.length - 1) return '';
    return last.substring(dot + 1).toLowerCase();
  }
}

/// Renders a note's attachment inline.
///
/// Port of the attachment block in the web's `StudentNoteCard` /
/// `NoteDetailsClient`: an image is shown inline (tap to zoom), a video gets a
/// player, and any other file gets a row that opens it inside the app — PDFs
/// in the app's PDF viewer. An attachment whose type the API does not state is
/// tried as an image first, so a picture served from an extension-less URL
/// still shows as a picture.
class NoteAttachmentPreview extends StatelessWidget {
  const NoteAttachmentPreview({super.key, required this.attachment});

  /// The raw `attachment` value from the note's attributes.
  final dynamic attachment;

  /// Whether [raw] carries an attachment worth rendering.
  static bool hasAttachment(dynamic raw) => NoteAttachment.parse(raw) != null;

  @override
  Widget build(BuildContext context) {
    final parsed = NoteAttachment.parse(attachment);
    if (parsed == null) return const SizedBox.shrink();

    final Widget child;
    switch (parsed.kind) {
      case NoteAttachmentKind.image:
      case NoteAttachmentKind.unknown:
        child = _NoteImage(attachment: parsed);
      case NoteAttachmentKind.video:
        child = _NoteVideoPlayer(attachment: parsed);
      case NoteAttachmentKind.pdf:
      case NoteAttachmentKind.file:
        child = _NoteFileRow(attachment: parsed);
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

class _NoteImage extends StatefulWidget {
  const _NoteImage({required this.attachment});

  final NoteAttachment attachment;

  @override
  State<_NoteImage> createState() => _NoteImageState();
}

class _NoteImageState extends State<_NoteImage> {
  Timer? _retryTimer;
  int _attempt = 0;
  bool _retryScheduled = false;

  NoteAttachment get attachment => widget.attachment;

  @override
  void didUpdateWidget(covariant _NoteImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.attachment.url != attachment.url) {
      _retryTimer?.cancel();
      _retryScheduled = false;
      _attempt = 0;
    }
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }

  Future<void> _retry() async {
    final url = attachment.url;
    await CachedNetworkImage.evictFromCache(url);
    if (!mounted || attachment.url != url) return;
    setState(() {
      _retryScheduled = false;
      _attempt++;
    });
  }

  Widget _loadError(BuildContext context) {
    if (_attempt < 2 && !_retryScheduled) {
      _retryScheduled = true;
      _retryTimer = Timer(Duration(seconds: _attempt + 1), _retry);
    }
    if (_retryScheduled) {
      return const SizedBox(height: 160, child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
    }
    return Column(children: [
      if (attachment.kind == NoteAttachmentKind.unknown)
        _NoteFileRow(attachment: attachment)
      else
        const SizedBox(height: 100, child: Center(child: Icon(Icons.broken_image_outlined, size: 36))),
      IconButton(tooltip: 'notes.retry'.tr(), onPressed: _retry, icon: const Icon(Icons.refresh)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final url = attachment.url;
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              title: Text(
                attachment.name,
                style: const TextStyle(fontSize: 15),
              ),
            ),
            body: PhotoView(
              imageProvider: CachedNetworkImageProvider(url),
              minScale: PhotoViewComputedScale.contained,
              maxScale: PhotoViewComputedScale.covered * 4,
            ),
          ),
        ),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 300),
        child: CachedNetworkImage(
          key: ValueKey('$url:$_attempt'),
          imageUrl: url,
          width: double.infinity,
          fit: BoxFit.contain,
          placeholder: (context, _) => const SizedBox(
            height: 160,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          errorWidget: (context, _, _) => _loadError(context),
        ),
      ),
    );
  }
}

class _NoteVideoPlayer extends StatefulWidget {
  const _NoteVideoPlayer({required this.attachment});

  final NoteAttachment attachment;

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
    final uri = Uri.tryParse(widget.attachment.url);
    if (uri == null) {
      setState(() => _failed = true);
      return;
    }
    final controller = VideoPlayerController.networkUrl(uri);
    CaptureMediaGuard.attachVideoPlayer(controller);
    try {
      await controller.initialize();
      if (!mounted) {
        CaptureMediaGuard.detach(controller);
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } catch (_) {
      CaptureMediaGuard.detach(controller);
      await controller.dispose();
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    if (_controller != null) CaptureMediaGuard.detach(_controller!);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return _NoteFileRow(attachment: widget.attachment);
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

/// A non-media attachment: a row that opens the file inside the app.
class _NoteFileRow extends StatelessWidget {
  const _NoteFileRow({required this.attachment});

  final NoteAttachment attachment;

  bool get _isPdf => attachment.kind == NoteAttachmentKind.pdf;

  Future<void> _open(BuildContext context) async {
    final title = attachment.name.isEmpty
        ? 'notes.attachment'.tr()
        : attachment.name;
    if (_isPdf) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PdfViewerScreen(pdfUrl: attachment.url, title: title),
        ),
      );
      return;
    }
    final uri = Uri.tryParse(attachment.url);
    if (uri == null) return;
    // In-app browser view (Custom Tabs / SFSafariViewController), not an
    // external download.
    final opened = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('notes.open_attachment_failed'.tr())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _open(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(
              _isPdf ? Icons.picture_as_pdf_outlined : Icons.insert_drive_file_outlined,
              size: 18,
              color: AppColors.primaryBlue,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                attachment.name.isEmpty
                    ? 'notes.open_attachment'.tr()
                    : attachment.name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.primaryBlue,
                ),
              ),
            ),
            const Icon(
              Icons.chevron_right,
              size: 18,
              color: AppColors.primaryBlue,
            ),
          ],
        ),
      ),
    );
  }
}
