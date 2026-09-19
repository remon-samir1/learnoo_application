import 'dart:async';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:shimmer/shimmer.dart';
import '../../../../core/services/student_scope.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/pagination_bar.dart';
import '../../../auth//data/auth_repository.dart';
import '../../../course_content/data/course_repository.dart';
import '../../../course_content/data/chapter_repository.dart';
import '../../data/exam_repository.dart';
import '../../data/exam_filter_service.dart';
import '../../domain/quiz_activation_lock.dart';
import '../../domain/usecases/exam_access_usecase.dart';
import '../../models/quiz_models.dart';

class ExamsListScreen extends StatefulWidget {
  const ExamsListScreen({super.key});

  @override
  State<ExamsListScreen> createState() => _ExamsListScreenState();
}

class _ExamsListScreenState extends State<ExamsListScreen> {
  final ExamRepository _examRepository = ExamRepository();
  final AuthRepository _authRepository = AuthRepository();
  final CourseRepository _courseRepository = CourseRepository();
  final ChapterRepository _chapterRepository = ChapterRepository();
  final ExamAccessUseCase _examAccessUseCase = ExamAccessUseCase();

  List<Quiz> _quizzes = [];
  final Map<int, int> _remainingAttempts = {};
  final Map<int, List<QuizAttempt>> _attemptsMap = {};
  bool _isLoading = true;
  String? _errorMessage;

  // Pagination & Search state
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _debounceTimer;
  int _currentPage = 1;
  int _lastPage = 1;
  static const int _perPage = 15;
  bool _hasNextPage = false;
  bool _isSearching = false;
  String _searchQuery = '';

  List<dynamic> _cachedAllowedCourses = [];
  List<dynamic> _cachedAllChapters = [];
  StudentScope _scope = const StudentScope.empty();

