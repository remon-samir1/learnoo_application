import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/course_repository.dart';
import '../../data/live_room_repository.dart';
import '../../data/models/live_room.dart' as lr;
import '../../data/course_files_repository.dart';
import '../../data/chapter_repository.dart';
import '../../data/library_repository.dart';
import '../../../exams/data/exam_repository.dart';
import '../../../exams/data/exam_filter_service.dart';
import '../../../exams/domain/usecases/exam_access_usecase.dart';
import '../../../exams/models/quiz_models.dart';
import 'course_detail_screen.dart';
import '../../../exams/presentation/screens/quiz_screen.dart';
import 'pdf_reviewer_screen.dart';
import 'unlock_material_screen.dart';
import 'pdf_viewer_screen.dart';
import '../../../community/data/repositories/community_repository.dart';
import '../../../community/data/models/post_model.dart';
import '../../../community/data/models/social_link_model.dart';
import '../../../community/presentation/screens/create_post_screen.dart';
import '../../services/attachment_permission_service.dart';

class SubjectDetailScreen extends StatefulWidget {
  final String subjectId;
  final String subjectTitle;
  final String? subjectImage;
  final String subtitle;

  const SubjectDetailScreen({
    super.key,
    required this.subjectId,
    required this.subjectTitle,
    this.subjectImage,
    this.subtitle = 'Course Content',
  });

  @override
  State<SubjectDetailScreen> createState() => _SubjectDetailScreenState();
}

