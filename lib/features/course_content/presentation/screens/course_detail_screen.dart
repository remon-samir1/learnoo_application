import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:shimmer/shimmer.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import '../../../../core/widgets/video_thumbnail_widget.dart';
import '../../../../core/network/api_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/lecture_repository.dart';
import '../../data/live_room_repository.dart';
import '../../data/models/live_room.dart' as lr;
import '../../services/attachment_permission_service.dart';
import '../../data/course_repository.dart';
import '../../../exams/domain/usecases/exam_access_usecase.dart';
import '../../../exams/models/quiz_models.dart';
import '../../../exams/presentation/screens/quiz_screen.dart';
import '../../../community/data/repositories/community_repository.dart';
import '../../../community/data/models/post_model.dart';
import '../../../community/data/models/social_link_model.dart';
import '../../../community/presentation/screens/create_post_screen.dart';
import 'lecture_detail_screen.dart';
import 'pdf_reviewer_screen.dart';

class CourseDetailScreen extends StatefulWidget {
  final String courseId;
  final String title;
  final String thumbnail;
  final String price;
  final String description;

  const CourseDetailScreen({
    super.key,
    required this.courseId,
    required this.title,
    required this.thumbnail,
    required this.price,
    required this.description,
  });

  @override
  State<CourseDetailScreen> createState() => _CourseDetailScreenState();
}

