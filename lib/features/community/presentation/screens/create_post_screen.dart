import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/models/post_model.dart';
import '../../data/repositories/community_repository.dart';

class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({super.key});

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  String _selectedPostType = 'post';
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _contentController = TextEditingController();
  final TextEditingController _tagController = TextEditingController();
  final List<String> _selectedTags = [];

  final CommunityRepository _repository = CommunityRepository();
  List<PostCourse> _availableCourses = [];
  PostCourse? _selectedCourse;
  bool _isLoading = true;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _loadCourses();
  }

  Future<void> _loadCourses() async {
    final result = await _repository.getCourses();
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (result['success']) {
        final List<dynamic> courseData = result['data'];
        _availableCourses = courseData.map((c) => PostCourse.fromJson(c)).toList();
      }
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _tagController.dispose();
    super.dispose();
  }

  void _selectCourse(PostCourse? course) {
    setState(() {
      _selectedCourse = course;
    });
  }

  void _addTag(String tag) {
    if (tag.trim().isNotEmpty && !_selectedTags.contains(tag.trim())) {
      setState(() {
        _selectedTags.add(tag.trim());
      });
    }
  }

  void _removeTag(String tag) {
    setState(() {
      _selectedTags.remove(tag);
    });
  }

  Future<void> _createPost() async {
    if (_contentController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('community.please_enter_content'.tr())),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    final request = CreatePostRequest(
      courseId: _selectedCourse != null ? int.tryParse(_selectedCourse!.id) : null,
      postType: _selectedPostType,
      title: _titleController.text.trim(),
      content: _contentController.text.trim(),
      tags: _selectedTags,
    );

    final result = await _repository.createPost(request);
    if (!mounted) return;

    setState(() {
      _isSubmitting = false;
    });

    if (result['success']) {
      Navigator.of(context).pop(true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('community.post_failed'.tr()),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF13151B) : Colors.white,
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),
                    _buildHeader(isDark),
                    const SizedBox(height: 24),
                    _buildUserInfo(isDark),
                    Divider(
                      height: 32,
                      color: isDark ? const Color(0xFF2E3344) : const Color(0xFFE5E7EB),
                    ),
                    const SizedBox(height: 16),
                    _buildPostTypeSelector(isDark),
                    const SizedBox(height: 24),
                    _buildTitleField(isDark),
                    const SizedBox(height: 20),
                    _buildContentField(isDark),
                    const SizedBox(height: 24),
                    _buildCourseSelector(isDark),
                    const SizedBox(height: 24),
                    _buildTagsSection(isDark),
                    const SizedBox(height: 32),
                    _buildActionButtons(isDark),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildHeader(bool isDark) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'community.publish_post'.tr(),
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: isDark ? const Color(0xFFF8FAFC) : AppColors.textDark,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'community.share_with_classmates'.tr(),
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? const Color(0xFF94A3B8) : AppColors.textGray,
                ),
              ),
            ],
          ),
        ),
        GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF262A36) : Colors.grey[100],
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.close,
              color: isDark ? const Color(0xFFCBD5E1) : AppColors.textGray,
              size: 20,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildUserInfo(bool isDark) {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: const BoxDecoration(
            color: AppColors.accentBlue,
            shape: BoxShape.circle,
          ),
          child: const Center(
            child: FaIcon(
              FontAwesomeIcons.user,
              color: Colors.white,
              size: 20,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'profile.you'.tr(),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isDark ? const Color(0xFFF8FAFC) : AppColors.textDark,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'profile.student'.tr(),
              style: TextStyle(
                fontSize: 13,
                color: isDark ? const Color(0xFF94A3B8) : AppColors.textGray,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPostTypeSelector(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'community.post_type'.tr(),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isDark ? const Color(0xFFCBD5E1) : AppColors.labelGray,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _buildPostTypeChip('community.type_post'.tr(), 'post', isDark),
            const SizedBox(width: 8),
            _buildPostTypeChip('community.type_question'.tr(), 'question', isDark),
            const SizedBox(width: 8),
            _buildPostTypeChip('community.type_summary'.tr(), 'summary', isDark),
          ],
        ),
      ],
    );
  }

  Widget _buildPostTypeChip(String label, String value, bool isDark) {
    final isSelected = _selectedPostType == value;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedPostType = value;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.primaryBlue
                : (isDark ? const Color(0xFF262A36) : const Color(0xFFF0F2FF)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: isSelected
                    ? Colors.white
                    : (isDark ? const Color(0xFFCBD5E1) : AppColors.textGray),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTitleField(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'community.title_optional'.tr(),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isDark ? const Color(0xFFCBD5E1) : AppColors.labelGray,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _titleController,
          style: TextStyle(color: isDark ? const Color(0xFFF8FAFC) : AppColors.textDark),
          cursorColor: isDark ? AppColors.lightBlue : AppColors.primaryBlue,
          decoration: InputDecoration(
            hintText: 'community.give_post_title'.tr(),
            hintStyle: TextStyle(
              color: isDark ? const Color(0xFF64748B) : const Color(0xFFC5C8D0),
              fontSize: 15,
            ),
            filled: true,
            fillColor: isDark ? const Color(0xFF262A36) : const Color(0xFFF8F9FB),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: isDark ? const Color(0xFF383E52) : Colors.transparent,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: isDark ? const Color(0xFF383E52) : Colors.transparent,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.primaryBlue, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContentField(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'community.content'.tr(),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isDark ? const Color(0xFFCBD5E1) : AppColors.labelGray,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _contentController,
          style: TextStyle(color: isDark ? const Color(0xFFF8FAFC) : AppColors.textDark),
          cursorColor: isDark ? AppColors.lightBlue : AppColors.primaryBlue,
          maxLines: 5,
          decoration: InputDecoration(
            hintText: 'community.what_to_share'.tr(),
            hintStyle: TextStyle(
              color: isDark ? const Color(0xFF64748B) : const Color(0xFFC5C8D0),
              fontSize: 15,
            ),
            filled: true,
            fillColor: isDark ? const Color(0xFF262A36) : const Color(0xFFF8F9FB),
            contentPadding: const EdgeInsets.all(16),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: isDark ? const Color(0xFF383E52) : Colors.transparent,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: isDark ? const Color(0xFF383E52) : Colors.transparent,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.primaryBlue, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCourseSelector(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'community.course_tag'.tr(),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isDark ? const Color(0xFFCBD5E1) : AppColors.labelGray,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF262A36) : const Color(0xFFF8F9FB),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? const Color(0xFF383E52) : Colors.transparent,
            ),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<PostCourse>(
              isExpanded: true,
              dropdownColor: isDark ? const Color(0xFF1E212B) : Colors.white,
              iconEnabledColor: isDark ? const Color(0xFFCBD5E1) : Colors.grey[700],
              hint: Text(
                'community.select_course'.tr(),
                style: TextStyle(
                  color: isDark ? const Color(0xFF64748B) : const Color(0xFFC5C8D0),
                  fontSize: 15,
                ),
              ),
              value: _selectedCourse,
              items: [
                DropdownMenuItem<PostCourse>(
                  value: null,
                  child: Text(
                    'community.no_course_tag'.tr(),
                    style: TextStyle(
                      color: isDark ? const Color(0xFFF8FAFC) : AppColors.textDark,
                    ),
                  ),
                ),
                ..._availableCourses.map((course) => DropdownMenuItem<PostCourse>(
                  value: course,
                  child: Text(
                    course.attributes.title,
                    style: TextStyle(
                      fontSize: 15,
                      color: isDark ? const Color(0xFFF8FAFC) : AppColors.textDark,
                    ),
                  ),
                )),
              ],
              onChanged: (course) => _selectCourse(course),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTagsSection(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'community.tags'.tr(),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isDark ? const Color(0xFFCBD5E1) : AppColors.labelGray,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _tagController,
                style: TextStyle(color: isDark ? const Color(0xFFF8FAFC) : AppColors.textDark),
          cursorColor: isDark ? AppColors.lightBlue : AppColors.primaryBlue,
                decoration: InputDecoration(
                  hintText: 'community.add_tag'.tr(),
                  hintStyle: TextStyle(
                    color: isDark ? const Color(0xFF64748B) : const Color(0xFFC5C8D0),
                    fontSize: 15,
                  ),
                  filled: true,
                  fillColor: isDark ? const Color(0xFF262A36) : const Color(0xFFF8F9FB),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: isDark ? const Color(0xFF383E52) : Colors.transparent,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: isDark ? const Color(0xFF383E52) : Colors.transparent,
                    ),
                  ),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.add, color: AppColors.primaryBlue),
                    onPressed: () {
                      _addTag(_tagController.text);
                      _tagController.clear();
                    },
                  ),
                ),
                onSubmitted: (value) {
                  _addTag(value);
                  _tagController.clear();
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_selectedTags.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _selectedTags.map((tag) => _buildSelectedTagChip(tag)).toList(),
          ),
      ],
    );
  }

  Widget _buildSelectedTagChip(String tag) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primaryBlue,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '# $tag',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () => _removeTag(tag),
            child: const Icon(
              Icons.close,
              size: 16,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(bool isDark) {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: _isSubmitting ? null : () => Navigator.of(context).pop(),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF262A36) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? const Color(0xFF383E52) : const Color(0xFFE5E7EB),
                ),
              ),
              child: Center(
                child: _isSubmitting
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            isDark ? Colors.white : AppColors.textDark,
                          ),
                        ),
                      )
                    : Text(
                        'profile.cancel'.tr(),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: isDark ? const Color(0xFFF8FAFC) : AppColors.textDark,
                        ),
                      ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: GestureDetector(
            onTap: _isSubmitting ? null : () => _createPost(),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: AppColors.primaryBlue,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : Text(
                        'community.publish_post'.tr(),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
