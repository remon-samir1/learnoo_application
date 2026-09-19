import '../../domain/library_material.dart';
import 'library_material_detail_screen.dart';
import 'package:flutter/material.dart';

import '../../../community/presentation/widgets/post_images.dart';
import '../../../../core/utils/media_url.dart';
import '../../../../core/widgets/cover_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:shimmer/shimmer.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import '../../../../core/widgets/video_thumbnail_widget.dart';
import '../../../../core/network/api_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/models/live_room.dart' as lr;
import '../../../../core/services/student_scope.dart';
import '../../../../core/utils/coerce.dart';
import '../../domain/chapter_access.dart';
import '../../services/attachment_permission_service.dart';
import '../../data/course_repository.dart';
import '../../data/library_repository.dart';
import '../../../notes/presentation/widgets/note_attachment_preview.dart';
import '../../../exams/domain/quiz_activation_lock.dart';
import '../../../exams/domain/usecases/exam_access_usecase.dart';
import '../../../exams/models/quiz_models.dart';
import '../../../community/data/repositories/community_repository.dart';
import '../../../community/data/models/post_model.dart';
import '../../../community/data/models/social_link_model.dart';
import '../../../community/presentation/screens/create_post_screen.dart';
import '../../../community/presentation/widgets/post_comments_section.dart';
import 'lecture_detail_screen.dart';
import 'pdf_reviewer_screen.dart';
import 'live_session_detail_screen.dart';
import '../widgets/live_room_widgets.dart';

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
  final _courseRepository = CourseRepository();
  final _communityRepository = CommunityRepository();
  final _libraryRepository = LibraryRepository();
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

  /// Notes and library materials for this course — the web's Notes and Library
  /// tabs, which the app's four-tab bar was missing entirely.
  bool _isLoadingNotes = true;

  /// Cover from the course record, preferred over the one the caller passed.
  String? _loadedThumbnail;
  bool _isLoadingLibrary = true;
  List<dynamic> _notes = [];
  List<dynamic> _libraryItems = [];
  String? _notesErrorMessage;
  String? _libraryErrorMessage;

  /// Signed-in student's id, so their own comments get a delete button.
  String? _currentUserId;

  /// Which courses the student activated. The exam gate needs it: an exam
  /// bundled with a course (`is_public: "included"`) unlocks through the
  /// course rather than through a code.
  StudentScope _scope = const StudentScope.empty();
  List<bool> _isExpanded = [];
  String? _communityErrorMessage;

  @override
  void initState() {
    super.initState();
    // Six tabs, in the same order as the web: lectures, exams, notes, live,
    // community, library.
    _tabController = TabController(length: 6, vsync: this);
    _loadData();
    _loadCurrentUserId();
    _loadScope();
  }

  Future<void> _loadData() async {
    await _loadCourseDetails();
    await _loadCourseLibrary();
  }

  Future<void> _loadCurrentUserId() async {
    final id = await _communityRepository.currentUserId();
    if (mounted) setState(() => _currentUserId = id);
  }

  Future<void> _loadScope() async {
    try {
      final scope = await StudentScopeService().load();
      if (mounted) setState(() => _scope = scope);
    } catch (_) {
      // An unavailable scope just means the activation gate falls back to
      // treating bundled exams as locked, which is the safe direction.
    }
  }

  Future<void> _loadCourseDetails() async {
    if (widget.courseId.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoadingLectures = false;
          _isLoadingExams = false;
          _isLoadingSocialLinks = false;
          _isLoadingCommunity = false;
          _isLoadingLiveRooms = false;
          _isLoadingNotes = false;
        });
      }
      return;
    }

    setState(() {
      _isLoadingLectures = true;
      _isLoadingExams = true;
      _isLoadingSocialLinks = true;
      _isLoadingCommunity = true;
      _isLoadingLiveRooms = true;
      _isLoadingNotes = true;
      _communityErrorMessage = null;
      _notesErrorMessage = null;
    });

    try {
      final courseResult =
          await _courseRepository.getCourseById(widget.courseId);

      if (courseResult['success'] == true &&
          courseResult['data'] != null &&
          mounted) {
        final rawData = courseResult['data'];
        final Map<String, dynamic> courseData = rawData is Map
            ? Map<String, dynamic>.from(rawData)
            : <String, dynamic>{};
        final Map<String, dynamic> attributes = courseData['attributes'] is Map
            ? Map<String, dynamic>.from(courseData['attributes'])
            : <String, dynamic>{};

        // Callers such as live rooms may not know the cover; the course
        // record always does.
        final loadedThumbnail = readMediaUrl(
          attributes,
          const ['thumbnail', 'image', 'cover_image'],
        );
        if (loadedThumbnail != null && loadedThumbnail != _loadedThumbnail) {
          setState(() => _loadedThumbnail = loadedThumbnail);
        }

        // 1. Lectures and Chapters from course attributes ONLY
        final rawLectures = attributes['lectures'];
        List<dynamic> lecturesList = [];
        if (rawLectures is List) {
          lecturesList = List<dynamic>.from(rawLectures);
        }

        // Attach chapter_attachments to chapters if missing in chapter payload
        final rawChapterAttachments = attributes['chapter_attachments'];
        if (rawChapterAttachments is List &&
            rawChapterAttachments.isNotEmpty) {
          for (var lec in lecturesList) {
            if (lec is Map) {
              final lecAttrs = lec['attributes'] is Map
                  ? lec['attributes'] as Map
                  : lec;
              final chs = lecAttrs['chapters'];
              if (chs is List) {
                for (var ch in chs) {
                  if (ch is Map) {
                    final chAttrs = ch['attributes'] is Map
                        ? ch['attributes'] as Map
                        : ch;
                    final chAtts = chAttrs['attachments'];
                    if (chAtts == null ||
                        (chAtts is List && chAtts.isEmpty)) {
                      final chId = ch['id']?.toString();
                      final matched = rawChapterAttachments.where((ca) {
                        final caAttrs = ca is Map && ca['attributes'] is Map
                            ? ca['attributes'] as Map
                            : (ca is Map ? ca : {});
                        return caAttrs['chapter_id']?.toString() == chId;
                      }).toList();
                      if (matched.isNotEmpty) {
                        chAttrs['attachments'] = matched;
                      }
                    }
                  }
                }
              }
            }
          }
        }

        // 2. Exams from course attributes ONLY
        final Map<String, Quiz> mergedExams = {};
        final rawExams = attributes['exams'];
        final examsList = rawExams is List
            ? rawExams
            : rawExams is Map && rawExams['data'] is List
            ? rawExams['data'] as List<dynamic>
            : <dynamic>[];

        for (final examItem in examsList) {
          if (examItem is Map) {
            try {
              final q = Quiz.fromJson(Map<String, dynamic>.from(examItem));
              mergedExams[q.id] = q;
            } catch (e) {
              debugPrint(
                '[CourseDetailScreen] Error parsing exam from course: $e',
              );
            }
          }
        }

        // 3. Social links from course attributes ONLY
        final rawSocialLinks =
            attributes['social-links'] ?? attributes['social_links'];
        List<SocialLink> socialLinksList = [];
        if (rawSocialLinks is List) {
          for (final item in rawSocialLinks) {
            if (item is Map) {
              try {
                socialLinksList.add(
                  SocialLink.fromJson(Map<String, dynamic>.from(item)),
                );
              } catch (e) {
                debugPrint(
                  '[CourseDetailScreen] Error parsing social link: $e',
                );
              }
            }
          }
        }

        // 4. Community Posts from course attributes ONLY
        final rawPosts = attributes['posts'];
        List<Post> postsList = [];
        if (rawPosts is List) {
          for (final item in rawPosts) {
            if (item is Map) {
              try {
                postsList.add(
                  Post.fromJson(Map<String, dynamic>.from(item)),
                );
              } catch (e) {
                debugPrint(
                  '[CourseDetailScreen] Error parsing post from course: $e',
                );
              }
            }
          }
        }

        // 5. Live rooms from course attributes ONLY
        final rawLiveRooms =
            attributes['live_rooms'] ?? attributes['live-rooms'];
        List<lr.LiveRoom> liveRoomsList = [];
        if (rawLiveRooms is List) {
          for (final item in rawLiveRooms) {
            if (item is Map) {
              try {
                liveRoomsList.add(
                  lr.LiveRoom.fromJson(Map<String, dynamic>.from(item)),
                );
              } catch (e) {
                debugPrint(
                  '[CourseDetailScreen] Error parsing live room from course: $e',
                );
              }
            }
          }
        }

        // 6. Notes from course attributes ONLY
        final rawNotes = attributes['notes'];
        List<dynamic> notesList = [];
        if (rawNotes is List) {
          notesList = List<dynamic>.from(rawNotes);
        }

        setState(() {
          // Same ordering as the web's `sortedLectures` (by `order`).
          _lectures = studentSortedLectures(lecturesList);
          _isExpanded = List<bool>.filled(_lectures.length, false);
          _exams = mergedExams.values.toList();
          _socialLinks = socialLinksList;
          _posts = postsList;
          _liveRooms = liveRoomsList;
          _notes = notesList;
          _isLoadingLectures = false;
          _isLoadingExams = false;
          _isLoadingSocialLinks = false;
          _isLoadingCommunity = false;
          _isLoadingLiveRooms = false;
          _isLoadingNotes = false;
        });
      } else {
        if (mounted) {
          setState(() {
            _isLoadingLectures = false;
            _isLoadingExams = false;
            _isLoadingSocialLinks = false;
            _isLoadingCommunity = false;
            _isLoadingLiveRooms = false;
            _isLoadingNotes = false;
          });
        }
      }
    } catch (e) {
      debugPrint('[CourseDetailScreen] _loadCourseDetails error: $e');
      if (mounted) {
        setState(() {
          _isLoadingLectures = false;
          _isLoadingExams = false;
          _isLoadingSocialLinks = false;
          _isLoadingCommunity = false;
          _isLoadingLiveRooms = false;
          _isLoadingNotes = false;
        });
      }
    }
  }

  Future<void> _loadLectures() => _loadCourseDetails();
  Future<void> _loadSocialLinks() => _loadCourseDetails();
  Future<void> _loadCommunityPosts() => _loadCourseDetails();

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
    final isLocked = coerceFlagOrNull(chapterAttrs['is_locked']) == true;
    final isActivated = coerceFlagOrNull(chapterAttrs['is_activated']) == true;
    final isFreePreview = coerceFlag(chapterAttrs['is_free_preview']);
    final isFreePreviewAttachment =
        coerceFlag(chapterAttrs['is_free_preview_attachment']);
    final maxViews = chapterMaxViews(chapter) ?? 0;

    // First PDF attachment, matched on extension or a `.pdf` path so a row
    // with a missing `extension` field is still found.
    final pdfAttachments = chapterPdfAttachments(chapter);
    dynamic pdfAttachment = pdfAttachments.isEmpty
        ? null
        : pdfAttachments.first;

    if (pdfAttachment == null && attachments.isNotEmpty) {
      for (final att in attachments) {
        if (att is Map) {
          final attrs = att['attributes'] is Map ? att['attributes'] as Map : att;
          final ext = coerceString(attrs['extension'])?.toLowerCase().trim() ?? '';
          final path = coerceString(attrs['path'])?.toLowerCase() ?? '';
          final name = coerceString(attrs['name'])?.toLowerCase() ?? '';
          if (ext == 'pdf' || path.endsWith('.pdf') || path.contains('.pdf') || name.endsWith('.pdf')) {
            pdfAttachment = att;
            break;
          }
        }
      }
      pdfAttachment ??= attachments.first;
    }

    if (pdfAttachment == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('course.no_pdf_available'.tr())));
      return;
    }

    final attachmentAttrs = (pdfAttachment is Map && pdfAttachment['attributes'] is Map)
        ? pdfAttachment['attributes'] as Map
        : (pdfAttachment is Map ? pdfAttachment : const <String, dynamic>{});
    final fileIsLocked =
        coerceFlagOrNull(attachmentAttrs['is_locked']) == true;
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
      currentViews: chapterCurrentViews(chapter),
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
                _buildNotesTab(),
                _buildLiveTab(),
                _buildCommunityTab(),
                _buildLibraryTab(),
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
          child: CoverImage(
            url: _loadedThumbnail ?? widget.thumbnail,
            title: widget.title,
            height: 320,
            showTitle: false,
            cacheWidth: 500,
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

  // -----------------------------------------------------------------------
  // Notes tab — the web's `StudentCourseNotesTab`.
  // -----------------------------------------------------------------------

  Widget _buildNotesTab() {
    if (_isLoadingNotes) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_notesErrorMessage != null) {
      return _buildTabMessage(_notesErrorMessage!, isError: true);
    }

    if (_notes.isEmpty) {
      return _buildTabMessage('course.notes_empty'.tr());
    }

    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: _notes.length,
      itemBuilder: (context, index) => _buildCourseNoteCard(_notes[index]),
    );
  }

  Widget _buildCourseNoteCard(dynamic note) {
    final attrs = note is Map ? (note['attributes'] ?? note) : const {};
    final title = (attrs is Map ? attrs['title'] : null)?.toString().trim() ?? '';
    final content =
        (attrs is Map ? attrs['content'] : null)?.toString().trim() ?? '';
    final linked =
        (attrs is Map ? attrs['linked_lecture'] : null)?.toString().trim() ?? '';
    final attachment = attrs is Map ? attrs['attachment'] : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.isEmpty ? 'course.untitled_note'.tr() : title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0F172A),
            ),
          ),
          if (linked.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              linked,
              style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
            ),
          ],
          if (content.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              content,
              style: const TextStyle(
                fontSize: 13,
                height: 1.6,
                color: Color(0xFF475569),
              ),
            ),
          ],
          if (attachment is Map) ...[
            const SizedBox(height: 12),
            NoteAttachmentPreview(attachment: Map<String, dynamic>.from(attachment)),
          ],
        ],
      ),
    );
  }

  // -----------------------------------------------------------------------
  // Library tab — the web's `StudentCourseLibraryTab`.
  // -----------------------------------------------------------------------

  Future<void> _loadCourseLibrary() async {
    setState(() => _isLoadingLibrary = true);
    try {
      final courseIdInt = int.tryParse(widget.courseId);
      final result = await _libraryRepository.getLibraries(courseId: courseIdInt);
      if (!mounted) return;

      if (result['success'] == true) {
        final all = (result['data'] as List?) ?? const [];
        setState(() {
          _libraryItems = all.where((item) {
            final attrs = item is Map ? (item['attributes'] ?? item) : null;
            if (attrs is! Map) return false;
            // The web hides unpublished materials.
            if (attrs['is_publish'] == false) return false;
            if (courseIdInt == null) return true;
            final id = attrs['course_id'];
            return id != null && id.toString() == widget.courseId;
          }).toList();
          _isLoadingLibrary = false;
        });
      } else {
        setState(() {
          _libraryErrorMessage = result['message']?.toString();
          _isLoadingLibrary = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingLibrary = false);
    }
  }

  Widget _buildLibraryTab() {
    if (_isLoadingLibrary) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_libraryErrorMessage != null) {
      return _buildTabMessage(_libraryErrorMessage!, isError: true);
    }

    if (_libraryItems.isEmpty) {
      return _buildTabMessage('course.library_empty'.tr());
    }

    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: _libraryItems.length,
      itemBuilder: (context, index) => _buildLibraryItemCard(_libraryItems[index]),
    );
  }

  void _openLibraryMaterial(dynamic item) {
    final id = libraryId(item);
    if (id == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LibraryMaterialDetailScreen(
          materialId: id,
          initialMaterial: item,
        ),
      ),
    );
  }

  Widget _buildLibraryItemCard(dynamic item) {
    final attrs = item is Map ? (item['attributes'] ?? item) : const {};
    final map = attrs is Map ? attrs : const {};
    final title = map['title']?.toString() ?? '';
    final description = map['description']?.toString() ?? '';
    final locked = libraryIsLocked(item);
    final cover = map['cover_image']?.toString() ?? '';
    final price = map['price']?.toString() ?? '0';
    final attachments = map['attachments'] is List
        ? (map['attachments'] as List)
        : const [];

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (cover.isNotEmpty)
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
              child: CachedNetworkImage(
                imageUrl: cover,
                height: 140,
                width: double.infinity,
                fit: BoxFit.cover,
                errorWidget: (context, url, error) => const SizedBox.shrink(),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ),
                    Icon(
                      locked ? Icons.lock_outline : Icons.lock_open_outlined,
                      size: 18,
                      color: locked
                          ? const Color(0xFFF97316)
                          : const Color(0xFF10B981),
                    ),
                  ],
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    description,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.6,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Text(
                  '${'course.price'.tr()}: $price',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF475569),
                  ),
                ),
                if (attachments.isEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'course.no_attachments'.tr(),
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                ] else
                  ...attachments.whereType<Map>().map((att) {
                    final attachment = Map<String, dynamic>.from(att);
                    final name = attachmentName(attachment);
                    final url = attachmentPath(attachment);
                    final downloadable = attachmentIsDownloadable(attachment);
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: InkWell(
                        // Opening the raw URL skipped the downloadable flag
                        // and the watermark; the material page applies both.
                        onTap: locked || url.isEmpty
                            ? null
                            : () => _openLibraryMaterial(item),
                        child: Row(
                          children: [
                            Icon(
                              locked
                                  ? Icons.lock_outline
                                  : downloadable
                                      ? Icons.download_outlined
                                      : Icons.visibility_outlined,
                              size: 16,
                              color: locked
                                  ? const Color(0xFF94A3B8)
                                  : AppColors.primaryBlue,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                name,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: locked
                                      ? const Color(0xFF94A3B8)
                                      : AppColors.primaryBlue,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              downloadable
                                  ? 'library.downloadable'.tr()
                                  : 'library.not_downloadable'.tr(),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: downloadable
                                    ? const Color(0xFF047857)
                                    : const Color(0xFFB45309),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Centred empty / error text shared by the two new tabs.
  Widget _buildTabMessage(String message, {bool isError = false}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: isError ? Colors.red : const Color(0xFF64748B),
          ),
        ),
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
          Tab(
            text: _lectures.isNotEmpty
                ? '${'course.lectures_and_pdf'.tr()} (${_lectures.length})'
                : 'course.lectures_and_pdf'.tr(),
          ),
          Tab(
            text: _exams.isNotEmpty
                ? '${'course.exams'.tr()} (${_exams.length})'
                : 'course.exams'.tr(),
          ),
          Tab(
            text: _notes.isNotEmpty
                ? '${'course.notes'.tr()} (${_notes.length})'
                : 'course.notes'.tr(),
          ),
          Tab(
            text: _liveRooms.isNotEmpty
                ? '${'course.live'.tr()} (${_liveRooms.length})'
                : 'course.live'.tr(),
          ),
          Tab(
            text: (_socialLinks.isNotEmpty || _posts.isNotEmpty)
                ? '${'course.community'.tr()} (${_socialLinks.length + _posts.length})'
                : 'course.community'.tr(),
          ),
          Tab(
            text: _libraryItems.isNotEmpty
                ? '${'course.library'.tr()} (${_libraryItems.length})'
                : 'course.library'.tr(),
          ),
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
    // Videos and files only, like the web's `LecturesTab`: exams live in the
    // Exams tab and live rooms in the Live tab.
    if (_lectures.isEmpty) {
      return Center(
        child: Text(
          'course.no_lectures_available'.tr(),
          style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (_lectures.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Center(
              child: Text(
                'course.no_lectures_available'.tr(),
                style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
              ),
            ),
          )
        else
          ..._lectures.asMap().entries.map((entry) {
            final index = entry.key;
            final lecture = entry.value;
            final attributes = lecture['attributes'] ?? {};
            final lectureTitle =
                attributes['title']?.toString() ?? 'course.untitled_lecture'.tr();

            return Padding(
              padding: EdgeInsets.only(
                bottom: index < _lectures.length - 1 ? 20 : 0,
              ),
              child: _buildChapterItem(index, lectureTitle, lecture),
            );
          }),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildChapterItem(int index, String title, dynamic lecture) {
    bool isExpanded = _isExpanded.length > index ? _isExpanded[index] : false;
    // The web hides chapters whose `schedule` is still in the future.
    final chapters = studentVisibleChapters(lecture);

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
          // A lecture with no released parts, like the web's `lectureNoParts`.
          if (isExpanded && chapters.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
              child: Center(
                child: Text(
                  'course.lecture_no_parts'.tr(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF9CA3AF),
                    fontSize: 13,
                  ),
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
                    // Read every flag through the shared helpers: the API sends
                    // 1 / "1" as often as true, which the old `as bool?` casts
                    // silently turned into false.
                    final isLocked =
                        coerceFlagOrNull(chapterAttrs['is_locked']) == true;
                    final isFreePreview =
                        coerceFlag(chapterAttrs['is_free_preview']);
                    final canWatch =
                        coerceCanWatchExplicitTrue(chapterAttrs['can_watch']);
                    final isActivated =
                        coerceFlagOrNull(chapterAttrs['is_activated']) == true;
                    final isFreePreviewAttachment =
                        coerceFlag(chapterAttrs['is_free_preview_attachment']);
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

                    // PDF-only: no stream in any of the video fields, but a PDF
                    // attached. Tapping such a chapter opens the reviewer
                    // directly instead of a player with nothing to play.
                    final hasPdfOnly = chapterIsPdfOnly(chapter) ||
                        (!chapterHasVideoContent(chapter) &&
                            (attachments.isNotEmpty ||
                                chapterPdfAttachments(chapter).isNotEmpty));

                    final widgets = <Widget>[
                      _buildNestedChapterItem(
                        chapter,
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
  /// Status badges for one chapter row.
  ///
  /// The web shows the video state and the PDF state independently, plus a
  /// re-activation prompt once the view allowance is spent. The app collapsed
  /// all of that into a single badge driven by `is_free_preview`, so a chapter
  /// whose PDF was free but whose video was locked looked completely unlocked.
  List<Widget> _buildChapterStateBadges(dynamic chapter) {
    // A course the student has activated is not locked; an unloaded scope is
    // treated as locked, which is the safe direction.
    final courseLocked = !_scope.isEnrolled(widget.courseId);

    if (chapterViewsExhausted(chapter)) {
      return [
        _chapterBadge(
          'course.views_exhausted'.tr(),
          const Color(0xFFB91C1C),
          const Color(0xFFFEF2F2),
        ),
      ];
    }

    final badges = <Widget>[];

    if (chapterHasVideoContent(chapter)) {
      if (isChapterVideoPlayable(chapter, courseLocked: courseLocked)) {
        badges.add(_chapterBadge(
          'course.watch'.tr(),
          const Color(0xFF2DBC77),
          const Color(0xFFE8F9F0),
        ));
      } else if (chapterVideoRequiresActivation(chapter,
          courseLocked: courseLocked)) {
        badges.add(_chapterBadge(
          'course.locked'.tr(),
          const Color(0xFF92400E),
          const Color(0xFFFFF7ED),
        ));
      }
    }

    if (chapterHasPdfAttachment(chapter)) {
      if (isChapterPdfVisible(chapter, courseLocked: courseLocked)) {
        badges.add(_chapterBadge(
          'course.open_file'.tr(),
          const Color(0xFFE74C3C),
          const Color(0xFFFFE8E8),
        ));
      } else if (chapterPdfRequiresActivation(chapter,
          courseLocked: courseLocked)) {
        badges.add(_chapterBadge(
          'course.requires_unlock'.tr(),
          const Color(0xFF6B7280),
          const Color(0xFFF5F5F5),
        ));
      }
    }

    if (badges.isEmpty) {
      badges.add(_chapterBadge(
        'course.locked'.tr(),
        Colors.grey,
        const Color(0xFFF0F2FF),
      ));
    }

    return [
      Wrap(spacing: 6, runSpacing: 6, children: badges),
    ];
  }

  Widget _chapterBadge(String label, Color foreground, Color background) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontWeight: FontWeight.bold,
          fontSize: 11,
        ),
      ),
    );
  }

  Widget _buildNestedChapterItem(
    dynamic chapter,
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
                      chapter,
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
    dynamic chapter,
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
                  ..._buildChapterStateBadges(chapter),
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

    // Grouped exactly like the web's ExamsTab: available, upcoming, completed,
    // locked, expired — instead of one flat list where a locked exam looked
    // identical to an open one.
    final grouped = <QuizBucket, List<Quiz>>{};
    for (final exam in _exams) {
      final bucket = classifyQuiz(
        {'attributes': exam.attributes},
        _scope.enrolledCourseIds,
      );
      grouped.putIfAbsent(bucket, () => []).add(exam);
    }

    const order = [
      QuizBucket.available,
      QuizBucket.upcoming,
      QuizBucket.completed,
      QuizBucket.courseNotEnrolled,
      QuizBucket.locked,
      QuizBucket.expired,
    ];

    final sections = <Widget>[];
    for (final bucket in order) {
      final exams = grouped[bucket];
      if (exams == null || exams.isEmpty) continue;

      sections
        ..add(Padding(
          padding: EdgeInsets.only(top: sections.isEmpty ? 0 : 8, bottom: 12),
          child: Text(
            _examBucketHeading(bucket),
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1F2937),
            ),
          ),
        ))
        ..addAll(exams.map((exam) => _buildExamCard(exam, bucket)));
    }

    return ListView(
      padding: const EdgeInsets.all(24.0),
      children: sections,
    );
  }

  String _examBucketHeading(QuizBucket bucket) {
    switch (bucket) {
      case QuizBucket.available:
        return 'exams.section_available'.tr();
      case QuizBucket.upcoming:
        return 'exams.section_upcoming'.tr();
      case QuizBucket.completed:
        return 'exams.section_completed'.tr();
      case QuizBucket.courseNotEnrolled:
      case QuizBucket.locked:
        return 'exams.section_locked'.tr();
      case QuizBucket.expired:
        return 'exams.section_expired'.tr();
    }
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

  /// Badge text for a bucket, matching the web's per-section badges.
  String _examBucketBadge(QuizBucket bucket) {
    switch (bucket) {
      case QuizBucket.available:
        return 'exams.status_available'.tr();
      case QuizBucket.upcoming:
        return 'exams.status_upcoming'.tr();
      case QuizBucket.completed:
        return 'exams.status_completed'.tr();
      case QuizBucket.expired:
        return 'exams.status_expired'.tr();
      case QuizBucket.courseNotEnrolled:
        return 'exams.status_course_locked'.tr();
      case QuizBucket.locked:
        return 'exams.status_locked'.tr();
    }
  }

  /// Call-to-action for a bucket. A locked exam invites activation rather than
  /// showing a dead "not available" button.
  String _examBucketButtonLabel(QuizBucket bucket) {
    switch (bucket) {
      case QuizBucket.available:
        return 'exams.btn_start_exam'.tr();
      case QuizBucket.upcoming:
        return 'exams.btn_not_available'.tr();
      case QuizBucket.completed:
        return 'exams.status_completed'.tr();
      case QuizBucket.expired:
        return 'exams.btn_exam_expired'.tr();
      case QuizBucket.courseNotEnrolled:
        return 'exams.btn_activate_course'.tr();
      case QuizBucket.locked:
        return 'exams.btn_activate_exam'.tr();
    }
  }

  Widget _buildExamCard(Quiz exam, QuizBucket bucket) {
    // The badge and the button both follow the bucket, so an exam that is
    // locked behind an activation code can never render a Start button.
    final statusText = _examBucketBadge(bucket);
    final Color statusColor;
    final Color statusBgColor;

    switch (bucket) {
      case QuizBucket.available:
        statusColor = const Color(0xFF27AE60);
        statusBgColor = const Color(0xFFE6F7F0);
        break;
      case QuizBucket.upcoming:
        statusColor = const Color(0xFFF2994A);
        statusBgColor = const Color(0xFFFFF9F0);
        break;
      case QuizBucket.completed:
        statusColor = const Color(0xFF2563EB);
        statusBgColor = const Color(0xFFEFF6FF);
        break;
      case QuizBucket.expired:
        statusColor = Colors.red;
        statusBgColor = const Color(0xFFFFF0F0);
        break;
      case QuizBucket.locked:
      case QuizBucket.courseNotEnrolled:
        statusColor = const Color(0xFF92400E);
        statusBgColor = const Color(0xFFFFF7ED);
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
            // Locked exams stay tappable: the use case opens the activation
            // prompt, which is how a student unlocks one on the web too.
            onPressed: bucket == QuizBucket.expired ||
                    bucket == QuizBucket.completed
                ? null
                : () async {
                    final examAccessUseCase = ExamAccessUseCase();
                    await examAccessUseCase.handleExamAccess(
                      context: context,
                      quiz: exam,
                      enrolledCourseIds: _scope.enrolledCourseIds,
                    );
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: bucket == QuizBucket.available
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
              _examBucketButtonLabel(bucket).toUpperCase(),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
        ],
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
      return LiveRoomsEmptyState(message: 'live.no_course_sessions'.tr());
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
    // Website course tab: "Join Now" when live, otherwise "View" — both open
    // the live session page.
    return LiveRoomCourseCard(
      room: room,
      onOpen: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              LiveSessionDetailScreen(roomId: room.id, initialRoom: room),
        ),
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
      // The web says so explicitly rather than collapsing the section, so a
      // student can tell "no groups yet" from "still loading".
      return Container(
        margin: const EdgeInsets.all(20),
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Text(
          'community.social_empty'.tr(),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const FaIcon(
                FontAwesomeIcons.shareNodes,
                size: 16,
                color: Color(0xFF3451E5),
              ),
              const SizedBox(width: 8),
              Text(
                context.locale.languageCode == 'ar'
                    ? 'روابط ومجموعات الكورس'
                    : 'Quick Links',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1F2937),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          activeLinks.length > 2
              ? SizedBox(
                  height: 115,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: activeLinks.length,
                    separatorBuilder: (_, index) => const SizedBox(width: 12),
                    itemBuilder: (context, index) => SizedBox(
                      width: 155,
                      child: _buildQuickLinkCard(activeLinks[index]),
                    ),
                  ),
                )
              : Row(
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
    } else {
      final target = '${link.link} ${link.attributes.title}'.toLowerCase();
      if (target.contains('youtu')) {
        gradientColors = [const Color(0xFFCC181E), const Color(0xFFFF4B4B)];
      } else if (target.contains('telegram') || target.contains('t.me')) {
        gradientColors = [const Color(0xFF0088CC), const Color(0xFF29B6F6)];
      } else if (target.contains('whatsapp') || target.contains('wa.me')) {
        gradientColors = [const Color(0xFF1EBE5D), const Color(0xFF4ADE80)];
      } else if (target.contains('facebook') || target.contains('fb.com')) {
        gradientColors = [const Color(0xFF1877F2), const Color(0xFF4292F7)];
      }
    }

    return GestureDetector(
      onTap: () async {
        String urlStr = link.link.trim();
        if (urlStr.isEmpty) return;
        if (!urlStr.startsWith('http://') && !urlStr.startsWith('https://')) {
          urlStr = 'https://$urlStr';
        }
        final url = Uri.tryParse(urlStr);
        if (url != null) {
          try {
            if (await canLaunchUrl(url)) {
              await launchUrl(url, mode: LaunchMode.externalApplication);
            } else {
              await launchUrl(url, mode: LaunchMode.platformDefault);
            }
          } catch (e) {
            debugPrint('[CourseDetailScreen] Error opening social link: $e');
          }
        }
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: gradientColors,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: gradientColors[0].withValues(alpha: 0.35),
              blurRadius: 10,
              offset: const Offset(0, 4),
              spreadRadius: -1,
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: _buildSocialIcon(link),
            ),
            const SizedBox(height: 8),
            Text(
              link.attributes.title.isNotEmpty
                  ? link.attributes.title
                  : link.attributes.subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                height: 1.2,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (link.attributes.title.isNotEmpty &&
                link.attributes.subtitle.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                link.attributes.subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.normal,
                  color: Colors.white.withValues(alpha: 0.85),
                  height: 1.2,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSocialIcon(SocialLink link) {
    final iconUrl = link.attributes.icon.trim();
    if (iconUrl.isNotEmpty) {
      return ClipOval(
        child: CachedNetworkImage(
          imageUrl: iconUrl,
          width: 24,
          height: 24,
          fit: BoxFit.cover,
          memCacheWidth: 48,
          memCacheHeight: 48,
          placeholder: (context, url) => const FaIcon(
            FontAwesomeIcons.link,
            color: Colors.white,
            size: 18,
          ),
          errorWidget: (context, url, error) => _buildFallbackSocialIcon(link),
        ),
      );
    }
    return _buildFallbackSocialIcon(link);
  }

  Widget _buildFallbackSocialIcon(SocialLink link) {
    final target =
        '${link.link} ${link.attributes.title} ${link.attributes.subtitle}'
            .toLowerCase();
    final dynamic iconData;
    if (target.contains('youtu')) {
      iconData = FontAwesomeIcons.youtube;
    } else if (target.contains('t.me') || target.contains('telegram')) {
      iconData = FontAwesomeIcons.telegram;
    } else if (target.contains('wa.me') || target.contains('whatsapp')) {
      iconData = FontAwesomeIcons.whatsapp;
    } else if (target.contains('facebook') || target.contains('fb.com')) {
      iconData = FontAwesomeIcons.facebook;
    } else {
      iconData = FontAwesomeIcons.link;
    }
    return FaIcon(
      iconData,
      color: Colors.white,
      size: 18,
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
          }),
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
          if (post.attributes.images.isNotEmpty) ...[
            const SizedBox(height: 12),
            PostImages(images: post.attributes.images),
          ],
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
          PostCommentsSection(
            post: post,
            currentUserId: _currentUserId,
            onChanged: _loadCommunityPosts,
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