class _CourseDetailScreenState extends State<CourseDetailScreen>
    with SingleTickerProviderStateMixin {
  final _lectureRepository = LectureRepository();
  final _courseRepository = CourseRepository();
  final _liveRoomRepository = LiveRoomRepository();
  final _communityRepository = CommunityRepository();
  late TabController _tabController;

  bool _isLoadingLectures = true;
  bool _isLoadingExams = true;
  bool _isLoadingLiveRooms = true;
  bool _isLoadingCommunity = true;
  bool _isLoadingSocialLinks = false;
  List<dynamic> _lectures = [];
  List<Quiz> _exams = [];
  List<lr.LiveRoom> _liveRooms = [];
  List<Post> _posts = [];
  List<SocialLink> _socialLinks = [];
  List<bool> _isExpanded = [];
  String _qaFilter = 'All';
  String? _communityErrorMessage;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadData();
  }

  Future<void> _loadData() async {
    await Future.wait([_loadLectures(), _loadExams()]);
    await Future.wait([
      _loadLiveRooms(),
      _loadCommunityPosts(),
      _loadSocialLinks(),
    ]);
  }

  Future<void> _loadExams() async {
    setState(() => _isLoadingExams = true);
    try {
      final courseResult = await _courseRepository.getCourseById(
        widget.courseId,
      );
      if (!mounted) return;

      if (courseResult['success']) {
        final courseData = courseResult['data'] as Map<String, dynamic>? ?? {};
        final attributes =
            courseData['attributes'] as Map<String, dynamic>? ?? {};
        final rawExams = attributes['exams'];
        final examsList = rawExams is List
            ? rawExams
            : rawExams is Map<String, dynamic> && rawExams['data'] is List
            ? rawExams['data'] as List<dynamic>
            : <dynamic>[];

        final courseExams = examsList
            .whereType<Map<String, dynamic>>()
            .map((examJson) => Quiz.fromJson(examJson))
            .toList();

        setState(() {
          _exams = courseExams;
          _isLoadingExams = false;
        });
      } else if (mounted) {
        setState(() => _isLoadingExams = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingExams = false);
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadLectures() async {
    if (widget.courseId.isEmpty) {
      setState(() => _isLoadingLectures = false);
      return;
    }

    setState(() => _isLoadingLectures = true);
    try {
      final courseId = int.tryParse(widget.courseId);
      final result = await _lectureRepository.getLectures(courseId: courseId);
      if (result['success'] && mounted) {
        final allLectures = result['data'] as List<dynamic>? ?? [];
        final filteredLectures = allLectures.where((lecture) {
          final attributes = lecture['attributes'] ?? {};
          final lectureCourseId = attributes['course_id']?.toString();
          return lectureCourseId == widget.courseId;
        }).toList();

        setState(() {
          _lectures = filteredLectures;
          _isExpanded = List<bool>.filled(filteredLectures.length, false);
          _isLoadingLectures = false;
        });
      } else if (mounted) {
        setState(() => _isLoadingLectures = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingLectures = false);
      }
    }
  }

  Future<void> _loadLiveRooms() async {
    if (!mounted) return;
    setState(() => _isLoadingLiveRooms = true);
    try {
      final result = await _liveRoomRepository.getLiveRooms();
      if (result['success'] && mounted) {
        final allLiveRooms = result['data'] as List<lr.LiveRoom>;
        final courseIdInt = int.tryParse(widget.courseId);
        setState(() {
          _liveRooms = allLiveRooms
              .where((room) => room.courseId == courseIdInt)
              .toList();
          _isLoadingLiveRooms = false;
        });
      } else if (mounted) {
        setState(() => _isLoadingLiveRooms = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingLiveRooms = false);
      }
    }
  }

  Future<void> _loadCommunityPosts() async {
    if (!mounted) return;
    setState(() {
      _isLoadingCommunity = true;
      _communityErrorMessage = null;
    });

    try {
      final courseIdInt = int.tryParse(widget.courseId);
      if (courseIdInt == null) {
        setState(() {
          _posts = [];
          _isLoadingCommunity = false;
        });
        return;
      }

      final result = await _communityRepository.getPosts(courseId: courseIdInt);
      if (result['success'] && result['data'] != null && mounted) {
        final posts = result['data'] as List<Post>;
        setState(() {
          _posts = posts;
          _isLoadingCommunity = false;
        });
      } else if (mounted) {
        setState(() {
          _posts = [];
          _isLoadingCommunity = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _communityErrorMessage = 'Failed to load community posts';
          _isLoadingCommunity = false;
        });
      }
    }
  }

  Future<void> _loadSocialLinks() async {
    if (!mounted) return;
    setState(() => _isLoadingSocialLinks = true);

    try {
      final result = await _communityRepository.getSocialLinks();
      if (result['success'] && mounted) {
        final allLinks = result['data'] as List<SocialLink>;
        final courseIdInt = int.tryParse(widget.courseId);

        final filteredLinks = allLinks.where((link) {
          return link.attributes.courses.any(
            (course) => course.id == widget.courseId,
          );
        }).toList();

        setState(() {
          _socialLinks = filteredLinks;
          _isLoadingSocialLinks = false;
        });
      } else if (mounted) {
        setState(() => _isLoadingSocialLinks = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingSocialLinks = false);
      }
    }
  }

  Future<void> _handleReaction(Post post, String reactionType) async {
    final currentReaction = post.attributes.userReaction;
    Post updatedPost;

    if (currentReaction == reactionType) {
      final result = await _communityRepository.removeReaction(post.id);
      if (result['success']) {
        updatedPost = Post(
          id: post.id,
          type: post.type,
          attributes: PostAttributes(
            user: post.attributes.user,
            course: post.attributes.course,
            status: post.attributes.status,
            postType: post.attributes.postType,
            title: post.attributes.title,
            content: post.attributes.content,
            tags: post.attributes.tags,
            reactionsCount: post.attributes.reactionsCount - 1,
            userReaction: null,
            createdAt: post.attributes.createdAt,
            updatedAt: post.attributes.updatedAt,
          ),
        );
      } else {
        return;
      }
    } else {
      final result = await _communityRepository.reactToPost(
        post.id,
        reactionType,
      );
      if (result['success']) {
        final newCount = currentReaction != null
            ? post.attributes.reactionsCount
            : post.attributes.reactionsCount + 1;
        updatedPost = Post(
          id: post.id,
          type: post.type,
          attributes: PostAttributes(
            user: post.attributes.user,
            course: post.attributes.course,
            status: post.attributes.status,
            postType: post.attributes.postType,
            title: post.attributes.title,
            content: post.attributes.content,
            tags: post.attributes.tags,
            reactionsCount: newCount,
            userReaction: reactionType,
            createdAt: post.attributes.createdAt,
            updatedAt: post.attributes.updatedAt,
          ),
        );
      } else {
        return;
      }
    }

    setState(() {
      final index = _posts.indexWhere((p) => p.id == post.id);
      if (index != -1) {
        _posts[index] = updatedPost;
      }
    });
  }

  void _navigateToCreatePost() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (context) => const CreatePostScreen()),
    );
    if (result == true) {
      _loadCommunityPosts();
    }
  }

  void _navigateToLecture(dynamic lecture, dynamic chapter) {
    final lectureId = lecture['id']?.toString() ?? '';
    final lectureTitle =
        lecture['attributes']?['title']?.toString() ??
        'course.untitled_lecture'.tr();
    final chapterId = chapter['id']?.toString() ?? '';
    final chapterTitle =
        chapter['attributes']?['title']?.toString() ??
        'course.untitled_chapter'.tr();
    // course_id comes directly from the chapter attributes in the chapters API response
    final courseId =
        chapter['attributes']?['course_id']?.toString() ?? widget.courseId;
    // Get max_views from chapter data if available
    final maxViews = int.tryParse(
      chapter['attributes']?['max_views']?.toString() ?? '',
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LectureDetailScreen(
          lectureId: lectureId,
          lectureTitle: lectureTitle,
          chapterId: chapterId,
          chapterTitle: chapterTitle,
          courseId: courseId,
          maxViews: maxViews,
        ),
      ),
    );
  }

  void _navigateToPdfViewer(dynamic chapter, List<dynamic> attachments) {
    final chapterAttrs = chapter['attributes'] ?? {};
    final chapterId = chapter['id']?.toString() ?? '';
    final chapterTitle =
        chapterAttrs['title']?.toString() ?? 'course.untitled_chapter'.tr();
    final isLocked = chapterAttrs['is_locked'] as bool? ?? false;
    final isActivated = chapterAttrs['is_activated'] as bool? ?? false;
    final isFreePreview = chapterAttrs['is_free_preview'] as bool? ?? false;
    final isFreePreviewAttachment =
        chapterAttrs['is_free_preview_attachment'] as bool? ?? false;
    final maxViews =
        int.tryParse(chapterAttrs['max_views']?.toString() ?? '') ?? 0;

    // Find first PDF attachment
    final pdfAttachment = attachments.firstWhere((att) {
      final ext =
          att['attributes']?['extension']?.toString().toLowerCase() ?? '';
      return ext == 'pdf';
    }, orElse: () => null);

    if (pdfAttachment == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('course.no_pdf_available'.tr())));
      return;
    }

    final attachmentAttrs = pdfAttachment['attributes'] ?? {};
    final fileIsLocked = attachmentAttrs['is_locked'] as bool? ?? false;
    final pdfPath = attachmentAttrs['path']?.toString() ?? '';
    final pdfName = attachmentAttrs['name']?.toString() ?? chapterTitle;

    // Check access control using AttachmentPermissionService
    final permissionService = AttachmentPermissionService();
    final canOpen = permissionService.canOpenAttachment(
      fileIsLocked: fileIsLocked,
      chapterIsLocked: isLocked,
      chapterIsActivated: isActivated,
      chapterIsFreePreview: isFreePreview,
      chapterIsFreePreviewAttachment: isFreePreviewAttachment,
      currentViews: 0, // TODO: Track current views if needed
      maxViews: maxViews,
    );

    if (!canOpen) {
      // Show bottom sheet modal for PDF-only chapters
      _showPdfUnlockBottomSheet(
        chapterId: int.tryParse(chapterId) ?? 0,
        chapterTitle: chapterTitle,
        attachments: attachments,
        pdfPath: pdfPath,
        pdfName: pdfName,
      );
      return;
    }

    // Process PDF URL
    String processedUrl = pdfPath;
    if (!processedUrl.startsWith('http')) {
      processedUrl = processedUrl.replaceAll('\\', '/');
      if (!processedUrl.startsWith('/')) {
        processedUrl = '/$processedUrl';
      }
      processedUrl = '${ApiConstants.baseUrl}$processedUrl';
    }

    // Navigate to PDF viewer
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PdfReviewerScreen(
          pdfUrl: processedUrl,
          title: pdfName,
          // allowDownload: false,
        ),
      ),
    );
  }

  /// Show bottom sheet modal for PDF-only chapter activation
  void _showPdfUnlockBottomSheet({
    required int chapterId,
    required String chapterTitle,
    required List<dynamic> attachments,
    required String pdfPath,
    required String pdfName,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.5,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFFE74C3C), Color(0xFFFF6B35)],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFE74C3C).withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: FaIcon(
                          FontAwesomeIcons.filePdf,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            chapterTitle,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1F2937),
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${attachments.length} ${attachments.length == 1 ? 'file' : 'files'}',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const Divider(height: 1),
              const SizedBox(height: 24),
              // Locked message
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF0F0),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFFE74C3C),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE74C3C),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const FaIcon(
                          FontAwesomeIcons.lock,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'course.attachment_locked'.tr(),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFE74C3C),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'course.unlock_to_access_attachment'.tr(),
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey[700],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              // Activation button
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    // Show the activation dialog
                    final permissionService = AttachmentPermissionService();
                    permissionService.showLockedAttachmentDialog(
                      context: context,
                      chapterId: chapterId,
                      courseId: widget.courseId,
                      onRefresh: _loadLectures,
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE74C3C),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 56),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const FaIcon(FontAwesomeIcons.key, size: 18),
                      const SizedBox(width: 12),
                      Text(
                        'course.unlock_now'.tr(),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Cancel button
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.grey[600],
                    minimumSize: const Size(double.infinity, 48),
                  ),
                  child: Text(
                    'course.cancel'.tr(),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          _buildHeader(),
          // _buildProgressSection(),
          _buildTabBar(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _isLoadingLectures
                    ? _buildLecturesSkeleton()
                    : _buildLecturesTab(),
                _buildExamsTab(),
                _buildLiveTab(),
                _buildCommunityTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Stack(
      children: [
        SizedBox(
          height: 320,
          width: double.infinity,
          child: CachedNetworkImage(
            imageUrl: widget.thumbnail.isNotEmpty
                ? widget.thumbnail
                : 'https://images.unsplash.com/photo-1554224155-6726b3ff858f?w=800',
            fit: BoxFit.cover,
            memCacheWidth: 800,
            memCacheHeight: 640,
            placeholder: (context, url) => Container(
              height: 320,
              width: double.infinity,
              color: Colors.grey[300],
            ),
            errorWidget: (context, url, error) => Container(
              height: 320,
              width: double.infinity,
              color: Colors.grey[300],
            ),
          ),
        ),
        Container(
          height: 320,
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.7),
                Colors.black.withValues(alpha: 0.3),
                Colors.black.withValues(alpha: 0.6),
              ],
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.arrow_back,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.description.isNotEmpty
                      ? widget.description.split('\n').first
                      : 'course.course'.tr(),
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProgressSection() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'course.course_progress'.tr(),
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const Text(
                '65%',
                style: TextStyle(
                  color: Color(0xFF3451E5),
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: const LinearProgressIndicator(
              value: 0.65,
              backgroundColor: Color(0xFFF1F1F1),
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF3451E5)),
              minHeight: 10,
            ),
          ),
        ],
      ),
    );
  }

 Widget _buildTabBar() {
  return Container(
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: Color(0xFFF1F1F1))),
    ),
    child: TabBar(
      controller: _tabController,
      labelColor: const Color(0xFF3451E5),
      unselectedLabelColor: Colors.grey,
      indicatorColor: const Color(0xFF3451E5),
      indicatorWeight: 3,
      indicatorPadding: EdgeInsets.zero,
      isScrollable: true,                  
      tabAlignment: TabAlignment.start,     
      tabs: [
        Tab(text: 'course.lectures_and_pdf'.tr()),
        Tab(text: 'course.exams'.tr()),
        Tab(text: 'course.live'.tr()),
        Tab(text: 'course.community'.tr()),
      ],
    ),
  );
}
  Widget _buildLecturesSkeleton() {
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: 1,
      itemBuilder: (context, index) {
        return Shimmer.fromColors(
          baseColor: Colors.grey[300]!,
          highlightColor: Colors.grey[100]!,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFF1F1F1)),
            ),
            child: Column(
              children: [
                ListTile(
                  title: Container(height: 16, width: 200, color: Colors.white),
                  subtitle: Container(
                    height: 12,
                    width: 100,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildLecturesTab() {
    if (_lectures.isEmpty) {
      return Center(
        child: Text(
          'course.no_lectures_available'.tr(),
          style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: _lectures.length,
      itemBuilder: (context, index) {
        final lecture = _lectures[index];
        final attributes = lecture['attributes'] ?? {};
        final lectureTitle =
            attributes['title']?.toString() ?? 'course.untitled_lecture'.tr();

        return Column(
          children: [
            _buildChapterItem(index, lectureTitle, lecture),
            if (index < _lectures.length - 1) const SizedBox(height: 20),
          ],
        );
      },
    );
  }

  Widget _buildChapterItem(int index, String title, dynamic lecture) {
    bool isExpanded = _isExpanded.length > index ? _isExpanded[index] : false;
    final attributes = lecture['attributes'] ?? {};
    final chapters = attributes['chapters'] as List<dynamic>? ?? [];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF1F1F1)),
        boxShadow: [
          if (isExpanded)
            BoxShadow(
              color: const Color(0xFF5A75FF).withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Parent lecture header with tree indicator
          InkWell(
            onTap: () {
              setState(() {
                if (_isExpanded.length > index) {
                  _isExpanded[index] = !isExpanded;
                }
              });
            },
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Tree structure indicator
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: isExpanded
                          ? const Color(0xFF5A75FF).withValues(alpha: 0.1)
                          : const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      isExpanded ? Icons.folder_open : Icons.folder,
                      color: isExpanded ? const Color(0xFF5A75FF) : Colors.grey,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: isExpanded
                                ? const Color(0xFF5A75FF)
                                : const Color(0xFF1F2937),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${chapters.length} ${chapters.length == 1 ? 'course.chapter'.tr() : 'course.chapters'.tr()}',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Expand/collapse indicator
                  AnimatedRotation(
                    turns: isExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: isExpanded
                            ? const Color(0xFF5A75FF).withValues(alpha: 0.1)
                            : Colors.transparent,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.keyboard_arrow_down,
                        color: isExpanded
                            ? const Color(0xFF5A75FF)
                            : Colors.grey,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Nested chapters with visual tree indentation
          if (isExpanded && chapters.isNotEmpty)
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFFFAFBFF),
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(16),
                ),
              ),
              child: Column(
                children: [
                  const Divider(height: 1, color: Color(0xFFE5E7EB)),
                  ...chapters.asMap().entries.expand((entry) {
                    final chapterIndex = entry.key;
                    final chapter = entry.value;
                    final chapterAttrs = chapter['attributes'] ?? {};
                    final chapterTitle =
                        chapterAttrs['title']?.toString() ??
                        'course.untitled_chapter'.tr();
                    final duration =
                        chapterAttrs['duration']?.toString() ?? '--:--';
                    final thumbnail =
                        chapterAttrs['thumbnail']?.toString() ?? '';
                    final rawVideo = chapterAttrs['video'];

                    final videoUrl =
                        (rawVideo == null || rawVideo.toString() == 'null')
                        ? ''
                        : rawVideo.toString();
                    final isLocked =
                        chapterAttrs['is_locked'] as bool? ?? false;
                    final isFreePreview =
                        chapterAttrs['is_free_preview'] as bool? ?? false;
                    final canWatch =
                        chapterAttrs['can_watch'] as bool? ?? false;
                    final isActivated =
                        chapterAttrs['is_activated'] as bool? ?? false;
                    final isFreePreviewAttachment =
                        chapterAttrs['is_free_preview_attachment'] as bool? ??
                        false;
                    final rawAttachments = chapterAttrs['attachments'];

                    final attachments = rawAttachments is List
                        ? rawAttachments as List<dynamic>
                        : rawAttachments is Map &&
                              rawAttachments['data'] is List
                        ? rawAttachments['data'] as List<dynamic>
                        : <dynamic>[];
                    final maxViews =
                        int.tryParse(
                          chapterAttrs['max_views']?.toString() ?? '',
                        ) ??
                        0;
                    final isLastItem = chapterIndex == chapters.length - 1;

                    // Check if chapter has PDF attachments but no video
                    final hasPdfOnly =
                        videoUrl.isEmpty &&
                        attachments.any((att) {
                          final ext =
                              att['attributes']?['extension']
                                  ?.toString()
                                  .toLowerCase() ??
                              '';
                          return ext == 'pdf';
                        });

                    final widgets = <Widget>[
                      _buildNestedChapterItem(
                        chapterTitle,
                        duration,
                        thumbnail,
                        videoUrl,
                        !isLocked,
                        index: chapterIndex,
                        totalCount: chapters.length,
                        onTap: () => hasPdfOnly
                            ? _navigateToPdfViewer(chapter, attachments)
                            : _navigateToLecture(lecture, chapter),
                        isFreePreview: isFreePreview,
                        isLocked: isLocked,
                        canWatch: canWatch,
                        isLastItem: isLastItem,
                        hasPdfOnly: hasPdfOnly,
                        attachments: attachments,
                        isActivated: isActivated,
                        isFreePreviewAttachment: isFreePreviewAttachment,
                        maxViews: maxViews,
                      ),
                    ];

                    return widgets;
                  }).toList(),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // New nested chapter item with tree visualization
  Widget _buildNestedChapterItem(
    String title,
    String duration,
    String imageUrl,
    String videoUrl,
    bool isCompleted, {
    required VoidCallback onTap,
    bool isFreePreview = false,
    bool isLocked = false,
    bool canWatch = false,
    required int index,
    required int totalCount,
    required bool isLastItem,
    bool hasPdfOnly = false,
    List<dynamic> attachments = const [],
    bool isActivated = false,
    bool isFreePreviewAttachment = false,
    int maxViews = 0,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Tree connector lines
            SizedBox(
              width: 32,
              height: 60,
              child: Stack(
                children: [
                  // Vertical line from parent
                  Positioned(
                    left: 8,
                    top: 0,
                    bottom: 0,
                    child: Container(width: 2, color: const Color(0xFFE5E7EB)),
                  ),
                  // Horizontal connector
                  Positioned(
                    left: 8,
                    top: 20,
                    child: Container(
                      width: 16,
                      height: 2,
                      color: const Color(0xFFE5E7EB),
                    ),
                  ),
                  // Last item corner or continue line
                  if (!isLastItem)
                    Positioned(
                      left: 8,
                      top: 22,
                      bottom: 0,
                      child: Container(
                        width: 2,
                        color: const Color(0xFFE5E7EB),
                      ),
                    ),
                  // Node indicator
                  Positioned(
                    left: 4,
                    top: 16,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: isLocked ? Colors.grey : const Color(0xFF5A75FF),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Content - use different widget for PDF-only chapters
            Expanded(
              child: hasPdfOnly
                  ? _buildPdfOnlyChapterItem(
                      title: title,
                      attachments: attachments,
                      isLocked: isLocked,
                      onTap: onTap,
                    )
                  : _buildLectureListItem(
                      title,
                      duration,
                      imageUrl,
                      videoUrl,
                      isCompleted,
                      onTap: onTap,
                      isFreePreview: isFreePreview,
                      isLocked: isLocked,
                      canWatch: canWatch,
                      hasPdfOnly: hasPdfOnly,
                      attachments: attachments,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLectureListItem(
    String title,
    String duration,
    String imageUrl,
    String videoUrl,
    bool isCompleted, {
    VoidCallback? onTap,
    bool isFreePreview = false,
    bool isLocked = false,
    bool canWatch = false,
    bool hasPdfOnly = false,
    List<dynamic> attachments = const [],
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Stack(
              children: [
                // Show network thumbnail if available, otherwise try video thumbnail
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: hasPdfOnly
                      ? Container(
                          width: 80,
                          height: 60,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF0F0),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: FaIcon(
                            FontAwesomeIcons.filePdf,
                            color: const Color(0xFFE74C3C),
                            size: 32,
                          ),
                        )
                      : imageUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: imageUrl,
                          width: 80,
                          height: 60,
                          fit: BoxFit.cover,
                          memCacheWidth: 160,
                          memCacheHeight: 120,
                          placeholder: (context, url) =>
                              _buildVideoThumbnail(videoUrl, isLocked),
                          errorWidget: (context, url, error) {
                            return _buildVideoThumbnail(videoUrl, isLocked);
                          },
                        )
                      : _buildVideoThumbnail(videoUrl, isLocked),
                ),
                if (isCompleted)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        color: Color(0xFF2DBC77),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check,
                        color: Colors.white,
                        size: 8,
                      ),
                    ),
                  ),
                if (hasPdfOnly)
                  Positioned(
                    top: 4,
                    left: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE74C3C),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'PDF',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      hasPdfOnly
                          ? const FaIcon(
                              FontAwesomeIcons.file,
                              size: 14,
                              color: Colors.grey,
                            )
                          : const Icon(
                              Icons.access_time,
                              size: 14,
                              color: Colors.grey,
                            ),
                      const SizedBox(width: 4),
                      Text(
                        hasPdfOnly
                            ? '${attachments.length} ${attachments.length == 1 ? 'file' : 'files'}'
                            : duration,
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (isFreePreview)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F9F0),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'course.free_preview'.tr(),
                        style: const TextStyle(
                          color: Color(0xFF2DBC77),
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    )
                  else if (canWatch)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F9F0),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.check_circle,
                            color: Color(0xFF2DBC77),
                            size: 12,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'course.available'.tr(),
                            style: const TextStyle(
                              color: Color(0xFF2DBC77),
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (hasPdfOnly)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: isLocked
                            ? const Color(0xFFF5F5F5)
                            : const Color(0xFFFFE8E8),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        isLocked
                            ? 'course.requires_unlock'.tr()
                            : 'course.open_file'.tr(),
                        style: TextStyle(
                          color: isLocked
                              ? Colors.grey[600]
                              : const Color(0xFFE74C3C),
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0F2FF),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        isLocked ? 'course.locked'.tr() : 'course.watch'.tr(),
                        style: TextStyle(
                          color: isLocked
                              ? Colors.grey
                              : const Color(0xFF3451E5),
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build PDF-only chapter item with special modern design
  Widget _buildPdfOnlyChapterItem({
    required String title,
    required List<dynamic> attachments,
    required bool isLocked,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isLocked
              ? [const Color(0xFFF5F5F5), const Color(0xFFE8E8E8)]
              : [const Color(0xFFFFF0F0), const Color(0xFFFFE8E8)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isLocked ? const Color(0xFFE0E0E0) : const Color(0xFFE74C3C),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: isLocked
                ? Colors.black.withOpacity(0.05)
                : const Color(0xFFE74C3C).withOpacity(0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // PDF Icon with gradient background
              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: isLocked
                        ? [const Color(0xFFE0E0E0), const Color(0xFFD0D0D0)]
                        : [const Color(0xFFE74C3C), const Color(0xFFFF6B35)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: isLocked
                          ? Colors.black.withOpacity(0.1)
                          : const Color(0xFFE74C3C).withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Center(
                  child: Stack(
                    children: [
                      FaIcon(
                        FontAwesomeIcons.filePdf,
                        color: Colors.white,
                        size: 32,
                      ),
                      if (isLocked)
                        Positioned(
                          top: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.lock,
                              size: 12,
                              color: Color(0xFFE74C3C),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: isLocked
                            ? Colors.grey[600]
                            : const Color(0xFF1F2937),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: isLocked
                                ? const Color(0xFFE0E0E0)
                                : const Color(0xFFE74C3C).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              FaIcon(
                                FontAwesomeIcons.file,
                                size: 12,
                                color: isLocked
                                    ? Colors.grey[600]
                                    : const Color(0xFFE74C3C),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '${attachments.length} ${attachments.length == 1 ? 'file' : 'files'}',
                                style: TextStyle(
                                  color: isLocked
                                      ? Colors.grey[600]
                                      : const Color(0xFFE74C3C),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        // PDF badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: isLocked
                                ? const Color(0xFFE0E0E0)
                                : const Color(0xFFE74C3C),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'PDF',
                            style: TextStyle(
                              color: isLocked ? Colors.grey[600] : Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Action button
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isLocked
                              ? [
                                  const Color(0xFFE0E0E0),
                                  const Color(0xFFD0D0D0),
                                ]
                              : [
                                  const Color(0xFFE74C3C),
                                  const Color(0xFFFF6B35),
                                ],
                        ),
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: isLocked
                                ? Colors.black.withOpacity(0.05)
                                : const Color(0xFFE74C3C).withOpacity(0.25),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isLocked ? Icons.lock_outline : Icons.visibility,
                            color: isLocked ? Colors.grey[600] : Colors.white,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            isLocked
                                ? 'course.requires_unlock'.tr()
                                : 'course.open_file'.tr(),
                            style: TextStyle(
                              color: isLocked ? Colors.grey[600] : Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Build video thumbnail widget when network thumbnail is not available
  Widget _buildVideoThumbnail(String videoUrl, bool isLocked) {
    if (videoUrl.isEmpty) {
      // No video URL, show fallback placeholder
      return Container(
        width: 80,
        height: 60,
        decoration: BoxDecoration(
          color: Colors.grey[300],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          isLocked ? Icons.lock : Icons.play_arrow,
          color: Colors.white,
          size: 32,
        ),
      );
    }

    // Process video URL - handle relative URLs
    String processedUrl = videoUrl;
    if (!processedUrl.startsWith('http')) {
      processedUrl = processedUrl.replaceAll('\\', '/');
      if (!processedUrl.startsWith('/')) {
        processedUrl = '/$processedUrl';
      }
      // Use base URL from API constants
      processedUrl = '${ApiConstants.baseUrl}$processedUrl';
    }

    return VideoThumbnailWidget(
      videoUrl: processedUrl,
      width: 80,
      height: 60,
      borderRadius: 12,
      isLocked: isLocked,
      showPlayIcon: true,
    );
  }

  Widget _buildExamsTab() {
    if (_isLoadingExams) {
      return _buildExamsSkeleton();
    }

    if (_exams.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Text(
            'course.no_exams_available'.tr(),
            style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(24.0),
      itemCount: _exams.length,
      itemBuilder: (context, index) {
        final exam = _exams[index];
        return _buildExamCard(exam);
      },
    );
  }

  Widget _buildExamsSkeleton() {
    return ListView.builder(
      padding: const EdgeInsets.all(24.0),
      itemCount: 2,
      itemBuilder: (context, index) {
        return Shimmer.fromColors(
          baseColor: Colors.grey[300]!,
          highlightColor: Colors.grey[100]!,
          child: Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(height: 18, width: 200, color: Colors.white),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Container(height: 14, width: 80, color: Colors.white),
                    const SizedBox(width: 24),
                    Container(height: 14, width: 80, color: Colors.white),
                  ],
                ),
                const SizedBox(height: 24),
                Container(
                  height: 54,
                  width: double.infinity,
                  color: Colors.white,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildExamCard(Quiz exam) {
    final status = exam.getStatus(exam.remainingAttempts);
    final statusText = exam.getStatusTextKey(status).tr();

    Color statusColor;
    Color statusBgColor;

    switch (status) {
      case QuizStatus.available:
        statusColor = const Color(0xFF27AE60);
        statusBgColor = const Color(0xFFE6F7F0);
        break;
      case QuizStatus.expired:
        statusColor = Colors.red;
        statusBgColor = const Color(0xFFFFF0F0);
        break;
      case QuizStatus.upcoming:
        statusColor = const Color(0xFFF2994A);
        statusBgColor = const Color(0xFFFFF9F0);
        break;
      case QuizStatus.noAttempts:
        statusColor = const Color(0xFFFF4B4B);
        statusBgColor = const Color(0xFFFFF0F0);
        break;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF1F1F1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: statusBgColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              statusText,
              style: TextStyle(
                color: statusColor,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            exam.title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: Color(0xFF1F2937),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              FaIcon(FontAwesomeIcons.clock, size: 14, color: Colors.grey[400]),
              const SizedBox(width: 8),
              Text(
                'course.duration_min'.tr(args: [exam.duration.toString()]),
                style: TextStyle(color: Colors.grey[600], fontSize: 15),
              ),
              const SizedBox(width: 24),
              FaIcon(
                FontAwesomeIcons.circleInfo,
                size: 14,
                color: Colors.grey[400],
              ),
              const SizedBox(width: 8),
              Text(
                exam.type.toUpperCase(),
                style: TextStyle(color: Colors.grey[600], fontSize: 15),
              ),
            ],
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: status == QuizStatus.available
                ? () async {
                    // Use ExamAccessUseCase to handle access control
                    final examAccessUseCase = ExamAccessUseCase();
                    await examAccessUseCase.handleExamAccess(
                      context: context,
                      quiz: exam,
                    );
                  }
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: status == QuizStatus.available
                  ? const Color(0xFF263EE2)
                  : const Color(0xFFC4C4C4),
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFFC4C4C4),
              disabledForegroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 54),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 0,
            ),
            child: Text(
              exam.getButtonTextKey(status).tr().toUpperCase(),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQATab() {
    return Column(
      children: [
        _buildQASubFilters(),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            children: [
              if (_qaFilter == 'All' || _qaFilter == 'Ask Question') ...[
                _buildQuestionItem(
                  'Ahmed Hassan',
                  '2 hours ago',
                  'Can you explain the difference between merge sort and quick sort?',
                  'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=100',
                  response: {
                    'name': 'Dr. Sarah Ahmed',
                    'role': 'Instructor',
                    'time': '1 hour ago',
                    'text':
                        'Great question! Merge sort always has O(n log n) complexity, while quick sort has average O(n log n) but worst case O(n²).',
                  },
                ),
              ],
              const SizedBox(height: 20),
            ],
          ),
        ),
        _buildQABottomBar(),
      ],
    );
  }

  Widget _buildQASubFilters() {
    final filters = ['All', 'Ask Question', 'Comments', 'Voice'];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: filters.map((filter) {
              bool isSelected = _qaFilter == filter;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: InkWell(
                  onTap: () => setState(() => _qaFilter = filter),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFFF0F2FF)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      filter,
                      style: TextStyle(
                        color: isSelected
                            ? const Color(0xFF3451E5)
                            : Colors.grey,
                        fontSize: 12,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildQuestionItem(
    String name,
    String time,
    String text,
    String avatarUrl, {
    Map<String, String>? response,
    bool isWaiting = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipOval(
                child: CachedNetworkImage(
                  imageUrl: avatarUrl,
                  width: 40,
                  height: 40,
                  fit: BoxFit.cover,
                  memCacheWidth: 80,
                  memCacheHeight: 80,
                  placeholder: (context, url) => const CircleAvatar(
                    radius: 20,
                    backgroundColor: Colors.grey,
                  ),
                  errorWidget: (context, url, error) => const CircleAvatar(
                    radius: 20,
                    backgroundColor: Colors.grey,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    time,
                    style: const TextStyle(color: Colors.grey, fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(left: 52),
            child: Text(
              text,
              style: TextStyle(color: Colors.grey[800], fontSize: 13),
            ),
          ),
          if (response != null) ...[
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.only(left: 40),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F2FF),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: const BoxDecoration(
                            color: Color(0xFF263EE2),
                            shape: BoxShape.circle,
                          ),
                          child: const Center(
                            child: Text(
                              'D',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              response['name']!,
                              style: const TextStyle(
                                color: Color(0xFF263EE2),
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF263EE2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                response['role']!,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        Text(
                          response['time']!,
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      response['text']!,
                      style: TextStyle(
                        color: Colors.grey[800],
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildQABottomBar() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFF1F1F1))),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F8FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: _qaFilter == 'Comments'
                        ? 'Write a comment...'
                        : 'Type here...',
                    hintStyle: const TextStyle(
                      color: Colors.grey,
                      fontSize: 14,
                    ),
                    border: InputBorder.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            _buildCircleActionButton(Icons.mic_none, const Color(0xFF263EE2)),
            const SizedBox(width: 12),
            _buildCircleActionButton(
              Icons.send_rounded,
              const Color(0xFF263EE2),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCircleActionButton(IconData icon, Color color) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: Colors.white, size: 20),
    );
  }

  Widget _buildLiveTab() {
    if (_isLoadingLiveRooms) {
      return _buildLiveRoomsSkeletonList();
    }

    if (_liveRooms.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            'course.no_live_subject'.tr(),
            style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: _liveRooms.length,
      itemBuilder: (context, index) {
        final room = _liveRooms[index];
        return _buildLiveRoomCard(room);
      },
    );
  }

  Widget _buildLiveRoomsSkeletonList() {
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: 2,
      itemBuilder: (context, index) {
        return Shimmer.fromColors(
          baseColor: Colors.grey[300]!,
          highlightColor: Colors.grey[100]!,
          child: Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 50,
                      height: 20,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    const Spacer(),
                    Container(
                      width: 20,
                      height: 20,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  height: 18,
                  width: double.infinity,
                  color: Colors.white,
                ),
                const SizedBox(height: 8),
                Container(height: 14, width: 120, color: Colors.white),
                const SizedBox(height: 4),
                Container(height: 12, width: 100, color: Colors.white),
                const SizedBox(height: 20),
                Container(
                  height: 50,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildLiveRoomCard(lr.LiveRoom room) {
    final isLive = room.status == lr.SessionStatus.now;
    final isUpcoming = room.status == lr.SessionStatus.upcoming;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: isLive
                      ? const Color(0xFFFFF0F0)
                      : (isUpcoming
                            ? const Color(0xFFFFF9F0)
                            : const Color(0xFFF0F2FF)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 3,
                      backgroundColor: isLive
                          ? const Color(0xFFFF4B4B)
                          : (isUpcoming
                                ? const Color(0xFFF2994A)
                                : const Color(0xFF5A75FF)),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isLive
                          ? 'course.live_uppercase'.tr()
                          : (isUpcoming
                                ? 'course.upcoming_uppercase'.tr()
                                : 'course.recorded_uppercase'.tr()),
                      style: TextStyle(
                        color: isLive
                            ? const Color(0xFFFF4B4B)
                            : (isUpcoming
                                  ? const Color(0xFFF2994A)
                                  : const Color(0xFF5A75FF)),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              FaIcon(
                FontAwesomeIcons.towerBroadcast,
                color: isLive
                    ? const Color(0xFFFF4B4B)
                    : const Color(0xFF5A75FF),
                size: 18,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            room.title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 17,
              color: Color(0xFF1F2937),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            room.instructorName,
            style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
          ),
          const SizedBox(height: 4),
          Text(
            '${room.formattedTime} • ${room.duration}',
            style: TextStyle(
              color: const Color(0xFF9CA3AF).withValues(alpha: 0.7),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 20),
          if (isLive)
            ElevatedButton(
              onPressed: () {
                // Handle join live
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2DBC77),
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: Text(
                'course.join_live'.tr(),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            )
          else if (isUpcoming)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      // Handle view details
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF6B7280),
                      side: const BorderSide(color: Color(0xFFD1D5DB)),
                      minimumSize: const Size(double.infinity, 44),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Text(
                      'course.view_details'.tr(),
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      // Handle set reminder
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF5A75FF),
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 44),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      'course.set_reminder'.tr(),
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ],
            )
          else
            ElevatedButton(
              onPressed: () {
                // Handle watch recorded
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF5A75FF),
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: const Text(
                'WATCH RECORDING',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCommunityTab() {
    if (_isLoadingCommunity) {
      return _buildCommunitySkeleton();
    }

    if (_communityErrorMessage != null) {
      return _buildCommunityError();
    }

    return RefreshIndicator(
      onRefresh: () async {
        await _loadCommunityPosts();
        await _loadSocialLinks();
      },
      color: const Color(0xFF5A75FF),
      backgroundColor: Colors.white,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCommunityHeader(),
            _buildCommunityInfoCard(),
            _buildSocialLinksSection(),
            if (_posts.isEmpty)
              _buildCommunityEmpty()
            else
              _buildCommunityPostsList(),
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }

  Widget _buildCommunityHeader() {
    return Container(
      margin: const EdgeInsets.all(20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Community',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1F2937),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${_posts.length} posts',
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              ),
            ],
          ),
          ElevatedButton.icon(
            onPressed: _navigateToCreatePost,
            icon: const FaIcon(FontAwesomeIcons.plus, size: 14),
            label: const Text('New Post'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF5A75FF),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommunityInfoCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3451E5), Color(0xFF5A75FF), Color(0xFF7B93FF)],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF3451E5).withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const FaIcon(
                  FontAwesomeIcons.users,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Course Community',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Stay connected with course updates, links, and class discussions for ${widget.title}.',
            style: TextStyle(
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.9),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSocialLinksSection() {
    if (_isLoadingSocialLinks) {
      return Container(
        margin: const EdgeInsets.all(20),
        child: Row(
          children: [
            Expanded(child: _buildSkeletonQuickLink()),
            const SizedBox(width: 12),
            Expanded(child: _buildSkeletonQuickLink()),
            const SizedBox(width: 12),
            Expanded(child: _buildSkeletonQuickLink()),
          ],
        ),
      );
    }

    final activeLinks = _socialLinks
        .where((link) => link.attributes.status)
        .toList();

    if (activeLinks.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Quick Links',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.grey[800],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: activeLinks.map((link) {
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: activeLinks.last == link ? 0 : 12,
                  ),
                  child: _buildQuickLinkCard(link),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildSkeletonQuickLink() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.grey[300],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Colors.grey[400],
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: 60,
            height: 11,
            decoration: BoxDecoration(
              color: Colors.grey[400],
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickLinkCard(SocialLink link) {
    List<Color> gradientColors = [
      AppColors.primaryBlue,
      const Color(0xFF5A75FF),
    ];

    if (link.attributes.color != null && link.attributes.color!.isNotEmpty) {
      try {
        String colorStr = link.attributes.color!;
        if (colorStr.startsWith('#')) {
          colorStr = '0xFF${colorStr.substring(1)}';
        }
        final baseColor = Color(int.parse(colorStr));
        final lighterColor = Color.fromARGB(
          baseColor.alpha,
          (baseColor.red + 40).clamp(0, 255),
          (baseColor.green + 40).clamp(0, 255),
          (baseColor.blue + 60).clamp(0, 255),
        );
        gradientColors = [baseColor, lighterColor];
      } catch (_) {
        // Keep default gradient
      }
    }

    return GestureDetector(
      onTap: () async {
        final url = Uri.parse(link.link);
        if (await canLaunchUrl(url)) {
          await launchUrl(url, mode: LaunchMode.externalApplication);
        }
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: gradientColors,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: gradientColors[0].withValues(alpha: 0.4),
              blurRadius: 12,
              offset: const Offset(0, 6),
              spreadRadius: -2,
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: link.attributes.icon.isNotEmpty
                  ? ClipOval(
                      child: CachedNetworkImage(
                        imageUrl: link.attributes.icon,
                        width: 28,
                        height: 28,
                        fit: BoxFit.cover,
                        memCacheWidth: 56,
                        memCacheHeight: 56,
                        placeholder: (context, url) => const FaIcon(
                          FontAwesomeIcons.link,
                          color: Colors.white,
                          size: 24,
                        ),
                        errorWidget: (context, url, error) {
                          return const FaIcon(
                            FontAwesomeIcons.link,
                            color: Colors.white,
                            size: 24,
                          );
                        },
                      ),
                    )
                  : const FaIcon(
                      FontAwesomeIcons.link,
                      color: Colors.white,
                      size: 24,
                    ),
            ),
            const SizedBox(height: 10),
            Text(
              link.attributes.title.isNotEmpty
                  ? link.attributes.title
                  : link.attributes.subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white,
                height: 1.3,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCommunitySkeleton() {
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: 3,
      itemBuilder: (context, index) => _buildCommunitySkeletonPost(),
    );
  }

  Widget _buildCommunitySkeletonPost() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF0F2FF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 120,
                      height: 14,
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: 80,
                      height: 12,
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            height: 60,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                width: 60,
                height: 24,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCommunityError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            _communityErrorMessage ?? 'An error occurred',
            style: const TextStyle(color: Colors.grey),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loadCommunityPosts,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF5A75FF),
              foregroundColor: Colors.white,
            ),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildCommunityEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(top: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.forum_outlined,
                size: 48,
                color: Colors.grey[400],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No posts yet in this course',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Be the first to start a discussion!',
              style: TextStyle(color: Colors.grey[400], fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCommunityPostsList() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          Text(
            'Recent Posts',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.grey[800],
            ),
          ),
          const SizedBox(height: 12),
          ..._posts.asMap().entries.map((entry) {
            final post = entry.value;
            final isPinned =
                entry.key == 0 && post.attributes.postType == 'summary';
            return _buildPostCard(post: post, isPinned: isPinned);
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildPostCard({required Post post, bool isPinned = false}) {
    final user = post.attributes.user;
    final course = post.attributes.course;
    final userName = user?.attributes.fullName ?? 'Unknown User';
    final isInstructor =
        user?.attributes.role.toLowerCase() == 'admin' ||
        user?.attributes.role.toLowerCase() == 'instructor';
    final timeAgo = _formatTimeAgo(post.attributes.createdAt);
    final hasReaction = post.attributes.userReaction != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF0F2FF)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isPinned) ...[
            Row(
              children: [
                FaIcon(
                  FontAwesomeIcons.thumbtack,
                  color: AppColors.accentBlue,
                  size: 14,
                ),
                const SizedBox(width: 6),
                Text(
                  'PINNED POST',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.accentBlue,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: FaIcon(
                    FontAwesomeIcons.user,
                    color: AppColors.textGray,
                    size: 16,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      userName,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          timeAgo,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textGray,
                          ),
                        ),
                        if (isInstructor) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.accountingBg,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'Instructor',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                                color: AppColors.accountingText,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (post.attributes.title.isNotEmpty) ...[
            Text(
              post.attributes.title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(height: 8),
          ],
          Linkify(
            onOpen: (link) async {
              final url = Uri.parse(link.url);
              if (await canLaunchUrl(url)) {
                await launchUrl(url, mode: LaunchMode.externalApplication);
              }
            },
            text: post.attributes.content,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textDark,
              height: 1.5,
            ),
            linkStyle: const TextStyle(
              fontSize: 14,
              color: AppColors.primaryBlue,
              height: 1.5,
              decoration: TextDecoration.underline,
            ),
          ),
          const SizedBox(height: 12),
          if (course != null) ...[
            _buildTagChip('#${course.attributes.title}'),
            const SizedBox(height: 8),
          ],
          if (post.attributes.tags.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: post.attributes.tags
                  .map((tag) => _buildTagChip('#$tag'))
                  .toList(),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              GestureDetector(
                onTap: () => _showReactionPicker(post),
                child: Row(
                  children: [
                    FaIcon(
                      hasReaction
                          ? _getReactionIcon(post.attributes.userReaction)
                          : FontAwesomeIcons.heart,
                      color: hasReaction
                          ? _getReactionColor(post.attributes.userReaction)
                          : AppColors.textGray,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${post.attributes.reactionsCount}',
                      style: TextStyle(
                        fontSize: 13,
                        color: hasReaction
                            ? _getReactionColor(post.attributes.userReaction)
                            : AppColors.textGray,
                        fontWeight: hasReaction
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTagChip(String tag) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F2FF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        tag,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: AppColors.textGray,
        ),
      ),
    );
  }

  void _showReactionPicker(Post post) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 16,
          children: [
            _buildReactionButton(
              post,
              'like',
              FontAwesomeIcons.thumbsUp,
              Colors.blue,
            ),
            _buildReactionButton(
              post,
              'love',
              FontAwesomeIcons.heart,
              Colors.red,
            ),
            _buildReactionButton(
              post,
              'haha',
              FontAwesomeIcons.faceLaughSquint,
              Colors.orange,
            ),
            _buildReactionButton(
              post,
              'wow',
              FontAwesomeIcons.faceSurprise,
              Colors.yellow,
            ),
            _buildReactionButton(
              post,
              'sad',
              FontAwesomeIcons.faceSadTear,
              Colors.purple,
            ),
            _buildReactionButton(
              post,
              'angry',
              FontAwesomeIcons.faceAngry,
              Colors.redAccent,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReactionButton(
    Post post,
    String type,
    FaIconData icon,
    Color color,
  ) {
    final isSelected = post.attributes.userReaction == type;
    return GestureDetector(
      onTap: () {
        Navigator.pop(context);
        _handleReaction(post, type);
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.1) : Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: FaIcon(icon, color: color, size: 32),
      ),
    );
  }

  FaIconData _getReactionIcon(String? reaction) {
    switch (reaction) {
      case 'like':
        return FontAwesomeIcons.solidThumbsUp;
      case 'love':
        return FontAwesomeIcons.solidHeart;
      case 'haha':
        return FontAwesomeIcons.faceLaughSquint;
      case 'wow':
        return FontAwesomeIcons.faceSurprise;
      case 'sad':
        return FontAwesomeIcons.faceSadTear;
      case 'angry':
        return FontAwesomeIcons.faceAngry;
      default:
        return FontAwesomeIcons.heart;
    }
  }

  Color _getReactionColor(String? reaction) {
    switch (reaction) {
      case 'like':
        return Colors.blue;
      case 'love':
        return Colors.red;
      case 'haha':
        return Colors.orange;
      case 'wow':
        return Colors.yellow.shade700;
      case 'sad':
        return Colors.purple;
      case 'angry':
        return Colors.redAccent;
      default:
        return AppColors.textGray;
    }
  }

  String _formatTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 365) {
      return '${difference.inDays ~/ 365} years ago';
    } else if (difference.inDays > 30) {
      return '${difference.inDays ~/ 30} months ago';
    } else if (difference.inDays > 0) {
      return '${difference.inDays} days ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} hours ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} minutes ago';
    } else {
      return 'Just now';
    }
  }
}
