import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../home/presentation/screens/main_screen.dart';
import '../../domain/academic_tree.dart';
import 'onboarding_step_header.dart';

/// Fourth onboarding step — the one the app was missing.
///
/// The web collects a department alongside university/centre/faculty
/// (`CompleteProfileForm.tsx`) and sends it as `department_id`. Departments are
/// not fetched separately: they ride along on the faculty as
/// `attributes.childrens`.
///
/// The step is skippable because `department_id` is optional on the backend and
/// some faculties genuinely have no children — blocking here would trap those
/// students in onboarding.
class DepartmentSelectionScreen extends StatefulWidget {
  const DepartmentSelectionScreen({
    super.key,
    required this.universityId,
    required this.universityName,
    required this.centerId,
    required this.centerName,
    required this.facultyId,
    required this.facultyName,
    required this.departments,
  });

  final dynamic universityId;
  final String universityName;
  final dynamic centerId;
  final String centerName;
  final dynamic facultyId;
  final String facultyName;

  /// `faculty.attributes.childrens`.
  final List<dynamic> departments;

  @override
  State<DepartmentSelectionScreen> createState() =>
      _DepartmentSelectionScreenState();
}

class _DepartmentSelectionScreenState extends State<DepartmentSelectionScreen> {
  final _searchController = TextEditingController();
  final _authRepository = AuthRepository();

  late List<dynamic> _filtered;
  dynamic _selectedId;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _filtered = widget.departments;
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
      _filtered = query.isEmpty
          ? widget.departments
          : widget.departments
              .where((d) => entityName(d).toLowerCase().contains(query))
              .toList();
    });
  }

  Future<void> _save({required bool skipDepartment}) async {
    setState(() => _isSaving = true);

    final result = await _authRepository.updateAcademicProfile(
      universityId: widget.universityId,
      centerId: widget.centerId,
      facultyId: widget.facultyId,
      departmentId: skipDepartment ? null : _selectedId,
    );

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (result['success'] == true) {
      _showSuccessDialog();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message']?.toString() ??
              'Failed to update profile'),
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
    return Scaffold(
      backgroundColor: AppColors.backgroundWhite,
      body: Column(
        children: [
          OnboardingStepHeader(
            step: 4,
            totalSteps: 4,
            title: 'academic.select_department_title'.tr(),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'academic.select_department_desc'.tr(),
                  style: const TextStyle(
                    color: AppColors.textGray,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    _contextChip(widget.centerName),
                    _contextChip(widget.facultyName),
                  ],
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
                hintText: 'academic.search_department'.tr(),
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
            child: _filtered.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Text(
                        'academic.no_departments'.tr(),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.textGray),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    itemCount: _filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final department = _filtered[index];
                      final id = entityId(department);
                      final name = entityName(department);
                      final isSelected = idsMatch(_selectedId, id);

                      return GestureDetector(
                        onTap: () => setState(() => _selectedId = id),
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
                                Icons.class_outlined,
                                color: isSelected
                                    ? AppColors.primaryBlue
                                    : AppColors.textGray,
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Text(
                                  name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
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
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
            child: PrimaryButton(
              text: 'academic.finish'.tr(),
              isLoading: _isSaving,
              onPressed: (_selectedId == null || _isSaving)
                  ? null
                  : () => _save(skipDepartment: false),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: TextButton(
              onPressed: _isSaving ? null : () => _save(skipDepartment: true),
              child: Text(
                'academic.skip_department'.tr(),
                style: const TextStyle(
                  color: AppColors.textGray,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _contextChip(String label) {
    if (label.trim().isEmpty) return const SizedBox.shrink();
    return Chip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      backgroundColor: AppColors.inputFill,
      side: BorderSide.none,
      padding: EdgeInsets.zero,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}
