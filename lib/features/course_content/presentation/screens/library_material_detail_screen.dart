import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/services/device_downloads.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/library_repository.dart';
import '../../domain/library_material.dart';
import '../../services/library_download_service.dart';
import 'pdf_reviewer_screen.dart';
import 'unlock_material_screen.dart';

/// One electronic-library material — the app's version of the website's
/// `StudentLibraryMaterialDetail`.
///
/// Same rules as the website: the material is locked on `code_activation`, the
/// download button works only for an unlocked material whose attachment is
/// `downloadable`, and a downloaded PDF carries the `library` watermark.
class LibraryMaterialDetailScreen extends StatefulWidget {
  const LibraryMaterialDetailScreen({
    super.key,
    required this.materialId,
    this.initialMaterial,
  });

  final String materialId;

  /// The list row, shown immediately while the detail request is in flight.
  final dynamic initialMaterial;

  @override
  State<LibraryMaterialDetailScreen> createState() =>
      _LibraryMaterialDetailScreenState();
}

class _LibraryMaterialDetailScreenState
    extends State<LibraryMaterialDetailScreen> {
  final _repository = LibraryRepository();
  final _downloads = LibraryDownloadService();

  dynamic _material;
  bool _isLoading = true;
  bool _loadFailed = false;

  bool _isDownloading = false;
  double _downloadProgress = 0;

  @override
  void initState() {
    super.initState();
    _material = widget.initialMaterial;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _loadFailed = false;
    });

    final result = await _repository.getLibraryById(widget.materialId);
    if (!mounted) return;

    setState(() {
      _isLoading = false;
      if (result['success'] == true && result['data'] is Map) {
        _material = result['data'];
      } else if (_material == null) {
        _loadFailed = true;
      }
    });
  }

  /// First attachment, as on the website (its per-attachment list is disabled).
  Map<String, dynamic>? get _selected {
    final attachments = libraryAttachments(_material);
    return attachments.isEmpty ? null : attachments.first;
  }

  Future<void> _unlock() async {
    final unlocked = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => UnlockMaterialScreen(
          library: _material,
          returnOnSuccess: true,
        ),
      ),
    );
    if (unlocked == true && mounted) await _load();
  }

  void _openDocument(Map<String, dynamic> attachment) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PdfReviewerScreen(
          pdfUrl: attachmentPath(attachment),
          title: attachmentName(attachment).isNotEmpty
              ? attachmentName(attachment)
              : libraryTitle(_material),
          watermarkType: 'library',
        ),
      ),
    );
  }

  Future<void> _download(Map<String, dynamic> attachment) async {
    if (_isDownloading) return;
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0;
    });

    final result = await _downloads.download(
      material: _material,
      attachment: attachment,
      onProgress: (value) {
        if (mounted) setState(() => _downloadProgress = value);
      },
    );

    if (!mounted) return;
    setState(() => _isDownloading = false);

    if (!result.isSuccess) {
      _showMessage(_failureMessage(result.failure), isError: true);
      return;
    }

    final saved = result.saved!;
    final location = Platform.isIOS
        ? 'library.saved_location_ios'.tr()
        : 'library.saved_location_android'
            .tr(args: [DeviceDownloads.folderName]);
    final done = result.watermarked
        ? 'library.download_done_watermarked'.tr()
        : 'library.download_done'.tr();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$done\n$location'),
        backgroundColor: const Color(0xFF059669),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: 'library.open_file'.tr(),
          textColor: Colors.white,
          onPressed: () async {
            final opened = await _downloads.open(saved);
            if (!opened && mounted) {
              _showMessage('library.no_app_to_open'.tr(), isError: true);
            }
          },
        ),
      ),
    );

    // iOS has no public Downloads folder: let the student pick a place in
    // Files (or another app) for the watermarked copy.
    if (Platform.isIOS) {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(saved.uri, mimeType: saved.mimeType)],
          subject: libraryTitle(_material),
        ),
      );
    }
  }

  String _failureMessage(LibraryDownloadFailure? failure) {
    switch (failure) {
      case LibraryDownloadFailure.locked:
        return 'library.locked_material'.tr();
      case LibraryDownloadFailure.notDownloadable:
        return 'library.not_downloadable'.tr();
      case LibraryDownloadFailure.missingFile:
        return 'library.no_attachments'.tr();
      case LibraryDownloadFailure.watermark:
        return 'library.download_watermark_failed'.tr();
      case LibraryDownloadFailure.storagePermission:
        return 'library.storage_permission_denied'.tr();
      case LibraryDownloadFailure.save:
        return 'library.download_save_failed'.tr();
      case LibraryDownloadFailure.network:
      case null:
        return 'library.download_failed'.tr();
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : const Color(0xFF059669),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0F172A),
        elevation: 0,
        title: Text(
          'library.back_to_library'.tr(),
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_material == null && _isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_material == null || _loadFailed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'library.detail_load_error'.tr(),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFFB91C1C)),
              ),
              TextButton(onPressed: _load, child: Text('library.retry'.tr())),
            ],
          ),
        ),
      );
    }

    final locked = libraryIsLocked(_material);
    final selected = _selected;
    final canDownload = LibraryDownloadService.canDownload(_material, selected);
    final isPdf = selected != null && attachmentIsPdf(selected);
    final canOpen = !locked && selected != null && attachmentPath(selected).isNotEmpty;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _buildHeader(locked),
          const SizedBox(height: 16),
          _buildDownloadButton(selected, canDownload, locked),
          const SizedBox(height: 16),
          _buildPreviewPanel(locked, canOpen, isPdf, selected),
          const SizedBox(height: 16),
          _buildCover(),
          if (libraryDescription(_material).isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildDescription(),
          ],
          if (locked) ...[
            const SizedBox(height: 16),
            _buildLockedCard(),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader(bool locked) {
    final type = libraryMaterialType(_material);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            libraryTitle(_material),
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'library.course_ref'.tr(args: [libraryCourseIdsLabel(_material)]),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (type.isNotEmpty)
                _chip(
                  _materialTypeLabel(type),
                  const Color(0xFFEEF2FF),
                  const Color(0xFF4338CA),
                ),
              Text(
                '${'library.price_label'.tr()}: ${libraryPriceLabel(_material)}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF64748B),
                ),
              ),
              locked
                  ? _chip(
                      'library.locked_material'.tr(),
                      const Color(0xFFFEF3C7),
                      const Color(0xFF78350F),
                    )
                  : _chip(
                      'library.unlocked_badge'.tr(),
                      const Color(0xFFD1FAE5),
                      const Color(0xFF065F46),
                    ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDownloadButton(
    Map<String, dynamic>? selected,
    bool canDownload,
    bool locked,
  ) {
    final watermark = _downloads.isWatermarkEnabled;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 48,
          child: ElevatedButton(
            onPressed: canDownload && !_isDownloading
                ? () => _download(selected!)
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryBlue,
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFFF1F5F9),
              disabledForegroundColor: const Color(0xFF94A3B8),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _isDownloading
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _downloadProgress > 0
                            ? '${(_downloadProgress * 100).round()}%'
                            : 'library.downloading'.tr(),
                      ),
                    ],
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.download_rounded, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'library.download'.tr(),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      if (canDownload && watermark) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.water_drop_outlined, size: 16),
                      ],
                    ],
                  ),
          ),
        ),
        // The website only greys the button out; a one-line reason is shown
        // here so a disabled button is not a mystery on a phone.
        if (!locked && selected != null && !attachmentIsDownloadable(selected))
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'library.not_downloadable'.tr(),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Color(0xFFB45309)),
            ),
          )
        else if (canDownload && watermark)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'library.download_includes_watermark'.tr(),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Color(0xFF1D4ED8)),
            ),
          ),
      ],
    );
  }

  Widget _buildPreviewPanel(
    bool locked,
    bool canOpen,
    bool isPdf,
    Map<String, dynamic>? selected,
  ) {
    Widget content;

    if (locked) {
      content = _panelMessage(
        icon: Icons.lock_outline,
        title: 'library.locked_material'.tr(),
        body: 'library.activate_course_hint'.tr(),
      );
    } else if (canOpen && isPdf) {
      content = Column(
        children: [
          if (_downloads.isWatermarkEnabled)
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: _chip(
                'library.watermarked'.tr(),
                const Color(0xFFEFF6FF),
                const Color(0xFF1D4ED8),
                icon: Icons.water_drop_outlined,
              ),
            ),
          const SizedBox(height: 12),
          const Icon(Icons.picture_as_pdf_outlined,
              size: 48, color: Color(0xFFE74C3C)),
          const SizedBox(height: 8),
          Text(
            attachmentName(selected!),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            formatLibraryAttachmentSize(attachmentAttributes(selected)['size']),
            style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
          ),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            onPressed: () => _openDocument(selected),
            icon: const Icon(Icons.menu_book_outlined, size: 18),
            label: Text('library.open_material'.tr()),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryBlue,
              foregroundColor: Colors.white,
              elevation: 0,
            ),
          ),
        ],
      );
    } else if (canOpen) {
      content = _panelMessage(
        icon: Icons.insert_drive_file_outlined,
        title: 'library.preview_unavailable_title'.tr(),
        body: 'library.preview_unavailable_body'.tr(),
      );
    } else {
      content = _panelMessage(
        icon: Icons.description_outlined,
        title: 'library.pdf_viewer_title'.tr(),
        body: 'library.no_attachments'.tr(),
      );
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDecoration(),
      child: content,
    );
  }

  Widget _panelMessage({
    required IconData icon,
    required String title,
    required String body,
  }) {
    return Column(
      children: [
        Icon(icon, size: 48, color: const Color(0xFF94A3B8)),
        const SizedBox(height: 10),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xFF1E293B),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          body,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
        ),
      ],
    );
  }

  Widget _buildCover() {
    final cover = libraryCover(_material);
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(
        aspectRatio: 3 / 4,
        child: cover.isEmpty
            ? Container(
                color: const Color(0xFFF1F5F9),
                child: const Icon(Icons.lock_outline,
                    size: 48, color: Color(0xFFCBD5E1)),
              )
            : CachedNetworkImage(
                imageUrl: cover,
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => Container(
                  color: const Color(0xFFF1F5F9),
                  child: const Icon(Icons.menu_book,
                      size: 48, color: Color(0xFFCBD5E1)),
                ),
              ),
      ),
    );
  }

  Widget _buildDescription() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'library.description_heading'.tr(),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            libraryDescription(_material),
            style: const TextStyle(
              fontSize: 14,
              height: 1.6,
              color: Color(0xFF475569),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLockedCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'library.activate_course_hint'.tr(),
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: Color(0xFF451A03),
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _unlock,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryBlue,
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            child: Text('library.unlock'.tr()),
          ),
        ],
      ),
    );
  }

  String _materialTypeLabel(String type) {
    return kLibraryMaterialTypes.contains(type)
        ? 'library.material_type.$type'.tr()
        : type;
  }

  static BoxDecoration _cardDecoration() => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      );

  static Widget _chip(
    String label,
    Color background,
    Color foreground, {
    IconData? icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: foreground),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: foreground,
            ),
          ),
        ],
      ),
    );
  }
}