  @override
  void initState() {
    super.initState();
    _loadQuizzes(page: 1);
    // Start a periodic timer to update countdown timers every second
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  Timer? _countdownTimer;

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    _debounceTimer?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadQuizzes({int page = 1}) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _currentPage = page;
    });

    try {
      // Fetch user profile, allowed courses, and chapters once (or reuse cache)
      if (_cachedAllowedCourses.isEmpty || _cachedAllChapters.isEmpty) {
        final results = await Future.wait([
          _authRepository.getProfile(),
          _courseRepository.getCourses(),
          StudentScopeService().load(),
          _chapterRepository.getChapters(),
        ]);

        if (!mounted) return;

        final meResult = results[0] as Map<String, dynamic>;
        final coursesResult = results[1] as Map<String, dynamic>;
        _scope = results[2] as StudentScope;
        final chaptersResult = results[3] as Map<String, dynamic>;

        if (meResult['success'] && coursesResult['success']) {
          final meData = meResult['data'] as Map<String, dynamic>;
          final allCourses = coursesResult['data'] as List<dynamic>? ?? [];
          final allChapters = chaptersResult['success']
              ? (chaptersResult['data'] as List<dynamic>? ?? [])
              : <dynamic>[];

          final allowedDeptIds = _getAllowedDepartmentIds(meData);
          _cachedAllowedCourses = allCourses.where((course) {
            final id = course['id']?.toString();
            if (id != null && _scope.isVisible(id)) return true;
            if (allowedDeptIds.isEmpty) return true;
            final attrs = course['attributes'] ?? {};
            final categoryId = attrs['category']?['data']?['id']?.toString() ??
                attrs['department']?['data']?['id']?.toString();
            if (categoryId == null) return false;
            return allowedDeptIds.contains(categoryId);
          }).toList();

          _cachedAllChapters = allChapters;
        }
      }

      final quizResult = await _examRepository.getQuizzes(
        page: page,
        perPage: _perPage,
        title: _searchQuery.isNotEmpty ? _searchQuery : null,
      );

      if (!mounted) return;

      if (quizResult['success']) {
        final allQuizzes = quizResult['data'] as List<Quiz>;
        final filteredQuizzes = await ExamFilterService.filterExams(
          exams: allQuizzes,
          allowedCourses: _cachedAllowedCourses,
          allChapters: _cachedAllChapters,
        );

        final meta = quizResult['meta'] as Map<String, dynamic>?;
        final lastPage = (meta?['last_page'] as num?)?.toInt() ?? 1;
        final curPage = (meta?['current_page'] as num?)?.toInt() ?? page;
        final hasNext = quizResult['hasNextPage'] as bool? ?? (curPage < lastPage);

        setState(() {
          _quizzes = filteredQuizzes;
          _currentPage = curPage;
          _lastPage = lastPage;
          _hasNextPage = hasNext;
          _isLoading = false;
          _isSearching = false;
        });

        for (final quiz in filteredQuizzes) {
          _remainingAttempts[quiz.quizId] = quiz.remainingAttempts;
        }

        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      } else {
        setState(() {
          _errorMessage = quizResult['message']?.toString() ?? 'exams.load_failed'.tr();
          _isLoading = false;
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'exams.network_error'.tr();
          _isLoading = false;
          _isSearching = false;
        });
      }
    }
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    setState(() {
      _isSearching = true;
      _searchQuery = query.trim();
    });

    _debounceTimer = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      _loadQuizzes(page: 1);
    });
  }

  void _clearSearch() {
    _searchController.clear();
    _debounceTimer?.cancel();
    setState(() {
      _searchQuery = '';
      _isSearching = false;
    });
    _loadQuizzes(page: 1);
  }

  List<Quiz> get _filteredQuizzes {
    if (_searchQuery.isEmpty) return _quizzes;
    final q = _searchQuery.toLowerCase();
    return _quizzes.where((quiz) {
      final title = quiz.title.toLowerCase();
      final chapter = (quiz.chapter?.title ?? '').toLowerCase();
      final type = quiz.type.toLowerCase();
      return title.contains(q) || chapter.contains(q) || type.contains(q);
    }).toList();
  }

  List<String> _getAllowedDepartmentIds(Map<String, dynamic> meData) {
    final Set<String> ids = {};

    final data = meData['data'] as Map<String, dynamic>?;
    final attributes = data?['attributes'] as Map<String, dynamic>?;

    // Get user's departments from me data
    final departmentsData = attributes?['departments']?['data'] as List<dynamic>? ?? [];

    for (final dept in departmentsData) {
      final deptId = dept['id']?.toString();
      if (deptId != null) {
        ids.add(deptId);
      }
    }

    return ids.toList();
  }

  Future<void> _loadAttemptsForQuiz(int quizId, int maxAttempts) async {
    final result = await _examRepository.getRemainingAttempts(quizId, maxAttempts);
    if (!mounted) return;

    if (result['success']) {
      setState(() {
        _remainingAttempts[quizId] = result['remainingAttempts'];
        if (result.containsKey('attempts') && result['attempts'] is List) {
          _attemptsMap[quizId] = result['attempts'] as List<QuizAttempt>;
        }
      });
    }
  }

  Widget _buildSearchBar() {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextField(
        controller: _searchController,
        onChanged: _onSearchChanged,
        style: const TextStyle(fontSize: 14, color: Color(0xFF1F2937)),
        decoration: InputDecoration(
          hintText: 'exams.search_exams_hint'.tr(),
          hintStyle: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
          prefixIcon: const Padding(
            padding: EdgeInsets.all(12),
            child: FaIcon(
              FontAwesomeIcons.magnifyingGlass,
              color: Color(0xFF9CA3AF),
              size: 16,
            ),
          ),
          suffixIcon: _isSearching
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Color(0xFF5A6AF0),
                      ),
                    ),
                  ),
                )
              : _searchController.text.isNotEmpty
                  ? GestureDetector(
                      onTap: _clearSearch,
                      child: const Padding(
                        padding: EdgeInsets.all(12),
                        child: FaIcon(
                          FontAwesomeIcons.xmark,
                          color: Color(0xFF9CA3AF),
                          size: 16,
                        ),
                      ),
                    )
                  : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          Container(
            height: 220,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF6B73FF), Color(0xFF5A6AF0)],
              ),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(24),
                bottomRight: Radius.circular(24),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                  child: Column(
                    children: [
                      Text(
                        'exams.title'.tr(),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildSearchBar(),
                    ],
                  ),
                ),
                Expanded(
                  child: _isLoading
                      ? _buildSkeletonList()
                      : _errorMessage != null
                          ? _buildErrorView()
                          : RefreshIndicator(
                              onRefresh: () => _loadQuizzes(page: 1),
                              child: _filteredQuizzes.isEmpty
                                  ? LayoutBuilder(
                                      builder: (context, constraints) {
                                        return SingleChildScrollView(
                                          physics:
                                              const AlwaysScrollableScrollPhysics(),
                                          child: ConstrainedBox(
                                            constraints: BoxConstraints(
                                              minHeight: constraints.maxHeight,
                                            ),
                                            child: _buildEmptyView(),
                                          ),
                                        );
                                      },
                                    )
                                  : ListView.builder(
                                      controller: _scrollController,
                                      padding: const EdgeInsets.fromLTRB(
                                          16, 8, 16, 16),
                                      physics:
                                          const AlwaysScrollableScrollPhysics(),
                                      itemCount: _filteredQuizzes.length,
                                      itemBuilder: (context, index) {
                                        final quiz = _filteredQuizzes[index];
                                        final remaining =
                                            _remainingAttempts[quiz.quizId] ??
                                                quiz.maxAttempts;
                                        return _buildQuizCard(
                                          context,
                                          quiz,
                                          remaining,
                                        );
                                      },
                                    ),
                            ),
                ),
                PaginationBar(
                  currentPage: _currentPage,
                  lastPage: _lastPage,
                  hasNextPage: _hasNextPage,
                  isLoading: _isLoading,
                  onPageChanged: (newPage) => _loadQuizzes(page: newPage),
                  primaryColor: const Color(0xFF5A6AF0),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const FaIcon(FontAwesomeIcons.circleExclamation, size: 48, color: Colors.white),
          const SizedBox(height: 16),
          Text(_errorMessage!, style: const TextStyle(color: Colors.white), textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loadQuizzes,
            style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: const Color(0xFF5A6AF0)),
            child: Text('exams.retry'.tr()),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FaIcon(FontAwesomeIcons.clipboardList, size: 48, color: AppColors.textGray.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          Text('exams.no_quizzes'.tr(), style: const TextStyle(color: AppColors.textGray, fontSize: 16)),
        ],
      ),
    );
  }

  Widget _buildQuizCard(BuildContext context, Quiz quiz, int remainingAttempts) {
    final isAvailable = quiz.isAvailable && remainingAttempts > 0;
    final isExpired = quiz.isExpired;
    final hasNoAttempts = remainingAttempts <= 0;
    final usedAttempts = quiz.currentAttempts;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [_buildTypeBadge(quiz.type), _buildStatusBadge(quiz, remainingAttempts)],
            ),
            const SizedBox(height: 12),
            Text(quiz.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textDark)),
            const SizedBox(height: 12),
            Row(
              children: [
                FaIcon(FontAwesomeIcons.clock, size: 14, color: AppColors.textGray.withValues(alpha: 0.7)),
                const SizedBox(width: 6),
                Text('course.duration_min'.tr(args: [quiz.duration.toString()]), style: const TextStyle(fontSize: 12, color: AppColors.textGray)),
                const SizedBox(width: 16),
                FaIcon(FontAwesomeIcons.calendar, size: 14, color: AppColors.textGray.withValues(alpha: 0.7)),
                const SizedBox(width: 6),
                Expanded(child: Text(_formatDateRange(quiz.startTime, quiz.endTime), style: const TextStyle(fontSize: 12, color: AppColors.textGray), overflow: TextOverflow.ellipsis)),
              ],
            ),
            if (quiz.chapter != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  FaIcon(FontAwesomeIcons.book, size: 14, color: AppColors.textGray.withValues(alpha: 0.7)),
                  const SizedBox(width: 6),
                  Expanded(child: Text('exams.chapter_prefix'.tr(args: [quiz.chapter!.title]), style: const TextStyle(fontSize: 12, color: AppColors.textGray), overflow: TextOverflow.ellipsis)),
                ],
              ),
            ],
            // Countdown timer for upcoming exams
            if (!quiz.isAvailable && !quiz.isExpired) ...[
              const SizedBox(height: 10),
              _buildCountdownTimer(quiz.startTime),
            ],
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: hasNoAttempts ? const Color(0xFFFFF0F0) : const Color(0xFFF5F7FA),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FaIcon(FontAwesomeIcons.rotateRight, size: 12, color: hasNoAttempts ? Colors.red : AppColors.textGray.withValues(alpha: 0.7)),
                  const SizedBox(width: 6),
                  Text(
                    'exams.attempts_count'.tr(args: [usedAttempts.toString(), quiz.maxAttempts.toString()]),
                    style: TextStyle(
                      fontSize: 12,
                      color: hasNoAttempts ? Colors.red : AppColors.textGray,
                      fontWeight: hasNoAttempts ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _buildActionButton(context, quiz, isAvailable, isExpired, hasNoAttempts),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeBadge(String type) {
    final isExam = type == 'exam';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: isExam ? const Color(0xFFFFF0F0) : const Color(0xFFE6F7F0), borderRadius: BorderRadius.circular(20)),
      child: Text(isExam ? 'exams.badge_exam'.tr() : 'exams.badge_homework'.tr(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isExam ? const Color(0xFFFF4B4B) : const Color(0xFF27AE60))),
    );
  }

  Widget _buildStatusBadge(Quiz quiz, int remainingAttempts) {
    // Classified through the shared gate rather than time alone, so an exam
    // that needs an activation code is never badged "Available Now".
    final bucket = classifyQuiz(
      {'attributes': quiz.attributes},
      _scope.enrolledCourseIds,
    );

    final String text;
    final Color bgColor;
    final Color textColor;

    switch (bucket) {
      case QuizBucket.expired:
        text = 'exams.status_expired'.tr();
        bgColor = const Color(0xFFF5F5F5);
        textColor = AppColors.textGray;
        break;
      case QuizBucket.completed:
        text = 'exams.status_completed'.tr();
        bgColor = const Color(0xFFEFF6FF);
        textColor = const Color(0xFF2563EB);
        break;
      case QuizBucket.locked:
        text = 'exams.status_locked'.tr();
        bgColor = const Color(0xFFFFF7ED);
        textColor = const Color(0xFF92400E);
        break;
      case QuizBucket.courseNotEnrolled:
        text = 'exams.status_course_locked'.tr();
        bgColor = const Color(0xFFFFF7ED);
        textColor = const Color(0xFF92400E);
        break;
      case QuizBucket.available:
        text = 'exams.status_available'.tr();
        bgColor = const Color(0xFFE6F7F0);
        textColor = const Color(0xFF27AE60);
        break;
      case QuizBucket.upcoming:
        text = 'exams.status_upcoming'.tr();
        bgColor = const Color(0xFFFFF4E6);
        textColor = const Color(0xFFF2994A);
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(20)),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: textColor),
      ),
    );
  }

  Widget _buildActionButton(BuildContext context, Quiz quiz, bool isAvailable, bool isExpired, bool hasNoAttempts) {
    final remainingAttempts = _remainingAttempts[quiz.quizId] ?? quiz.maxAttempts;
    final status = quiz.getStatus(remainingAttempts);

    if (status == QuizStatus.available) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: () async {
            // Use ExamAccessUseCase to handle access control
            await _examAccessUseCase.handleExamAccess(
              context: context,
              quiz: quiz,
              enrolledCourseIds: _scope.enrolledCourseIds,
            );
            // Refresh attempts when returning
            if (mounted) {
              _loadAttemptsForQuiz(quiz.quizId, quiz.maxAttempts);
            }
          },
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryBlue, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0),
          child: Text(quiz.getButtonTextKey(status).tr(), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        ),
      );
    } else {
      return _buildDisabledButton(quiz.getButtonTextKey(status).tr());
    }
  }

  Widget _buildDisabledButton(String text) {
    return SizedBox(
      width: double.infinity,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(color: const Color(0xFFE5E7EB), borderRadius: BorderRadius.circular(12)),
        child: Center(child: Text(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textGray))),
      ),
    );
  }

  Widget _buildCountdownTimer(DateTime startTime) {
    final now = DateTime.now().toUtc();
    final remaining = startTime.difference(now);

    if (remaining.isNegative) return const SizedBox.shrink();

    final days = remaining.inDays;
    final hours = remaining.inHours % 24;
    final minutes = remaining.inMinutes % 60;
    final seconds = remaining.inSeconds % 60;

    String countdownText;
    if (days > 0) {
      countdownText = 'exams.countdown_days_hours_minutes'.tr(args: [
        '$days',
        hours.toString().padLeft(2, '0'),
        minutes.toString().padLeft(2, '0'),
      ]);
    } else {
      countdownText =
          '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFF4E6), Color(0xFFFFEDD5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFDBA74).withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.timer_outlined,
            size: 15,
            color: Color(0xFFF97316),
          ),
          const SizedBox(width: 6),
          Text(
            'exams.starts_in'.tr(args: [countdownText]),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFFC2410C),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateRange(DateTime start, DateTime end) {
    // Month names follow the app language (e.g. "١٢ مايو" in Arabic).
    DateFormat format;
    try {
      format = DateFormat.MMMd(context.locale.toString());
    } catch (_) {
      format = DateFormat.MMMd('en');
    }
    return '${format.format(start.toLocal())} - ${format.format(end.toLocal())}';
  }

  Widget _buildSkeletonList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: 3,
      itemBuilder: (context, index) => _buildSkeletonCard(),
    );
  }

  Widget _buildSkeletonCard() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row - badges
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(width: 80, height: 24, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20))),
                Container(width: 100, height: 24, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20))),
              ],
            ),
            const SizedBox(height: 16),
            // Title
            Container(width: double.infinity, height: 20, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8))),
            const SizedBox(height: 8),
            Container(width: 200, height: 20, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8))),
            const SizedBox(height: 16),
            // Info rows
            Row(
              children: [
                Container(width: 100, height: 14, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))),
                const SizedBox(width: 16),
                Container(width: 120, height: 14, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))),
              ],
            ),
            const SizedBox(height: 8),
            Container(width: 180, height: 14, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))),
            const SizedBox(height: 16),
            // Button
            Container(width: double.infinity, height: 46, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12))),
          ],
        ),
      ),
    );
  }
}
