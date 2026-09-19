import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../home/presentation/screens/main_screen.dart';
import '../../domain/academic_tree.dart';
import 'department_selection_screen.dart';
import 'onboarding_step_header.dart';

/// Third onboarding step.
///
/// Faculties are matched to the chosen centre through [facultyBelongsToCenter],
/// which compares ids as strings and accepts both `parent_id` and
/// `parent.data.id` — the old `parentId == widget.centerId` check missed every
/// payload where one side was a string.
///
/// When the faculty carries departments (`attributes.childrens`) the flow
/// continues to the department step; otherwise the profile is saved here.
class FacultySelectionScreen extends StatefulWidget {
  final dynamic universityId;
  final String universityName;
  final dynamic centerId;
  final String centerName;
  final List<dynamic> allFaculties;

  const FacultySelectionScreen({
    super.key,
    required this.universityId,
    required this.universityName,
    required this.centerId,
    required this.centerName,
    required this.allFaculties,
  });

  @override
  State<FacultySelectionScreen> createState() => _FacultySelectionScreenState();
}

class _FacultySelectionScreenState extends State<FacultySelectionScreen> {
  final _searchController = TextEditingController();
  final _authRepository = AuthRepository();

  List<dynamic> _centerFaculties = const [];
  List<dynamic> _filteredFaculties = const [];
  dynamic _selectedFaculty;
  bool _isUpdating = false;

  @override
  void initState() {
    super.initState();
    _centerFaculties =
        facultiesForCenter(widget.allFaculties, widget.centerId);
    _filteredFaculties = _centerFaculties;
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      _filteredFaculties = query.isEmpty
          ? _centerFaculties
          : _centerFaculties
              .where((f) => entityName(f).toLowerCase().contains(query))
              .toList();
    });
  }

  Future<void> _handleContinue() async {
    final faculty = _selectedFaculty;
    if (faculty == null) return;

    final departments = facultyDepartments(faculty);

    if (departments.isNotEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => DepartmentSelectionScreen(
            universityId: widget.universityId,
            universityName: widget.universityName,
            centerId: widget.centerId,
            centerName: widget.centerName,
            facultyId: entityId(faculty),
            facultyName: entityName(faculty),
            departments: departments,
          ),
        ),
      );
      return;
    }

    // No departments on this faculty — save the three ids we have.
    setState(() => _isUpdating = true);

    final result = await _authRepository.updateAcademicProfile(
      universityId: widget.universityId,
      centerId: widget.centerId,
      facultyId: entityId(faculty),
    );

    if (!mounted) return;
    setState(() => _isUpdating = false);

    if (result['success'] == true) {
      _showSuccessDialog();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result['message']?.toString() ?? 'Failed to update profile',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showSuccessDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: isDark ? const Color(0xFF1E212B) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: const BoxDecoration(
                  color: Color(0xFF27AE60),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check, color: Colors.white, size: 40),
              ),
              const SizedBox(height: 24),
              Text(
                'academic_profile_set'.tr(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'courses_filtered'.tr(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isDark ? const Color(0xFF94A3B8) : AppColors.textGray,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 32),
              PrimaryButton(
                text: 'go_to_home_caps'.tr(),
                onPressed: () {
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (context) => const MainScreen()),
                    (route) => false,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selectedId = entityId(_selectedFaculty);
    final hasDepartments =
        _selectedFaculty != null && facultyDepartments(_selectedFaculty).isNotEmpty;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF13151B) : AppColors.backgroundWhite,
      body: Column(
        children: [
          OnboardingStepHeader(
            step: 3,
            totalSteps: 4,
            title: 'select_faculty'.tr(),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'selected_centers'.tr(),
                  style: TextStyle(
                    color: isDark ? const Color(0xFFCBD5E1) : AppColors.textGray,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Chip(
                  label: Text(
                    widget.centerName,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? const Color(0xFFF8FAFC) : AppColors.textDark,
                    ),
                  ),
                  backgroundColor: isDark ? const Color(0xFF1E212B) : AppColors.inputFill,
                  side: BorderSide(
                    color: isDark ? const Color(0xFF383E52) : Colors.transparent,
                  ),
                  padding: EdgeInsets.zero,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: TextField(
              controller: _searchController,
              style: TextStyle(color: isDark ? const Color(0xFFF8FAFC) : AppColors.textDark),
              decoration: InputDecoration(
                hintText: 'search_faculties'.tr(),
                hintStyle: TextStyle(color: isDark ? const Color(0xFF64748B) : AppColors.textGray),
                prefixIcon: Icon(Icons.search, color: isDark ? const Color(0xFF64748B) : AppColors.textGray),
                filled: true,
                fillColor: isDark ? const Color(0xFF1E212B) : Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: isDark ? const Color(0xFF383E52) : AppColors.inputBorder,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: isDark ? const Color(0xFF383E52) : AppColors.inputBorder,
                  ),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                  borderSide: BorderSide(color: AppColors.primaryBlue, width: 2),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _filteredFaculties.isEmpty
                ? Center(
                    child: Text(
                      'no_options_available'.tr(),
                      style: TextStyle(
                        color: isDark ? const Color(0xFF94A3B8) : Colors.grey,
                        fontSize: 16,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    itemCount: _filteredFaculties.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final faculty = _filteredFaculties[index];
                      final id = entityId(faculty);
                      final name = entityName(faculty);
                      final isSelected = idsMatch(selectedId, id);
                      final departmentCount = facultyDepartments(faculty).length;

                      return GestureDetector(
                        onTap: () => setState(() => _selectedFaculty = faculty),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF1E212B) : Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isSelected
                                  ? AppColors.primaryBlue
                                  : (isDark ? const Color(0xFF383E52) : AppColors.inputBorder),
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.school_outlined,
                                color: isSelected
                                    ? AppColors.primaryBlue
                                    : (isDark ? const Color(0xFF94A3B8) : AppColors.textGray),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name.isEmpty ? 'profile.faculty'.tr() : name,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                        color: isDark ? const Color(0xFFF8FAFC) : AppColors.textDark,
                                      ),
                                    ),
                                    if (departmentCount > 0)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Text(
                                          '$departmentCount ${'profile.department'.tr()}',
                                          style: TextStyle(
                                            color: isDark ? const Color(0xFF94A3B8) : AppColors.textGray,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              if (isSelected)
                                const Icon(Icons.check_circle,
                                    color: AppColors.primaryBlue),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: PrimaryButton(
              text: hasDepartments
                  ? 'auth.continue_btn'.tr()
                  : 'academic.finish'.tr(),
              isLoading: _isUpdating,
              onPressed: (_selectedFaculty == null || _isUpdating)
                  ? null
                  : _handleContinue,
            ),
          ),
        ],
      ),
    );
  }
}
