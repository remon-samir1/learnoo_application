import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import '../../../../features/exams/data/exam_filter_service.dart';
import '../../../../features/exams/data/exam_repository.dart';
import '../../../../features/exams/domain/usecases/exam_access_usecase.dart';
import '../../../../features/exams/models/quiz_models.dart';
import '../../../../features/exams/presentation/screens/quiz_screen.dart';
import '../../../../features/course_content/data/course_repository.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/network/api_constants.dart';
import '../../data/live_room_repository.dart';
import '../../data/models/live_room.dart' as lr;
import '../../services/attachment_permission_service.dart';
import '../../../community/data/repositories/community_repository.dart';
import '../../../community/data/models/post_model.dart';
import '../../../community/data/models/social_link_model.dart';
import '../../../community/presentation/screens/create_post_screen.dart';
import '../../data/lecture_repository.dart';
import 'pdf_reviewer_screen.dart';

class CourseContentScreen extends StatefulWidget {
  final String courseTitle;
  final String instructorName;
  final int courseId;

  const CourseContentScreen({
    super.key,
    required this.courseTitle,
    required this.instructorName,
    required this.courseId,
  });

  @override
  State<CourseContentScreen> createState() => _CourseContentScreenState();
}

class _CourseContentScreenState extends State<CourseContentScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final List<bool> _isExpanded = [true, false]; // For chapters
  final _courseRepository = CourseRepository();
  final _lectureRepository = LectureRepository();
  final _liveRoomRepository = LiveRoomRepository();
  final _communityRepository = CommunityRepository();
  final _examRepository = ExamRepository();
  List<Quiz> _exams = [];
  List<lr.LiveRoom> _liveRooms = [];
  List<Post> _posts = [];
  List<SocialLink> _socialLinks = [];
  bool _isLoadingExams = true;
  bool _isLoadingLiveRooms = true;
  bool _isLoadingCommunity = true;
  bool _isLoadingSocialLinks = false;
  String? _communityErrorMessage;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadExams();
    _loadLiveRooms();
    _loadCommunityPosts();
    _loadSocialLinks();
  }

  Future<void> _loadExams() async {
    setState(() => _isLoadingExams = true);
    try {
      // Fetch exams and chapters for this course
      final results = await Future.wait([
        _examRepository.getQuizzes(),
        _lectureRepository.getLectures(courseId: widget.courseId),
      ]);

      if (!mounted) return;

      final examResult = results[0];
      final lecturesResult = results[1];

      if (examResult['success']) {
        final allExams = examResult['data'] as List<Quiz>;

        // Extract chapters from lectures data
        final List<dynamic> chapters = [];
        if (lecturesResult['success']) {
          final lectures = lecturesResult['data'] as List<dynamic>? ?? [];
          print('[CourseContentScreen] Lectures count: ${lectures.length}');
          for (final lecture in lectures) {
            final lectureChapters = lecture['attributes']?['chapters']?['data'] as List<dynamic>?;
            if (lectureChapters != null) {
              print('[CourseContentScreen] Lecture has ${lectureChapters.length} chapters');
              chapters.addAll(lectureChapters);
            }
          }
          print('[CourseContentScreen] Total chapters extracted: ${chapters.length}');
        }

        // Use ExamFilterService for proper course-level filtering
        final filteredExams = await ExamFilterService.filterExamsByCourse(
          exams: allExams,
          courseId: widget.courseId,
          courseChapters: chapters,
        );

        print('[CourseContentScreen] Filtered exams count: ${filteredExams.length}');

        setState(() {
          _exams = filteredExams;
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

  Future<void> _loadLiveRooms() async {
    if (!mounted) return;
    setState(() => _isLoadingLiveRooms = true);
    try {
      final result = await _liveRoomRepository.getLiveRooms();
      if (result['success'] && mounted) {
        final allLiveRooms = result['data'] as List<lr.LiveRoom>;
        setState(() {
          _liveRooms = allLiveRooms
              .where((room) => room.courseId == widget.courseId)
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
      final result = await _communityRepository.getPosts(courseId: widget.courseId);
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

        final filteredLinks = allLinks.where((link) {
          return link.attributes.courses.any((course) => course.id == widget.courseId.toString());
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
      final result = await _communityRepository.reactToPost(post.id, reactionType);
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
      MaterialPageRoute(
        builder: (context) => const CreatePostScreen(),
      ),
    );
    if (result == true) {
      _loadCommunityPosts();
    }
  }

  void _navigateToPdfViewer(dynamic chapter, List<dynamic> attachments) {
    final chapterAttrs = chapter['attributes'] ?? {};
    final chapterId = chapter['id']?.toString() ?? '';
    final chapterTitle = chapterAttrs['title']?.toString() ?? 'course.untitled_chapter'.tr();
    final isLocked = chapterAttrs['is_locked'] as bool? ?? false;
    final isActivated = chapterAttrs['is_activated'] as bool? ?? false;
    final isFreePreview = chapterAttrs['is_free_preview'] as bool? ?? false;
    final isFreePreviewAttachment = chapterAttrs['is_free_preview_attachment'] as bool? ?? false;
    final maxViews = int.tryParse(chapterAttrs['max_views']?.toString() ?? '') ?? 0;

    // Find first PDF attachment
    final pdfAttachment = attachments.firstWhere(
      (att) {
        final ext = att['attributes']?['extension']?.toString().toLowerCase() ?? '';
        return ext == 'pdf';
      },
      orElse: () => null,
    );

    if (pdfAttachment == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('course.no_pdf_available'.tr())),
      );
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
                    border: Border.all(color: const Color(0xFFE74C3C), width: 1),
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
                      courseId: widget.courseId.toString(),
                      onRefresh: _loadExams,
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
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          _buildHeader(),
          _buildProgressSection(),
          _buildTabBar(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildLecturesTab(),
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
        // Background Image
        Container(
          // height: 240,
          width: double.infinity,
          decoration: const BoxDecoration(
            image: DecorationImage(
              image: NetworkImage(
                'https://images.unsplash.com/photo-1554224155-6726b3ff858f?w=800',
              ),
              fit: BoxFit.cover,
            ),
          ),
        ),
        // Darkened Overlay with Gradient
        Container(
          height: 240,
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
        // Content
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Back Button
                InkWell(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.arrow_back, color: Colors.white, size: 24),
                  ),
                ),
                const SizedBox(height: 20),
                // Title
                Text(
                  widget.courseTitle,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.instructorName,
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
    return Padding(
      padding: const EdgeInsets.all(20.0),
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
        tabAlignment: TabAlignment.fill,

        indicatorPadding: const EdgeInsets.symmetric(horizontal: 15),
        tabs: [
          Tab(text: 'course.lectures_and_pdf'.tr()),
          Tab(text: 'course.exams'.tr()),
          Tab(text: 'course.live'.tr()),
          Tab(text: 'course.community'.tr()),
        ],
      ),
    );
  }

  Widget _buildLecturesTab() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _buildChapterItem(0, 'course.chapter_1_intro'.tr()),
        const SizedBox(height: 20),
        _buildChapterItem(1, 'course.chapter_2_stack'.tr()),
      ],
    );
  }

  Widget _buildChapterItem(int index, String title) {
    bool isExpanded = _isExpanded[index];
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF1F1F1)),
      ),
      child: Column(
        children: [
          ListTile(
            title: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            trailing: Icon(
              isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
              color: Colors.grey,
            ),
            onTap: () => setState(() => _isExpanded[index] = !isExpanded),
          ),
          if (isExpanded) ...[
            const Divider(height: 1, color: Color(0xFFF1F1F1)),
            _buildLectureListItem(
              'course.what_is_financial'.tr(),
              '45:30',
              'https://images.unsplash.com/photo-1554224155-6726b3ff858f?w=400',
              true,
            ),
            const Divider(height: 1, color: Color(0xFFF1F1F1)),
            _buildLectureListItem(
              'course.accounting_concepts'.tr(),
              '52:15',
              'https://images.unsplash.com/photo-1454165833767-027ffcb7141b?w=400',
              true,
            ),
            const Divider(height: 1, color: Color(0xFFF1F1F1)),
            _buildPDFListItem('course.chapter_1_notes'.tr(), 'course.twenty_four_pages'.tr()),
          ],
        ],
      ),
    );
  }

  Widget _buildLectureListItem(
    String title,
    String duration,
    String imageUrl,
    bool isCompleted, {
    bool hasPdfOnly = false,
    List<dynamic> attachments = const [],
  }) {
    // Use modern PDF-only design for PDF chapters
    if (hasPdfOnly) {
      return _buildPdfOnlyListItem(
        title: title,
        attachments: attachments,
        isLocked: false, // Default to unlocked for mock data
        onTap: () {}, // No-op for mock data
      );
    }

    // Original video chapter design
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(imageUrl, width: 80, height: 60, fit: BoxFit.cover),
              ),
              Positioned.fill(
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.8),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.play_arrow, color: Colors.black, size: 14),
                  ),
                ),
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
                    child: const Icon(Icons.check, color: Colors.white, size: 8),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.access_time, size: 14, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(
                      duration,
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F2FF),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'course.watch'.tr(),
                    style: const TextStyle(
                      color: Color(0xFF3451E5),
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
    );
  }

  /// Build PDF-only chapter item with special modern design
  Widget _buildPdfOnlyListItem({
    required String title,
    required List<dynamic> attachments,
    required bool isLocked,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isLocked
              ? [
                  const Color(0xFFF5F5F5),
                  const Color(0xFFE8E8E8),
                ]
              : [
                  const Color(0xFFFFF0F0),
                  const Color(0xFFFFE8E8),
                ],
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
                        ? [
                            const Color(0xFFE0E0E0),
                            const Color(0xFFD0D0D0),
                          ]
                        : [
                            const Color(0xFFE74C3C),
                            const Color(0xFFFF6B35),
                          ],
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
                        color: isLocked ? Colors.grey[600] : const Color(0xFF1F2937),
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
                                color: isLocked ? Colors.grey[600] : const Color(0xFFE74C3C),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '${attachments.length} ${attachments.length == 1 ? 'file' : 'files'}',
                                style: TextStyle(
                                  color: isLocked ? Colors.grey[600] : const Color(0xFFE74C3C),
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
                            isLocked ? 'course.requires_unlock'.tr() : 'course.open_file'.tr(),
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

  Widget _buildPDFListItem(String title, String pages) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF0F0),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.insert_drive_file, color: Color(0xFFFF4B4B), size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 4),
                Text(pages, style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          ),
          Row(
            children: [
              _buildSmallIconButton(FontAwesomeIcons.eye),
              const SizedBox(width: 8),
              _buildSmallIconButton(FontAwesomeIcons.download),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSmallIconButton(dynamic icon) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFF1F1F1)),
      ),
      child: FaIcon(icon as FaIconData, size: 14, color: Colors.grey[600]),
    );
  }

  Widget _buildExamsTab() {
    if (_isLoadingExams) {
      return _buildExamsSkeletonList();
    }

    if (_exams.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Text(
            'course.no_exams_available'.tr(),
            style: const TextStyle(color: Colors.grey, fontSize: 15),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(24.0),
      itemCount: _exams.length,
      itemBuilder: (context, index) {
        final exam = _exams[index];
        final isAvailable = exam.isAvailable;
        return _buildExamCard(exam: exam, isAvailable: isAvailable);
      },
    );
  }

  Widget _buildExamsSkeletonList() {
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
                Container(height: 54, width: double.infinity, color: Colors.white),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildExamCard({required Quiz exam, required bool isAvailable}) {
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  exam.title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF1F2937)),
                ),
              ),
              const SizedBox(width: 8),
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
            ],
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
              FaIcon(FontAwesomeIcons.circleInfo, size: 14, color: Colors.grey[400]),
              const SizedBox(width: 8),
              Text(exam.type.toUpperCase(), style: TextStyle(color: Colors.grey[600], fontSize: 15)),
            ],
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: status == QuizStatus.available ? () async {
              // Use ExamAccessUseCase to handle access control
              final examAccessUseCase = ExamAccessUseCase();
              await examAccessUseCase.handleExamAccess(
                context: context,
                quiz: exam,
              );
            } : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: status == QuizStatus.available ? const Color(0xFF263EE2) : const Color(0xFFC4C4C4),
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFFC4C4C4),
              disabledForegroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 54),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[600],
                ),
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
            'Stay connected with course updates, links, and class discussions for ${widget.courseTitle}.',
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

    final activeLinks = _socialLinks.where((link) => link.attributes.status).toList();

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
                  padding: EdgeInsets.only(right: activeLinks.last == link ? 0 : 12),
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
                      child: Image.network(
                        link.attributes.icon,
                        width: 28,
                        height: 28,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
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
              link.attributes.title.isNotEmpty ? link.attributes.title : link.attributes.subtitle,
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
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 13,
              ),
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
            final isPinned = entry.key == 0 && post.attributes.postType == 'summary';
            return _buildPostCard(post: post, isPinned: isPinned);
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildPostCard({
    required Post post,
    bool isPinned = false,
  }) {
    final user = post.attributes.user;
    final course = post.attributes.course;
    final userName = user?.attributes.fullName ?? 'Unknown User';
    final isInstructor = user?.attributes.role.toLowerCase() == 'admin' ||
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
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
              children: post.attributes.tags.map((tag) => _buildTagChip('#$tag')).toList(),
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
                        fontWeight: hasReaction ? FontWeight.w600 : FontWeight.normal,
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
            _buildReactionButton(post, 'like', FontAwesomeIcons.thumbsUp, Colors.blue),
            _buildReactionButton(post, 'love', FontAwesomeIcons.heart, Colors.red),
            _buildReactionButton(post, 'haha', FontAwesomeIcons.faceLaughSquint, Colors.orange),
            _buildReactionButton(post, 'wow', FontAwesomeIcons.faceSurprise, Colors.yellow),
            _buildReactionButton(post, 'sad', FontAwesomeIcons.faceSadTear, Colors.purple),
            _buildReactionButton(post, 'angry', FontAwesomeIcons.faceAngry, Colors.redAccent),
          ],
        ),
      ),
    );
  }

  Widget _buildReactionButton(Post post, String type, FaIconData icon, Color color) {
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
