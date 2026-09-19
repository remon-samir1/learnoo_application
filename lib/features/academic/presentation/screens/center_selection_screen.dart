import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../auth/data/auth_repository.dart';
import 'faculty_selection_screen.dart';

class CenterSelectionScreen extends StatefulWidget {
  final dynamic universityId;
  final String universityName;
  final List<dynamic> allCenters;
  final List<dynamic> allFaculties;

  const CenterSelectionScreen({
    super.key,
    required this.universityId,
    required this.universityName,
    required this.allCenters,
    required this.allFaculties,
  });

  @override
  State<CenterSelectionScreen> createState() => _CenterSelectionScreenState();
}

class _CenterSelectionScreenState extends State<CenterSelectionScreen> {
  final _searchController = TextEditingController();
  final _authRepository = AuthRepository();

  List<dynamic> _filteredCenters = [];
  dynamic _selectedCenterId;
  String? _selectedCenterName;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _applyFilter();
    _searchController.addListener(_onSearchChanged);
  }

  void _applyFilter() {
    final uniId = widget.universityId.toString();
    final availableCenters = widget.allCenters.where((center) {
      final relationships = center['relationships'];
      if (relationships != null && relationships['university'] != null) {
        final uId = relationships['university']['data']?['id']?.toString();
        return uId == uniId;
      }
      final uId = center['attributes']?['university_id']?.toString();
      return uId == uniId;
    }).toList();

    setState(() {
      _filteredCenters = availableCenters;
      if (_filteredCenters.isEmpty && widget.allCenters.isNotEmpty) {
        _filteredCenters = widget.allCenters;
      }
    });
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredCenters = widget.allCenters.where((c) {
        final name = (c['attributes']?['name'] ?? c['name'] ?? '').toString().toLowerCase();
        return name.contains(query);
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
      backgroundColor: isDark ? const Color(0xFF13151B) : AppColors.backgroundWhite,
      body: Column(
        children: [
          // Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.only(top: 60, bottom: 24, left: 24, right: 24),
            decoration: const BoxDecoration(
              gradient: AppColors.mainGradient,
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(40),
                bottomRight: Radius.circular(40),
              ),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(2))),
                    const SizedBox(width: 8),
                    Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(2))),
                    const SizedBox(width: 8),
                    Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(2))),
                    const SizedBox(width: 8),
                    Container(width: 20, height: 4, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(2))),
                  ],
                ),
                const SizedBox(height: 12),
                Text('step_x_of_y'.tr(args: ['2', '3']), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 24),
                Text(
                  'select_center'.tr(),
                  style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'selected_university'.tr(),
                  style: TextStyle(
                    color: isDark ? const Color(0xFFCBD5E1) : AppColors.textGray,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Chip(
                  label: Text(
                    widget.universityName,
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

          // Search
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: TextField(
              controller: _searchController,
              style: TextStyle(color: isDark ? const Color(0xFFF8FAFC) : AppColors.textDark),
              decoration: InputDecoration(
                hintText: 'search_centers'.tr(),
                hintStyle: TextStyle(color: isDark ? const Color(0xFF64748B) : AppColors.textGray),
                prefixIcon: Icon(Icons.search, color: isDark ? const Color(0xFF64748B) : AppColors.textGray),
                filled: true,
                fillColor: isDark ? const Color(0xFF1E212B) : Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: isDark ? const Color(0xFF383E52) : AppColors.inputBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: isDark ? const Color(0xFF383E52) : AppColors.inputBorder),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                  borderSide: BorderSide(color: AppColors.primaryBlue, width: 2),
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
                        child: Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
                      )
                    : _filteredCenters.isEmpty
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
                            itemCount: _filteredCenters.length,
                            separatorBuilder: (context, index) => const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final center = _filteredCenters[index];
                              final id = center['id'];
                              final attributes = center['attributes'] ?? center;
                              final name = attributes['name'] ?? '';
                              final isSelected = _selectedCenterId == id;

                              return GestureDetector(
                                onTap: () => setState(() {
                                  _selectedCenterId = id;
                                  _selectedCenterName = name;
                                }),
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
                                      Container(
                                        width: 48,
                                        height: 48,
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? AppColors.primaryBlue
                                              : (isDark ? const Color(0xFF262A36) : AppColors.inputFill),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Icon(
                                          Icons.location_on_outlined,
                                          color: isSelected ? Colors.white : AppColors.primaryBlue,
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Text(
                                          name,
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                            color: isDark ? const Color(0xFFF8FAFC) : AppColors.textDark,
                                          ),
                                        ),
                                      ),
                                      if (isSelected)
                                        const Icon(Icons.check_circle, color: AppColors.primaryBlue),
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
              text: 'next'.tr(),
              onPressed: _selectedCenterId == null
                  ? null
                  : () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => FacultySelectionScreen(
                            universityId: widget.universityId,
                            universityName: widget.universityName,
                            centerId: _selectedCenterId,
                            centerName: _selectedCenterName!,
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
