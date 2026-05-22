import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:shimmer/shimmer.dart';
import '../../data/library_repository.dart';
import 'unlock_material_screen.dart';
import 'pdf_viewer_screen.dart';

class ElectronicLibraryScreen extends StatefulWidget {
  const ElectronicLibraryScreen({super.key});

  @override
  State<ElectronicLibraryScreen> createState() => _ElectronicLibraryScreenState();
}

class _ElectronicLibraryScreenState extends State<ElectronicLibraryScreen> {
  final LibraryRepository _libraryRepository = LibraryRepository();
  String _selectedFilter = 'All';
  final List<String> _filters = ['All', 'guide', 'reference', 'booklet'];

  List<dynamic> _libraries = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadLibraries();
  }

  Future<void> _loadLibraries() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await _libraryRepository.getLibraries();
      if (mounted) {
        if (result['success']) {
          setState(() {
            _libraries = result['data'] ?? [];
            _isLoading = false;
          });
        } else {
          setState(() {
            _errorMessage = result['message'] ?? 'course.failed_load_libraries'.tr();
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'course.connection_error'.tr(args: [e.toString()]);
          _isLoading = false;
        });
      }
    }
  }

  List<dynamic> get _filteredLibraries {
    if (_selectedFilter == 'All') return _libraries;
    return _libraries.where((lib) {
      final materialType = lib['attributes']?['material_type']?.toString().toLowerCase() ?? '';
      return materialType == _selectedFilter.toLowerCase();
    }).toList();
  }

  Map<String, List<dynamic>> get _groupedLibraries {
    final grouped = <String, List<dynamic>>{};
    for (final library in _filteredLibraries) {
      final materialType = library['attributes']?['material_type']?.toString() ?? 'Other';
      if (!grouped.containsKey(materialType)) {
        grouped[materialType] = [];
      }
      grouped[materialType]!.add(library);
    }
    return grouped;
  }

  void _navigateToUnlock(dynamic library) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => UnlockMaterialScreen(library: library),
      ),
    );
  }

  void _openPdf(dynamic library) {
    final attributes = library['attributes'] ?? {};
    final title = attributes['title']?.toString() ?? 'course.material'.tr();
    final attachments = attributes['attachments'] as List<dynamic>? ?? [];

    // Find first PDF attachment that is not locked or downloadable
    final pdfAttachment = attachments.firstWhere(
      (attachment) {
        final ext = attachment['attributes']?['extension']?.toString().toLowerCase() ?? '';
        final isLocked = attachment['attributes']?['is_locked'] == true;
        final downloadable = attachment['attributes']?['downloadable'] == true;
        return ext == 'pdf' && (!isLocked || downloadable);
      },
      orElse: () => null,
    );

    final pdfUrl = pdfAttachment?['attributes']?['path']?.toString() ?? '';

    if (pdfUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('course.pdf_not_available'.tr())),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PdfViewerScreen(
          pdfUrl: pdfUrl,
          title: title,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // Background gradient header
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 180,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF5A75FF),
                    Color(0xFF7B93FF),
                  ],
                ),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(30),
                  bottomRight: Radius.circular(30),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.arrow_back,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          'course.electronic_library'.tr(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 40),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                // Search Bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    height: 50,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: 'course.search_materials'.tr(),
                        hintStyle: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 14,
                        ),
                        prefixIcon: Icon(
                          Icons.search,
                          color: Colors.grey[400],
                          size: 20,
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 15,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                // Filter Chips
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: _filters.map((filter) {
                      final isSelected = _selectedFilter == filter;
                      return Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedFilter = filter;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFF2137D6)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isSelected
                                    ? const Color(0xFF2137D6)
                                    : Colors.grey[300]!,
                              ),
                            ),
                            child: Text(
                              filter == 'All' ? 'course.all'.tr() : 'course.$filter'.tr(),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: isSelected
                                    ? Colors.white
                                    : Colors.grey[600],
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 20),
                // Materials List
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _loadLibraries,
                    color: const Color(0xFF5A75FF),
                    backgroundColor: Colors.white,
                    child: _buildBody(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return _buildSkeletonList();
    }

    if (_errorMessage != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: MediaQuery.of(context).size.height * 0.3),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadLibraries,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF5A75FF),
                foregroundColor: Colors.white,
              ),
              child: Text('course.retry'.tr()),
            ),
          ],
        ),
      ]);
    }

    if (_libraries.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: MediaQuery.of(context).size.height * 0.3),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
            Icon(
              Icons.library_books_outlined,
              size: 48,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'course.no_materials_available'.tr(),
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 14,
              ),
            ),
          ],
        ),
      ]);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _groupedLibraries.entries.map((entry) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const FaIcon(
                          FontAwesomeIcons.book,
                          color: Color(0xFF5A75FF),
                          size: 14,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          entry.key == 'Other' ? entry.key.toUpperCase() : 'course.${entry.key.toLowerCase()}'.tr().toUpperCase(),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1F2937),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ...entry.value.map((library) => _buildMaterialCard(library)),
                    const SizedBox(height: 20),
                  ],
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSkeletonList() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSkeletonHeader(),
          const SizedBox(height: 12),
          _buildSkeletonCard(),
          _buildSkeletonCard(),
          const SizedBox(height: 20),
          _buildSkeletonHeader(),
          const SizedBox(height: 12),
          _buildSkeletonCard(),
        ],
      ),
    );
  }

  Widget _buildSkeletonHeader() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: Container(
        width: 100,
        height: 16,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }

  Widget _buildSkeletonCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF1F1F1)),
      ),
      child: Shimmer.fromColors(
        baseColor: Colors.grey[300]!,
        highlightColor: Colors.grey[100]!,
        child: Row(
          children: [
            Container(
              width: 80,
              height: 100,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    height: 16,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: 120,
                    height: 12,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: 60,
                    height: 20,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMaterialCard(dynamic library) {
    final attributes = library['attributes'] ?? {};
    final title = attributes['title']?.toString() ?? 'course.untitled'.tr();
    final description = attributes['description']?.toString() ?? '';
    final materialType = attributes['material_type']?.toString() ?? 'course.unknown'.tr();
    final coverImage = attributes['cover_image']?.toString() ?? '';
    final isLocked = attributes['is_locked'] == true;
    final price = attributes['price']?.toString() ?? '0';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF1F1F1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  coverImage,
                  width: 80,
                  height: 100,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      width: 80,
                      height: 100,
                      color: const Color(0xFFF3F4F6),
                      child: const Icon(Icons.book, color: Color(0xFF9CA3AF)),
                    );
                  },
                ),
              ),
              if (isLocked)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: Colors.grey[600],
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.lock,
                      color: Colors.white,
                      size: 12,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1F2937),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[500],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F2FF),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    materialType == 'course.unknown'.tr() || materialType == 'Other' ? materialType : 'course.${materialType.toLowerCase()}'.tr(),
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF5A75FF),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                if (isLocked)
                  Row(
                    children: [
                      FaIcon(
                        FontAwesomeIcons.lock,
                        color: Colors.grey[500],
                        size: 12,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${'course.requires_unlock'.tr()} - EGP $price',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  )
                else
                  Row(
                    children: [
                      const FaIcon(
                        FontAwesomeIcons.lockOpen,
                        color: Color(0xFF27AE60),
                        size: 12,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'course.paid_access'.tr(),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF27AE60),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          if (!isLocked)
            OutlinedButton.icon(
              onPressed: () => _openPdf(library),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF5A75FF),
                side: const BorderSide(color: Color(0xFF5A75FF)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              icon: const FaIcon(FontAwesomeIcons.bookOpen, size: 12),
              label: Text(
                'course.open'.tr(),
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            )
          else
            ElevatedButton.icon(
              onPressed: () => _navigateToUnlock(library),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2137D6),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                elevation: 0,
              ),
              icon: const FaIcon(FontAwesomeIcons.key, size: 12),
              label: Text(
                'course.unlock'.tr(),
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
        ],
      ),
    );
  }
}
