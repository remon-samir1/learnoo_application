import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../auth/data/auth_repository.dart';
import '../../domain/academic_tree.dart';

/// University -> Centre -> Faculty (-> Department) dropdowns.
///
/// Port of the web's `UniversityFacultyFields`, which is what lets a student
/// change their academic selection from the profile editor instead of only
/// during onboarding. The option lists follow the same rules as the web:
/// centres are derived from the faculty list, and a selection lower in the tree
/// is cleared whenever the level above it changes to something incompatible.
class AcademicPickerFields extends StatefulWidget {
  const AcademicPickerFields({
    super.key,
    required this.universityId,
    required this.centerId,
    required this.facultyId,
    this.departmentId,
    required this.onChanged,
    this.enabled = true,
    this.showDepartment = false,
  });

  final String? universityId;
  final String? centerId;
  final String? facultyId;
  final String? departmentId;
  final bool showDepartment;

  /// Fires on every change with the full selection, so the host form keeps one
  /// source of truth.
  final void Function({
    String? universityId,
    String? centerId,
    String? facultyId,
    String? departmentId,
  }) onChanged;

  final bool enabled;

  @override
  State<AcademicPickerFields> createState() => _AcademicPickerFieldsState();
}

class _AcademicPickerFieldsState extends State<AcademicPickerFields> {
  final _authRepository = AuthRepository();

  List<AcademicOption> _universities = const [];
  List<dynamic> _faculties = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final universities = await _authRepository.getUniversities();
    final faculties = await _authRepository.getFaculties();

    if (!mounted) return;

    setState(() {
      _loading = false;
      if (universities['success'] == true) {
        final list = (universities['data'] as List?) ?? const [];
        _universities = list
            .map((u) =>
                AcademicOption(id: entityId(u) ?? '', label: entityName(u)))
            .where((o) => o.id.isNotEmpty && o.label.isNotEmpty)
            .toList();
      }
      if (faculties['success'] == true) {
        _faculties = (faculties['data'] as List?) ?? const [];
      } else {
        _error = faculties['message']?.toString();
      }
    });
  }

  /// Keeps [value] only while it is still one of [options] — the equivalent of
  /// the web's "clear the child when the parent no longer contains it" effects,
  /// and what stops `DropdownButton` from asserting on a stale value.
  String? _valid(String? value, List<AcademicOption> options) {
    if (value == null || value.isEmpty) return null;
    for (final option in options) {
      if (idsMatch(option.id, value)) return option.id;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _error!,
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ),
            TextButton(onPressed: _load, child: Text('profile.retry'.tr())),
          ],
        ),
      );
    }

    final centerOptions = centerOptionsForUniversity(
      _faculties,
      widget.universityId,
    );
    final facultyOptions = facultyOptionsForCenter(_faculties, widget.centerId);
    final departmentOptions = widget.showDepartment
        ? departmentOptionsForFaculty(_faculties, widget.facultyId)
        : const <AcademicOption>[];

    final hasUniversity =
        widget.universityId != null && widget.universityId!.isNotEmpty;
    final hasCenter = widget.centerId != null && widget.centerId!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _dropdown(
          label: 'profile.university'.tr(),
          hint: 'profile.select_university'.tr(),
          value: _valid(widget.universityId, _universities),
          options: _universities,
          onChanged: (value) => widget.onChanged(
            universityId: value,
            centerId: null,
            facultyId: null,
            departmentId: null,
          ),
        ),
        _dropdown(
          label: 'profile.center'.tr(),
          hint: hasUniversity
              ? 'profile.select_center'.tr()
              : 'profile.select_university_first'.tr(),
          value: _valid(widget.centerId, centerOptions),
          options: centerOptions,
          onChanged: (value) => widget.onChanged(
            universityId: widget.universityId,
            centerId: value,
            facultyId: null,
            departmentId: null,
          ),
        ),
        _dropdown(
          label: 'profile.faculty'.tr(),
          hint: hasCenter
              ? 'profile.select_faculty'.tr()
              : 'profile.select_center_first'.tr(),
          value: _valid(widget.facultyId, facultyOptions),
          options: facultyOptions,
          onChanged: (value) => widget.onChanged(
            universityId: widget.universityId,
            centerId: widget.centerId,
            facultyId: value,
            departmentId: null,
          ),
        ),
        if (widget.showDepartment && departmentOptions.isNotEmpty)
          _dropdown(
            label: 'profile.department'.tr(),
            hint: 'profile.select_department'.tr(),
            value: _valid(widget.departmentId, departmentOptions),
            options: departmentOptions,
            onChanged: (value) => widget.onChanged(
              universityId: widget.universityId,
              centerId: widget.centerId,
              facultyId: widget.facultyId,
              departmentId: value,
            ),
          ),
      ],
    );
  }

  Widget _dropdown({
    required String label,
    required String hint,
    required String? value,
    required List<AcademicOption> options,
    required ValueChanged<String?> onChanged,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF374151),
            ),
          ),
          const SizedBox(height: 8),
          DecoratedBox(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF262A36) : const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark ? const Color(0xFF383E52) : const Color(0xFFE5E7EB),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: value,
                  dropdownColor: isDark ? const Color(0xFF1E212B) : Colors.white,
                  iconEnabledColor: isDark ? const Color(0xFFCBD5E1) : Colors.grey[700],
                  iconDisabledColor: isDark ? const Color(0xFF64748B) : Colors.grey[400],
                  hint: Text(
                    hint,
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF9CA3AF),
                    ),
                  ),
                  items: options
                      .map(
                        (option) => DropdownMenuItem(
                          value: option.id,
                          child: Text(
                            option.label,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF1F2937),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged:
                      widget.enabled && options.isNotEmpty ? onChanged : null,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
