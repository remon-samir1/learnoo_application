import '../../../course_content/domain/library_material.dart';
import '../../../course_content/presentation/screens/library_material_detail_screen.dart';
import 'package:flutter/material.dart';
import '../../../../core/utils/media_url.dart';
import '../../../../core/widgets/cover_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:shimmer/shimmer.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../../core/services/student_scope.dart';
import '../../../../core/utils/coerce.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/feature_provider.dart';
import '../../../auth/data/auth_repository.dart';
import 'notifications_screen.dart';
import '../../../course_content/data/course_repository.dart';
import '../../../course_content/data/library_repository.dart';
import '../../../course_content/presentation/screens/course_detail_screen.dart';
import '../../../course_content/presentation/screens/electronic_library_screen.dart';
import '../../../course_content/presentation/screens/lecture_detail_screen.dart';
import '../../../course_content/presentation/screens/unlock_material_screen.dart';
import '../../../course_content/presentation/screens/pdf_reviewer_screen.dart';
import '../../../course_content/domain/chapter_access.dart';
import '../../../../core/network/api_constants.dart';
import '../../../course_content/presentation/screens/live_session_detail_screen.dart';
import '../../../course_content/presentation/widgets/live_room_widgets.dart';
import '../../../course_content/data/chapter_repository.dart';
import '../../../course_content/data/live_room_repository.dart';
import '../../../course_content/data/models/live_room.dart';
import '../../../community/data/models/post_model.dart';
import '../../../community/data/repositories/community_repository.dart';
import '../../../community/presentation/screens/community_screen.dart';
import '../../../exams/data/exam_repository.dart';
import '../../../exams/domain/usecases/exam_access_usecase.dart';
import '../../../exams/models/quiz_models.dart';
import '../../../exams/presentation/screens/exams_list_screen.dart';
import '../../../notes/data/notes_repository.dart';
import '../../../notes/presentation/screens/summaries_list_screen.dart';
import '../../../notes/presentation/screens/summary_detail_screen.dart';
import '../../../profile/presentation/screens/my_profile_screen.dart';
import '../../data/department_repository.dart';
import '../../../search/data/search_repository.dart';
import 'package:learnoo/features/category_tree/presentation/screens/category_tree_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _authRepository = AuthRepository();
  final _courseRepository = CourseRepository();
  final _departmentRepository = DepartmentRepository();
  final _notesRepository = NotesRepository();
  final _libraryRepository = LibraryRepository();
  final _chapterRepository = ChapterRepository();
  final _searchRepository = SearchRepository();
  final _liveRoomRepository = LiveRoomRepository();
  final _communityRepository = CommunityRepository();
  final _examRepository = ExamRepository();
  final _examAccessUseCase = ExamAccessUseCase();
  bool _isLoading = true;
  bool _isContinueWatchingLoading = true;
  bool _isCoursesLoading = true;
  bool _isSubjectsLoading = true;
  bool _isNotesLoading = true;
  bool _isLibrariesLoading = true;
  String _userName = 'Loading...';
  String _universityName = 'Loading...';
  String _facultyName = 'Loading...';
  String? _userImageUrl;
  List<String> _centers = [];
  
  // User hierarchy data for filtering
  String? _userUniversityId;
  String? _userFacultyId;
  List<String> _userCenterIds = [];
  List<dynamic> _allCenters = [];
  List<dynamic> _allFaculties = [];
  List<dynamic> _allDepartments = []; // Unfiltered list for navigation
  List<dynamic> _courses = [];
  List<dynamic> _subjects = [];
  List<dynamic> _notes = [];
  List<dynamic> _libraries = [];
  List<dynamic> _continueWatchingList = [];
  List<LiveRoom> _liveClasses = [];
  bool _isLiveClassesLoading = true;

  /// Latest general community posts and upcoming exams — the home page's
  /// `LatestPostsSection` and `NewestExams`, which the app was missing.
  List<Post> _latestPosts = const [];
  bool _isLatestPostsLoading = true;
  List<Quiz> _latestExams = const [];
  bool _isLatestExamsLoading = true;

  /// Which courses this student may see and which they activated. Every
  /// section on this screen is narrowed through it, matching the web.
  StudentScope _scope = const StudentScope.empty();

  // Search state variables
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  List<dynamic> _searchResults = [];
  Map<String, dynamic> _searchMeta = {};

  void _navigateToCourse(dynamic course) {
    final courseId = course['id']?.toString() ?? '';
    final attributes = course['attributes'] ?? {};
    final title = attributes['title']?.toString() ?? 'Course';
    final thumbnail =
        readMediaUrl(attributes, const ['thumbnail', 'image', 'cover_image']) ??
            '';
    final price = attributes['price']?.toString() ?? '0';
    final description = attributes['description']?.toString() ?? '';

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
  }

  Future<void> _loadCourses() async {
    setState(() => _isCoursesLoading = true);
    try {
      final result = await _courseRepository.getActivatedCourses();
      if (result['success'] && mounted) {
        setState(() {
          _courses = result['data'] ?? [];
          _isCoursesLoading = false;
        });
      } else if (mounted) {
        setState(() => _isCoursesLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isCoursesLoading = false);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    // The scope has to land before the sections that filter through it, so
    // nothing flashes content from a course the student is not enrolled in.
    _loadScopeThenSections();
    _loadUserData();
  }

  /// Loads the student's course scope, then every section that filters by it.
  ///
  /// The web builds `enrolledCourseIds` once and narrows continue-watching,
  /// notes, library, live sessions and the subject tree through it
  /// (`app/[locale]/student/page.tsx`). Without this the app showed material
  /// for courses the student never activated.
  Future<void> _loadScopeThenSections() async {
    try {
      final scope = await StudentScopeService().load();
      if (mounted) setState(() => _scope = scope);
    } catch (_) {
      // Fall through with an empty scope; sections handle it below.
    }

    if (!mounted) return;
    await Future.wait([
      _loadLiveClasses(),
      _loadNotes(),
      _loadLibraries(),
      _loadContinueWatching(),
      _loadLatestPosts(),
      _loadLatestExams(),
    ]);
  }

  /// Filters a list by the course id each item carries.
  ///
  /// Once the scope has loaded this is strict, exactly like the web: an item
  /// with no course id, or one pointing at a course the student has not
  /// activated, is dropped — and a student enrolled in nothing sees empty
  /// sections rather than the whole catalogue. Only a scope that never loaded
  /// (offline, or the call failed) lets the list through untouched.
  List<dynamic> _keepEnrolled(
    List<dynamic> items,
    dynamic Function(dynamic item) courseIdOf,
  ) {
    if (!_scope.isLoaded) return items;
    return items.where((item) => _scope.isEnrolled(courseIdOf(item))).toList();
  }

  /// The three newest general posts, matching `getLatestGeneralPosts`:
  /// top-level (no parent), published, and attached to no course.
  Future<void> _loadLatestPosts() async {
    setState(() => _isLatestPostsLoading = true);
    try {
      final result = await _communityRepository.getPosts();
      if (result['success'] == true && mounted) {
        final all = (result['data'] as List<Post>?) ?? const <Post>[];
        final general = all
            .where((post) =>
                post.attributes.parentId == null &&
                post.attributes.status == 'published' &&
                post.attributes.courseId == null)
            .toList()
          ..sort((a, b) =>
              b.attributes.createdAt.compareTo(a.attributes.createdAt));

        setState(() {
          _latestPosts = general.take(3).toList();
          _isLatestPostsLoading = false;
        });
      } else if (mounted) {
        setState(() => _isLatestPostsLoading = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLatestPostsLoading = false);
    }
  }

  /// The newest non-expired exams for the student's own courses, matching
  /// `getLatestStudentExams` plus the home page's enrolled-course filter.
  Future<void> _loadLatestExams() async {
    setState(() => _isLatestExamsLoading = true);
    try {
      final result = await _examRepository.getQuizzes(perPage: 100);
      if (result['success'] == true && mounted) {
        final all = (result['data'] as List<Quiz>?) ?? const <Quiz>[];

        final upcoming = all.where((quiz) {
          if (quiz.isExpired) return false;
          if (!_scope.isLoaded) return true;
          final ids = <dynamic>[
            ...quiz.courseIds,
            if (quiz.courseId != null) quiz.courseId,
          ];
          // An exam attached to no course at all is hidden, like on the web.
          return ids.isNotEmpty && _scope.isAnyEnrolled(ids);
        }).toList()
          ..sort((a, b) => b.startTime.compareTo(a.startTime));

        setState(() {
          _latestExams = upcoming.take(3).toList();
          _isLatestExamsLoading = false;
        });
      } else if (mounted) {
        setState(() => _isLatestExamsLoading = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLatestExamsLoading = false);
    }
  }

  Future<void> _loadLibraries() async {
    setState(() => _isLibrariesLoading = true);
    try {
      final result = await _libraryRepository.getLibraries();
      if (result['success'] && mounted) {
        final all = (result['data'] ?? []) as List<dynamic>;
        setState(() {
          _libraries = _keepEnrolled(all, (item) {
            final attrs = item is Map ? (item['attributes'] ?? item) : null;
            return attrs is Map ? attrs['course_id'] : null;
          });
          _isLibrariesLoading = false;
        });
      } else if (mounted) {
        setState(() => _isLibrariesLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLibrariesLoading = false);
      }
    }
  }

  Future<void> _loadNotes() async {
    setState(() => _isNotesLoading = true);
    try {
      final result = await _notesRepository.getNotes();
      if (result['success'] && mounted) {
        final all = (result['data'] ?? []) as List<dynamic>;
        setState(() {
          _notes = _keepEnrolled(all, (item) {
            final attrs = item is Map ? (item['attributes'] ?? item) : null;
            return attrs is Map ? attrs['course_id'] : null;
          });
          _isNotesLoading = false;
        });
      } else if (mounted) {
        setState(() => _isNotesLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isNotesLoading = false);
      }
    }
  }

  Future<void> _loadSubjects() async {
    setState(() => _isSubjectsLoading = true);
    try {
      final departmentsResult = await _departmentRepository.getDepartments();
      
      if (departmentsResult['success'] && mounted) {
        final allDepartments = departmentsResult['data'] ?? [];
        
        // Store unfiltered list for nested navigation
        _allDepartments = allDepartments;
        
        // Filter departments by user's faculty
        List<dynamic> filteredSubjects = allDepartments;
        if (_userFacultyId != null && _userFacultyId!.isNotEmpty) {
          filteredSubjects = allDepartments.where((dept) {
            final attributes = dept['attributes'] ?? {};
            
            // Check parent_id (direct children of faculty)
            final parentId = attributes['parent_id']?.toString();
            if (parentId == _userFacultyId) return true;
            
            // Check parent.data.id (nested parent structure)
            final parentDataId = attributes['parent']?['data']?['id']?.toString();
            if (parentDataId == _userFacultyId) return true;
            
            return false;
          }).toList();
        }
        
        setState(() {
          _subjects = filteredSubjects;
          _isSubjectsLoading = false;
        });
      } else if (mounted) {
        setState(() => _isSubjectsLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubjectsLoading = false);
      }
    }
  }

  Future<void> _loadLiveClasses() async {
    setState(() => _isLiveClassesLoading = true);
    try {
      final result = await _liveRoomRepository.getLiveRooms();
      if (result['success'] && mounted) {
        final all = result['data'] as List<LiveRoom>;
        setState(() {
          // A session can belong to several courses; keep it when any of them
          // is one the student activated. A session attached to no course at
          // all is dropped, which is what the web does.
          _liveClasses = !_scope.isLoaded
              ? all
              : all
                  .where((room) =>
                      _scope.isAnyEnrolled(room.courseIds) ||
                      (room.courseId != null && _scope.isEnrolled(room.courseId)))
                  .toList();
          _isLiveClassesLoading = false;
        });
      } else if (mounted) {
        setState(() => _isLiveClassesLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLiveClassesLoading = false);
      }
    }
  }

  Future<void> _loadUserData() async {
    try {
      // 1. Get Profile
      final profileResult = await _authRepository.getProfile();
      if (profileResult['success']) {
        final attributes = profileResult['data']['attributes'];
        final firstName = (attributes['first_name'] ?? '').toString();
        final lastName = (attributes['last_name'] ?? '').toString();
        final fullName = '$firstName $lastName'.trim();

        final universityName =
            (attributes['university']?['data']?['attributes']?['name'] ??
                    'home.university_not_set'.tr())
                .toString();

        // Parse faculty (data.attributes.name)
        final facultyName =
            (attributes['faculty']?['data']?['attributes']?['name'] ??
                    'home.faculty_not_set'.tr())
                .toString();

        // Parse centers (array of categories)
        final centersData = attributes['centers'] as List<dynamic>? ?? [];
        final centers = centersData
            .map((center) {
              return (center['attributes']?['name'] ?? '').toString();
            })
            .where((name) => name.isNotEmpty)
            .toList();

        // Extract user hierarchy IDs for filtering
        final universityId = attributes['university']?['data']?['id']?.toString();
        final facultyId = attributes['faculty']?['data']?['id']?.toString();
        final centerIds = centersData
            .map((c) => c['id']?.toString())
            .where((id) => id != null)
            .cast<String>()
            .toList();

        // Parse user image
        final userImage = attributes['image']?.toString();

        setState(() {
          _userName = fullName.isEmpty ? 'User' : fullName;
          _universityName = universityName;
          _facultyName = facultyName;
          _userImageUrl = userImage;
          _centers = centers;
          _userUniversityId = universityId;
          _userFacultyId = facultyId;
          _userCenterIds = centerIds;
          _isLoading = false;
        });

        // Load centers and faculties for hierarchy validation
        await _loadCentersAndFaculties();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadCentersAndFaculties() async {
    try {
      // Load centers
      final centersResult = await _departmentRepository.getCenters();
      if (centersResult['success']) {
        _allCenters = centersResult['data'] ?? [];
      }

      // Load faculties
      final facultiesResult = await _departmentRepository.getFaculties();
      if (facultiesResult['success']) {
        _allFaculties = facultiesResult['data'] ?? [];
      }

      // Reload subjects with hierarchy filtering
      await _loadSubjects();
      // Reload courses to filter by available departments
      await _loadCourses();
    } catch (e) {
      // Fallback: load subjects without filtering
      await _loadSubjects();
      // Still try to load courses
      await _loadCourses();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _performSearch(String query) async {
    if (query.isEmpty) {
      setState(() {
        _isSearching = false;
        _searchResults = [];
        _searchMeta = {};
      });
      return;
    }

    setState(() => _isSearching = true);

    try {
      final result = await _searchRepository.search(
        query: query,
        type: null, // Empty type to get all types
        limit: 10,
      );

      if (mounted) {
        setState(() {
          if (result['success']) {
            _searchResults = result['data'] ?? [];
            _searchMeta = result['meta'] ?? {};
          } else {
            _searchResults = [];
            _searchMeta = {};
          }
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSearching = false;
          _searchResults = [];
          _searchMeta = {};
        });
      }
    }
  }

  void _clearSearch() {
    setState(() {
      _searchController.clear();
      _isSearching = false;
      _searchResults = [];
      _searchMeta = {};
    });
  }

  Map<String, List<dynamic>> _groupSearchResultsByType() {
    final grouped = <String, List<dynamic>>{};

    for (final item in _searchResults) {
      final type = item['type']?.toString() ?? 'unknown';
      // Filter out user results
      if (type.toLowerCase() == 'user') {
        continue;
      }
      if (!grouped.containsKey(type)) {
        grouped[type] = [];
      }
      grouped[type]!.add(item);
    }

    return grouped;
  }

  String _getTypeDisplayName(String type) {
    switch (type.toLowerCase()) {
      case 'course':
        return 'home.type_courses'.tr();
      case 'chapter':
        return 'home.type_chapters'.tr();
      case 'librarie':
        return 'home.type_libraries'.tr();
      case 'post':
        return 'home.type_posts'.tr();
      case 'note':
        return 'home.type_notes'.tr();
      case 'quizze':
        return 'home.type_quizzes'.tr();
      default:
        return type.isNotEmpty
            ? type[0].toUpperCase() + type.substring(1)
            : type;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // Background Gradients
          Positioned(
            top: -100,
            left: -50,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFFFFE4E1).withValues(alpha: 0.4),
                    const Color(0xFFFFE4E1).withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: -50,
            right: -100,
            child: Container(
              width: 400,
              height: 400,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFFE6E6FA).withValues(alpha: 0.4),
                    const Color(0xFFE6E6FA).withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 100,
            right: -150,
            child: Container(
              width: 500,
              height: 500,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFFFFFACD).withValues(alpha: 0.3),
                    const Color(0xFFFFFACD).withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),

          SafeArea(
            child: RefreshIndicator(
              onRefresh: _onRefresh,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),
                    _buildHeader(),
                    const SizedBox(height: 24),
                    _buildSearchBar(),
                    const SizedBox(height: 32),
                    if (_searchController.text.isNotEmpty) ...[
                      _buildSearchResults(),
                    ] else ...[
                      FeatureVisibility(
                        featureKey: 'feature_continue_watching',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSectionHeader('home.continue_watching'.tr()),
                            const SizedBox(height: 20),
                            _buildContinueWatching(),
                            const SizedBox(height: 32),
                          ],
                        ),
                      ),
                      _buildSectionHeaderWithAction(
                        'home.my_subjects'.tr(),
                        'home.view_all'.tr(),
                        () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const CategoryTreeScreen(),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 20),
                      _buildSubjectsList(),
                      const SizedBox(height: 32),
                      _buildSectionHeader('home.my_courses_title'.tr()),
                      const SizedBox(height: 20),
                      _buildCoursesList(),
                      const SizedBox(height: 32),
                      _buildSectionHeaderWithAction(
                        'home.latest_posts'.tr(),
                        'home.view_all'.tr(),
                        () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const CommunityScreen(),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 20),
                      _buildLatestPostsList(),
                      const SizedBox(height: 32),
                      _buildSectionHeaderWithAction(
                        'home.newest_exams'.tr(),
                        'home.view_all'.tr(),
                        () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const ExamsListScreen(),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 20),
                      _buildNewestExamsList(),
                      const SizedBox(height: 32),
                      _buildSectionHeader('home.upcoming_live_classes'.tr()),
                      const SizedBox(height: 20),
                      _buildLiveClassesList(),
                      const SizedBox(height: 32),
                      _buildSectionHeaderWithAction(
                        'home.new_notes'.tr(),
                        'home.view_all'.tr(),
                        () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const SummariesListScreen(),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 20),
                      _buildNotesSummariesList(),
                      const SizedBox(height: 32),
                      FeatureVisibility(
                        featureKey: 'feature_electronic_library',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSectionHeaderWithAction(
                              'home.electronic_library'.tr(),
                              'home.view_all'.tr(),
                              () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        const ElectronicLibraryScreen(),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 20),
                            _buildLibraryList(),
                            const SizedBox(height: 32),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipOval(
            child: _userImageUrl != null && _userImageUrl!.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: _userImageUrl!,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                    memCacheWidth: 96,
                    memCacheHeight: 96,
                    placeholder: (context, url) => const CircleAvatar(
                      radius: 24,
                      backgroundColor: Color(0xFFEEEEEE),
                      child: FaIcon(
                        FontAwesomeIcons.user,
                        color: Color(0xFF5A75FF),
                        size: 20,
                      ),
                    ),
                    errorWidget: (context, url, error) => const CircleAvatar(
                      radius: 24,
                      backgroundColor: Color(0xFFEEEEEE),
                      child: FaIcon(
                        FontAwesomeIcons.user,
                        color: Color(0xFF5A75FF),
                        size: 20,
                      ),
                    ),
                  )
                : const CircleAvatar(
                    radius: 24,
                    backgroundColor: Color(0xFFEEEEEE),
                    child: FaIcon(
                      FontAwesomeIcons.user,
                      color: Color(0xFF5A75FF),
                      size: 20,
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${'home.welcome_back'.tr()}$_userName',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF4B4B4B),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _isLoading ? 'home.loading_profile'.tr() : _buildSubtitleText(),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: const Color(0xFF4B4B4B).withValues(alpha: 0.6),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const NotificationsScreen(),
              ),
            );
          },
          child: Container(
            height: 44,
            width: 44,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                const FaIcon(
                  FontAwesomeIcons.bell,
                  color: Color(0xFF5A75FF),
                  size: 22,
                ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF4B4B),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const MyProfileScreen()),
            );
          },
          child: Container(
            height: 44,
            width: 44,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Center(
              child: FaIcon(
                FontAwesomeIcons.gear,
                color: Color(0xFF5A75FF),
                size: 22,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: TextField(
        controller: _searchController,
        onChanged: (value) {
          _performSearch(value);
        },
        decoration: InputDecoration(
          hintText: 'home.search_hint'.tr(),
          hintStyle: const TextStyle(color: Color(0xFFD1D1D1), fontSize: 14),
          prefixIcon: const Padding(
            padding: EdgeInsets.all(14),
            child: FaIcon(
              FontAwesomeIcons.magnifyingGlass,
              color: Color(0xFFD1D1D1),
              size: 18,
            ),
          ),
          suffixIcon: _isSearching
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Color(0xFF5A75FF),
                      ),
                    ),
                  ),
                )
              : _searchController.text.isNotEmpty
              ? GestureDetector(
                  onTap: _clearSearch,
                  child: const Padding(
                    padding: EdgeInsets.all(14),
                    child: FaIcon(
                      FontAwesomeIcons.xmark,
                      color: Color(0xFFD1D1D1),
                      size: 18,
                    ),
                  ),
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 18),
        ),
      ),
    );
  }

  Widget _buildSearchResults() {
    if (_isSearching) {
      return _buildSearchShimmer();
    }

    if (_searchResults.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Column(
            children: [
              const FaIcon(
                FontAwesomeIcons.magnifyingGlass,
                color: Color(0xFFD1D1D1),
                size: 48,
              ),
              const SizedBox(height: 16),
              Text(
                'home.no_results'.tr(),
                style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    final groupedResults = _groupSearchResultsByType();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Show total results count
        if (_searchMeta.isNotEmpty && _searchMeta['counts'] != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              'home.found_results'.tr(args: [_searchResults.length.toString()]),
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF9CA3AF),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        // Show results grouped by type
        ...groupedResults.entries.map((entry) {
          final type = entry.key;
          final items = entry.value;
          return _buildSearchResultSection(type, items);
        }).toList(),
      ],
    );
  }

  Widget _buildSearchShimmer() {
    return Column(
      children: List.generate(3, (index) {
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Shimmer.fromColors(
            baseColor: Colors.grey[300]!,
            highlightColor: Colors.grey[100]!,
            child: Row(
              children: [
                Container(
                  width: 64,
                  height: 64,
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
                        width: double.infinity,
                        height: 16,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: 150,
                        height: 12,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  Widget _buildSearchResultSection(String type, List<dynamic> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _getTypeDisplayName(type),
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppColors.textDark,
          ),
        ),
        const SizedBox(height: 12),
        ...items.map((item) => _buildSearchResultItem(type, item)).toList(),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildSearchResultItem(String type, dynamic item) {
    final attributes = item['attributes'] ?? {};
    final title = attributes['title']?.toString() ?? 'Untitled';
    final description = attributes['description']?.toString() ?? '';
    final thumbnail = resolveMediaUrl(
          attributes['thumbnail'] ?? attributes['image'],
        ) ??
        '';

    FaIconData iconData;
    Color iconColor;

    switch (type.toLowerCase()) {
      case 'course':
        iconData = FontAwesomeIcons.graduationCap;
        iconColor = const Color(0xFF5A75FF);
        break;
      case 'chapter':
        iconData = FontAwesomeIcons.playCircle;
        iconColor = const Color(0xFF10B981);
        break;
      case 'librarie':
        iconData = FontAwesomeIcons.book;
        iconColor = const Color(0xFFF59E0B);
        break;
      case 'post':
        iconData = FontAwesomeIcons.newspaper;
        iconColor = const Color(0xFFEC4899);
        break;
      case 'note':
        iconData = FontAwesomeIcons.noteSticky;
        iconColor = const Color(0xFF8B5CF6);
        break;
      case 'quizze':
        iconData = FontAwesomeIcons.circleQuestion;
        iconColor = const Color(0xFFEF4444);
        break;
      default:
        iconData = FontAwesomeIcons.file;
        iconColor = const Color(0xFF9CA3AF);
    }

    return GestureDetector(
      onTap: () => _navigateToSearchResult(type, item),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
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
            if (thumbnail.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CachedNetworkImage(
                  imageUrl: thumbnail,
                  width: 64,
                  height: 64,
                  fit: BoxFit.cover,
                  memCacheWidth: 128,
                  memCacheHeight: 128,
                  placeholder: (context, url) => Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: FaIcon(iconData, color: iconColor, size: 24),
                    ),
                  ),
                  errorWidget: (context, url, error) {
                    return Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: iconColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: FaIcon(iconData, color: iconColor, size: 24),
                      ),
                    );
                  },
                ),
              )
            else
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: FaIcon(iconData, color: iconColor, size: 24),
                ),
              ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1F2937),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF9CA3AF),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const FaIcon(
              FontAwesomeIcons.chevronRight,
              color: Color(0xFFD1D1D1),
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToSearchResult(String type, dynamic item) {
    // Navigate based on type
    switch (type.toLowerCase()) {
      case 'course':
        _navigateToCourse(item);
        break;
      case 'chapter':
        _navigateToChapter(item);
        break;
      case 'note':
        _navigateToNote(item);
        break;
      case 'librarie':
        // Navigate to library
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const ElectronicLibraryScreen(),
          ),
        );
        break;
      case 'post':
        // Could navigate to post detail screen
        break;
      case 'quizze':
        // Could navigate to quiz detail screen
        break;
    }
  }

  void _navigateToChapter(dynamic chapter) {
    final chapterId = chapter['id']?.toString() ?? '';
    final attributes = chapter['attributes'] ?? {};
    final title = attributes['title']?.toString() ?? 'Chapter';
    // course_id is a flat attribute in the chapter search result
    final courseId = attributes['course_id']?.toString() ?? '';
    // Get max_views from chapter data if available
    final maxViews = int.tryParse(attributes['max_views']?.toString() ?? '');

    if (chapterIsPdfOnly(chapter)) {
      final pdfs = chapterPdfAttachments(chapter);
      dynamic chosenPdf = pdfs.isNotEmpty ? pdfs.first : null;
      final rawAtts = attributes['attachments'];
      if (chosenPdf == null && rawAtts is List && rawAtts.isNotEmpty) {
        chosenPdf = rawAtts.first;
      }
      if (chosenPdf != null) {
        final attAttrs = chosenPdf['attributes'] is Map ? chosenPdf['attributes'] as Map : chosenPdf;
        String pdfPath = attAttrs['path']?.toString() ?? '';
        final pdfName = attAttrs['name']?.toString() ?? title;
        if (pdfPath.isNotEmpty) {
          if (!pdfPath.startsWith('http')) {
            pdfPath = pdfPath.replaceAll('\\', '/');
            if (!pdfPath.startsWith('/')) pdfPath = '/$pdfPath';
            pdfPath = '${ApiConstants.baseUrl}$pdfPath';
          }
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PdfReviewerScreen(
                pdfUrl: pdfPath,
                title: pdfName,
              ),
            ),
          );
          return;
        }
      }
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LectureDetailScreen(
          lectureId: '',
          lectureTitle: title,
          chapterId: chapterId,
          chapterTitle: title,
          courseId: courseId,
          maxViews: maxViews,
        ),
      ),
    );
  }

  void _navigateToNote(dynamic note) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => SummaryDetailScreen(note: note)),
    );
  }

  void _openLibraryPdf(dynamic library) {
    final id = libraryId(library);
    if (id == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LibraryMaterialDetailScreen(
          materialId: id,
          initialMaterial: library,
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: AppColors.textDark,
      ),
    );
  }

  Widget _buildSectionHeaderWithAction(
    String title,
    String actionText,
    VoidCallback onAction,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.textDark,
          ),
        ),
        TextButton(
          onPressed: onAction,
          child: Text(
            actionText,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF5A75FF),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContinueWatching() {
    if (_isContinueWatchingLoading) {
      return _buildContinueWatchingShimmer();
    }

    if (_continueWatchingList.isEmpty) {
      return const SizedBox.shrink();
    }

    // Show the first item (most recent) from the continue watching list
    final progressItem = _continueWatchingList.first;
    final attributes = progressItem['attributes'] ?? {};
    final chapterData = attributes['chapter']?['data'] ?? {};
    final chapterAttributes = chapterData['attributes'] ?? {};

    final chapterTitle = chapterAttributes['title']?.toString() ?? 'Chapter';
    final thumbnail = chapterAttributes['thumbnail']?.toString() ?? '';
    final duration = chapterAttributes['duration']?.toString() ?? '00:00';
    final progressSeconds =
        (attributes['progress_seconds'] as num?)?.toInt() ?? 0;
    // The API sends 1 / "1" as often as true, which an `as bool?` cast turns
    // into false.
    final isCompleted = coerceFlag(attributes['is_completed']);

    // Calculate progress percentage from duration and progress_seconds
    double progress = 0.0;
    int totalSeconds = 0;
    final durationParts = duration.split(':');
    if (durationParts.length == 2) {
      final minutes = int.tryParse(durationParts[0]) ?? 0;
      final seconds = int.tryParse(durationParts[1]) ?? 0;
      totalSeconds = minutes * 60 + seconds;
      if (totalSeconds > 0) {
        progress = progressSeconds / totalSeconds;
      }
    }

    // Format current position (where user left off) and total duration
    String timeDisplay;
    if (isCompleted) {
      timeDisplay = 'Completed';
    } else {
      // Format current position
      final currMinutes = progressSeconds ~/ 60;
      final currSecs = progressSeconds % 60;
      final currentTimeStr =
          '${currMinutes.toString().padLeft(2, '0')}:${currSecs.toString().padLeft(2, '0')}';

      // Format total duration
      final totalMinutes = totalSeconds ~/ 60;
      final totalSecs = totalSeconds % 60;
      final totalTimeStr =
          '${totalMinutes.toString().padLeft(2, '0')}:${totalSecs.toString().padLeft(2, '0')}';

      timeDisplay = '$currentTimeStr / $totalTimeStr';
    }

    return _buildContinueWatchingCard(
      courseName: chapterTitle,
      lectureName: chapterTitle,
      thumbnail: thumbnail,
      progress: progress,
      timeDisplay: timeDisplay,
      onContinue: () => _navigateToLectureDetail(progressItem),
    );
  }

  Widget _buildContinueWatchingShimmer() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFF1F1F1)),
      ),
      child: Shimmer.fromColors(
        baseColor: Colors.grey[300]!,
        highlightColor: Colors.grey[100]!,
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 104,
                  height: 78,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        height: 16,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: 100,
                        height: 12,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(2),
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
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContinueWatchingCard({
    required String courseName,
    required String lectureName,
    required String thumbnail,
    required double progress,
    required String timeDisplay,
    required VoidCallback onContinue,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
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
        children: [
          Row(
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: CachedNetworkImage(
                      imageUrl: thumbnail,
                      width: 104,
                      height: 78,
                      fit: BoxFit.cover,
                      memCacheWidth: 208,
                      memCacheHeight: 156,
                      placeholder: (context, url) => Container(
                        width: 104,
                        height: 78,
                        color: Colors.grey[300],
                      ),
                      errorWidget: (context, url, error) => Container(
                        width: 104,
                        height: 78,
                        color: Colors.grey[300],
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: const FaIcon(
                      FontAwesomeIcons.play,
                      color: Color(0xFF5A75FF),
                      size: 14,
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
                      courseName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      lectureName,
                      style: const TextStyle(
                        color: Color(0xFF9CA3AF),
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: LinearProgressIndicator(
                              value: progress,
                              backgroundColor: const Color(0xFFF1F1F1),
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                Color(0xFF5A75FF),
                              ),
                              minHeight: 4,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          timeDisplay,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF9CA3AF),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: onContinue,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2137D6),
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Continue',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                SizedBox(width: 8),
                FaIcon(FontAwesomeIcons.play, size: 14),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Filter only root departments (direct children of faculties)
  List<dynamic> get _rootDepartments {
    return _subjects.where((subject) {
      final attributes = subject['attributes'] as Map<String, dynamic>?;
      if (attributes == null) return false;

      // Check nested parent.data.type format
      final parent = attributes['parent'] as Map<String, dynamic>?;
      if (parent != null) {
        final parentData = parent['data'] as Map<String, dynamic>?;
        if (parentData != null) {
          return parentData['type'] == 'faculty';
        }
      }

      // Fallback: check flat parent_id format (API returns parent_id pointing to faculty)
      final parentId = attributes['parent_id']?.toString();
      final parentType = attributes['parent_type']?.toString();
      
      // If parent_type is explicitly set, use it
      if (parentType != null) {
        return parentType == 'faculty';
      }
      
      // If has parent_id but no parent_type, assume it's a faculty (root department)
      return parentId != null;
    }).toList();
  }

  // Check if a department has children
  bool _hasChildren(dynamic subject) {
    final attributes = subject['attributes'] as Map<String, dynamic>?;
    if (attributes == null) return false;

    // First check if childrens array exists and is not empty
    final childrens = attributes['childrens'] as List<dynamic>?;
    if (childrens != null && childrens.isNotEmpty) {
      return true;
    }

    final departmentId = subject['id']?.toString();
    if (departmentId == null) return false;

    // Fallback: check if any subject has this as parent
    return _subjects.any((s) {
      final attrs = s['attributes'] as Map<String, dynamic>?;
      if (attrs == null) return false;

      // Check nested parent.data.id format
      final parent = attrs['parent'] as Map<String, dynamic>?;
      if (parent != null) {
        final parentData = parent['data'] as Map<String, dynamic>?;
        if (parentData != null) {
          return parentData['id']?.toString() == departmentId;
        }
      }

      // Fallback: check flat parent_id format
      final parentId = attrs['parent_id']?.toString();
      final parentType = attrs['parent_type']?.toString();
      if (parentId == departmentId) {
        return parentType == 'department' || parentType == null;
      }
      return false;
    });
  }

  Widget _buildSubjectsList() {
    if (_isSubjectsLoading) {
      return _buildSubjectsShimmerList();
    }

    final rootDepartments = _rootDepartments;

    if (rootDepartments.isEmpty) {
      return const SizedBox(
        height: 100,
        child: Center(
          child: Text(
            'No subjects available',
            style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      clipBehavior: Clip.none,
      child: Row(
        children: rootDepartments.asMap().entries.map((entry) {
          final index = entry.key;
          final subject = entry.value;
          final attributes = subject['attributes'] ?? {};
          final id = subject['id']?.toString() ?? '';
          final title =
              attributes['name']?.toString() ??
              attributes['title']?.toString() ??
              'Subject';
          final image =
              attributes['image']?.toString() ??
              attributes['icon']?.toString() ??
              '';

          // Get color based on index
          final colorIndex = index % AppColors.subjectColors.length;
          final colors = AppColors.subjectColors[colorIndex];

          return _buildSubjectItem(
            subject,
            id,
            title,
            image,
            colors['bg']!,
            colors['text']!,
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSubjectsShimmerList() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      clipBehavior: Clip.none,
      child: Row(
        children: List.generate(3, (index) {
          return Container(
            width: _subjectCardWidth,
            height: _subjectCardHeight,
            margin: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Shimmer.fromColors(
              baseColor: Colors.grey[300]!,
              highlightColor: Colors.grey[100]!,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: _subjectThumbnailHeight,
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(16),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: double.infinity,
                          height: 14,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: 80,
                          height: 11,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildSubjectItem(
    dynamic subject,
    String subjectId,
    String title,
    String imageUrl,
    Color bgColor,
    Color iconColor,
  ) {
    final attributes = subject is Map ? (subject['attributes'] ?? {}) : {};
    final stats = attributes is Map ? attributes['stats'] : null;
    final coursesCount = stats is Map ? coerceInt(stats['courses']) : 0;
    final studentsCount = stats is Map ? coerceInt(stats['students']) : 0;

    return Container(
      width: _subjectCardWidth,
      height: _subjectCardHeight,
      margin: const EdgeInsets.only(right: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: InkWell(
        onTap: () =>
            _navigateToSubjectDetail(subject, subjectId, title, imageUrl),
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
              child: CoverImage(
                url: imageUrl,
                title: title,
                height: _subjectThumbnailHeight,
                icon: Icons.menu_book_rounded,
                cacheWidth: _subjectCardWidth.round(),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: iconColor,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        height: 1.25,
                        letterSpacing: -0.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const Spacer(),
                    // Same two counters the web card shows under the title.
                    Row(
                      children: [
                        _subjectStat(
                          Icons.menu_book_outlined,
                          '$coursesCount',
                          iconSize: 14,
                          fontSize: 12,
                        ),
                        const SizedBox(width: 12),
                        _subjectStat(
                          Icons.people_alt_outlined,
                          '$studentsCount',
                          iconSize: 14,
                          fontSize: 12,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Department card metrics.
  ///
  /// Sized to be visually prominent but still fit two cards side by side on
  /// a 360dp screen. Larger than before to match the web's department cards.
  static const double _subjectCardWidth = 200;
  static const double _subjectThumbnailHeight = 130;
  static const double _subjectCardHeight = 222;

  Widget _subjectStat(IconData icon, String value, {double iconSize = 13, double fontSize = 11}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: iconSize, color: const Color(0xFF9CA3AF)),
        const SizedBox(width: 4),
        Text(
          value,
          style: TextStyle(fontSize: fontSize, color: const Color(0xFF6B7280)),
        ),
      ],
    );
  }

  void _navigateToSubjectDetail(
    dynamic subject,
    String subjectId,
    String title,
    String imageUrl,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CategoryTreeScreen(
          initialSelectedId: subjectId,
        ),
      ),
    );
  }

  Widget _buildCoursesList() {
    if (_isCoursesLoading) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        clipBehavior: Clip.none,
        child: Row(
          children: [_buildCourseShimmerCard(), _buildCourseShimmerCard()],
        ),
      );
    }

    if (_courses.isEmpty) {
      return const SizedBox(
        height: 100,
        child: Center(
          child: Text(
            'No courses available',
            style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      clipBehavior: Clip.none,
      child: Row(
        children: _courses.map((course) {
          final attributes = course['attributes'] ?? {};
          final title = attributes['title']?.toString() ?? 'Untitled Course';
          final instructor =
              attributes['instructor']?['data']?['attributes']?['full_name']
                  ?.toString() ??
              attributes['instructor_name']?.toString() ??
              'Unknown Instructor';
          final thumbnail = attributes['thumbnail']?.toString() ?? '';
          final accentColor = const Color(0xFF2137D6);

          return _buildCourseCard(
            course,
            title,
            instructor,
            thumbnail,
            accentColor: accentColor,
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCourseShimmerCard() {
    return Container(
      width: 260,
      margin: const EdgeInsets.only(right: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Shimmer.fromColors(
        baseColor: Colors.grey[300]!,
        highlightColor: Colors.grey[100]!,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 130,
              width: double.infinity,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    height: 16,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: 100,
                    height: 12,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
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

  Widget _buildCourseCard(
    dynamic course,
    String title,
    String instructor,
    String imageUrl, {
    Color? accentColor,
  }) {
    final color = accentColor ?? const Color(0xFF2137D6);
    return Container(
      width: 240,
      margin: const EdgeInsets.only(right: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: InkWell(
        onTap: () => _navigateToCourse(course),
        borderRadius: BorderRadius.circular(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
              child: CoverImage(
                url: imageUrl,
                title: title,
                height: 120,
                cacheWidth: 240,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: Color(0xFF1F2937),
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    instructor,
                    style: TextStyle(
                      color: const Color(0xFF9CA3AF),
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              height: 4,
              width: double.infinity,
              decoration: BoxDecoration(
                color: color,
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(20),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<dynamic> get _summaryNotes {
    return _notes.where((note) {
      final attributes = note['attributes'] ?? {};
      return attributes['type'] == 'summary';
    }).toList();
  }

  // -----------------------------------------------------------------------
  // Latest community posts — the web's `LatestPostsSection`.
  // -----------------------------------------------------------------------

  Widget _buildLatestPostsList() {
    if (_isLatestPostsLoading) {
      return Column(
        children: [_buildFeedShimmerCard(), _buildFeedShimmerCard()],
      );
    }

    if (_latestPosts.isEmpty) {
      return _buildFeedEmptyState('home.no_posts'.tr());
    }

    return Column(children: _latestPosts.map(_buildLatestPostCard).toList());
  }

  Widget _buildLatestPostCard(Post post) {
    final attrs = post.attributes;
    final author = attrs.user?.attributes;
    final authorName = author == null || author.fullName.trim().isEmpty
        ? 'community.unknown_user'.tr()
        : author.fullName.trim();
    final title = attrs.title.trim().isEmpty ? attrs.content : attrs.title;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const CommunityScreen()),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 48,
              width: 48,
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.person_outline,
                color: AppColors.primaryBlue,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: Color(0xFF1F2937),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    authorName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF9CA3AF),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(
                        Icons.chat_bubble_outline,
                        size: 13,
                        color: Color(0xFF9CA3AF),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${attrs.commentsCount}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF9CA3AF),
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Icon(
                        Icons.thumb_up_outlined,
                        size: 13,
                        color: Color(0xFF9CA3AF),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${attrs.reactionsCount}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF9CA3AF),
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

  // -----------------------------------------------------------------------
  // Newest exams — the web's `NewestExams`.
  // -----------------------------------------------------------------------

  Widget _buildNewestExamsList() {
    if (_isLatestExamsLoading) {
      return Column(
        children: [_buildFeedShimmerCard(), _buildFeedShimmerCard()],
      );
    }

    if (_latestExams.isEmpty) {
      return _buildFeedEmptyState('home.no_exams'.tr());
    }

    return Column(children: _latestExams.map(_buildNewestExamCard).toList());
  }

  Widget _buildNewestExamCard(Quiz quiz) {
    final isAvailable = quiz.isAvailable;
    final title = quiz.title.trim().isEmpty
        ? 'home.untitled_exam'.tr()
        : quiz.title.trim();
    final typeLabel = quiz.type == 'homework'
        ? 'exams.type_homework'.tr()
        : 'exams.type_exam'.tr();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 48,
                width: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.assignment_outlined,
                  color: AppColors.primaryBlue,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        _examMetaChip(Icons.description_outlined, typeLabel),
                        if (quiz.duration > 0)
                          _examMetaChip(
                            Icons.schedule,
                            'exams.duration_minutes'
                                .tr(args: ['${quiz.duration}']),
                          ),
                        _examMetaChip(
                          Icons.calendar_today_outlined,
                          _formatExamDate(quiz.startTime),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isAvailable
                      ? const Color(0xFFECFDF5)
                      : const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  isAvailable
                      ? 'exams.status_available'.tr()
                      : 'exams.status_upcoming'.tr(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isAvailable
                        ? const Color(0xFF047857)
                        : const Color(0xFFC2410C),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: isAvailable
                  ? () => _examAccessUseCase.handleExamAccess(
                        context: context,
                        quiz: quiz,
                        enrolledCourseIds: _scope.enrolledCourseIds,
                      )
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFFE5E7EB),
                disabledForegroundColor: AppColors.textGray,
                padding: const EdgeInsets.symmetric(vertical: 12),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                isAvailable
                    ? 'exams.btn_start_exam'.tr()
                    : 'exams.btn_not_available'.tr(),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _examMetaChip(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: const Color(0xFF9CA3AF)),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
        ),
      ],
    );
  }

  static const List<String> _monthAbbreviations = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _formatExamDate(DateTime value) {
    final local = value.toLocal();
    final month = _monthAbbreviations[local.month - 1];
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.day.toString().padLeft(2, '0')} $month, ${local.hour}:$minute';
  }

  /// Shared empty state for the two feed sections above.
  Widget _buildFeedEmptyState(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
      ),
    );
  }

  Widget _buildFeedShimmerCard() {
    return Shimmer.fromColors(
      baseColor: const Color(0xFFEEEEEE),
      highlightColor: const Color(0xFFF5F5F5),
      child: Container(
        height: 96,
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }

  Widget _buildNotesSummariesList() {
    if (_isNotesLoading) {
      return _buildNotesSummariesShimmer();
    }

    if (_summaryNotes.isEmpty) {
      return const SizedBox(
        height: 100,
        child: Center(
          child: Text(
            'No summaries available',
            style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      clipBehavior: Clip.none,
      child: Row(
        children: _summaryNotes.take(5).map((note) {
          final attributes = note['attributes'] ?? {};
          final title = attributes['title']?.toString() ?? 'Untitled';
          final type = attributes['type']?.toString() ?? 'note';
          final linkedLecture = attributes['linked_lecture']?.toString();
          final createdAt = attributes['created_at']?.toString();
          final imageUrl = attributes['image']?.toString() ??
              attributes['thumbnail']?.toString() ?? '';

          final typeStyles = _getNoteTypeStyles(type);
          final dateText = _formatNoteDate(createdAt);
          final subtitle = linkedLecture != null
              ? '$linkedLecture • $dateText'
              : dateText;

          return GestureDetector(
            onTap: () => _navigateToNoteDetail(note),
            child: _buildNoteSummaryCard(
              title,
              subtitle,
              typeStyles['icon'],
              typeStyles['bgColor'],
              typeStyles['iconColor'],
              imageUrl: imageUrl,
            ),
          );
        }).toList(),
      ),
    );
  }

  Map<String, dynamic> _getNoteTypeStyles(String type) {
    switch (type) {
      case 'summary':
        return {
          'icon': FontAwesomeIcons.fileLines,
          'bgColor': const Color(0xFFFFF0F0),
          'iconColor': const Color(0xFFFF4B4B),
        };
      case 'highlight':
      case 'key_point':
        return {
          'icon': FontAwesomeIcons.highlighter,
          'bgColor': const Color(0xFFE6F9F1),
          'iconColor': const Color(0xFF10B981),
        };
      case 'important_notice':
        return {
          'icon': FontAwesomeIcons.circleExclamation,
          'bgColor': const Color(0xFFFFE6E6),
          'iconColor': const Color(0xFFEF4444),
        };
      case 'video_note':
        return {
          'icon': FontAwesomeIcons.video,
          'bgColor': const Color(0xFFEEF0FF),
          'iconColor': const Color(0xFF5A75FF),
        };
      default:
        return {
          'icon': FontAwesomeIcons.noteSticky,
          'bgColor': const Color(0xFFFFF9F0),
          'iconColor': const Color(0xFFF2994A),
        };
    }
  }

  String _formatNoteDate(String? dateString) {
    if (dateString == null) return 'Recently';
    try {
      final date = DateTime.parse(dateString);
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inDays == 0) {
        return 'Today';
      } else if (difference.inDays == 1) {
        return 'Yesterday';
      } else if (difference.inDays < 7) {
        return '${difference.inDays} days ago';
      } else {
        return '${(difference.inDays / 7).floor()} weeks ago';
      }
    } catch (e) {
      return 'Recently';
    }
  }

  void _navigateToNoteDetail(dynamic note) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => SummaryDetailScreen(note: note)),
    );
  }

  Widget _buildNotesSummariesShimmer() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      clipBehavior: Clip.none,
      child: Row(
        children: List.generate(3, (index) {
          return Container(
            width: 180,
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFF1F1F1)),
            ),
            child: Shimmer.fromColors(
              baseColor: Colors.grey[300]!,
              highlightColor: Colors.grey[100]!,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    height: 14,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: 100,
                    height: 12,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildNoteSummaryCard(
    String title,
    String subtitle,
    FaIconData icon,
    Color bgColor,
    Color iconColor, {
    String imageUrl = '',
  }) {
    return Container(
      width: 190,
      margin: const EdgeInsets.only(right: 16),
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
          // Thumbnail image on top of card if available
          if (imageUrl.isNotEmpty)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                width: double.infinity,
                height: 100,
                fit: BoxFit.cover,
                memCacheWidth: 380,
                memCacheHeight: 200,
                placeholder: (context, url) => Container(
                  height: 100,
                  color: bgColor,
                  child: Center(child: FaIcon(icon, color: iconColor, size: 24)),
                ),
                errorWidget: (context, url, error) => Container(
                  height: 100,
                  color: bgColor,
                  child: Center(child: FaIcon(icon, color: iconColor, size: 24)),
                ),
              ),
            )
          else
            // Icon-only fallback header
            Container(
              height: 72,
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: FaIcon(icon, color: iconColor, size: 24),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: Color(0xFF1F2937),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLibraryList() {
    if (_isLibrariesLoading) {
      return _buildLibraryShimmerList();
    }

    if (_libraries.isEmpty) {
      return const SizedBox(
        height: 100,
        child: Center(
          child: Text(
            'No library materials available',
            style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      clipBehavior: Clip.none,
      child: Row(
        children: _libraries.take(5).map((library) {
          final attributes = library['attributes'] ?? {};
          final title = attributes['title']?.toString() ?? 'Untitled';
          final price = attributes['price']?.toString() ?? '0';
          final coverImage = attributes['cover_image']?.toString() ?? '';
          final isLocked = libraryIsLocked(library);

          return _buildLibraryCard(
            title: title,
            price: 'EGP $price',
            imageUrl: coverImage,
            requiresCode: isLocked,
            library: library,
          );
        }).toList(),
      ),
    );
  }

  Widget _buildLibraryShimmerList() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      clipBehavior: Clip.none,
      child: Row(
        children: [
          _buildLibraryShimmerCard(),
          _buildLibraryShimmerCard(),
          _buildLibraryShimmerCard(),
        ],
      ),
    );
  }

  Widget _buildLibraryShimmerCard() {
    return Container(
      width: 280,
      margin: const EdgeInsets.only(right: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF1F1F1)),
      ),
      child: Shimmer.fromColors(
        baseColor: Colors.grey[300]!,
        highlightColor: Colors.grey[100]!,
        child: Row(
          children: [
            Container(
              width: 80,
              height: 100,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.horizontal(
                  left: Radius.circular(16),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      height: 16,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: 60,
                      height: 14,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: 80,
                      height: 28,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLibraryCard({
    required String title,
    required String price,
    required String imageUrl,
    required bool requiresCode,
    required dynamic library,
  }) {
    return Container(
      width: 280,
      margin: const EdgeInsets.only(right: 16),
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
      child: Row(
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(16),
            ),
            child: CachedNetworkImage(
              imageUrl: imageUrl,
              width: 80,
              height: 100,
              fit: BoxFit.cover,
              memCacheWidth: 160,
              memCacheHeight: 200,
              placeholder: (context, url) => Container(
                width: 80,
                height: 100,
                color: const Color(0xFFF3F4F6),
                child: const Icon(Icons.book, color: Color(0xFF9CA3AF)),
              ),
              errorWidget: (context, url, error) {
                return Container(
                  width: 80,
                  height: 100,
                  color: const Color(0xFFF3F4F6),
                  child: const Icon(Icons.book, color: Color(0xFF9CA3AF)),
                );
              },
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: Color(0xFF1F2937),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        price,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: Color(0xFF5A75FF),
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          if (requiresCode) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    UnlockMaterialScreen(library: library),
                              ),
                            );
                          } else {
                            _openLibraryPdf(library);
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2137D6),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            requiresCode ? 'Unlock' : 'Open',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveClassesList() {
    if (_isLiveClassesLoading) {
      return Column(
        children: [
          _buildLiveClassShimmer(),
          const SizedBox(height: 16),
          _buildLiveClassShimmer(),
        ],
      );
    }

    if (_liveClasses.isEmpty) {
      return SizedBox(
        height: 100,
        child: Center(
          child: Text(
            'live.home_empty'.tr(),
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted(context), fontSize: 14),
          ),
        ),
      );
    }

    return Column(
      children: _liveClasses.take(3).map((liveClass) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _buildLiveClassCard(liveRoom: liveClass),
        );
      }).toList(),
    );
  }

  Widget _buildLiveClassShimmer() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF1F1F1)),
      ),
      child: Shimmer.fromColors(
        baseColor: Colors.grey[300]!,
        highlightColor: Colors.grey[100]!,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 50,
                  height: 24,
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
              width: double.infinity,
              height: 20,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: 150,
              height: 14,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: 100,
              height: 12,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              height: 52,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveClassCard({required LiveRoom liveRoom}) {
    // Website home card: every action opens the live session page.
    return LiveHomeCard(
      room: liveRoom,
      onOpen: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => LiveSessionDetailScreen(
            roomId: liveRoom.id,
            initialRoom: liveRoom,
          ),
        ),
      ),
    );
  }

  String _buildSubtitleText() {
    final parts = <String>[];
    if (_universityName != 'University not set') {
      parts.add(_universityName);
    }
    if (_facultyName != 'Faculty not set') {
      parts.add(_facultyName);
    }
    if (_centers.isNotEmpty) {
      parts.add(_centers.join(', '));
    }
    return parts.isEmpty ? 'Profile not complete' : parts.join(' — ');
  }

  Future<void> _onRefresh() async {
    await _loadUserData();
    await _loadCourses();
    await _loadSubjects();
    await _loadLiveClasses();
    await _loadNotes();
    await _loadLibraries();
    await _loadContinueWatching();
  }

  Future<void> _loadContinueWatching() async {
    setState(() => _isContinueWatchingLoading = true);
    try {
      final result = await _chapterRepository.getUserProgress();
      if (result['success'] && mounted) {
        final all = (result['data'] ?? []) as List<dynamic>;
        setState(() {
          // Progress rows reach the course through the chapter they belong to.
          _continueWatchingList = _keepEnrolled(all, (item) {
            if (item is! Map) return null;
            final attrs = item['attributes'];
            if (attrs is! Map) return null;
            final chapter = attrs['chapter']?['data']?['attributes'];
            return chapter is Map ? chapter['course_id'] : null;
          });
          _isContinueWatchingLoading = false;
        });
      } else if (mounted) {
        setState(() => _isContinueWatchingLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isContinueWatchingLoading = false);
      }
    }
  }

  void _navigateToLectureDetail(dynamic progressItem) {
    final attributes = progressItem['attributes'] ?? {};
    final chapterData = attributes['chapter']?['data'] ?? {};
    final chapterAttributes = chapterData['attributes'] ?? {};

    final chapterId = chapterData['id']?.toString() ?? '';
    final chapterTitle = chapterAttributes['title']?.toString() ?? 'Chapter';
    final lectureId = chapterAttributes['lecture_id']?.toString() ?? '';
    final lectureTitle =
        chapterAttributes['lecture_title']?.toString() ?? 'Lecture';
    // course_id is a flat attribute in the chapter data
    final courseId = chapterAttributes['course_id']?.toString() ?? '';
    // Get max_views from chapter data if available
    final maxViews = int.tryParse(chapterAttributes['max_views']?.toString() ?? '');
    // Get the saved progress seconds to resume from where user left off
    final progressSeconds =
        (attributes['progress_seconds'] as num?)?.toInt() ?? 0;

    if (chapterId.isNotEmpty) {
      if (chapterIsPdfOnly(chapterData)) {
        final pdfs = chapterPdfAttachments(chapterData);
        dynamic chosenPdf = pdfs.isNotEmpty ? pdfs.first : null;
        final rawAtts = chapterAttributes['attachments'];
        if (chosenPdf == null && rawAtts is List && rawAtts.isNotEmpty) {
          chosenPdf = rawAtts.first;
        }
        if (chosenPdf != null) {
          final attAttrs = chosenPdf['attributes'] is Map ? chosenPdf['attributes'] as Map : chosenPdf;
          String pdfPath = attAttrs['path']?.toString() ?? '';
          final pdfName = attAttrs['name']?.toString() ?? chapterTitle;
          if (pdfPath.isNotEmpty) {
            if (!pdfPath.startsWith('http')) {
              pdfPath = pdfPath.replaceAll('\\', '/');
              if (!pdfPath.startsWith('/')) pdfPath = '/$pdfPath';
              pdfPath = '${ApiConstants.baseUrl}$pdfPath';
            }
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => PdfReviewerScreen(
                  pdfUrl: pdfPath,
                  title: pdfName,
                ),
              ),
            );
            return;
          }
        }
      }

      if (lectureId.isNotEmpty) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => LectureDetailScreen(
              lectureId: lectureId,
              lectureTitle: lectureTitle,
              chapterId: chapterId,
              chapterTitle: chapterTitle,
              courseId: courseId,
              initialPosition: progressSeconds,
              maxViews: maxViews,
            ),
          ),
        );
      }
    }
  }
}
