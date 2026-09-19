import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/library_repository.dart';
import '../../domain/library_material.dart';
import 'library_material_detail_screen.dart';
import 'unlock_material_screen.dart';

/// Electronic library — the app's version of the website's
/// `StudentElectronicLibrary`.
///
/// Same content and rules: published materials only, the all / booklet /
/// reference / guide tabs, a working search over title, description, course
/// ids and type, the "how to unlock" banner, and a card per material that is
/// locked on `code_activation` and opens the material page otherwise.
class ElectronicLibraryScreen extends StatefulWidget {
  const ElectronicLibraryScreen({super.key});

  @override
  State<ElectronicLibraryScreen> createState() =>
      _ElectronicLibraryScreenState();
}

class _ElectronicLibraryScreenState extends State<ElectronicLibraryScreen> {
  final _repository = LibraryRepository();
  final _searchController = TextEditingController();

  /// `all` or one of [kLibraryMaterialTypes].
  String _tab = 'all';
  String _query = '';

  List<dynamic> _materials = const [];
  bool _isLoading = true;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _loadFailed = false;
    });

    try {
      final result = await _repository.getLibraries();
      if (!mounted) return;
      if (result['success'] == true) {
        final all = (result['data'] as List?) ?? const [];
        setState(() {
          _materials = all.where(libraryIsPublished).toList();
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
          _loadFailed = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadFailed = true;
        });
      }
    }
  }

  List<dynamic> get _visible {
    return _materials.where((material) {
      if (_tab != 'all' && libraryMaterialType(material) != _tab) return false;
      return libraryMatchesSearch(material, _query);
    }).toList();
  }

  /// The banner's button activates the first locked material, like the web.
  dynamic get _firstLocked {
    for (final material in _materials) {
      if (libraryIsLocked(material)) return material;
    }
    return null;
  }

  Future<void> _unlock(dynamic material) async {
    final unlocked = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => UnlockMaterialScreen(
          library: material,
          returnOnSuccess: true,
        ),
      ),
    );
    if (unlocked == true && mounted) await _load();
  }

  Future<void> _open(dynamic material) async {
    final id = libraryId(material);
    if (id == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LibraryMaterialDetailScreen(
          materialId: id,
          initialMaterial: material,
        ),
      ),
    );
    // Activation can happen on the detail page; reflect it in the list.
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0F172A),
        elevation: 0,
        title: Text(
          'library.page_title'.tr(),
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Text(
              'library.page_subtitle'.tr(),
              style: const TextStyle(
                fontSize: 14,
                height: 1.5,
                color: Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 16),
            _buildBanner(),
            const SizedBox(height: 16),
            _buildSearchAndTabs(),
            const SizedBox(height: 16),
            ..._buildContent(),
          ],
        ),
      ),
    );
  }

  Widget _buildBanner() {
    final firstLocked = _firstLocked;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [Color(0xFF4F46E5), Color(0xFF6366F1), Color(0xFF7C3AED)],
        ),
      ),
      child: Stack(
        children: [
          PositionedDirectional(
            end: 0,
            top: 0,
            child: Icon(
              Icons.lock_outline,
              size: 72,
              color: Colors.white.withValues(alpha: 0.18),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'library.unlock_banner_title'.tr(),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 56),
                child: Text(
                  'library.unlock_banner_body'.tr(),
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton.icon(
                  onPressed:
                      firstLocked == null ? null : () => _unlock(firstLocked),
                  icon: const Icon(Icons.key, size: 18, color: Colors.amber),
                  label: Text('library.activate_material'.tr()),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF4F46E5),
                    disabledBackgroundColor:
                        Colors.white.withValues(alpha: 0.5),
                    disabledForegroundColor: const Color(0xFF4F46E5),
                    elevation: 0,
                    textStyle: const TextStyle(fontWeight: FontWeight.bold),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndTabs() {
    const tabs = ['all', ...kLibraryMaterialTypes];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            onChanged: (value) => setState(() => _query = value),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'library.search_placeholder'.tr(),
              prefixIcon: const Icon(Icons.search, color: Color(0xFF94A3B8)),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                    ),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: tabs.map((tab) {
                final selected = _tab == tab;
                return Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: ChoiceChip(
                    label: Text(
                      tab == 'all'
                          ? 'library.tab_all'.tr()
                          : 'library.material_type.$tab'.tr(),
                    ),
                    selected: selected,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _tab = tab),
                    selectedColor: const Color(0xFF2563EB),
                    backgroundColor: const Color(0xFFF1F5F9),
                    labelStyle: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: selected ? Colors.white : const Color(0xFF64748B),
                    ),
                    side: BorderSide.none,
                    shape: const StadiumBorder(),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildContent() {
    if (_isLoading) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 60),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }

    if (_loadFailed) {
      return [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFEF2F2),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFFEE2E2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'library.load_error'.tr(),
                style: const TextStyle(color: Color(0xFF991B1B)),
              ),
              TextButton(onPressed: _load, child: Text('library.retry'.tr())),
            ],
          ),
        ),
      ];
    }

    final visible = _visible;
    if (visible.isEmpty) {
      return [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Text(
            _query.trim().isNotEmpty
                ? 'library.empty_search'.tr()
                : 'library.empty'.tr(),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF64748B)),
          ),
        ),
      ];
    }

    return visible.map(_buildCard).toList();
  }

  Widget _buildCard(dynamic material) {
    final locked = libraryIsLocked(material);
    final cover = libraryCover(material);
    final attachments = libraryAttachments(material);
    final type = libraryMaterialType(material);
    final description = libraryDescription(material);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 4 / 3,
            child: Stack(
              fit: StackFit.expand,
              children: [
                cover.isEmpty
                    ? Container(
                        color: const Color(0xFFF1F5F9),
                        child: const Icon(Icons.lock_outline,
                            size: 40, color: Color(0xFFCBD5E1)),
                      )
                    : CachedNetworkImage(
                        imageUrl: cover,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Container(
                          color: const Color(0xFFF1F5F9),
                          child: const Icon(Icons.menu_book,
                              size: 40, color: Color(0xFFCBD5E1)),
                        ),
                      ),
                if (!locked)
                  PositionedDirectional(
                    top: 8,
                    end: 8,
                    child: Container(
                      height: 36,
                      width: 36,
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Icon(Icons.lock_open,
                          size: 18, color: Colors.white),
                    ),
                  )
                else
                  Container(
                    color: const Color(0xA60F172A),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.lock, size: 40, color: Colors.white),
                        const SizedBox(height: 6),
                        Text(
                          'library.locked'.tr(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 10),
                        ElevatedButton(
                          onPressed: () => _unlock(material),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF4F46E5),
                            elevation: 0,
                            textStyle:
                                const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          child: Text('library.unlock'.tr()),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (locked)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      'library.activate_course_hint'.tr(),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF92400E),
                      ),
                    ),
                  ),
                Text(
                  libraryTitle(material),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'library.course_ref'
                      .tr(args: [libraryCourseIdsLabel(material)]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF64748B),
                  ),
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    description,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (type.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEEF2FF),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          kLibraryMaterialTypes.contains(type)
                              ? 'library.material_type.$type'.tr()
                              : type,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF4338CA),
                          ),
                        ),
                      ),
                    Text(
                      '${'library.price_label'.tr()}: ${libraryPriceLabel(material)}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
                if (attachments.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${'library.file_count'.plural(attachments.length)} · '
                    '${formatLibraryAttachmentSize(attachmentAttributes(attachments.first)['size'])}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                SizedBox(
                  height: 46,
                  child: locked
                      ? OutlinedButton(
                          onPressed: () => _unlock(material),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF475569),
                            backgroundColor: const Color(0xFFF8FAFC),
                            side: const BorderSide(color: Color(0xFFE2E8F0)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text('library.locked_material'.tr()),
                        )
                      : ElevatedButton(
                          onPressed: () => _open(material),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryBlue,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            textStyle:
                                const TextStyle(fontWeight: FontWeight.bold),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text('library.open_material'.tr()),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
