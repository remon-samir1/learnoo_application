import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../home/presentation/screens/main_screen.dart';

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

  List<dynamic> _filteredFaculties = [];
  dynamic _selectedFacultyId;
  bool _isLoading = false;
  bool _isUpdating = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _applyFilter();
    _searchController.addListener(_onSearchChanged);
  }

  void _applyFilter() {
    final filtered = widget.allFaculties.where((faculty) {
      final attributes = faculty['attributes'] ?? {};
      final parentId = attributes['parent_id'];
      final parentData = attributes['parent']?['data'];
      final parentDataId = parentData?['id'];

      return parentId == widget.centerId || parentDataId == widget.centerId;
    }).toList();

    setState(() {
      _filteredFaculties = filtered;
    });
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase();
    final allFiltered = widget.allFaculties.where((faculty) {
      final attributes = faculty['attributes'] ?? {};
      final parentId = attributes['parent_id'];
      final parentData = attributes['parent']?['data'];
      final parentDataId = parentData?['id'];

      return parentId == widget.centerId || parentDataId == widget.centerId;
    }).toList();

    setState(() {
      _filteredFaculties = allFiltered.where((faculty) {
        final attributes = faculty['attributes'] ?? {};
        final name = attributes['name']?.toLowerCase() ?? '';
        return name.contains(query);
      }).toList();
    });
  }

  Future<void> _handleUpdate() async {
    setState(() => _isUpdating = true);

    final result = await _authRepository.updateAcademicProfile(
      universityId: widget.universityId,
      centerIds: [widget.centerId],
      facultyId: _selectedFacultyId,
    );

    if (mounted) {
      setState(() => _isUpdating = false);
      if (result['success']) {
        _showSuccessDialog();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result['message'] ?? 'Failed to update profile')),
        );
      }
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
                decoration: const BoxDecoration(color: Color(0xFF27AE60), shape: BoxShape.circle),
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

  String _selectedFacultyName = '';

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
                    Container(width: 20, height: 4, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(2))),
                    const SizedBox(width: 8),
                    Container(width: 20, height: 4, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(2))),
                  ],
                ),
                const SizedBox(height: 12),
                const Text('Step 3 of 3', style: TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 24),
                const Text(
                  'Select Your Faculty',
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
                const Text('Selected Center:', style: TextStyle(color: AppColors.textGray, fontSize: 14)),
                const SizedBox(height: 4),
                Chip(
                  label: Text(widget.centerName, style: const TextStyle(fontSize: 12)),
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
                hintText: 'Search faculties...',
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
                    : _filteredFaculties.isEmpty
                        ? const Center(child: Text('No options available'))
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            itemCount: _filteredFaculties.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final faculty = _filteredFaculties[index];
                          final id = faculty['id'];
                          final attributes = faculty['attributes'];
                          final name = attributes['name'] ?? 'Unknown';
                          final isSelected = _selectedFacultyId == id;
                          
                          return GestureDetector(
                            onTap: () => setState(() {
                              _selectedFacultyId = id;
                              _selectedFacultyName = name;
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
                                  Icon(Icons.school_outlined, color: isSelected ? AppColors.primaryBlue : AppColors.textGray),
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
              text: 'FINISH',
              isLoading: _isUpdating,
              onPressed: _selectedFacultyId == null || _isUpdating
                  ? null
                  : () { _handleUpdate(); },
            ),
          ),
        ],
      ),
    );
  }
}
