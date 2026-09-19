import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Image attachments of a community post: one large image, or a horizontal
/// strip when there are several. Each image shows a spinner while loading, a
/// placeholder when it fails, and opens full screen on tap.
class PostImages extends StatelessWidget {
  const PostImages({super.key, required this.images});

  final List<String> images;

  @override
  Widget build(BuildContext context) {
    if (images.isEmpty) return const SizedBox.shrink();

    if (images.length == 1) {
      return _PostImageTile(
        url: images.first,
        width: double.infinity,
        height: 220,
        onTap: () => _openViewer(context, 0),
      );
    }

    return SizedBox(
      height: 170,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: images.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) => _PostImageTile(
          url: images[index],
          width: 220,
          height: 170,
          onTap: () => _openViewer(context, index),
        ),
      ),
    );
  }

  void _openViewer(BuildContext context, int initialIndex) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => _PostImageViewer(
          images: images,
          initialIndex: initialIndex,
        ),
      ),
    );
  }
}

class _PostImageTile extends StatelessWidget {
  const _PostImageTile({
    required this.url,
    required this.width,
    required this.height,
    required this.onTap,
  });

  final String url;
  final double width;
  final double height;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final placeholderColor = AppColors.isDark(context)
        ? const Color(0xFF262A36)
        : const Color(0xFFF0F2FF);

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: CachedNetworkImage(
          imageUrl: url,
          width: width,
          height: height,
          fit: BoxFit.cover,
          placeholder: (context, _) => Container(
            width: width,
            height: height,
            color: placeholderColor,
            child: const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.accentBlue),
                ),
              ),
            ),
          ),
          errorWidget: (context, _, _) => Container(
            width: width,
            height: height,
            color: placeholderColor,
            child: Center(
              child: Icon(
                Icons.broken_image_outlined,
                color: AppColors.muted(context),
                size: 36,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PostImageViewer extends StatelessWidget {
  const _PostImageViewer({required this.images, required this.initialIndex});

  final List<String> images;
  final int initialIndex;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: PageView.builder(
        controller: PageController(initialPage: initialIndex),
        itemCount: images.length,
        itemBuilder: (context, index) => InteractiveViewer(
          minScale: 1,
          maxScale: 4,
          child: Center(
            child: CachedNetworkImage(
              imageUrl: images[index],
              fit: BoxFit.contain,
              placeholder: (context, _) => const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
              errorWidget: (context, _, _) => const Icon(
                Icons.broken_image_outlined,
                color: Colors.white54,
                size: 48,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
