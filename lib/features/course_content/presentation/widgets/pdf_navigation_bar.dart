import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import '../../../../core/theme/app_colors.dart';

/// Zoom and page controls under a PDF.
///
/// The app's reader had annotation tools but no way to zoom or to reach a
/// specific page, which the web reader offers. This bar adds both: zoom out /
/// zoom in around the viewer's own zoom level, the current page out of the
/// total, and a tap on that indicator to jump straight to a page number.
class PdfNavigationBar extends StatelessWidget {
  const PdfNavigationBar({
    super.key,
    required this.controller,
    required this.currentPage,
    required this.pageCount,
  });

  final PdfViewerController controller;

  /// 1-based page currently in view, or 0 before the document loads.
  final int currentPage;

  final int pageCount;

  /// Zoom bounds the Syncfusion viewer accepts.
  static const double _minZoom = 1.0;
  static const double _maxZoom = 3.0;
  static const double _zoomStep = 0.25;

  void _zoom(double delta) {
    final next = (controller.zoomLevel + delta).clamp(_minZoom, _maxZoom);
    controller.zoomLevel = next;
  }

  Future<void> _promptForPage(BuildContext context) async {
    if (pageCount <= 1) return;

    // The dialog owns its text controller. Disposing it here, right after
    // `showDialog` returned, crashed: the route's closing animation still
    // rebuilds the TextField after the future completes.
    final page = await showDialog<int>(
      context: context,
      builder: (_) => _PageJumpDialog(
        initialPage: currentPage,
        pageCount: pageCount,
      ),
    );

    if (page == null) return;
    // Out-of-range input is clamped rather than rejected, so a typo still lands
    // somewhere sensible.
    controller.jumpToPage(page.clamp(1, pageCount));
  }

  @override
  Widget build(BuildContext context) {
    final zoomPercent = (controller.zoomLevel * 100).round();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            IconButton(
              tooltip: 'pdf.zoom_out'.tr(),
              icon: const Icon(Icons.zoom_out),
              onPressed: controller.zoomLevel <= _minZoom
                  ? null
                  : () => _zoom(-_zoomStep),
            ),
            SizedBox(
              width: 52,
              child: Text(
                '$zoomPercent%',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF475569),
                ),
              ),
            ),
            IconButton(
              tooltip: 'pdf.zoom_in'.tr(),
              icon: const Icon(Icons.zoom_in),
              onPressed: controller.zoomLevel >= _maxZoom
                  ? null
                  : () => _zoom(_zoomStep),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'pdf.previous_page'.tr(),
              icon: const Icon(Icons.keyboard_arrow_up),
              onPressed:
                  currentPage <= 1 ? null : () => controller.previousPage(),
            ),
            InkWell(
              onTap: () => _promptForPage(context),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Text(
                  pageCount == 0
                      ? '—'
                      : 'pdf.page_of'.tr(args: ['$currentPage', '$pageCount']),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryBlue,
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'pdf.next_page'.tr(),
              icon: const Icon(Icons.keyboard_arrow_down),
              onPressed: currentPage >= pageCount
                  ? null
                  : () => controller.nextPage(),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Go to page" prompt. Stateful so the text controller lives exactly as long
/// as the dialog, including its exit animation.
class _PageJumpDialog extends StatefulWidget {
  const _PageJumpDialog({required this.initialPage, required this.pageCount});

  final int initialPage;
  final int pageCount;

  @override
  State<_PageJumpDialog> createState() => _PageJumpDialogState();
}

class _PageJumpDialogState extends State<_PageJumpDialog> {
  late final TextEditingController _text = TextEditingController(
    text: widget.initialPage > 0 ? '${widget.initialPage}' : '',
  );

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.pop(context, int.tryParse(_text.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('pdf.go_to_page'.tr()),
      content: TextField(
        controller: _text,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          hintText: 'pdf.page_range'.tr(args: ['${widget.pageCount}']),
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('profile.cancel'.tr()),
        ),
        TextButton(
          onPressed: _submit,
          child: Text('pdf.go'.tr()),
        ),
      ],
    );
  }
}
