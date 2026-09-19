import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:learnoo/features/auth/data/auth_repository.dart';
import 'package:learnoo/features/auth/presentation/screens/login_screen.dart';
import 'package:learnoo/core/services/feature_manager.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:learnoo/features/support/presentation/screens/support_screen.dart';
import 'edit_profile_screen.dart';
import 'downloads_screen.dart';
import 'settings_screen.dart';

class MyProfileScreen extends StatefulWidget {
  const MyProfileScreen({super.key});

  @override
  State<MyProfileScreen> createState() => _MyProfileScreenState();
}

class _MyProfileScreenState extends State<MyProfileScreen> {
  final AuthRepository _authRepository = AuthRepository();
  final FeatureManager _featureManager = FeatureManager();
  Map<String, dynamic>? _userData;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchProfile();
  }

  Future<void> _fetchProfile() async {
    setState(() => _isLoading = true);
    final result = await _authRepository.getProfile();
    if (result['success']) {
      setState(() {
        _userData = result['data'];
        _isLoading = false;
      });
    } else {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result['message'] ?? 'profile.failed_load_profile'.tr(),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: isDark ? const Color(0xFF13151B) : const Color(0xFFFAFBFF),
        body: const Center(child: CircularProgressIndicator(color: Color(0xFF5A75FF))),
      );
    }

    final attributes = _userData?['attributes'];
    final String firstName = (attributes?['first_name'] ?? attributes?['name'] ?? '').toString();
    final String lastName = (attributes?['last_name'] ?? '').toString();
    final String fullName = lastName.isEmpty ? firstName : '$firstName $lastName';
    final String phone = (attributes?['phone'] ?? attributes?['phone_number'] ?? '').toString();
    final String email = (attributes?['email'] ?? '').toString();
    final String? userImageUrl = attributes?['image']?.toString();

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF13151B) : const Color(0xFFFAFBFF),
      body: RefreshIndicator(
        onRefresh: _fetchProfile,
        color: const Color(0xFF5A75FF),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              _buildHeader(fullName, userImageUrl, isDark),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    const SizedBox(height: 24),
                    _buildAccountInfoCard(phone, email, isDark),
                    const SizedBox(height: 16),
                    _buildQRCodeCard(fullName, phone, email, isDark),
                    const SizedBox(height: 16),
                    _buildMenuItem(
                      icon: FontAwesomeIcons.download,
                      label: 'profile.downloads'.tr(),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const DownloadsScreen()),
                      ),
                      isDark: isDark,
                    ),
                    const SizedBox(height: 12),
                    _buildMenuItem(
                      icon: FontAwesomeIcons.gear,
                      label: 'profile.settings'.tr(),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const SettingsScreen()),
                      ),
                      isDark: isDark,
                    ),
                    const SizedBox(height: 12),
                    _buildMenuItem(
                      icon: FontAwesomeIcons.lifeRing,
                      label: 'support.title'.tr(),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const SupportScreen()),
                      ),
                      isDark: isDark,
                    ),
                    const SizedBox(height: 24),
                    _buildConnectWithUs(isDark),
                    const SizedBox(height: 24),
                    _buildLogoutButton(isDark),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(String fullName, String? userImageUrl, bool isDark) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          height: 190,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF5A75FF), Color(0xFF8E7CFF)],
            ),
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(40),
              bottomRight: Radius.circular(40),
            ),
          ),
          child: SafeArea(
            child: Center(
              child: Text(
                'profile.title'.tr(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
        Transform.translate(
          offset: const Offset(0, -50),
          child: Column(
            children: [
              Stack(
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E212B) : Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 10,
                          offset: Offset(0, 5),
                        ),
                      ],
                    ),
                    child: CircleAvatar(
                      radius: 50,
                      backgroundColor: isDark ? const Color(0xFF262A36) : const Color(0xFFF0F2FF),
                      backgroundImage: userImageUrl != null && userImageUrl.isNotEmpty
                          ? NetworkImage(userImageUrl)
                          : null,
                      child: userImageUrl == null || userImageUrl.isEmpty
                          ? const FaIcon(
                              FontAwesomeIcons.user,
                              color: Color(0xFF5A75FF),
                              size: 40,
                            )
                          : null,
                    ),
                  ),
                  if (_featureManager.isProfileEditingEnabled)
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: GestureDetector(
                        onTap: _showEditProfile,
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
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                fullName,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF1F2937),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAccountInfoCard(String phone, String email, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E212B) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? const Color(0xFF2E3344) : Colors.transparent,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'profile.account_info'.tr(),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF1F2937),
                ),
              ),
              if (_featureManager.isProfileEditingEnabled)
                TextButton.icon(
                  onPressed: () => _showEditProfile(),
                  icon: const FaIcon(FontAwesomeIcons.penToSquare, size: 14),
                  label: Text('profile.edit'.tr()),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF5A75FF),
                    textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _buildInfoRow(
            FontAwesomeIcons.phone,
            'profile.phone_number'.tr(),
            phone,
            isDark ? const Color(0xFF1E3A2B) : Colors.green[50]!,
            Colors.green,
            isDark,
          ),
          const SizedBox(height: 16),
          _buildInfoRow(
            FontAwesomeIcons.envelope,
            'profile.email_address'.tr(),
            email,
            isDark ? const Color(0xFF1E2D4A) : Colors.blue[50]!,
            Colors.blue,
            isDark,
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(
    dynamic icon,
    String label,
    String value,
    Color bgColor,
    Color iconColor,
    bool isDark,
  ) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: FaIcon(
              icon is FaIconData ? icon : FontAwesomeIcons.circleQuestion,
              color: iconColor,
              size: 16,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: isDark ? const Color(0xFF94A3B8) : Colors.grey,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF1F2937),
                fontSize: 14,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildQRCodeCard(String name, String phone, String email, bool isDark) {
    final qrData = 'Learnoo Student\nName: $name\nPhone: $phone\nEmail: $email';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E212B) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? const Color(0xFF2E3344) : Colors.transparent,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            'profile.student_qr'.tr(),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF1F2937),
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: const Color(0xFFF3F4F6)),
              borderRadius: BorderRadius.circular(16),
            ),
            child: QrImageView(
              data: qrData,
              version: QrVersions.auto,
              size: 160.0,
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: Color(0xFF1F2937),
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: Color(0xFF1F2937),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'profile.scan_verify'.tr(),
            style: TextStyle(
              color: isDark ? const Color(0xFF94A3B8) : Colors.grey,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem({
    required dynamic icon,
    required String label,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E212B) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? const Color(0xFF2E3344) : Colors.transparent,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.02),
              blurRadius: 5,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF262A36) : const Color(0xFFF5F3FF),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: FaIcon(
                  icon is FaIconData ? icon : FontAwesomeIcons.circleQuestion,
                  color: const Color(0xFF8B5CF6),
                  size: 16,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF1F2937),
              ),
            ),
            const Spacer(),
            FaIcon(
              FontAwesomeIcons.arrowUpRightFromSquare,
              color: isDark ? const Color(0xFF64748B) : const Color(0xFFD1D5DB),
              size: 14,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectWithUs(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'profile.connect_with_us'.tr(),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF1F2937),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            _buildSocialButton(FontAwesomeIcons.whatsapp, 'profile.whatsapp'.tr(), const Color(0xFF22C55E)),
            const SizedBox(width: 8),
            _buildSocialButton(FontAwesomeIcons.telegram, 'profile.telegram'.tr(), const Color(0xFF3B82F6)),
            const SizedBox(width: 8),
            _buildSocialButton(FontAwesomeIcons.globe, 'profile.website'.tr(), const Color(0xFFF87171)),
          ],
        ),
      ],
    );
  }

  Widget _buildSocialButton(dynamic icon, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            FaIcon(
              icon is FaIconData ? icon : FontAwesomeIcons.globe,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('profile.logout'.tr()),
        content: Text('profile.logout_confirm'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('profile.cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFFF4B4B)),
            child: Text('profile.logout'.tr()),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);

    final result = await _authRepository.logout();

    setState(() => _isLoading = false);

    if (mounted) {
      if (result['success']) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const LoginScreen()),
          (route) => false,
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result['message'] ?? 'auth.login_failed'.tr(),
            ),
          ),
        );
      }
    }
  }

  Widget _buildLogoutButton(bool isDark) {
    return SizedBox(
      width: double.infinity,
      child: TextButton.icon(
        onPressed: _handleLogout,
        icon: const FaIcon(FontAwesomeIcons.rightFromBracket, size: 16),
        label: Text('profile.logout'.tr()),
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFFFF4B4B),
          backgroundColor: isDark ? const Color(0xFF2A1B1E) : const Color(0xFFFFF1F1),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
      ),
    );
  }

  void _showEditProfile() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => EditProfileScreen(
        userData: _userData,
        onUpdate: (updatedData) {
          setState(() => _userData = updatedData);
        },
      ),
    );
  }
}
