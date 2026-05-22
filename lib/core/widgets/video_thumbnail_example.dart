import 'package:flutter/material.dart';
import 'video_thumbnail_widget.dart';

/// Example usage of VideoThumbnailWidget in a ListView
class VideoThumbnailExample extends StatelessWidget {
  final List<Map<String, dynamic>> chapters;

  const VideoThumbnailExample({
    super.key,
    required this.chapters,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: chapters.length,
      itemBuilder: (context, index) {
        final chapter = chapters[index];
        final String title = chapter['title'] ?? 'Untitled';
        final String thumbnail = chapter['thumbnail'] ?? '';
        final String videoUrl = chapter['video'] ?? '';

        return ListTile(
          leading: thumbnail.isNotEmpty
              // Use network thumbnail if available
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    thumbnail,
                    width: 80,
                    height: 60,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      // Fallback to video thumbnail on network error
                      return VideoThumbnailWidget(
                        videoUrl: videoUrl,
                        width: 80,
                        height: 60,
                      );
                    },
                  ),
                )
              // Otherwise use video thumbnail widget
              : VideoThumbnailWidget(
                  videoUrl: videoUrl,
                  width: 80,
                  height: 60,
                  borderRadius: 12,
                  showPlayIcon: true,
                  isLocked: chapter['is_locked'] ?? false,
                  onTap: () {
                    // Handle tap
                    debugPrint('Tapped on $title');
                  },
                ),
          title: Text(title),
          subtitle: Text(chapter['duration'] ?? '00:00'),
          onTap: () {
            // Navigate to video player
          },
        );
      },
    );
  }
}

/// Simple standalone usage example
class SimpleVideoThumbnailExample extends StatelessWidget {
  const SimpleVideoThumbnailExample({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Video Thumbnail Example')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Example 1: Basic usage
            VideoThumbnailWidget(
              videoUrl: 'https://example.com/video.mp4',
              width: 120,
              height: 90,
              onTap: () => debugPrint('Video tapped'),
            ),

            const SizedBox(height: 20),

            // Example 2: Locked state
            const VideoThumbnailWidget(
              videoUrl: 'https://example.com/video2.mp4',
              width: 120,
              height: 90,
              isLocked: true,
            ),

            const SizedBox(height: 20),

            // Example 3: No play icon overlay
            const VideoThumbnailWidget(
              videoUrl: 'https://example.com/video3.mp4',
              width: 120,
              height: 90,
              showPlayIcon: false,
            ),
          ],
        ),
      ),
    );
  }
}
