import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../auth/data/auth_repository.dart';
import 'center_selection_screen.dart';

class UniversitySelectionScreen extends StatefulWidget {
  const UniversitySelectionScreen({super.key});

  @override
  State<UniversitySelectionScreen> createState() => _UniversitySelectionScreenState();
}

class _UniversitySelectionScreenState extends State<UniversitySelectionScreen> {
  final _searchController = TextEditingController();
  final _authRepository = AuthRepository();
  
  List<dynamic> _universities = [];
  List<dynamic> _filteredUniversities = [];
  List<dynamic> _centers = [];
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
      _authRepository.getCenters(),
      _authRepository.getFaculties(),
    ]);

    if (mounted) {
      setState(() {
        _isLoading = false;
        final uniResult = results[0];
        final centerResult = results[1];
        final facultyResult = results[2];

        if (uniResult['success'] && centerResult['success'] && facultyResult['success']) {
          _universities = uniResult['data'] ?? [];
          _filteredUniversities = _universities;
          _centers = centerResult['data'] ?? [];
          _faculties = facultyResult['data'] ?? [];
        } else {
          _errorMessage = uniResult['message'] ?? centerResult['message'] ?? facultyResult['message'];
        }
      });
    }
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredUniversities = _universities.where((uni) {
        final name = uni['attributes']['name']?.toLowerCase() ?? '';
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
                    Container(width: 20, height: 4, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(2))),
                    const SizedBox(width: 8),
                    Container(width: 20, height: 4, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(2))),
                    const SizedBox(width: 8),
                    Container(width: 20, height: 4, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(2))),
                  ],
                ),
                const SizedBox(height: 12),
                const Text('Step 1 of 3', style: TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 24),
                const Text(
                  'Select Your University',
                  style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Search
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search universities...',
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
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
                            const SizedBox(height: 16),
                            ElevatedButton(onPressed: _fetchData, child: const Text('Retry')),
                          ],
                        ),
                      )
                    : _filteredUniversities.isEmpty
                        ? const Center(child: Text('No options available'))
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            itemCount: _filteredUniversities.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final uni = _filteredUniversities[index];
                          final id = uni['id'];
                          final attributes = uni['attributes'];
                          final name = attributes['name'] ?? 'Unknown';
                          final isSelected = _selectedUniversityId == id;
                          
                          return GestureDetector(
                            onTap: () => setState(() {
                              _selectedUniversityId = id;
                              _selectedUniversityName = name;
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
                                      decoration: BoxDecoration(color: AppColors.inputFill, borderRadius: BorderRadius.circular(8)),
                                      child: const Icon(Icons.school, color: AppColors.primaryBlue),
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
              onPressed: _selectedUniversityId == null
                  ? null
                  : () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => CenterSelectionScreen(
                            universityId: _selectedUniversityId,
                            universityName: _selectedUniversityName!,
                            allCenters: _centers,
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
