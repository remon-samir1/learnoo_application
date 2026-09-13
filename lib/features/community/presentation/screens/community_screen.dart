import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/models/post_model.dart';
import '../../data/models/social_link_model.dart';
import '../../data/repositories/community_repository.dart';
import '../widgets/post_comments_section.dart';
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
  String _selectedFilter = 'All';
  final TextEditingController _commentController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final CommunityRepository _repository = CommunityRepository();
  final SearchRepository _searchRepository = SearchRepository();

  List<Post> _posts = [];
  List<PostCourse> _courses = [];
  List<SocialLink> _socialLinks = [];
  bool _isLoading = true;
  bool _isLoadingSocialLinks = false;
  String? _errorMessage;

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
      _errorMessage = null;
    });

    String? courseId;
    if (_selectedFilter != 'All') {
      final selectedCourse = _courses.where((c) => c.attributes.title == _selectedFilter).firstOrNull;
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
          _errorMessage = result['message'];
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

  void _updateSocialLinks() {
    if (!mounted) return;

    if (_selectedFilter == 'All') {
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
      final selectedCourse = _courses.where((c) => c.attributes.title == _selectedFilter).firstOrNull;
      setState(() {
        _socialLinks = selectedCourse?.attributes.socialLinks ?? [];
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
        final newCount = currentReaction != null
            ? (post.attributes.reactionsCount > 0 ? post.attributes.reactionsCount - 1 : 0)
            : post.attributes.reactionsCount;
        updatedPost = post.copyWith(
          attributes: post.attributes.copyWith(
            reactionsCount: newCount,
            userReaction: null,
          ),
        );
      } else {
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
      _loadPosts();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
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
                                : _errorMessage != null
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
                  const Text(
                    'Community',
                    style: TextStyle(
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
                      decoration: InputDecoration(
                        hintText: 'Search posts...',
                        hintStyle: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 14,
                        ),
                        prefixIcon: const Padding(
                          padding: EdgeInsets.only(left: 16, right: 12 , top:14),
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
                                      padding: EdgeInsets.only(right: 16, left: 12, top: 12),
                                      child: FaIcon(
                                        FontAwesomeIcons.xmark,
                                        color: Colors.white,
                                        size: 18,
                                      ),
                                    ),
                                  )
                                : null,
                        border: InputBorder.none,
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
    final filters = ['All', ..._courses.map((c) => c.attributes.title)];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: filters.map((filter) {
            final isSelected = _selectedFilter == filter;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedFilter = filter;
                  });
                  _updateSocialLinks();
                  _loadPosts();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.primaryBlue : const Color(0xFFF0F2FF),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    filter,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: isSelected ? Colors.white : AppColors.textGray,
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

  Widget _buildCommunityInfoCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(20),
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
          const Center(
            child: Text(
              'Community',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textDark,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              'Stay connected with course updates, links, and class discussions.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textGray,
              ),
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
              Text(
                _selectedFilter == 'All'
                    ? 'روابط ومجموعات الكورسات'
                    : 'روابط ومجموعات $_selectedFilter',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
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
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Could not open link: ${link.link}')),
              );
            }
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
              child: link.attributes.icon.isNotEmpty
                  ? ClipOval(
                      child: Image.network(
                        link.attributes.icon,
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
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
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
              const SizedBox(width: 8),
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

  Widget _buildErrorWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            _errorMessage ?? 'An error occurred',
            style: const TextStyle(color: Colors.grey),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loadPosts,
            child: const Text('Retry'),
          ),
        ],
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
              'No posts yet',
              style: TextStyle(
                color: Colors.grey[600],
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
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _posts.length,
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
          padding: const EdgeInsets.symmetric(vertical: 60),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const FaIcon(
                FontAwesomeIcons.magnifyingGlass,
                color: Color(0xFFD1D1D1),
                size: 48,
              ),
              const SizedBox(height: 16),
              Text(
                'No posts found for "${_searchController.text}"',
                style: const TextStyle(
                  color: Color(0xFF9CA3AF),
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search results header
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'Search Results (${_searchResults.length})',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textDark,
              ),
            ),
          ),
          // Search results list
          ..._searchResults.map((item) {
            final attributes = item['attributes'] ?? {};
            final post = Post(
              id: item['id']?.toString() ?? '',
              type: item['type']?.toString() ?? 'post',
              attributes: PostAttributes(
                user: null,
                course: null,
                status: attributes['status']?.toString() ?? 'draft',
                postType: attributes['post_type']?.toString() ?? 'discussion',
                title: attributes['title']?.toString() ?? '',
                content: attributes['content']?.toString() ?? '',
                tags: (attributes['tags'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
                reactionsCount: 0,
                userReaction: null,
                createdAt: DateTime.tryParse(attributes['created_at']?.toString() ?? '') ?? DateTime.now(),
                updatedAt: DateTime.tryParse(attributes['updated_at']?.toString() ?? '') ?? DateTime.now(),
              ),
            );
            return _buildPostCard(
              post: post,
              isPinned: false,
            );
          }),
        ],
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
        return Colors.yellow;
      case 'sad':
        return Colors.purple;
      case 'angry':
        return Colors.redAccent;
      default:
        return AppColors.textGray;
    }
  }

  Widget _buildPostCard({
    required Post post,
    bool isPinned = false,
  }) {
    final user = post.attributes.user;
    final course = post.attributes.course ??
        (post.attributes.courseId != null
            ? _courses.where((c) => c.id == post.attributes.courseId).firstOrNull
            : null);
    final userName = user?.attributes.fullName ?? 'Unknown User';
    final isInstructor = user?.attributes.role.toLowerCase() == 'admin' ||
        user?.attributes.role.toLowerCase() == 'instructor';
    final timeAgo = _formatTimeAgo(post.attributes.createdAt);
    final hasReaction = post.attributes.userReaction != null;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
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
              Icon(
                Icons.more_horiz,
                color: AppColors.textGray,
                size: 20,
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
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
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
                          const Text(
                            'روابط ومجموعات الكورس',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textDark,
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
          PostCommentsSection(
            post: post,
            currentUserId: _currentUserId,
            onChanged: _loadPosts,
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
          } catch (_) {}
        }
      },
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
      child: const Icon(
        Icons.add,
        color: Colors.white,
        size: 28,
      ),
    );
  }
}
