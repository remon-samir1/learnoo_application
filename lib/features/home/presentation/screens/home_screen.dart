import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:shimmer/shimmer.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/services/feature_manager.dart';
import '../../../../core/widgets/feature_provider.dart';
import '../../../auth/data/auth_repository.dart';
import 'notifications_screen.dart';
import '../../../course_content/data/course_repository.dart';
import '../../../course_content/data/library_repository.dart';
import '../../../course_content/presentation/screens/course_detail_screen.dart';
import '../../../course_content/presentation/screens/electronic_library_screen.dart';
import '../../../course_content/presentation/screens/lecture_detail_screen.dart';
import '../../../course_content/presentation/screens/subject_detail_screen.dart';
import '../../../course_content/presentation/screens/unlock_material_screen.dart';
import '../../../course_content/presentation/screens/pdf_viewer_screen.dart';
import '../../../course_content/presentation/screens/live_sessions_screen.dart';
import '../../../course_content/presentation/screens/live_stream_screen.dart';
import '../../../course_content/data/chapter_repository.dart';
import '../../../course_content/data/live_room_repository.dart';
import '../../../course_content/data/models/live_room.dart';
import '../../../notes/data/notes_repository.dart';
import '../../../notes/presentation/screens/summaries_list_screen.dart';
import '../../../notes/presentation/screens/summary_detail_screen.dart';
import '../../../profile/presentation/screens/my_profile_screen.dart';
import '../../data/department_repository.dart';
import '../../data/department_filter_service.dart';
import '../../../search/data/search_repository.dart';
import 'sub_departments_screen.dart';
import 'department_options_screen.dart';

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

  // Search state variables
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  List<dynamic> _searchResults = [];
  Map<String, dynamic> _searchMeta = {};

  void _navigateToCourse(dynamic course) {
    final courseId = course['id']?.toString() ?? '';
    final attributes = course['attributes'] ?? {};
    final title = attributes['title']?.toString() ?? 'Course';
    final thumbnail = attributes['thumbnail']?.toString() ?? '';
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
    _loadUserData();
    _loadLiveClasses();
    _loadNotes();
    _loadLibraries();
    _loadContinueWatching();
  }

  Future<void> _loadLibraries() async {
    setState(() => _isLibrariesLoading = true);
    try {
      final result = await _libraryRepository.getLibraries();
      if (result['success'] && mounted) {
        setState(() {
          _libraries = result['data'] ?? [];
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
        setState(() {
          _notes = result['data'] ?? [];
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
        setState(() {
          _liveClasses = result['data'] as List<LiveRoom>;
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
                      _buildSectionHeader('home.my_subjects'.tr()),
                      const SizedBox(height: 20),
                      _buildSubjectsList(),
                      const SizedBox(height: 32),
                      _buildSectionHeader('home.my_courses_title'.tr()),
                      const SizedBox(height: 20),
                      _buildCoursesList(),
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
    final thumbnail = attributes['thumbnail']?.toString() ?? '';

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
    final attributes = library['attributes'] ?? {};
    final title = attributes['title']?.toString() ?? 'Material';
    final attachments = attributes['attachments'] as List<dynamic>? ?? [];

    // Find first PDF attachment that is not locked or downloadable
    final pdfAttachment = attachments.firstWhere((attachment) {
      final ext =
          attachment['attributes']?['extension']?.toString().toLowerCase() ??
          '';
      final isLocked = attachment['attributes']?['is_locked'] == true;
      final downloadable = attachment['attributes']?['downloadable'] == true;
      return ext == 'pdf' && (!isLocked || downloadable);
    }, orElse: () => null);

    final pdfUrl = pdfAttachment?['attributes']?['path']?.toString() ?? '';

    if (pdfUrl.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('PDF not available')));
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PdfViewerScreen(pdfUrl: pdfUrl, title: title),
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
    final thumbnail =
        chapterAttributes['thumbnail']?.toString() ??
        'https://images.unsplash.com/photo-1554224155-6726b3ff858f?w=400';
    final duration = chapterAttributes['duration']?.toString() ?? '00:00';
    final progressSeconds =
        (attributes['progress_seconds'] as num?)?.toInt() ?? 0;
    final isCompleted = attributes['is_completed'] as bool? ?? false;

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
            width: 280,
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
                    height: 160,
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(20),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: double.infinity,
                          height: 18,
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
    final firstLetter = title.isNotEmpty ? title[0].toUpperCase() : '?';

    return Container(
      width: 280,
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
        onTap: () =>
            _navigateToSubjectDetail(subject, subjectId, title, imageUrl),
        borderRadius: BorderRadius.circular(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
              child: imageUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: imageUrl,
                      width: double.infinity,
                      height: 160,
                      fit: BoxFit.cover,
                      memCacheWidth: 400,
                      memCacheHeight: 320,
                      placeholder: (context, url) => _buildSubjectIconFallback(
                        firstLetter,
                        iconColor,
                      ),
                      errorWidget: (context, url, error) {
                        return _buildSubjectIconFallback(
                          firstLetter,
                          iconColor,
                        );
                      },
                    )
                  : _buildSubjectIconFallback(firstLetter, iconColor),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: iconColor,
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      letterSpacing: -0.5,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Container(
                    height: 4,
                    width: 40,
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
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

  Widget _buildSubjectIconFallback(String letter, Color color) {
    return Container(
      width: double.infinity,
      height: 160,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Center(
        child: Text(
          letter,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w900,
            fontSize: 64,
          ),
        ),
      ),
    );
  }

  void _navigateToSubjectDetail(
    dynamic subject,
    String subjectId,
    String title,
    String imageUrl,
  ) {
    // Check if this department has children (sub-departments)
    final hasChildren = _hasChildren(subject);

    // Extract childrens array if available
    final attributes = subject['attributes'] as Map<String, dynamic>?;
    final children = attributes?['childrens'] as List<dynamic>?;

    // Check if this department has courses
    final stats = attributes?['stats'] as Map<String, dynamic>?;
    final coursesCount = stats?['courses'] as int? ?? 0;
    final hasCourses = coursesCount > 0;

    if (hasChildren && hasCourses) {
      // Department has both courses and children - show options screen
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => DepartmentOptionsScreen(
            departmentId: subjectId,
            departmentTitle: title,
            departmentImage: imageUrl,
            allDepartments: _allDepartments,
            children: children,
            coursesCount: coursesCount,
          ),
        ),
      );
    } else if (hasChildren) {
      // Navigate to sub-departments screen
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => SubDepartmentsScreen(
            parentId: subjectId,
            parentTitle: title,
            parentImage: imageUrl,
            allDepartments: _allDepartments,
            children: children,
          ),
        ),
      );
    } else {
      // Navigate directly to subject detail
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => SubjectDetailScreen(
            subjectId: subjectId,
            subjectTitle: title,
            subjectImage: imageUrl,
          ),
        ),
      );
    }
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
          final thumbnail =
              attributes['thumbnail']?.toString() ??
              'https://images.unsplash.com/photo-1554224155-26032ffc0d07?w=400';
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
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                height: 120,
                width: double.infinity,
                fit: BoxFit.cover,
                memCacheWidth: 300,
                memCacheHeight: 240,
                placeholder: (context, url) => Container(
                  height: 120,
                  width: double.infinity,
                  color: Colors.grey[300],
                ),
                errorWidget: (context, url, error) => Container(
                  height: 120,
                  width: double.infinity,
                  color: Colors.grey[300],
                ),
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
    Color iconColor,
  ) {
    return Container(
      width: 180,
      margin: const EdgeInsets.only(right: 16),
      padding: const EdgeInsets.all(16),
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
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: FaIcon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: Color(0xFF1F2937),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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
          final isLocked = attributes['is_locked'] == true;

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
      return const SizedBox(
        height: 100,
        child: Center(
          child: Text(
            'No upcoming live classes',
            style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
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
    return Container(
      padding: const EdgeInsets.all(20),
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
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: liveRoom.isLive
                      ? AppColors.liveBg
                      : const Color(0xFFFFF9F0),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 3,
                      backgroundColor: liveRoom.isLive
                          ? AppColors.liveText
                          : const Color(0xFFF2994A),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      liveRoom.isLive ? 'LIVE' : 'UPCOMING',
                      style: TextStyle(
                        color: liveRoom.isLive
                            ? AppColors.liveText
                            : const Color(0xFFF2994A),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              const FaIcon(
                FontAwesomeIcons.towerBroadcast,
                color: Color(0xFF5A75FF),
                size: 20,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            liveRoom.title,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 17,
              color: Color(0xFF1F2937),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            liveRoom.instructorName,
            style: const TextStyle(
              color: Color(0xFF9CA3AF),
              fontSize: 14,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            liveRoom.formattedTime,
            style: TextStyle(
              color: const Color(0xFF9CA3AF).withValues(alpha: 0.7),
              fontSize: 12,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () {
              if (liveRoom.isLive) {
                // Navigate to live stream screen
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => LiveStreamScreen(liveRoom: liveRoom),
                  ),
                );
              } else {
                // Navigate to live sessions screen for upcoming sessions
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const LiveSessionsScreen(),
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: liveRoom.isLive
                  ? AppColors.joinLiveGreen
                  : const Color(0xFF5A75FF),
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
            child: Text(
              liveRoom.isLive ? 'JOIN LIVE' : 'VIEW DETAILS',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
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
        setState(() {
          _continueWatchingList = result['data'] ?? [];
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

    if (chapterId.isNotEmpty && lectureId.isNotEmpty) {
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