class _SubjectDetailScreenState extends State<SubjectDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _courseRepository = CourseRepository();
  final _examRepository = ExamRepository();
  final _courseFilesRepository = CourseFilesRepository();
  final _liveRoomRepository = LiveRoomRepository();
  final _chapterRepository = ChapterRepository();
  final _libraryRepository = LibraryRepository();
  final _communityRepository = CommunityRepository();
  final _permissionService = AttachmentPermissionService();
  bool _isLoadingCourses = true;
  bool _isLoadingExams = true;
  bool _isLoadingLiveRooms = true;
  bool _isLoadingFiles = true;
  bool _isLoadingLibraries = true;
  bool _isLoadingCommunity = true;
  bool _isLoadingSocialLinks = false;
  List<dynamic> _courses = [];
  List<Quiz> _exams = [];
  List<lr.LiveRoom> _liveRooms = [];
  List<CourseFile> _files = [];
  List<dynamic> _libraries = [];
  List<Post> _posts = [];
  List<SocialLink> _socialLinks = [];
  String? _filesErrorMessage;
  String? _communityErrorMessage;
  Map<int, int> _remainingAttempts = {};

  // Expansion state for files tree view
  Map<String, bool> _expandedCourses = {};
  Map<String, bool> _expandedLectures = {};
  Map<String, bool> _expandedChapters = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _loadData();
  }

  Future<void> _loadData() async {
    await Future.wait([_loadCourses()]);
    // Load files, exams, live rooms, libraries, and community after courses to have course IDs for filtering
    await Future.wait([_loadFiles(), _loadExams(), _loadLiveRooms(), _loadLibraries(), _loadCommunityPosts(), _loadSocialLinks()]);
  }

  Future<void> _loadExams() async {
    if (!mounted) return;
    setState(() => _isLoadingExams = true);
    try {
      // Fetch all exams and chapters for this department
      final results = await Future.wait([
        _examRepository.getQuizzes(),
        _chapterRepository.getChapters(),
      ]);

      if (!mounted) return;

      final examResult = results[0];
      final chaptersResult = results[1];

      if (examResult['success']) {
        final allExams = examResult['data'] as List<Quiz>;
        final allChapters = chaptersResult['success']
            ? (chaptersResult['data'] as List<dynamic>? ?? [])
            : <dynamic>[];

        // Filter exams by courses in this subject (NOT by department)
        final filteredExams = await ExamFilterService.filterExams(
          exams: allExams,
          allowedCourses: _courses,
          allChapters: allChapters,
        );

        setState(() {
          _exams = filteredExams;
          _isLoadingExams = false;
        });

        // Initialize remaining attempts from quiz data
        for (final exam in filteredExams) {
          _remainingAttempts[exam.quizId] = exam.remainingAttempts;
        }
      } else if (mounted) {
        setState(() => _isLoadingExams = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingExams = false);
      }
    }
  }

  Future<void> _loadAttemptsForQuiz(int quizId, int maxAttempts) async {
    final result = await _examRepository.getRemainingAttempts(quizId, maxAttempts);
    if (!mounted) return;

    if (result['success']) {
      setState(() {
        _remainingAttempts[quizId] = result['remainingAttempts'];
      });
    }
  }

  Future<void> _loadCourses() async {
    if (!mounted) return;
    if (widget.subjectId.isEmpty) {
      if (mounted) {
        setState(() => _isLoadingCourses = false);
      }
      return;
    }

    setState(() => _isLoadingCourses = true);
    try {
      final categoryId = int.tryParse(widget.subjectId);
      final result = await _courseRepository.getCourses(
        categoryId: categoryId,
        include: 'attachments',
      );
      if (result['success'] && mounted) {
        setState(() {
          _courses = result['data'] ?? [];
          _isLoadingCourses = false;
        });
      } else if (mounted) {
        setState(() => _isLoadingCourses = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingCourses = false);
      }
    }
  }

  Future<void> _loadFiles() async {
    if (!mounted) return;
    setState(() {
      _isLoadingFiles = true;
      _filesErrorMessage = null;
    });

    try {
      // Files are now displayed in a hierarchical tree from _courses data
      // Extract files for header count only
      final files = _extractFilesFromCourses(_courses);

      if (mounted) {
        setState(() {
          _files = files;
          _isLoadingFiles = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _filesErrorMessage = 'course.connection_error'.tr(
            args: [e.toString()],
          );
          _isLoadingFiles = false;
        });
      }
    }
  }

  /// Extract files from course data
  /// Files are in lectures > chapters > attachments
  List<CourseFile> _extractFilesFromCourses(List<dynamic> courses) {
    final files = <CourseFile>[];

    for (final course in courses) {
      final courseAttributes = course['attributes'] ?? {};
      final courseName = courseAttributes['title']?.toString();

      // Check attachments nested in lectures > chapters
      final lectures = courseAttributes['lectures'] as List<dynamic>? ?? [];
      for (final lecture in lectures) {
        final lectureAttrs = lecture['attributes'] ?? {};
        final lectureName = lectureAttrs['title']?.toString();
        final chapters = lectureAttrs['chapters'] as List<dynamic>? ?? [];
        for (final chapter in chapters) {
          final chapterAttrs = chapter['attributes'] ?? {};
          final chapterId = int.tryParse(chapter['id']?.toString() ?? '');
          final chapterIsLocked = chapterAttrs['is_locked'] == true;
          final chapterIsFreePreviewAttachment =
              chapterAttrs['is_free_preview_attachment'] == true;
          final chapterIsActivated = chapterAttrs['is_activated'] == true;
          final chapterIsFreePreview = chapterAttrs['is_free_preview'] == true;
          final currentViews =
              int.tryParse(chapterAttrs['current_user_views']?.toString() ?? '') ??
                  0;
          final maxViews =
              int.tryParse(chapterAttrs['max_views']?.toString() ?? '') ?? 5;
          final chapterName = chapterAttrs['title']?.toString();
          final attachments =
              chapterAttrs['attachments'] as List<dynamic>? ?? [];
          for (final attachment in attachments) {
            try {
              final file = CourseFile.fromJson(
                attachment,
                courseName: courseName,
                lectureName: lectureName,
                chapterName: chapterName,
                chapterId: chapterId,
                chapterIsLocked: chapterIsLocked,
                chapterIsFreePreviewAttachment: chapterIsFreePreviewAttachment,
                chapterIsActivated: chapterIsActivated,
                chapterIsFreePreview: chapterIsFreePreview,
                currentViews: currentViews,
                maxViews: maxViews,
                courseId: course['id']?.toString(),
              );
              if (file.filePath.isNotEmpty) {
                files.add(file);
              }
            } catch (e) {
              continue;
            }
          }
        }
      }
    }

    return files;
  }

  Future<void> _refreshFiles() async {
    await _loadFiles();
  }

  Future<void> _loadLibraries() async {
    if (!mounted) return;
    setState(() => _isLoadingLibraries = true);

    try {
      final result = await _libraryRepository.getLibraries();
      if (result['success'] && mounted) {
        final allLibraries = result['data'] as List<dynamic>? ?? [];
        // Filter libraries by course_id matching courses in this subject
        final courseIds = _courses
            .map((c) => int.tryParse(c['id']?.toString() ?? ''))
            .where((id) => id != null)
            .toSet();

        final filteredLibraries = allLibraries.where((lib) {
          final courseId = lib['attributes']?['course_id'] as int?;
          return courseId != null && courseIds.contains(courseId);
        }).toList();

        setState(() {
          _libraries = filteredLibraries;
          _isLoadingLibraries = false;
        });
      } else if (mounted) {
        setState(() => _isLoadingLibraries = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingLibraries = false);
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
      // Get all course IDs in this subject
      final courseIds = _courses
          .map((c) => int.tryParse(c['id']?.toString() ?? ''))
          .where((id) => id != null)
          .cast<int>()
          .toList();

      if (courseIds.isEmpty) {
        setState(() {
          _posts = [];
          _isLoadingCommunity = false;
        });
        return;
      }

      // Fetch posts for all courses in this subject
      final List<Post> allPosts = [];
      for (final courseId in courseIds) {
        final result = await _communityRepository.getPosts(courseId: courseId);
        if (result['success'] && result['data'] != null) {
          final posts = result['data'] as List<Post>;
          allPosts.addAll(posts);
        }
      }

      // Remove duplicates and sort by date
      final uniquePosts = allPosts.toSet().toList();
      uniquePosts.sort((a, b) => b.attributes.createdAt.compareTo(a.attributes.createdAt));

      if (mounted) {
        setState(() {
          _posts = uniquePosts;
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

        // Filter social links by courses in this subject
        final courseIds = _courses
            .map((c) => c['id']?.toString())
            .where((id) => id != null)
            .toSet();

        final filteredLinks = allLinks.where((link) {
          return link.attributes.courses.any((course) => courseIds.contains(course.id));
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
      // Remove reaction
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
      // Add or change reaction
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

  // Get total file count including libraries for header display
  int get _totalFileCount {
    return _files.length + _libraries.length;
  }

  void _navigateToUnlock(dynamic library) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => UnlockMaterialScreen(library: library),
      ),
    );
  }

  void _openLibraryPdf(dynamic library) {
    final attributes = library['attributes'] ?? {};
    final title = attributes['title']?.toString() ?? 'course.material'.tr();
    final attachments = attributes['attachments'] as List<dynamic>? ?? [];

    // Find first PDF attachment that is not locked or downloadable
    final pdfAttachment = attachments.firstWhere(
      (attachment) {
        final ext = attachment['attributes']?['extension']?.toString().toLowerCase() ?? '';
        final isLocked = attachment['attributes']?['is_locked'] == true;
        final downloadable = attachment['attributes']?['downloadable'] == true;
        return ext == 'pdf' && (!isLocked || downloadable);
      },
      orElse: () => null,
    );

    final pdfUrl = pdfAttachment?['attributes']?['path']?.toString() ?? '';

    if (pdfUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('course.pdf_not_available'.tr())),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PdfViewerScreen(
          pdfUrl: pdfUrl,
          title: title,
        ),
      ),
    );
  }

  void _openFile(CourseFile file) {
    if (file.filePath.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('course.file_not_available'.tr())));
      return;
    }

    // Check permission before opening
    final canOpen = _permissionService.canOpenAttachment(
      fileIsLocked: file.isLocked,
      chapterIsLocked: file.chapterIsLocked,
      chapterIsActivated: file.chapterIsActivated,
      chapterIsFreePreview: file.chapterIsFreePreview,
      chapterIsFreePreviewAttachment: file.chapterIsFreePreviewAttachment,
      currentViews: file.currentViews,
      maxViews: file.maxViews,
    );

    if (!canOpen) {
      // Show locked attachment dialog
      if (file.chapterId != null) {
        _permissionService.showLockedAttachmentDialog(
          context: context,
          chapterId: file.chapterId!,
          courseId: file.courseId,
          onRefresh: _refreshFiles,
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('course.file_locked'.tr()),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    if (file.isPdf) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) =>
              PdfReviewerScreen(pdfUrl: file.filePath, title: file.title),
        ),
      );
    } else if (file.canPreview) {
      // For other previewable files, use the appropriate viewer
      // For now, show a message that file type is not directly viewable
      _downloadOrOpenFile(file);
    } else {
      // For non-previewable files, offer download
      _downloadOrOpenFile(file);
    }
  }

  void _downloadOrOpenFile(CourseFile file) async {
    // Check permission before showing options
    final canOpen = _permissionService.canOpenAttachment(
      fileIsLocked: file.isLocked,
      chapterIsLocked: file.chapterIsLocked,
      chapterIsActivated: file.chapterIsActivated,
      chapterIsFreePreview: file.chapterIsFreePreview,
      chapterIsFreePreviewAttachment: file.chapterIsFreePreviewAttachment,
      currentViews: file.currentViews,
      maxViews: file.maxViews,
    );

    // Show options for non-PDF files
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                file.title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1F2937),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                '.${file.extension.toUpperCase()} ${file.formattedSize.isNotEmpty ? '• ${file.formattedSize}' : ''}',
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
              const SizedBox(height: 24),
              Builder(
                builder: (context) {
                  if (!canOpen) {
                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF0F0),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              const FaIcon(
                                FontAwesomeIcons.lock,
                                color: Color(0xFFFF4B4B),
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'course.attachment_locked'.tr(),
                                  style: const TextStyle(
                                    color: Color(0xFFFF4B4B),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (file.chapterId != null) ...[
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.pop(context);
                                  _permissionService.showLockedAttachmentDialog(
                                    context: context,
                                    chapterId: file.chapterId!,
                                    courseId: file.courseId,
                                    onRefresh: _refreshFiles,
                                  );
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF5A75FF),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                icon: const FaIcon(FontAwesomeIcons.key, size: 14),
                                label: Text('course.unlock'.tr()),
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  } else {
                    return Column(
                      children: [
                        if (file.canPreview || file.isPdf)
                          ListTile(
                            leading: const FaIcon(
                              FontAwesomeIcons.eye,
                              color: Color(0xFF5A75FF),
                            ),
                            title: Text('course.open_file'.tr()),
                            onTap: () {
                              Navigator.pop(context);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => PdfReviewerScreen(
                                    pdfUrl: file.filePath,
                                    title: file.title,
                                  ),
                                ),
                              );
                            },
                          ),
                        if (file.downloadable)
                          ListTile(
                            leading: const FaIcon(
                              FontAwesomeIcons.download,
                              color: Color(0xFF5A75FF),
                            ),
                            title: Text('course.download_file'.tr()),
                            onTap: () {
                              Navigator.pop(context);
                              // TODO: Implement download functionality
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'course.download_started'.tr(
                                      args: [file.title],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ListTile(
                          leading: const FaIcon(
                            FontAwesomeIcons.share,
                            color: Color(0xFF5A75FF),
                          ),
                          title: Text('course.share_file'.tr()),
                          onTap: () {
                            Navigator.pop(context);
                            // TODO: Implement share functionality
                          },
                        ),
                      ],
                    );
                  }
                },
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  void _showChapterUnlockDialog(CourseFile file) {
    final codeController = TextEditingController();
    bool isVerifying = false;

    showDialog(
      context: context,
      barrierDismissible: !isVerifying,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Column(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F2FF),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Center(
                  child: FaIcon(
                    FontAwesomeIcons.key,
                    color: Color(0xFF5A75FF),
                    size: 24,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'course.unlock_chapter'.tr(),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1F2937),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'course.enter_code_to_unlock'.tr(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: codeController,
                enabled: !isVerifying,
                keyboardType: TextInputType.text,
                textCapitalization: TextCapitalization.characters,
                maxLength: 20,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 2,
                  color: Color(0xFF1F2937),
                ),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: 'ABCD-1234',
                  hintStyle: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 2,
                    color: Colors.grey[400],
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF5A75FF)),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isVerifying ? null : () => Navigator.pop(context),
              child: Text(
                'course.cancel'.tr(),
                style: TextStyle(color: Colors.grey[600]),
              ),
            ),
            ElevatedButton(
              onPressed: isVerifying
                  ? null
                  : () async {
                      final code = codeController.text.trim();
                      if (code.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('course.please_enter_code'.tr()),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }

                      setDialogState(() => isVerifying = true);

                      final result = await _chapterRepository.activateCode(
                        code: code,
                        itemId: file.chapterId!,
                        itemType: 'chapter',
                      );

                      setDialogState(() => isVerifying = false);

                      if (result['success']) {
                        Navigator.pop(context);
                        // Refresh all data to reflect unlocked status
                        await _loadData();
                        // Now open the file
                        _openFile(file);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('course.chapter_unlocked_success'.tr()),
                            backgroundColor: const Color(0xFF2DBC77),
                          ),
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              result['message'] ?? 'course.invalid_code'.tr(),
                            ),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF5A75FF),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: isVerifying
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Text('course.unlock'.tr()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubjectIconFallback() {
    final firstLetter = widget.subjectTitle.isNotEmpty
        ? widget.subjectTitle[0].toUpperCase()
        : '?';
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.3),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          firstLetter,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
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
      backgroundColor: const Color(0xFFFAFBFF),
      body: Column(
        children: [
          _buildHeader(),
          _buildTabBar(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _KeepAliveWrapper(child: _buildLecturesTab()),
                _KeepAliveWrapper(child: _buildLiveTab()),
                _KeepAliveWrapper(child: _buildFilesTab()),
                _KeepAliveWrapper(child: _buildExamsTab()),
                _KeepAliveWrapper(child: _buildCommunityTab()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF5A75FF), Color(0xFF8E7CFF)],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(30),
          bottomRight: Radius.circular(30),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
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
                  const SizedBox(width: 16),
                  if (widget.subjectImage != null &&
                      widget.subjectImage!.isNotEmpty)
                    ClipOval(
                      child: Image.network(
                        widget.subjectImage!,
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return _buildSubjectIconFallback();
                        },
                      ),
                    )
                  else
                    _buildSubjectIconFallback(),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.subjectTitle,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          widget.subtitle == 'Course Content'
                              ? 'course.course_content'.tr()
                              : widget.subtitle,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildHeaderInfoCard(
                    FontAwesomeIcons.play,
                    'course.courses_count'.tr(
                      args: [_courses.length.toString()],
                    ),
                  ),
                  _buildHeaderInfoCard(
                    FontAwesomeIcons.fileLines,
                    'course.files_count'.tr(args: [_totalFileCount.toString()]),
                  ),
                  _buildHeaderInfoCard(
                    FontAwesomeIcons.calendarCheck,
                    'course.exams_count'.tr(args: [_exams.length.toString()]),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderInfoCard(dynamic icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          FaIcon(icon as FaIconData, color: Colors.white, size: 14),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFF3F4F6), width: 1)),
      ),
      child: TabBar(
        controller: _tabController,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        labelColor: const Color(0xFF3451E5),
        unselectedLabelColor: const Color(0xFF6B7280),
        indicatorColor: const Color(0xFF3451E5),
        indicatorWeight: 2,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: Colors.transparent,
        labelPadding: const EdgeInsets.symmetric(horizontal: 18),
        labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        unselectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w500,
          fontSize: 13,
        ),
        tabs: [
          _buildTabItem(FontAwesomeIcons.circlePlay, 'course.courses'.tr()),
          _buildTabItem(FontAwesomeIcons.video, 'course.live'.tr()),
          _buildTabItem(FontAwesomeIcons.fileLines, 'course.files'.tr()),
          _buildTabItem(FontAwesomeIcons.calendarCheck, 'course.exams'.tr()),
          _buildTabItem(FontAwesomeIcons.users, 'course.community'.tr()),
        ],
      ),
    );
  }

  Widget _buildTabItem(dynamic icon, String label) {
    return Tab(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FaIcon(icon as FaIconData, size: 14),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }

  Widget _buildLecturesTab() {
    if (_isLoadingCourses) {
      return _buildCoursesSkeletonList();
    }

    if (_courses.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            'course.no_courses_subject'.tr(),
            style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: _courses.length,
      itemBuilder: (context, index) {
        final course = _courses[index];
        final attributes = course['attributes'] ?? {};
        final title =
            attributes['title']?.toString() ?? 'course.untitled_course'.tr();
        final thumbnail = attributes['thumbnail']?.toString() ?? '';
        final price = attributes['price']?.toString() ?? '0';

        return _buildCourseCard(
          courseId: course['id']?.toString() ?? '',
          title: title,
          thumbnail: thumbnail,
          price: price,
          description: attributes['description']?.toString() ?? '',
        );
      },
    );
  }

  Widget _buildCoursesSkeletonList() {
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: 3,
      itemBuilder: (context, index) {
        return Shimmer.fromColors(
          baseColor: Colors.grey[300]!,
          highlightColor: Colors.grey[100]!,
          child: Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Container(
                  width: 100,
                  height: 75,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(height: 16, color: Colors.white),
                      const SizedBox(height: 8),
                      Container(height: 12, width: 80, color: Colors.white),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCourseCard({
    required String courseId,
    required String title,
    required String thumbnail,
    required String price,
    required String description,
  }) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => CourseDetailScreen(
              courseId: courseId,
              title: title,
              thumbnail: thumbnail,
              price: price,
              description: description,
            ),
          ),
        );
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(12),
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
        child: Row(
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: thumbnail.isNotEmpty
                      ? Image.network(
                          thumbnail,
                          width: 100,
                          height: 75,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return _buildCourseImagePlaceholder();
                          },
                        )
                      : _buildCourseImagePlaceholder(),
                ),
                Positioned.fill(
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.play_arrow,
                        color: Color(0xFF1F2937),
                        size: 16,
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
                      fontSize: 14,
                      color: Color(0xFF1F2937),
                      height: 1.2,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      FaIcon(
                        FontAwesomeIcons.tag,
                        size: 12,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'EGP $price',
                        style: TextStyle(
                          color: const Color(0xFF5A75FF),
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
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

  Widget _buildCourseImagePlaceholder() {
    return Container(
      width: 100,
      height: 75,
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Center(
        child: Icon(
          Icons.image_not_supported,
          color: Color(0xFF9CA3AF),
          size: 24,
        ),
      ),
    );
  }

  Future<void> _loadLiveRooms() async {
    if (!mounted) return;
    setState(() => _isLoadingLiveRooms = true);
    try {
      final result = await _liveRoomRepository.getLiveRooms();
      if (result['success'] && mounted) {
        final allLiveRooms = result['data'] as List<lr.LiveRoom>;
        // Filter live rooms by course IDs in this subject
        final courseIds = _courses
            .map((c) => c['id']?.toString())
            .where((id) => id != null)
            .toSet();
        setState(() {
          _liveRooms = allLiveRooms
              .where((room) => courseIds.contains(room.courseId))
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

  Widget _buildFilesTab() {
    final isLoading = _isLoadingFiles && _isLoadingLibraries;
    final hasError = _filesErrorMessage != null;
    final isEmpty = _courses.isEmpty && _libraries.isEmpty && !isLoading;

    if (isLoading) {
      return _buildFilesSkeletonList();
    }

    if (hasError) {
      return _buildFilesErrorState();
    }

    if (isEmpty) {
      return _buildFilesEmptyState();
    }

    return RefreshIndicator(
      onRefresh: () async {
        await _refreshFiles();
        await _loadLibraries();
      },
      color: const Color(0xFF5A75FF),
      backgroundColor: Colors.white,
      child: ListView(
        padding: const EdgeInsets.all(20),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          // Library Files Section
          if (_libraries.isNotEmpty) ...[
            _buildLibraryFilesSection(),
            const SizedBox(height: 24),
          ],
          // Course Files Section
          if (_courses.isNotEmpty) ...[
            ..._courses.map((course) => _buildCourseFilesItem(course)).toList(),
          ],
        ],
      ),
    );
  }

  Widget _buildLibraryFilesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Header
        Row(
          children: [
            const FaIcon(
              FontAwesomeIcons.bookOpen,
              color: Color(0xFF5A75FF),
              size: 16,
            ),
            const SizedBox(width: 8),
            Text(
              'course.library_materials'.tr(),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1F2937),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF5A75FF).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${_libraries.length}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF5A75FF),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Library Cards
        ..._libraries.map((library) => _buildLibraryCard(library)).toList(),
      ],
    );
  }

  Widget _buildLibraryCard(dynamic library) {
    final attributes = library['attributes'] ?? {};
    final title = attributes['title']?.toString() ?? 'course.untitled'.tr();
    final description = attributes['description']?.toString() ?? '';
    final materialType = attributes['material_type']?.toString() ?? 'reference';
    final coverImage = attributes['cover_image']?.toString() ?? '';
    final isLocked = attributes['is_locked'] == true;
    final price = attributes['price']?.toString() ?? '0';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF1F1F1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Cover Image
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  coverImage,
                  width: 80,
                  height: 100,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      width: 80,
                      height: 100,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.book, color: Color(0xFF9CA3AF)),
                    );
                  },
                ),
              ),
              if (isLocked)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: Colors.grey[600],
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.lock,
                      color: Colors.white,
                      size: 12,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 16),
          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1F2937),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[500],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                // Material Type Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F2FF),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'course.${materialType.toLowerCase()}'.tr().toUpperCase(),
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF5A75FF),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // Lock Status
                if (isLocked)
                  Row(
                    children: [
                      FaIcon(
                        FontAwesomeIcons.lock,
                        color: Colors.grey[500],
                        size: 12,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${'course.requires_unlock'.tr()} - EGP $price',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  )
                else
                  Row(
                    children: [
                      const FaIcon(
                        FontAwesomeIcons.lockOpen,
                        color: Color(0xFF27AE60),
                        size: 12,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'course.paid_access'.tr(),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF27AE60),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          // Action Button
          if (!isLocked)
            OutlinedButton.icon(
              onPressed: () => _openLibraryPdf(library),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF5A75FF),
                side: const BorderSide(color: Color(0xFF5A75FF)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              icon: const FaIcon(FontAwesomeIcons.bookOpen, size: 12),
              label: Text(
                'course.open'.tr(),
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            )
          else
            ElevatedButton.icon(
              onPressed: () => _navigateToUnlock(library),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2137D6),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                elevation: 0,
              ),
              icon: const FaIcon(FontAwesomeIcons.key, size: 12),
              label: Text(
                'course.unlock'.tr(),
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFilesSkeletonList() {
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: 4,
      itemBuilder: (context, index) {
        return Shimmer.fromColors(
          baseColor: Colors.grey[300]!,
          highlightColor: Colors.grey[100]!,
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 16,
                        width: double.infinity,
                        color: Colors.white,
                      ),
                      const SizedBox(height: 8),
                      Container(height: 12, width: 120, color: Colors.white),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFilesEmptyState() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.2),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FaIcon(
                  FontAwesomeIcons.fileCircleXmark,
                  size: 48,
                  color: Colors.grey[400],
                ),
                const SizedBox(height: 16),
                Text(
                  'course.no_files_subject'.tr(),
                  style: const TextStyle(
                    color: Color(0xFF9CA3AF),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFilesErrorState() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.2),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 48, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  _filesErrorMessage!,
                  style: TextStyle(color: Colors.grey[600], fontSize: 14),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _refreshFiles,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF5A75FF),
                    foregroundColor: Colors.white,
                  ),
                  child: Text('course.retry'.tr()),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // Hierarchical tree view for files: Course > Lecture > Chapter > Files
  Widget _buildCourseFilesItem(dynamic course) {
    final courseId = course['id']?.toString() ?? '';
    final courseAttributes = course['attributes'] ?? {};
    final courseName =
        courseAttributes['title']?.toString() ?? 'course.untitled_course'.tr();
    final lectures = courseAttributes['lectures'] as List<dynamic>? ?? [];

    final isExpanded = _expandedCourses[courseId] ?? false;
    final hasContent = lectures.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
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
          // Course Header
          InkWell(
            onTap: hasContent
                ? () {
                    setState(() {
                      _expandedCourses[courseId] = !isExpanded;
                    });
                  }
                : null,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFF5A75FF).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.folder,
                      color: Color(0xFF5A75FF),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          courseName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: Color(0xFF1F2937),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _getCourseFileCount(course),
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (hasContent)
                    AnimatedRotation(
                      turns: isExpanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        Icons.keyboard_arrow_down,
                        color: isExpanded
                            ? const Color(0xFF5A75FF)
                            : Colors.grey,
                      ),
                    ),
                ],
              ),
            ),
          ),
          // Lectures with nested chapters and files
          if (isExpanded && lectures.isNotEmpty)
            Container(
              decoration: const BoxDecoration(
                color: Color(0xFFFAFBFF),
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(16),
                ),
              ),
              child: Column(
                children: [
                  ...lectures.asMap().entries.map((entry) {
                    return _buildLectureFilesItem(
                      entry.value,
                      courseName: courseName,
                      isLast: entry.key == lectures.length - 1,
                    );
                  }).toList(),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _getCourseFileCount(dynamic course) {
    final courseAttributes = course['attributes'] ?? {};
    final lectures = courseAttributes['lectures'] as List<dynamic>? ?? [];
    final chapterAttachments =
        courseAttributes['chapter_attachments'] as List<dynamic>? ?? [];

    int fileCount = chapterAttachments.length;

    for (final lecture in lectures) {
      final lectureAttrs = lecture['attributes'] ?? {};
      final chapters = lectureAttrs['chapters'] as List<dynamic>? ?? [];
      for (final chapter in chapters) {
        final chapterAttrs = chapter['attributes'] ?? {};
        final attachments = chapterAttrs['attachments'] as List<dynamic>? ?? [];
        fileCount += attachments.length;
      }
    }

    return '$fileCount ${fileCount == 1 ? 'file' : 'files'}';
  }

  Widget _buildLectureFilesItem(
    dynamic lecture, {
    required String courseName,
    required bool isLast,
  }) {
    final lectureId = lecture['id']?.toString() ?? '';
    final lectureAttrs = lecture['attributes'] ?? {};
    final lectureName =
        lectureAttrs['title']?.toString() ?? 'course.untitled_lecture'.tr();
    final chapters = lectureAttrs['chapters'] as List<dynamic>? ?? [];

    final isExpanded = _expandedLectures[lectureId] ?? false;

    return Column(
      children: [
        const Divider(height: 1, color: Color(0xFFE5E7EB), indent: 16),
        InkWell(
          onTap: chapters.isNotEmpty
              ? () {
                  setState(() {
                    _expandedLectures[lectureId] = !isExpanded;
                  });
                }
              : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                // Tree connector
                SizedBox(
                  width: 24,
                  height: 32,
                  child: Stack(
                    children: [
                      Positioned(
                        left: 8,
                        top: 0,
                        bottom: 0,
                        child: Container(
                          width: 2,
                          color: const Color(0xFFE5E7EB),
                        ),
                      ),
                      Positioned(
                        left: 8,
                        top: 12,
                        child: Container(
                          width: 12,
                          height: 2,
                          color: const Color(0xFFE5E7EB),
                        ),
                      ),
                      if (!isLast)
                        Positioned(
                          left: 8,
                          top: 14,
                          bottom: 0,
                          child: Container(
                            width: 2,
                            color: const Color(0xFFE5E7EB),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.folder_outlined,
                  color: isExpanded
                      ? const Color(0xFF5A75FF)
                      : Colors.grey[400],
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    lectureName,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: isExpanded
                          ? const Color(0xFF5A75FF)
                          : const Color(0xFF4B5563),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (chapters.isNotEmpty)
                  AnimatedRotation(
                    turns: isExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.keyboard_arrow_down,
                      size: 18,
                      color: isExpanded ? const Color(0xFF5A75FF) : Colors.grey,
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (isExpanded)
          Container(
            color: const Color(0xFFF7F8FF),
            child: Column(
              children: chapters.asMap().entries.map((entry) {
                return _buildChapterFilesItem(
                  entry.value,
                  courseName: courseName,
                  lectureName: lectureName,
                  isLast: entry.key == chapters.length - 1,
                );
              }).toList(),
            ),
          ),
      ],
    );
  }

  Widget _buildChapterFilesItem(
    dynamic chapter, {
    required String courseName,
    required String lectureName,
    required bool isLast,
  }) {
    final chapterId = chapter['id']?.toString() ?? '';
    final chapterAttrs = chapter['attributes'] ?? {};
    final chapterName =
        chapterAttrs['title']?.toString() ?? 'course.untitled_chapter'.tr();
    final attachments = chapterAttrs['attachments'] as List<dynamic>? ?? [];
    final chapterIsLocked = chapterAttrs['is_locked'] == true;
    final chapterIsActivated = chapterAttrs['is_activated'] == true;
    final chapterIsFreePreview = chapterAttrs['is_free_preview'] == true;
    final chapterIsFreePreviewAttachment = chapterAttrs['is_free_preview_attachment'] == true;
    final currentViews = int.tryParse(chapterAttrs['current_user_views']?.toString() ?? '') ?? 0;
    final maxViews = int.tryParse(chapterAttrs['max_views']?.toString() ?? '') ?? 5;

    final isExpanded =
        _expandedChapters[chapterId] ??
        true; // Default expanded for chapters with files

    return Column(
      children: [
        const Divider(height: 1, color: Color(0xFFE5E7EB), indent: 40),
        InkWell(
          onTap: attachments.isNotEmpty
              ? () {
                  setState(() {
                    _expandedChapters[chapterId] = !isExpanded;
                  });
                }
              : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 10),
            child: Row(
              children: [
                // Tree connector
                SizedBox(
                  width: 24,
                  height: 28,
                  child: Stack(
                    children: [
                      Positioned(
                        left: 8,
                        top: 0,
                        bottom: 0,
                        child: Container(
                          width: 2,
                          color: const Color(0xFFE5E7EB),
                        ),
                      ),
                      Positioned(
                        left: 8,
                        top: 10,
                        child: Container(
                          width: 12,
                          height: 2,
                          color: const Color(0xFFE5E7EB),
                        ),
                      ),
                      if (!isLast)
                        Positioned(
                          left: 8,
                          top: 12,
                          bottom: 0,
                          child: Container(
                            width: 2,
                            color: const Color(0xFFE5E7EB),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  Icons.insert_drive_file_outlined,
                  color: attachments.isNotEmpty
                      ? (isExpanded
                            ? const Color(0xFF5A75FF)
                            : Colors.grey[500])
                      : Colors.grey[300],
                  size: 16,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    chapterName,
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 12,
                      color: attachments.isNotEmpty
                          ? (isExpanded
                                ? const Color(0xFF5A75FF)
                                : const Color(0xFF6B7280))
                          : Colors.grey[400],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (attachments.isNotEmpty)
                  Text(
                    '${attachments.length}',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[500],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (isExpanded && attachments.isNotEmpty)
          Container(
            color: Colors.white,
            child: Column(
              children: attachments.map((attachment) {
                try {
                  final chapterIdInt = int.tryParse(chapterId);
                  final file = CourseFile.fromJson(
                    attachment,
                    courseName: courseName,
                    lectureName: lectureName,
                    chapterName: chapterName,
                    chapterId: chapterIdInt,
                    chapterIsLocked: chapterIsLocked,
                    chapterIsFreePreviewAttachment: chapterIsFreePreviewAttachment,
                    chapterIsActivated: chapterIsActivated,
                    chapterIsFreePreview: chapterIsFreePreview,
                    currentViews: currentViews,
                    maxViews: maxViews,
                  );
                  if (file.filePath.isNotEmpty) {
                    return _buildAttachmentItem(file, level: 2);
                  }
                  return const SizedBox.shrink();
                } catch (e) {
                  return const SizedBox.shrink();
                }
              }).toList(),
            ),
          ),
      ],
    );
  }

  Widget _buildAttachmentItem(CourseFile file, {required int level}) {
    final isFileLocked = file.isLocked && !file.downloadable;
    final isChapterLocked = file.chapterIsLocked;
    final isLocked = isFileLocked || isChapterLocked;
    final canView = !isLocked && (file.isPdf || file.canPreview);

    final indent = 16.0 + (level * 32.0);

    return InkWell(
      onTap: isLocked
          ? (isChapterLocked && file.chapterId != null
              ? () => _showChapterUnlockDialog(file)
              : null)
          : () => _openFile(file),
      child: Container(
        padding: EdgeInsets.fromLTRB(indent, 10, 16, 10),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xFFE5E7EB), width: 0.5)),
        ),
        child: Row(
          children: [
            // Tree connector
            SizedBox(
              width: 24,
              height: 36,
              child: Stack(
                children: [
                  Positioned(
                    left: 8,
                    top: 0,
                    bottom: 0,
                    child: Container(width: 2, color: const Color(0xFFE5E7EB)),
                  ),
                  Positioned(
                    left: 8,
                    top: 14,
                    child: Container(
                      width: 12,
                      height: 2,
                      color: const Color(0xFFE5E7EB),
                    ),
                  ),
                  Positioned(
                    left: 4,
                    top: 10,
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
            const SizedBox(width: 12),
            FaIcon(
              isLocked ? FontAwesomeIcons.lock : _getFileIcon(file.extension),
              color: isLocked
                  ? const Color(0xFF9CA3AF)
                  : const Color(0xFFFF4B4B),
              size: 18,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.title,
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                      color: isLocked
                          ? const Color(0xFF9CA3AF)
                          : const Color(0xFF1F2937),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${file.extension.toUpperCase()}${file.formattedSize.isNotEmpty ? ' • ${file.formattedSize}' : ''}${isChapterLocked ? ' • ${'course.chapter_locked'.tr()}' : ''}',
                    style: TextStyle(color: Colors.grey[500], fontSize: 11),
                  ),
                ],
              ),
            ),
            if (isChapterLocked && file.chapterId != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF2137D6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const FaIcon(
                  FontAwesomeIcons.key,
                  color: Colors.white,
                  size: 12,
                ),
              )
            else if (canView)
              const Icon(Icons.open_in_new, color: Color(0xFF5A75FF), size: 16)
            else if (isLocked)
              const Icon(Icons.lock, color: Color(0xFF9CA3AF), size: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildFileCard(CourseFile file) {
    // Use permission service to determine access state
    final accessState = _permissionService.getAttachmentAccessState(
      fileIsLocked: file.isLocked,
      chapterIsLocked: file.chapterIsLocked,
      chapterIsActivated: file.chapterIsActivated,
      chapterIsFreePreview: file.chapterIsFreePreview,
      chapterIsFreePreviewAttachment: file.chapterIsFreePreviewAttachment,
      currentViews: file.currentViews,
      maxViews: file.maxViews,
    );

    final isLocked = accessState == AttachmentAccessState.locked;
    final isFreePreview = accessState == AttachmentAccessState.freePreview;
    final canView = !isLocked && (file.isPdf || file.canPreview);

    return InkWell(
      onTap: isLocked
          ? (file.chapterId != null
              ? () {
                  _permissionService.showLockedAttachmentDialog(
                    context: context,
                    chapterId: file.chapterId!,
                    courseId: file.courseId,
                    onRefresh: _refreshFiles,
                  );
                }
              : null)
          : () => _openFile(file),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isLocked
                    ? const Color(0xFFF3F4F6)
                    : const Color(0xFFFFF0F0),
                borderRadius: BorderRadius.circular(12),
              ),
              child: FaIcon(
                isLocked ? FontAwesomeIcons.lock : _getFileIcon(file.extension),
                color: isLocked
                    ? const Color(0xFF9CA3AF)
                    : const Color(0xFFFF4B4B),
                size: 20,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          file.title,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: isLocked
                                ? const Color(0xFF9CA3AF)
                                : const Color(0xFF1F2937),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isFreePreview) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'course.free_preview'.tr(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _getFileInfo(file),
                    style: TextStyle(
                      color: isLocked
                          ? const Color(0xFF9CA3AF)
                          : const Color(0xFF9CA3AF),
                      fontSize: 12,
                    ),
                  ),
                  if (file.courseName != null ||
                      file.lectureName != null ||
                      file.chapterName != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: _buildSourceBreadcrumb(file),
                    ),
                ],
              ),
            ),
            if (isLocked && file.chapterId != null)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF2137D6),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const FaIcon(
                  FontAwesomeIcons.key,
                  color: Colors.white,
                  size: 16,
                ),
              )
            else if (canView)
              _buildFileActionButton(FontAwesomeIcons.eye)
            else if (file.downloadable && !isLocked)
              _buildFileActionButton(FontAwesomeIcons.download)
            else if (isLocked)
              _buildFileActionButton(FontAwesomeIcons.lock),
          ],
        ),
      ),
    );
  }

  FaIconData _getFileIcon(String extension) {
    switch (extension.toLowerCase()) {
      case 'pdf':
        return FontAwesomeIcons.filePdf;
      case 'doc':
      case 'docx':
        return FontAwesomeIcons.fileWord;
      case 'xls':
      case 'xlsx':
        return FontAwesomeIcons.fileExcel;
      case 'ppt':
      case 'pptx':
        return FontAwesomeIcons.filePowerpoint;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
        return FontAwesomeIcons.fileImage;
      case 'mp4':
      case 'mov':
      case 'avi':
        return FontAwesomeIcons.fileVideo;
      case 'mp3':
      case 'wav':
      case 'aac':
        return FontAwesomeIcons.fileAudio;
      case 'zip':
      case 'rar':
      case '7z':
        return FontAwesomeIcons.fileZipper;
      default:
        return FontAwesomeIcons.fileLines;
    }
  }

  String _getFileInfo(CourseFile file) {
    final parts = <String>[];

    if (file.extension.isNotEmpty) {
      parts.add(file.extension.toUpperCase());
    }

    if (file.formattedSize.isNotEmpty) {
      parts.add(file.formattedSize);
    }

    if (file.isLocked && !file.downloadable) {
      parts.add('course.locked'.tr());
    }

    return parts.join(' • ');
  }

  Widget _buildSourceBreadcrumb(CourseFile file) {
    final parts = <Widget>[];

    if (file.courseName != null && file.courseName!.isNotEmpty) {
      parts.add(
        Text(
          file.courseName!,
          style: const TextStyle(
            fontSize: 11,
            color: Color(0xFF5A75FF),
            fontWeight: FontWeight.w500,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }

    if (file.lectureName != null && file.lectureName!.isNotEmpty) {
      if (parts.isNotEmpty) {
        parts.add(
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Icon(
              Icons.chevron_right,
              size: 12,
              color: Color(0xFF9CA3AF),
            ),
          ),
        );
      }
      parts.add(
        Text(
          file.lectureName!,
          style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }

    if (file.chapterName != null && file.chapterName!.isNotEmpty) {
      if (parts.isNotEmpty) {
        parts.add(
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Icon(
              Icons.chevron_right,
              size: 12,
              color: Color(0xFF9CA3AF),
            ),
          ),
        );
      }
      parts.add(
        Text(
          file.chapterName!,
          style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }

    return Row(mainAxisSize: MainAxisSize.min, children: parts);
  }

  Widget _buildFileActionButton(dynamic icon) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FF),
        borderRadius: BorderRadius.circular(10),
      ),
      child: FaIcon(
        icon as FaIconData,
        color: const Color(0xFF4B5563),
        size: 16,
      ),
    );
  }

  Widget _buildExamsTab() {
    if (_isLoadingExams) {
      return _buildExamsSkeletonList();
    }

    if (_exams.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text(
            'No exams available for this subject',
            style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: _exams.length,
      itemBuilder: (context, index) {
        final exam = _exams[index];
        final remainingAttempts = _remainingAttempts[exam.quizId] ?? exam.maxAttempts;
        final isAvailable = exam.isAvailable && remainingAttempts > 0;

        return _buildExamCard(exam: exam, isAvailable: isAvailable, remainingAttempts: remainingAttempts);
      },
    );
  }

  Widget _buildExamsSkeletonList() {
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: 3,
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
                Container(height: 12, width: 60, color: Colors.white),
                const SizedBox(height: 12),
                Container(
                  height: 16,
                  width: double.infinity,
                  color: Colors.white,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Container(height: 12, width: 80, color: Colors.white),
                    const SizedBox(width: 20),
                    Container(height: 12, width: 80, color: Colors.white),
                  ],
                ),
                const SizedBox(height: 20),
                Container(
                  height: 50,
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

  Widget _buildExamCard({required Quiz exam, required bool isAvailable, required int remainingAttempts}) {
    final status = exam.getStatus(remainingAttempts);
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
              fontSize: 16,
              color: Color(0xFF1F2937),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              FaIcon(FontAwesomeIcons.clock, size: 14, color: Colors.grey[400]),
              const SizedBox(width: 8),
              Text(
                'course.duration_min'.tr(args: [exam.duration.toString()]),
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
              ),
              const SizedBox(width: 20),
              Text(
                exam.type.toUpperCase(),
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
              ),
              const SizedBox(width: 20),
              FaIcon(
                FontAwesomeIcons.rotateRight,
                size: 14,
                color: remainingAttempts <= 0 ? Colors.red : Colors.grey[400],
              ),
              const SizedBox(width: 8),
              Text(
                'exams.attempts_count'.tr(args: [
                  exam.currentAttempts.toString(),
                  exam.maxAttempts.toString(),
                ]),
                style: TextStyle(
                  color: remainingAttempts <= 0 ? Colors.red : Colors.grey[600],
                  fontSize: 13,
                  fontWeight: remainingAttempts <= 0 ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: status == QuizStatus.available
                ? () async {
                    // Use ExamAccessUseCase to handle access control
                    final examAccessUseCase = ExamAccessUseCase();
                    await examAccessUseCase.handleExamAccess(
                      context: context,
                      quiz: exam,
                    );
                    // Refresh attempts when returning
                    if (mounted) {
                      _loadAttemptsForQuiz(exam.quizId, exam.maxAttempts);
                    }
                  }
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: status == QuizStatus.available
                  ? const Color(0xFF263EE2)
                  : const Color(0xFFC4C4C4),
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFFC4C4C4),
              disabledForegroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
            child: Text(
              exam.getButtonTextKey(status).tr().toUpperCase(),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnnouncementCard(
    String tag,
    String time,
    String title,
    String content,
  ) {
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F2FF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  tag,
                  style: const TextStyle(
                    color: Color(0xFF5A75FF),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Text(
                time,
                style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: Color(0xFF1F2937),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            content,
            style: const TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () {},
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              backgroundColor: const Color(0xFFF9FAFB),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Reply',
              style: TextStyle(
                color: Color(0xFF9CA3AF),
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
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
                  'Department Community',
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
            'Stay connected with course updates, links, and class discussions for ${widget.subjectTitle}.',
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
          colorStr = '0xFF\${colorStr.substring(1)}';
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
              'No posts yet in this department',
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
            _buildTagChip('#\${course.attributes.title}'),
            const SizedBox(height: 8),
          ],
          if (post.attributes.tags.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: post.attributes.tags.map((tag) => _buildTagChip('#\$tag')).toList(),
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
                      '\${post.attributes.reactionsCount}',
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
}

class _KeepAliveWrapper extends StatefulWidget {
  final Widget child;
  const _KeepAliveWrapper({required this.child});

  @override
  State<_KeepAliveWrapper> createState() => _KeepAliveWrapperState();
}

class _KeepAliveWrapperState extends State<_KeepAliveWrapper>
    with AutomaticKeepAliveClientMixin {
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }

  @override
  bool get wantKeepAlive => true;
}
