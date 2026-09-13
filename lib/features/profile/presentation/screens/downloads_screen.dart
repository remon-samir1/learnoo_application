import 'dart:io';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:path_provider/path_provider.dart';
import '../../../../core/services/encrypted_video_service.dart';
import '../../../course_content/presentation/screens/lecture_detail_screen.dart';

/// Grouped course data for display
class _CourseGroup {
  final String courseId;
  String courseName;
  final List<DownloadedVideo> videos;

  _CourseGroup({required this.courseId, this.courseName = '', required this.videos});
}

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  final _encryptedVideoService = EncryptedVideoService();
  List<DownloadedVideo> _downloadedVideos = [];
  List<_CourseGroup> _courseGroups = [];
  bool _isLoading = true;
  int _totalStorageUsed = 0;
  int _totalDeviceSpace = 0;
  int _freeDeviceSpace = 0;
  int _usedDeviceSpace = 0;

  @override
  void initState() {
    super.initState();
    _loadDownloads();
  }

  Future<void> _loadDownloads() async {
    await _encryptedVideoService.loadDownloadedVideos();
    await _loadDeviceStorageInfo();
    if (mounted) {
      setState(() {
        _downloadedVideos = _encryptedVideoService.getAllDownloadedVideos();
        // Recalculate total storage used from videos if directory calculation fails
        final videoStorage = _encryptedVideoService.getTotalStorageUsed();
        if (_totalStorageUsed < videoStorage) {
          _totalStorageUsed = videoStorage;
        }
        _groupVideosByCourse();
        _isLoading = false;
      });
    }
  }

  void _groupVideosByCourse() {
    final Map<String, _CourseGroup> groups = {};

    for (final video in _downloadedVideos) {
      if (!groups.containsKey(video.courseId)) {
        groups[video.courseId] = _CourseGroup(
          courseId: video.courseId,
          courseName: video.courseId, // Will be updated when we have course names
          videos: [],
        );
      }
      groups[video.courseId]!.videos.add(video);
    }

    // Sort videos within each group by download date (newest first)
    for (final group in groups.values) {
      group.videos.sort((a, b) => b.downloadDate.compareTo(a.downloadDate));
    }

    // Convert to list and sort groups by most recent video
    _courseGroups = groups.values.toList()
      ..sort((a, b) => b.videos.first.downloadDate.compareTo(a.videos.first.downloadDate));
  }

  Future<void> _loadDeviceStorageInfo() async {
    try {
      // Get app storage info
      final appDir = await getApplicationDocumentsDirectory();
      _totalStorageUsed = await _calculateDirectorySize(appDir);

      // Get device storage info
      if (Platform.isAndroid) {
        await _getAndroidStorageInfo();
      } else if (Platform.isIOS) {
        await _getIOSStorageInfo();
      }
    } catch (e) {
      debugPrint('Error getting storage info: $e');
    }
  }

  Future<int> _calculateDirectorySize(Directory directory) async {
    int totalSize = 0;
    try {
      if (await directory.exists()) {
        await for (final entity in directory.list(recursive: true, followLinks: false)) {
          if (entity is File) {
            try {
              totalSize += await entity.length();
            } catch (e) {
              // Ignore files that can't be accessed
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error calculating directory size: $e');
    }
    return totalSize;
  }

  Future<void> _getAndroidStorageInfo() async {
    try {
      // Get external storage directory for device-wide storage info
      final externalDir = await getExternalStorageDirectory();
      if (externalDir != null) {
        final stat = await FileStat.stat(externalDir.path);
        _totalDeviceSpace = stat.size;

        // Try to get more accurate storage info from /data or /storage
        final rootDir = Directory('/storage/emulated/0');
        if (await rootDir.exists()) {
          try {
            final result = await Process.run('stat', ['-f', rootDir.path]);
            if (result.exitCode == 0) {
              final output = result.stdout.toString();
              // Parse stat output for block size and available blocks
              final lines = output.split('\n');
              for (final line in lines) {
                if (line.contains('Block size:')) {
                  final match = RegExp(r'(\d+)').firstMatch(line);
                  if (match != null) {
                    final blockSize = int.tryParse(match.group(0)!) ?? 4096;
                  }
                }
              }
            }
          } catch (e) {
            // Process.run may fail, fallback to estimation
          }
        }
      }

      // Fallback: try to estimate from app directories
      if (_totalDeviceSpace == 0) {
        final appDir = await getApplicationDocumentsDirectory();
        final stat = await FileStat.stat(appDir.path);
        // Estimate based on available space in the filesystem
        _totalDeviceSpace = 64 * 1024 * 1024 * 1024; // 64GB fallback
      }

      // Estimate free space (rough approximation)
      _freeDeviceSpace = (_totalDeviceSpace * 0.3).toInt(); // Assume 30% free as fallback
      _usedDeviceSpace = _totalDeviceSpace - _freeDeviceSpace;
    } catch (e) {
      debugPrint('Error getting Android storage: $e');
    }
  }

  Future<void> _getIOSStorageInfo() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final stat = await FileStat.stat(appDir.path);

      // On iOS, we get limited storage info
      // Use NSFileManager attributes for better estimates if available
      _totalDeviceSpace = 128 * 1024 * 1024 * 1024; // 128GB typical fallback

      // Estimate free space based on app directory availability
      _freeDeviceSpace = (_totalDeviceSpace * 0.25).toInt(); // Assume 25% free
      _usedDeviceSpace = _totalDeviceSpace - _freeDeviceSpace;
    } catch (e) {
      debugPrint('Error getting iOS storage: $e');
    }
  }

  Future<void> _playOfflineVideo(DownloadedVideo video) async {
    debugPrint('[OFFLINE_PLAY] _playOfflineVideo called for ${video.id}');
    // Check if views are already exhausted
    if (video.currentViews >= video.maxViews && video.maxViews > 0) {
      // Delete the video
      await _encryptedVideoService.deleteDownloadedVideo(video.id);
      await _loadDownloads();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('course.maximum_views_reached'.tr()),
            backgroundColor: const Color(0xFFFF4B4B),
          ),
        );
      }
      return;
    }

    // Navigate to video player
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LectureDetailScreen(
          lectureId: video.chapterId,
          lectureTitle: video.lectureTitle,
          chapterId: video.chapterId,
          chapterTitle: video.chapterTitle,
          courseId: video.courseId,
          offlineVideoPath: video.encryptedFilePath,
          maxViews: video.maxViews,
        ),
      ),
    );

    // After returning from video player, refresh the list to show updated view counts
    await _loadDownloads();

    // Check if views are now exhausted and delete if needed
    final current = _encryptedVideoService.getDownloadedVideo(video.id);
    if (current != null && current.currentViews >= current.maxViews && current.maxViews > 0) {
      await _encryptedVideoService.deleteDownloadedVideo(video.id);
      await _loadDownloads();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('course.maximum_views_reached'.tr()),
            backgroundColor: const Color(0xFFFF4B4B),
          ),
        );
      }
    }
  }

  String get _formattedAppStorage {
    return _formatBytes(_totalStorageUsed);
  }

  String get _formattedDeviceStorage {
    return _formatBytes(_totalDeviceSpace);
  }

  String get _formattedFreeStorage {
    return _formatBytes(_freeDeviceSpace);
  }

  String get _formattedUsedDeviceStorage {
    return _formatBytes(_usedDeviceSpace);
  }

  double get _storageUsageRatio {
    if (_totalDeviceSpace <= 0) return 0.0;
    return _usedDeviceSpace / _totalDeviceSpace;
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 MB';
    const suffixes = ['B', 'KB', 'MB', 'GB'];
    var i = 0;
    double size = bytes.toDouble();
    while (size >= 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(1)} ${suffixes[i]}';
  }

  Future<void> _deleteVideo(String videoId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('downloads.delete_title'.tr()),
        content: Text('downloads.delete_confirm'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('downloads.cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFFF4B4B)),
            child: Text('downloads.delete'.tr()),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await _encryptedVideoService.deleteDownloadedVideo(videoId);
      if (success && mounted) {
        _loadDownloads();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('downloads.video_deleted'.tr()),
            backgroundColor: const Color(0xFF2DBC77),
          ),
        );
      }
    }
  }

  Future<void> _deleteAllVideos() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('downloads.delete_all_title'.tr()),
        content: Text('downloads.delete_all_confirm'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('downloads.cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFFF4B4B)),
            child: Text('downloads.delete_all'.tr()),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await _encryptedVideoService.deleteAllVideos();
      if (success && mounted) {
        _loadDownloads();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('downloads.all_deleted'.tr()),
            backgroundColor: const Color(0xFF2DBC77),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFBFF),
      body: Column(
        children: [
          _buildHeader(context),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _courseGroups.isEmpty
                    ? _buildEmptyState()
                    : RefreshIndicator(
                        onRefresh: _loadDownloads,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(20),
                          itemCount: _courseGroups.length + 1,
                          itemBuilder: (context, index) {
                            if (index == _courseGroups.length) {
                              return Padding(
                                padding: const EdgeInsets.only(top: 32),
                                child: _buildDeleteAllButton(),
                              );
                            }
                            final courseGroup = _courseGroups[index];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 24),
                              child: _buildCourseSection(courseGroup),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: const Color(0xFFEEF2FF),
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: FaIcon(
                FontAwesomeIcons.download,
                size: 48,
                color: Color(0xFF3451E5),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'downloads.no_downloads'.tr(),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1F2937),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'downloads.no_downloads_desc'.tr(),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 220,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF5A75FF), Color(0xFF8E7CFF)],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(40),
          bottomRight: Radius.circular(40),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.2),
                    ),
                  ),
                  const Expanded(
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.only(right: 48),
                        child: Text(
                          'Downloads',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const FaIcon(FontAwesomeIcons.hardDrive, color: Colors.white, size: 16),
                          const SizedBox(width: 8),
                          Text(
                            'Storage Used',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 13),
                          ),
                        ],
                      ),
                      Text(
                        _formattedAppStorage,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: _storageUsageRatio.clamp(0.0, 1.0),
                      backgroundColor: Colors.white.withValues(alpha: 0.2),
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                      minHeight: 6,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Used: $_formattedUsedDeviceStorage',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 11),
                      ),
                      Text(
                        'Free: $_formattedFreeStorage',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 11),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCourseSection(_CourseGroup courseGroup) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Course Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF3451E5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const FaIcon(
                FontAwesomeIcons.graduationCap,
                color: Colors.white,
                size: 16,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  courseGroup.courseName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${courseGroup.videos.length} ${courseGroup.videos.length == 1 ? 'video' : 'videos'}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Course Videos
        ...courseGroup.videos.map((video) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildDownloadItem(video),
            )),
      ],
    );
  }

  Widget _buildDownloadItem(DownloadedVideo video) {
    return InkWell(
      onTap: () => _playOfflineVideo(video),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 5,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Thumbnail with better handling
            Container(
              width: 100,
              height: 60,
              decoration: BoxDecoration(
                color: const Color(0xFFE5E7EB),
                borderRadius: BorderRadius.circular(10),
              ),
              clipBehavior: Clip.antiAlias,
              child: video.thumbnailUrl.isNotEmpty
                  ? Image.network(
                      video.thumbnailUrl,
                      fit: BoxFit.cover,
                      width: 100,
                      height: 60,
                      errorBuilder: (context, error, stackTrace) {
                        return _buildThumbnailPlaceholder();
                      },
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return _buildThumbnailLoading();
                      },
                    )
                  : _buildThumbnailPlaceholder(),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    video.chapterTitle,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1F2937)),
                  ),
                  Text(
                    video.lectureTitle,
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const FaIcon(
                        FontAwesomeIcons.fileVideo,
                        size: 10,
                        color: Colors.grey,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        video.formattedSize,
                        style: const TextStyle(color: Colors.grey, fontSize: 11),
                      ),
                      const SizedBox(width: 12),
                      const FaIcon(
                        FontAwesomeIcons.clock,
                        size: 10,
                        color: Colors.grey,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        video.duration,
                        style: const TextStyle(color: Colors.grey, fontSize: 11),
                      ),
                      const SizedBox(width: 12),
                      FaIcon(
                        FontAwesomeIcons.eye,
                        size: 10,
                        color: video.currentViews >= video.maxViews
                            ? const Color(0xFFFF4B4B)
                            : const Color(0xFF2DBC77),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${video.currentViews}/${video.maxViews}',
                        style: TextStyle(
                          color: video.currentViews >= video.maxViews
                              ? const Color(0xFFFF4B4B)
                              : const Color(0xFF2DBC77),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFFFFF1F1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: IconButton(
                onPressed: () => _deleteVideo(video.id),
                icon: const Icon(Icons.delete_outline, color: Color(0xFFFF4B4B), size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThumbnailPlaceholder() {
    return Container(
      color: const Color(0xFFE5E7EB),
      child: const Center(
        child: FaIcon(
          FontAwesomeIcons.play,
          color: Colors.white,
          size: 24,
        ),
      ),
    );
  }

  Widget _buildThumbnailLoading() {
    return Container(
      color: const Color(0xFFE5E7EB),
      child: const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        ),
      ),
    );
  }

  Widget _buildDeleteAllButton() {
    return SizedBox(
      width: double.infinity,
      child: TextButton.icon(
        onPressed: _deleteAllVideos,
        icon: const Icon(Icons.delete_outline, size: 18),
        label: Text('downloads.delete_all'.tr()),
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFFFF4B4B),
          backgroundColor: const Color(0xFFFFF1F1),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
      ),
    );
  }
}
