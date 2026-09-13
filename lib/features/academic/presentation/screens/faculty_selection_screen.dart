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
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
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
              const Text(
                'Your academic profile has been set successfully.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text(
                'Courses will be filtered based on your specialization.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textGray, fontSize: 14),
              ),
              const SizedBox(height: 32),
              PrimaryButton(
                text: 'GO TO HOME',
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
    final selectedId = entityId(_selectedFaculty);
    final hasDepartments =
        _selectedFaculty != null && facultyDepartments(_selectedFaculty).isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.backgroundWhite,
      body: Column(
        children: [
          const OnboardingStepHeader(
            step: 3,
            totalSteps: 4,
            title: 'Select Your Faculty',
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Selected Center:',
                  style: TextStyle(color: AppColors.textGray, fontSize: 14),
                ),
                const SizedBox(height: 4),
                Chip(
                  label: Text(
                    widget.centerName,
                    style: const TextStyle(fontSize: 12),
                  ),
                  backgroundColor: AppColors.inputFill,
                  side: BorderSide.none,
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
              decoration: InputDecoration(
                hintText: 'Search faculties...',
                prefixIcon: const Icon(Icons.search, color: AppColors.textGray),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.inputBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.inputBorder),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _filteredFaculties.isEmpty
                ? const Center(child: Text('No options available'))
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
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isSelected
                                  ? AppColors.primaryBlue
                                  : AppColors.inputBorder,
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.school_outlined,
                                color: isSelected
                                    ? AppColors.primaryBlue
                                    : AppColors.textGray,
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name.isEmpty ? 'Unknown' : name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                    if (departmentCount > 0)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Text(
                                          '$departmentCount departments',
                                          style: const TextStyle(
                                            color: AppColors.textGray,
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
