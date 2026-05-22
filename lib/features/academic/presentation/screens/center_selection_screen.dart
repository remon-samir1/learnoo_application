import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../home/presentation/screens/main_screen.dart';
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
    final filtered = widget.allCenters.where((center) {
      final attributes = center['attributes'] ?? center;
      final parentId = attributes['parent_id'];
      return parentId?.toString() == widget.universityId?.toString();
    }).toList();

    setState(() {
      _filteredCenters = filtered;
    });
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase();
    final allFiltered = widget.allCenters.where((center) {
      final attributes = center['attributes'] ?? center;
      final parentId = attributes['parent_id'];
      return parentId?.toString() == widget.universityId?.toString();
    }).toList();

    setState(() {
      _filteredCenters = allFiltered.where((center) {
        final attributes = center['attributes'] ?? center;
        final name = attributes['name']?.toLowerCase() ?? '';
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
    return Scaffold(
      backgroundColor: AppColors.backgroundWhite,
      body: Column(
        children: [
          // Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.only(top: 60, bottom: 40, left: 24, right: 24),
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
                const Text('Step 2 of 3', style: TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 24),
                const Text(
                  'Select Your Center',
                  style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
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
                const Text('Selected University:', style: TextStyle(color: AppColors.textGray, fontSize: 14)),
                const SizedBox(height: 4),
                Chip(
                  label: Text(widget.universityName, style: const TextStyle(fontSize: 12)),
                  backgroundColor: AppColors.inputFill,
                  side: BorderSide.none,
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
              decoration: InputDecoration(
                hintText: 'Search Center...',
                prefixIcon: const Icon(Icons.search, color: AppColors.textGray),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.inputBorder)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.inputBorder)),
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
                        ? const Center(child: Text('No options available'))
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            itemCount: _filteredCenters.length,
                            separatorBuilder: (context, index) => const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final center = _filteredCenters[index];
                              final id = center['id'];
                              final attributes = center['attributes'] ?? center;
                              final name = attributes['name'] ?? 'Unknown';
                              final isSelected = _selectedCenterId == id;

                              return GestureDetector(
                                onTap: () => setState(() {
                                  _selectedCenterId = id;
                                  _selectedCenterName = name;
                                }),
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: isSelected ? AppColors.primaryBlue : AppColors.inputBorder, width: isSelected ? 2 : 1),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(color: isSelected ? AppColors.primaryBlue : AppColors.inputFill, borderRadius: BorderRadius.circular(12)),
                                    child: Icon(Icons.location_on_outlined, color: isSelected ? Colors.white : AppColors.primaryBlue),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
              text: 'NEXT',
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
