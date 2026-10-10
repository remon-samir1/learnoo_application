import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../domain/academic_tree.dart';
import 'faculty_selection_screen.dart';
import 'onboarding_step_header.dart';

/// Second onboarding step: select a center belonging to the chosen university.
/// Center IDs and names come from faculty.attributes.parent.data.
class CenterSelectionScreen extends StatefulWidget {
  final dynamic universityId;
  final String universityName;
  final List<dynamic> allFaculties;

  const CenterSelectionScreen({
    super.key,
    required this.universityId,
    required this.universityName,
    required this.allFaculties,
  });

  @override
  State<CenterSelectionScreen> createState() => _CenterSelectionScreenState();
}

class _CenterSelectionScreenState extends State<CenterSelectionScreen> {
  final _searchController = TextEditingController();

  List<AcademicOption> _universityCenters = const [];
  List<AcademicOption> _filteredCenters = const [];
  AcademicOption? _selectedCenter;

  @override
  void initState() {
    super.initState();
    _universityCenters = centerOptionsForUniversity(
      widget.allFaculties,
      widget.universityId,
    );
    _filteredCenters = _universityCenters;
    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      _filteredCenters = query.isEmpty
          ? _universityCenters
          : _universityCenters
                .where((c) => c.label.toLowerCase().contains(query))
                .toList();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF13151B)
          : AppColors.backgroundWhite,
      body: Column(
        children: [
          OnboardingStepHeader(step: 2, title: 'academic.select_center'.tr()),

          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'academic.selected_university'.tr(),
                  style: TextStyle(
                    color: isDark
                        ? const Color(0xFFCBD5E1)
                        : AppColors.textGray,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Chip(
                  label: Text(
                    widget.universityName,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark
                          ? const Color(0xFFF8FAFC)
                          : AppColors.textDark,
                    ),
                  ),
                  backgroundColor: isDark
                      ? const Color(0xFF1E212B)
                      : AppColors.inputFill,
                  side: BorderSide(
                    color: isDark
                        ? const Color(0xFF383E52)
                        : Colors.transparent,
                  ),
                  padding: EdgeInsets.zero,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Search
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: TextField(
              controller: _searchController,
              style: TextStyle(
                color: isDark ? const Color(0xFFF8FAFC) : AppColors.textDark,
              ),
              decoration: InputDecoration(
                hintText: 'academic.search_centers'.tr(),
                hintStyle: TextStyle(
                  color: isDark ? const Color(0xFF64748B) : AppColors.textGray,
                ),
                prefixIcon: Icon(
                  Icons.search,
                  color: isDark ? const Color(0xFF64748B) : AppColors.textGray,
                ),
                filled: true,
                fillColor: isDark ? const Color(0xFF1E212B) : Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: isDark
                        ? const Color(0xFF383E52)
                        : AppColors.inputBorder,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: isDark
                        ? const Color(0xFF383E52)
                        : AppColors.inputBorder,
                  ),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                  borderSide: BorderSide(
                    color: AppColors.primaryBlue,
                    width: 2,
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // List
          Expanded(
            child: _filteredCenters.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        _universityCenters.isEmpty
                            ? 'academic.empty_centers'.tr()
                            : 'no_options_available'.tr(),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: isDark ? const Color(0xFF94A3B8) : Colors.grey,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    itemCount: _filteredCenters.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final center = _filteredCenters[index];
                      final isSelected = _selectedCenter?.id == center.id;

                      return GestureDetector(
                        onTap: () => setState(() => _selectedCenter = center),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF1E212B)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isSelected
                                  ? AppColors.primaryBlue
                                  : (isDark
                                        ? const Color(0xFF383E52)
                                        : AppColors.inputBorder),
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? AppColors.primaryBlue
                                      : (isDark
                                            ? const Color(0xFF262A36)
                                            : AppColors.inputFill),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  Icons.location_on_outlined,
                                  color: isSelected
                                      ? Colors.white
                                      : AppColors.primaryBlue,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Text(
                                  center.label,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: isDark
                                        ? const Color(0xFFF8FAFC)
                                        : AppColors.textDark,
                                  ),
                                ),
                              ),
                              if (isSelected)
                                const Icon(
                                  Icons.check_circle,
                                  color: AppColors.primaryBlue,
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),

          // Bottom Button
          Padding(
            padding: const EdgeInsets.all(24),
            child: PrimaryButton(
              text: 'academic.next'.tr(),
              onPressed: _selectedCenter == null
                  ? null
                  : () {
                      final center = _selectedCenter!;
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => FacultySelectionScreen(
                            universityId: widget.universityId,
                            universityName: widget.universityName,
                            centerId: center.id,
                            centerName: center.label,
                            allFaculties: widget.allFaculties,
                          ),
                        ),
                      );
                    },
            ),
          ),
        ],
      ),
    );
  }
}
