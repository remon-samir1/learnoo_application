import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/models/post_model.dart';
import '../../data/models/social_link_model.dart';
import '../../data/repositories/community_repository.dart';
import '../widgets/post_comments_section.dart';
import '../widgets/post_images.dart';
import 'create_post_screen.dart';
import '../../../search/data/search_repository.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_linkify/flutter_linkify.dart';

class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key});

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  /// Filter value meaning "every enrolled course". Kept apart from the
  /// displayed label so switching language doesn't break the selection.
  static const String _allFilter = '__all__';

  String _selectedFilter = _allFilter;
  final TextEditingController _commentController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final CommunityRepository _repository = CommunityRepository();
  final SearchRepository _searchRepository = SearchRepository();

  List<Post> _posts = [];
  List<PostCourse> _courses = [];
  List<SocialLink> _socialLinks = [];
  bool _isLoading = true;
  bool _isLoadingSocialLinks = false;
  bool _hasError = false;

  /// Signed-in student's id, so their own comments get a delete button — the
  /// same check the web's comment list makes.
  String? _currentUserId;

  // Search state variables
  bool _isSearching = false;
  List<dynamic> _searchResults = [];
  bool _showSearchResults = false;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    _loadCurrentUserId();
  }

  Future<void> _loadInitialData() async {
    await _loadCourses();
    await _loadPosts();
  }

  Future<void> _loadCurrentUserId() async {
    final id = await _repository.currentUserId();
    if (mounted) setState(() => _currentUserId = id);
  }

  Future<void> _loadPosts() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    String? courseId;
    if (_selectedFilter != _allFilter) {
      final selectedCourse = _courses.where((c) => c.id == _selectedFilter).firstOrNull;
      if (selectedCourse != null && selectedCourse.id.isNotEmpty) {
        courseId = selectedCourse.id;
      }
    }

    final result = await _repository.getEnrolledCoursesPosts(
      courseId: courseId,
      enrolledCourses: _courses,
    );

    if (mounted) {
      setState(() {
        _isLoading = false;
        if (result['success']) {
          _posts = List<Post>.from(result['data'] ?? []);
          if (result['courses'] is List<PostCourse>) {
            _courses = result['courses'] as List<PostCourse>;
          } else if (result['course'] is PostCourse) {
            final updated = result['course'] as PostCourse;
            final idx = _courses.indexWhere((c) => c.id == updated.id);
            if (idx != -1) {
              _courses[idx] = updated;
            }
          }
        } else {
          _hasError = true;
        }
      });
      _updateSocialLinks();
    }
  }

  Future<void> _loadCourses() async {
    final result = await _repository.getCourses(activated: true);
    if (result['success'] && mounted) {
      final List<dynamic> courseData = result['data'] ?? [];
      setState(() {
        _courses = courseData.map((c) => PostCourse.fromJson(c)).toList();
      });
      _updateSocialLinks();
    }
  }

  PostCourse? get _selectedCourse => _selectedFilter == _allFilter
      ? null
      : _courses.where((c) => c.id == _selectedFilter).firstOrNull;

  void _updateSocialLinks() {
    if (!mounted) return;

    if (_selectedFilter == _allFilter) {
      // Gather all unique active social links from all enrolled courses
      final Map<String, SocialLink> uniqueLinks = {};
      for (final course in _courses) {
        for (final link in course.attributes.socialLinks) {
          final key = link.id.isNotEmpty ? link.id : link.link;
          if (key.isNotEmpty && !uniqueLinks.containsKey(key)) {
            uniqueLinks[key] = link;
          }
        }
      }
      setState(() {
        _socialLinks = uniqueLinks.values.toList();
        _isLoadingSocialLinks = false;
      });
    } else {
      setState(() {
        _socialLinks = _selectedCourse?.attributes.socialLinks ?? [];
        _isLoadingSocialLinks = false;
      });
    }
  }

  Future<void> _handleReaction(Post post, String reactionType) async {
    final currentReaction = post.attributes.userReaction;
    Post updatedPost;

    if (currentReaction == reactionType) {
      // Remove reaction
      final result = await _repository.removeReaction(post.id);
      if (result['success']) {
        final newCount = post.attributes.reactionsCount > 0
            ? post.attributes.reactionsCount - 1
            : 0;
        updatedPost = post.copyWith(
          attributes: post.attributes.copyWith(
            reactionsCount: newCount,
            userReaction: null,
          ),
        );
      } else {
        _showSnack('community.reaction_failed'.tr(), isError: true);
        return;
      }
    } else {
      // Add or change reaction
      final result = await _repository.reactToPost(post.id, reactionType);
      if (result['success']) {
        final newCount = currentReaction != null
            ? post.attributes.reactionsCount
            : post.attributes.reactionsCount + 1;
        updatedPost = post.copyWith(
          attributes: post.attributes.copyWith(
            reactionsCount: newCount,
            userReaction: reactionType,
          ),
        );
      } else {
        _showSnack('community.reaction_failed'.tr(), isError: true);
        return;
      }
    }

    if (!mounted) return;
    setState(() {
      final index = _posts.indexWhere((p) => p.id == post.id);
      if (index != -1) {
        _posts[index] = updatedPost;
      }
    });
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : null,
      ),
    );
  }

  String _formatTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 365) {
      return 'community.years_ago'.tr(args: ['${difference.inDays ~/ 365}']);
    } else if (difference.inDays > 30) {
      return 'community.months_ago'.tr(args: ['${difference.inDays ~/ 30}']);
    } else if (difference.inDays > 0) {
      return 'community.days_ago'.tr(args: ['${difference.inDays}']);
    } else if (difference.inHours > 0) {
      return 'community.hours_ago'.tr(args: ['${difference.inHours}']);
    } else if (difference.inMinutes > 0) {
      return 'community.minutes_ago'.tr(args: ['${difference.inMinutes}']);
    } else {
      return 'community.just_now'.tr();
    }
  }

  @override
  void dispose() {
    _commentController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _performSearch(String query) async {
    if (query.isEmpty) {
      setState(() {
        _showSearchResults = false;
        _searchResults = [];
      });
      return;
    }

    setState(() => _isSearching = true);

    try {
      final result = await _searchRepository.search(
        query: query,
        type: 'posts', // Filter by posts type
        limit: 10,
      );

      if (mounted) {
        setState(() {
          if (result['success']) {
            _searchResults = result['data'] ?? [];
          } else {
            _searchResults = [];
          }
          _showSearchResults = true;
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSearching = false;
          _searchResults = [];
        });
      }
    }
  }

  void _clearSearch() {
    setState(() {
      _searchController.clear();
      _showSearchResults = false;
      _searchResults = [];
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
      _showSnack('community.post_created'.tr());
      _loadPosts();
    }
  }

  Future<void> _openLink(String rawLink) async {
    String urlStr = rawLink.trim();
    if (urlStr.isEmpty) return;
    if (!urlStr.startsWith('http://') && !urlStr.startsWith('https://')) {
      urlStr = 'https://$urlStr';
    }
    final url = Uri.tryParse(urlStr);
    if (url == null) {
      _showSnack('community.could_not_open_link'.tr(), isError: true);
      return;
    }
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(url, mode: LaunchMode.platformDefault);
      }
    } catch (_) {
      _showSnack('community.could_not_open_link'.tr(), isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface(context),
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                await _loadCourses();
                await _loadPosts();
              },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!_showSearchResults) ...[
                      _buildFilterTabs(),
                      _buildCommunityInfoCard(),
                      _buildQuickLinks(),
                    ],
                    _isSearching
                        ? _buildSkeletonPosts()
                        : _showSearchResults
                            ? _buildSearchResultsList()
                            : _isLoading
                                ? _buildSkeletonPosts()
                                : _hasError
                                    ? _buildErrorWidget()
                                    : _posts.isEmpty
                                        ? _buildEmptyWidget()
                                        : _buildPostsList(),
                    const SizedBox(height: 80),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: _buildFloatingActionButton(),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  Widget _buildHeader() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF3451E5),
            Color(0xFF5A75FF),
            Color(0xFF7B93FF),
          ],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      child: Column(
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 26),
              child: Column(
                children: [
                  Text(
                    'community.title'.tr(),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (value) {
                        _performSearch(value);
                      },
                      style: const TextStyle(color: Colors.white),
                      cursorColor: Colors.white,
                      decoration: InputDecoration(
                        hintText: 'community.search_posts'.tr(),
                        hintStyle: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 14,
                        ),
                        filled: false,
                        prefixIcon: const Padding(
                          padding: EdgeInsetsDirectional.only(start: 16, end: 12, top: 14),
                          child: FaIcon(
                            FontAwesomeIcons.magnifyingGlass,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                        prefixIconConstraints: const BoxConstraints(
                          minWidth: 46,
                          minHeight: 46,
                        ),
                        suffixIcon: _isSearching
                            ? const Padding(
                                padding: EdgeInsets.all(14),
                                child: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                ),
                              )
                            : _searchController.text.isNotEmpty
                                ? GestureDetector(
                                    onTap: _clearSearch,
                                    child: const Padding(
                                      padding: EdgeInsetsDirectional.only(end: 16, start: 12, top: 12),
                                      child: FaIcon(
                                        FontAwesomeIcons.xmark,
                                        color: Colors.white,
                                        size: 18,
                                      ),
                                    ),
                                  )
                                : null,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterTabs() {
    final isDark = AppColors.isDark(context);
    final filters = <MapEntry<String, String>>[
      MapEntry(_allFilter, 'community.all'.tr()),
      ..._courses.map((c) => MapEntry(c.id, c.attributes.title)),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: filters.map((filter) {
            final isSelected = _selectedFilter == filter.key;
            return Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedFilter = filter.key;
                  });
                  _updateSocialLinks();
                  _loadPosts();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primaryBlue
                        : (isDark ? AppColors.input(context) : const Color(0xFFF0F2FF)),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    filter.value,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: isSelected ? Colors.white : AppColors.subtext(context),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: AppColors.card(context),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: AppColors.isDark(context) ? AppColors.border(context) : const Color(0xFFF0F2FF),
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.03),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ],
    );
  }

  Widget _buildCommunityInfoCard() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(20),
      decoration: _cardDecoration(),
      child: Column(
        children: [
          Text(
            'community.title'.tr(),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.text(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'community.subtitle'.tr(),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: AppColors.subtext(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickLinks() {
    if (_isLoadingSocialLinks) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
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

    final selectedCourse = _selectedCourse;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const FaIcon(
                FontAwesomeIcons.shareNodes,
                size: 14,
                color: AppColors.primaryBlue,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  selectedCourse == null
                      ? 'community.courses_links_title'.tr()
                      : 'community.course_links_title_named'
                          .tr(args: [selectedCourse.attributes.title]),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text(context),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          activeLinks.length > 2
              ? SizedBox(
                  height: 110,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    itemCount: activeLinks.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 12),
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
                        padding: EdgeInsetsDirectional.only(
                          end: activeLinks.last == link ? 0 : 12,
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
    final base = AppColors.isDark(context) ? AppColors.input(context) : Colors.grey[300];
    final inner = AppColors.isDark(context) ? AppColors.border(context) : Colors.grey[400];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: BoxDecoration(
        color: base,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: inner,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: 60,
            height: 11,
            decoration: BoxDecoration(
              color: inner,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ),
    );
  }

  FaIconData _getSocialIconData(SocialLink link) {
    final target = '${link.link} ${link.attributes.title} ${link.attributes.subtitle}'.toLowerCase();
    if (target.contains('youtu')) return FontAwesomeIcons.youtube;
    if (target.contains('telegram') || target.contains('t.me')) return FontAwesomeIcons.telegram;
    if (target.contains('whatsapp') || target.contains('wa.me')) return FontAwesomeIcons.whatsapp;
    if (target.contains('facebook') || target.contains('fb.com')) return FontAwesomeIcons.facebook;
    return FontAwesomeIcons.link;
  }

  Widget _buildQuickLinkCard(SocialLink link) {
    // Build gradient colors from custom color or platform detection or default
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
        final a = (baseColor.a * 255.0).round();
        final r = (baseColor.r * 255.0).round();
        final g = (baseColor.g * 255.0).round();
        final b = (baseColor.b * 255.0).round();
        final lighterColor = Color.fromARGB(
          a,
          (r + 40).clamp(0, 255),
          (g + 40).clamp(0, 255),
          (b + 60).clamp(0, 255),
        );
        gradientColors = [baseColor, lighterColor];
      } catch (_) {
        // Keep default gradient
      }
    } else {
      final target = '${link.link} ${link.attributes.title} ${link.attributes.subtitle}'.toLowerCase();
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

    final iconUrl = resolveCommunityMediaUrl(link.attributes.icon);

    return GestureDetector(
      onTap: () => _openLink(link.link),
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
              child: iconUrl != null
                  ? ClipOval(
                      child: Image.network(
                        iconUrl,
                        width: 24,
                        height: 24,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return FaIcon(
                            _getSocialIconData(link),
                            color: Colors.white,
                            size: 18,
                          );
                        },
                      ),
                    )
                  : FaIcon(
                      _getSocialIconData(link),
                      color: Colors.white,
                      size: 18,
                    ),
            ),
            const SizedBox(height: 8),
            Text(
              link.attributes.title.isNotEmpty ? link.attributes.title : link.attributes.subtitle,
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
            if (link.attributes.title.isNotEmpty && link.attributes.subtitle.isNotEmpty) ...[
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

  Widget _buildSkeletonPosts() {
    return Column(
      children: List.generate(3, (index) => _buildSkeletonPostCard()),
    );
  }

  Widget _buildSkeletonPostCard() {
    final block = AppColors.isDark(context) ? AppColors.input(context) : Colors.grey[200];

    Widget bar(double? width, double height, {double radius = 4}) => Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: block,
            borderRadius: BorderRadius.circular(radius),
          ),
        );

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: block,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    bar(120, 14),
                    const SizedBox(height: 8),
                    bar(80, 12),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          bar(double.infinity, 60, radius: 8),
          const SizedBox(height: 16),
          Row(
            children: [
              bar(60, 24, radius: 12),
              const SizedBox(width: 8),
              bar(60, 24, radius: 12),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(top: 40, left: 20, right: 20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: AppColors.muted(context)),
            const SizedBox(height: 16),
            Text(
              'community.failed_load_posts'.tr(),
              style: TextStyle(color: AppColors.subtext(context)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadPosts,
              child: Text('community.retry'.tr()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyWidget() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(top: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.isDark(context) ? AppColors.input(context) : Colors.grey[100],
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.forum_outlined,
                size: 48,
                color: AppColors.muted(context),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'community.no_posts'.tr(),
              style: TextStyle(
                color: AppColors.subtext(context),
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPostsList() {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _posts.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final post = _posts[index];
        return _buildPostCard(
          post: post,
          isPinned: index == 0 && post.attributes.postType == 'summary',
        );
      },
    );
  }

  Widget _buildSearchResultsList() {
    if (_searchResults.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FaIcon(
                FontAwesomeIcons.magnifyingGlass,
                color: AppColors.muted(context),
                size: 48,
              ),
              const SizedBox(height: 16),
              Text(
                'community.no_posts_found'.tr(args: [_searchController.text]),
                style: TextStyle(
                  color: AppColors.subtext(context),
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final results = _searchResults
        .whereType<Map>()
        .map((item) => Post.fromJson(Map<String, dynamic>.from(item)))
        .toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search results header
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'community.search_results'.tr(args: ['${results.length}']),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.text(context),
              ),
            ),
          ),
          // Search results list
          for (final post in results) ...[
            _buildPostCard(post: post, isPinned: false, horizontalMargin: 0),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  void _showReactionPicker(Post post) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card(context),
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 16,
          children: [
            _buildReactionButton(post, 'like', FontAwesomeIcons.thumbsUp, Colors.blue),
            _buildReactionButton(post, 'love', FontAwesomeIcons.heart, Colors.red),
            _buildReactionButton(post, 'haha', FontAwesomeIcons.faceLaughSquint, Colors.orange),
            _buildReactionButton(post, 'wow', FontAwesomeIcons.faceSurprise, Colors.amber),
            _buildReactionButton(post, 'sad', FontAwesomeIcons.faceSadTear, Colors.purple),
            _buildReactionButton(post, 'angry', FontAwesomeIcons.faceAngry, Colors.redAccent),
          ],
        ),
      ),
    );
  }

  Widget _buildReactionButton(Post post, String type, FaIconData icon, Color color) {
    final isSelected = post.attributes.userReaction == type;
    return Tooltip(
      message: 'community.reaction_$type'.tr(),
      child: GestureDetector(
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
        return Colors.amber;
      case 'sad':
        return Colors.purple;
      case 'angry':
        return Colors.redAccent;
      default:
        return AppColors.subtext(context);
    }
  }

  String _postTypeLabel(String type) {
    switch (type) {
      case 'question':
        return 'community.type_question'.tr();
      case 'summary':
        return 'community.type_summary'.tr();
      default:
        return 'community.type_post'.tr();
    }
  }

  Widget _buildPostCard({
    required Post post,
    bool isPinned = false,
    double horizontalMargin = 20,
  }) {
    final isDark = AppColors.isDark(context);
    final user = post.attributes.user;
    final course = post.attributes.course ??
        (post.attributes.courseId != null
            ? _courses.where((c) => c.id == post.attributes.courseId).firstOrNull
            : null);
    final rawName = user == null
        ? ''
        : '${user.attributes.firstName} ${user.attributes.lastName}'.trim();
    final userName = rawName.isNotEmpty ? rawName : 'community.unknown_user'.tr();
    final role = user?.attributes.role.toLowerCase() ?? '';
    final isInstructor = role == 'admin' || role == 'instructor' || role == 'doctor';
    final timeAgo = _formatTimeAgo(post.attributes.createdAt);
    final hasReaction = post.attributes.userReaction != null;
    final textColor = AppColors.text(context);
    final subColor = AppColors.subtext(context);

    return Container(
      margin: EdgeInsets.symmetric(horizontal: horizontalMargin),
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isPinned) ...[
            Row(
              children: [
                const FaIcon(
                  FontAwesomeIcons.thumbtack,
                  color: AppColors.accentBlue,
                  size: 14,
                ),
                const SizedBox(width: 6),
                Text(
                  'community.pinned_post'.tr(),
                  style: const TextStyle(
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
                  color: const Color(0xFF5A75FF).withValues(alpha: isDark ? 0.25 : 0.1),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: rawName.isNotEmpty
                      ? Text(
                          rawName.characters.first.toUpperCase(),
                          style: TextStyle(
                            color: isDark ? AppColors.lightBlue : const Color(0xFF5A75FF),
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        )
                      : FaIcon(
                          FontAwesomeIcons.user,
                          color: subColor,
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
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          timeAgo,
                          style: TextStyle(
                            fontSize: 12,
                            color: subColor,
                          ),
                        ),
                        if (isInstructor)
                          _buildBadge('community.instructor'.tr()),
                        _buildBadge(_postTypeLabel(post.attributes.postType)),
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
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (post.attributes.content.isNotEmpty)
            Linkify(
              onOpen: (link) => _openLink(link.url),
              text: post.attributes.content,
              style: TextStyle(
                fontSize: 14,
                color: isDark ? const Color(0xFFE2E8F0) : AppColors.textDark,
                height: 1.5,
              ),
              linkStyle: TextStyle(
                fontSize: 14,
                color: isDark ? AppColors.lightBlue : AppColors.primaryBlue,
                height: 1.5,
                decoration: TextDecoration.underline,
              ),
            ),
          // Post images
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
              children: post.attributes.tags.map((tag) => _buildTagChip('#$tag')).toList(),
            ),
          // Post course social links
          Builder(
            builder: (context) {
              final postSocialLinks = _getSocialLinksForPost(post);
              if (postSocialLinks.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.input(context) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark ? AppColors.border(context) : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const FaIcon(
                            FontAwesomeIcons.shareNodes,
                            size: 11,
                            color: AppColors.primaryBlue,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'community.course_links_title'.tr(),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: textColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: postSocialLinks
                            .map((link) => _buildPostSocialChip(link))
                            .toList(),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              InkWell(
                onTap: () => _showReactionPicker(post),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: Row(
                    children: [
                      FaIcon(
                        hasReaction
                            ? _getReactionIcon(post.attributes.userReaction)
                            : FontAwesomeIcons.heart,
                        color: hasReaction
                            ? _getReactionColor(post.attributes.userReaction)
                            : subColor,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'community.reactions_count'
                            .tr(args: ['${post.attributes.reactionsCount}']),
                        style: TextStyle(
                          fontSize: 13,
                          color: hasReaction
                              ? _getReactionColor(post.attributes.userReaction)
                              : subColor,
                          fontWeight: hasReaction ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          PostCommentsSection(
            post: post,
            currentUserId: _currentUserId,
            onChanged: _loadPosts,
          ),
        ],
      ),
    );
  }

  Widget _buildBadge(String label) {
    final isDark = AppColors.isDark(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2A3154) : AppColors.accountingBg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: isDark ? AppColors.lightBlue : AppColors.accountingText,
        ),
      ),
    );
  }

  Widget _buildTagChip(String tag) {
    final isDark = AppColors.isDark(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? AppColors.input(context) : const Color(0xFFF0F2FF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        tag,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: AppColors.subtext(context),
        ),
      ),
    );
  }

  List<SocialLink> _getSocialLinksForPost(Post post) {
    // 1. If post itself has socialLinks parsed
    if (post.attributes.socialLinks.isNotEmpty) {
      final links = post.attributes.socialLinks.where((l) => l.attributes.status).toList();
      if (links.isNotEmpty) return links;
    }
    // 2. If post's course has socialLinks
    if (post.attributes.course?.attributes.socialLinks.isNotEmpty == true) {
      final links = post.attributes.course!.attributes.socialLinks.where((l) => l.attributes.status).toList();
      if (links.isNotEmpty) return links;
    }
    // 3. Match post courseId against loaded enrolled _courses
    final courseId = post.attributes.courseId ?? post.attributes.course?.id;
    if (courseId != null && courseId.isNotEmpty) {
      final matched = _courses.where((c) => c.id == courseId).toList();
      if (matched.isNotEmpty && matched.first.attributes.socialLinks.isNotEmpty) {
        return matched.first.attributes.socialLinks.where((l) => l.attributes.status).toList();
      }
    }
    // 4. Match post course title against loaded enrolled _courses
    final courseTitle = post.attributes.course?.attributes.title;
    if (courseTitle != null && courseTitle.isNotEmpty) {
      final matched = _courses.where((c) => c.attributes.title == courseTitle).toList();
      if (matched.isNotEmpty && matched.first.attributes.socialLinks.isNotEmpty) {
        return matched.first.attributes.socialLinks.where((l) => l.attributes.status).toList();
      }
    }
    return [];
  }

  Widget _buildPostSocialChip(SocialLink link) {
    List<Color> gradientColors = [
      AppColors.primaryBlue,
      const Color(0xFF5A75FF),
    ];
    final target = '${link.link} ${link.attributes.title} ${link.attributes.subtitle}'.toLowerCase();
    if (target.contains('youtu')) {
      gradientColors = [const Color(0xFFCC181E), const Color(0xFFFF4B4B)];
    } else if (target.contains('telegram') || target.contains('t.me')) {
      gradientColors = [const Color(0xFF0088CC), const Color(0xFF29B6F6)];
    } else if (target.contains('whatsapp') || target.contains('wa.me')) {
      gradientColors = [const Color(0xFF1EBE5D), const Color(0xFF4ADE80)];
    } else if (target.contains('facebook') || target.contains('fb.com')) {
      gradientColors = [const Color(0xFF1877F2), const Color(0xFF4292F7)];
    }

    final title = link.attributes.title.isNotEmpty
        ? link.attributes.title
        : link.attributes.subtitle;

    return GestureDetector(
      onTap: () => _openLink(link.link),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: gradientColors,
          ),
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: gradientColors[0].withValues(alpha: 0.25),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FaIcon(
              _getSocialIconData(link),
              color: Colors.white,
              size: 12,
            ),
            if (title.isNotEmpty) ...[
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFloatingActionButton() {
    return FloatingActionButton(
      onPressed: _navigateToCreatePost,
      backgroundColor: AppColors.primaryBlue,
      shape: const CircleBorder(),
      tooltip: 'community.create_post'.tr(),
      child: const Icon(
        Icons.add,
        color: Colors.white,
        size: 28,
      ),
    );
  }
}
