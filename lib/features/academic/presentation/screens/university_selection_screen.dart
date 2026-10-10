import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../auth/data/auth_repository.dart';
import '../../domain/academic_tree.dart';
import 'center_selection_screen.dart';
import 'onboarding_step_header.dart';

/// First onboarding step, mirroring the website's "complete profile" form
/// (`CompleteProfileForm` + `UniversityFacultyFields`): it loads
/// `/v1/university` and `/v1/faculty` only. The centres offered next are
/// derived from the faculty list and narrowed to the chosen university on the
/// client, exactly like `buildUniversityCenterOptions`.
class UniversitySelectionScreen extends StatefulWidget {
  const UniversitySelectionScreen({super.key});

  @override
  State<UniversitySelectionScreen> createState() =>
      _UniversitySelectionScreenState();
}

class _UniversitySelectionScreenState extends State<UniversitySelectionScreen> {
  final _searchController = TextEditingController();
  final _authRepository = AuthRepository();

  List<dynamic> _universities = [];
  List<dynamic> _filteredUniversities = [];
  List<dynamic> _faculties = [];
  dynamic _selectedUniversityId;
  String? _selectedUniversityName;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchData();
    _searchController.addListener(_onSearchChanged);
  }

  Future<void> _fetchData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final results = await Future.wait([
      _authRepository.getUniversities(),
      _authRepository.getFaculties(),
    ]);

    if (!mounted) return;

    final uniRes = results[0];
    final facRes = results[1];

    setState(() {
      _isLoading = false;
      if (uniRes['success'] == true) {
        _universities = (uniRes['data'] as List?) ?? const [];
        _filteredUniversities = _universities;
      } else {
        _errorMessage =
            uniRes['message']?.toString() ?? 'auth.failed_fetch'.tr();
      }

      // The next steps are built from the faculty list, so without it the
      // student cannot continue.
      if (facRes['success'] == true) {
        _faculties = (facRes['data'] as List?) ?? const [];
      } else {
        _errorMessage ??=
            facRes['message']?.toString() ?? 'auth.failed_fetch'.tr();
      }
    });
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      _filteredUniversities = _universities.where((u) {
        return entityName(u).toLowerCase().contains(query);
      }).toList();
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
          OnboardingStepHeader(
            step: 1,
            title: 'academic.select_university'.tr(),
          ),

          const SizedBox(height: 24),

          // Search
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: TextField(
              controller: _searchController,
              style: TextStyle(
                color: isDark ? const Color(0xFFF8FAFC) : AppColors.textDark,
              ),
              decoration: InputDecoration(
                hintText: 'academic.search_universities'.tr(),
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
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.red),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _fetchData,
                          child: Text('profile.retry'.tr()),
                        ),
                      ],
                    ),
                  )
                : _filteredUniversities.isEmpty
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
                    itemCount: _filteredUniversities.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final uni = _filteredUniversities[index];
                      final id = entityId(uni);
                      final name = entityName(uni);
                      final isSelected = idsMatch(_selectedUniversityId, id);

                      return GestureDetector(
                        onTap: () => setState(() {
                          _selectedUniversityId = id;
                          _selectedUniversityName = name;
                        }),
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
                                  color: isDark
                                      ? const Color(0xFF262A36)
                                      : AppColors.inputFill,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.school,
                                  color: AppColors.primaryBlue,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Text(
                                  name,
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
              onPressed:
                  _isLoading ||
                      _errorMessage != null ||
                      _selectedUniversityId == null
                  ? null
                  : () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => CenterSelectionScreen(
                            universityId: _selectedUniversityId,
                            universityName: _selectedUniversityName ?? '',
                            allFaculties: _faculties,
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
