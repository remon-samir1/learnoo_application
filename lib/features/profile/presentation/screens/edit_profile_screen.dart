import 'dart:io';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:learnoo/features/academic/presentation/widgets/academic_picker_fields.dart';
import 'package:learnoo/features/auth/data/auth_repository.dart';
import 'package:learnoo/features/auth/domain/student_profile.dart';

class EditProfileScreen extends StatefulWidget {
  final Map<String, dynamic>? userData;
  final Function(Map<String, dynamic>) onUpdate;

  const EditProfileScreen({super.key, this.userData, required this.onUpdate});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _isLoading = false;
  final _authRepository = AuthRepository();
  final _imagePicker = ImagePicker();
  File? _selectedImage;
  String? _currentImageUrl;

  // Academic selection, editable here exactly like the web profile form.
  String? _universityId;
  String? _centerId;
  String? _facultyId;
  String? _departmentId;

  @override
  void initState() {
    super.initState();
    final attributes = widget.userData?['attributes'] ?? widget.userData;
    _firstNameController.text = (attributes?['first_name'] ?? attributes?['name'] ?? '').toString();
    _lastNameController.text = (attributes?['last_name'] ?? '').toString();
    _emailController.text = (attributes?['email'] ?? '').toString();
    _phoneController.text = (attributes?['phone'] ?? attributes?['phone_number'] ?? '').toString();
    _currentImageUrl = attributes?['image']?.toString();

    final profile = StudentProfile.fromAttributes(
      attributes is Map ? Map<String, dynamic>.from(attributes) : null,
    );
    _universityId = profile.universityId;
    _centerId = profile.centerId;
    _facultyId = profile.facultyId;
    _departmentId = profile.departmentId;
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        setState(() {
          _selectedImage = File(pickedFile.path);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error picking image: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showImagePickerOptions() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1E212B) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'profile.change_photo'.tr(),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF1F2937),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: _buildPickerOption(
                      icon: FontAwesomeIcons.camera,
                      label: 'profile.camera'.tr(),
                      onTap: () {
                        Navigator.pop(context);
                        _pickImage(ImageSource.camera);
                      },
                      isDark: isDark,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildPickerOption(
                      icon: FontAwesomeIcons.image,
                      label: 'profile.gallery'.tr(),
                      onTap: () {
                        Navigator.pop(context);
                        _pickImage(ImageSource.gallery);
                      },
                      isDark: isDark,
                    ),
                  ),
                ],
              ),
              if (_selectedImage != null || (_currentImageUrl != null && _currentImageUrl!.isNotEmpty)) ...[
                const SizedBox(height: 16),
                _buildPickerOption(
                  icon: FontAwesomeIcons.trash,
                  label: 'profile.remove_photo'.tr(),
                  color: Colors.red,
                  onTap: () {
                    Navigator.pop(context);
                    setState(() {
                      _selectedImage = null;
                      _currentImageUrl = null;
                    });
                  },
                  isDark: isDark,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPickerOption({
    required FaIconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
    required bool isDark,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: color != null
              ? color.withValues(alpha: 0.1)
              : (isDark ? const Color(0xFF262A36) : const Color(0xFFF0F2FF)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            FaIcon(
              icon,
              color: color ?? const Color(0xFF5A75FF),
              size: 24,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: color ?? (isDark ? const Color(0xFFF8FAFC) : const Color(0xFF1F2937)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Map<String, dynamic> _academicPayload() {
    final map = <String, dynamic>{};
    if (_universityId != null) map['university_id'] = _universityId;
    if (_centerId != null) map['center_id'] = _centerId;
    if (_facultyId != null) map['faculty_id'] = _facultyId;
    if (_departmentId != null) map['department_id'] = _departmentId;
    return map;
  }

  Future<void> _handleSave() async {
    setState(() => _isLoading = true);

    final result = await _authRepository.updateProfileWithImage(
      profileData: {
        'first_name': _firstNameController.text,
        'last_name': _lastNameController.text,
        'email': _emailController.text,
        ..._academicPayload(),
      },
      imageFile: _selectedImage,
    );

    if (mounted) {
      setState(() => _isLoading = false);
      if (result['success']) {
        widget.onUpdate(result['data'] ?? {
          'first_name': _firstNameController.text,
          'last_name': _lastNameController.text,
          'email': _emailController.text,
          'phone': _phoneController.text,
          'image': result['data']?['attributes']?['image'] ?? _currentImageUrl,
        });
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'profile.profile_updated'.tr()),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'profile.failed_update_profile'.tr()),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E212B) : Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(30),
          topRight: Radius.circular(30),
        ),
      ),
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'profile.edit_profile'.tr(),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF1F2937),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close, color: isDark ? const Color(0xFF94A3B8) : Colors.grey),
                  style: IconButton.styleFrom(
                    backgroundColor: isDark ? const Color(0xFF262A36) : const Color(0xFFF9FAFB),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Center(
              child: GestureDetector(
                onTap: _showImagePickerOptions,
                child: Stack(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E212B) : Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isDark ? const Color(0xFF383E52) : const Color(0xFFE5E7EB),
                          width: 2,
                        ),
                      ),
                      child: CircleAvatar(
                        radius: 50,
                        backgroundColor: isDark ? const Color(0xFF262A36) : const Color(0xFFF0F2FF),
                        backgroundImage: _selectedImage != null
                            ? FileImage(_selectedImage!)
                            : (_currentImageUrl != null && _currentImageUrl!.isNotEmpty
                                ? NetworkImage(_currentImageUrl!)
                                : null),
                        child: (_selectedImage == null && (_currentImageUrl == null || _currentImageUrl!.isEmpty))
                            ? const FaIcon(
                                FontAwesomeIcons.user,
                                color: Color(0xFF5A75FF),
                                size: 40,
                              )
                            : null,
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(
                          color: Color(0xFF5A75FF),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black26,
                              blurRadius: 4,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const FaIcon(
                          FontAwesomeIcons.camera,
                          color: Colors.white,
                          size: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: _buildTextField(
                    'profile.first_name'.tr(),
                    _firstNameController,
                    Icons.person_outline,
                    isDark: isDark,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildTextField(
                    'profile.last_name'.tr(),
                    _lastNameController,
                    Icons.person_outline,
                    isDark: isDark,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildTextField(
              'profile.email_address'.tr(),
              _emailController,
              Icons.email_outlined,
              isDark: isDark,
            ),
            const SizedBox(height: 16),
            _buildTextField(
              'profile.phone_number'.tr(),
              _phoneController,
              Icons.phone_outlined,
              enabled: false,
              isDark: isDark,
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 4, right: 4),
              child: Text(
                'profile.phone_cannot_change'.tr(),
                style: TextStyle(
                  color: isDark ? const Color(0xFF94A3B8) : Colors.grey,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(height: 24),
            AcademicPickerFields(
              universityId: _universityId,
              centerId: _centerId,
              facultyId: _facultyId,
              departmentId: _departmentId,
              enabled: !_isLoading,
              showDepartment: false,
              onChanged: ({
                String? universityId,
                String? centerId,
                String? facultyId,
                String? departmentId,
              }) {
                setState(() {
                  _universityId = universityId;
                  _centerId = centerId;
                  _facultyId = facultyId;
                  _departmentId = departmentId;
                });
              },
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _handleSave,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF263EE2),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: _isLoading 
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text(
                        'profile.save_changes'.tr(),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller,
    IconData icon, {
    bool enabled = true,
    required bool isDark,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF374151),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          enabled: enabled,
          style: TextStyle(
            color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF1F2937),
          ),
          decoration: InputDecoration(
            prefixIcon: Icon(icon, color: isDark ? const Color(0xFF94A3B8) : Colors.grey, size: 20),
            filled: true,
            fillColor: enabled
                ? (isDark ? const Color(0xFF262A36) : const Color(0xFFF9FAFB))
                : (isDark ? const Color(0xFF1B1D25) : const Color(0xFFF3F4F6)),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: isDark ? const Color(0xFF383E52) : const Color(0xFFE5E7EB),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: isDark ? const Color(0xFF383E52) : const Color(0xFFE5E7EB),
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
      ],
    );
  }
}
