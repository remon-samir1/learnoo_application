import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:learnoo/features/auth/data/auth_repository.dart';
import 'package:learnoo/features/auth/presentation/screens/login_screen.dart';
import 'package:learnoo/core/services/feature_manager.dart';
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
          SnackBar(content: Text(result['message'] ?? 'Failed to load profile')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: Color(0xFF5A75FF))),
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
      backgroundColor: const Color(0xFFFAFBFF),
      body: RefreshIndicator(
        onRefresh: _fetchProfile,
        color: const Color(0xFF5A75FF),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              _buildHeader(fullName, userImageUrl),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    const SizedBox(height: 24),
                    _buildAccountInfoCard(phone, email),
                    const SizedBox(height: 16),
                    _buildQRCodeCard(fullName, phone, email),
                    const SizedBox(height: 16),
                    _buildMenuItem(
                      icon: FontAwesomeIcons.download,
                      label: 'Downloads',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const DownloadsScreen()),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildMenuItem(
                      icon: FontAwesomeIcons.gear,
                      label: 'Settings',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const SettingsScreen()),
                      ),
                    ),
                    const SizedBox(height: 24),
                    _buildConnectWithUs(),
                    const SizedBox(height: 24),
                    _buildLogoutButton(),
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
  Widget _buildHeader(String fullName, String? userImageUrl) {
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
          child: const SafeArea(
            child: Center(
              child: Text(
                'My Profile',
                style: TextStyle(
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
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 10,
                          offset: Offset(0, 5),
                        ),
                      ],
                    ),
                    child: CircleAvatar(
                      radius: 50,
                      backgroundColor: const Color(0xFFF0F2FF),
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
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1F2937),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAccountInfoCard(String phone, String email) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
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
              const Text(
                'Account Information',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1F2937),
                ),
              ),
              if (_featureManager.isProfileEditingEnabled)
                TextButton.icon(
                  onPressed: () => _showEditProfile(),
                  icon: const FaIcon(FontAwesomeIcons.penToSquare, size: 14),
                  label: const Text('Edit'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF5A75FF),
                    textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _buildInfoRow(FontAwesomeIcons.phone, 'Phone Number', phone, Colors.green[50]!, Colors.green),
          const SizedBox(height: 16),
          _buildInfoRow(FontAwesomeIcons.envelope, 'Email Address', email, Colors.blue[50]!, Colors.blue),
        ],
      ),
    );
  }

  Widget _buildInfoRow(dynamic icon, String label, String value, Color bgColor, Color iconColor) {
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
            child: FaIcon(icon is FaIconData ? icon : FontAwesomeIcons.circleQuestion, color: iconColor, size: 16),
          ),
        ),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Color(0xFF1F2937),
                fontSize: 14,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildQRCodeCard(String name, String phone, String email) {
    // Generate QR data without password
    final qrData = 'Learnoo Student\nName: $name\nPhone: $phone\nEmail: $email';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          const Text(
            'Student QR Code',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1F2937),
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
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
          const Text(
            'Scan to verify student identity',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem({required dynamic icon, required String label, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
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
                color: const Color(0xFFF5F3FF),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: FaIcon(icon is FaIconData ? icon : FontAwesomeIcons.circleQuestion, color: const Color(0xFF8B5CF6), size: 16),
              ),
            ),
            const SizedBox(width: 16),
            Text(
              label,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1F2937),
              ),
            ),
            const Spacer(),
            const FaIcon(FontAwesomeIcons.arrowUpRightFromSquare, color: Color(0xFFD1D5DB), size: 14),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectWithUs() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Connect With Us',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1F2937),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            _buildSocialButton(FontAwesomeIcons.whatsapp, 'WhatsApp', const Color(0xFF22C55E)),
            const SizedBox(width: 8),
            _buildSocialButton(FontAwesomeIcons.telegram, 'Telegram', const Color(0xFF3B82F6)),
            const SizedBox(width: 8),
            _buildSocialButton(FontAwesomeIcons.globe, 'Website', const Color(0xFFF87171)),
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
            FaIcon(icon is FaIconData ? icon : FontAwesomeIcons.circleQuestion, color: Colors.white, size: 20),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleLogout() async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFFF4B4B)),
            child: const Text('Logout'),
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
        // Navigate to login screen and clear navigation stack
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const LoginScreen()),
          (route) => false,
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result['message'] ?? 'Logout failed')),
        );
      }
    }
  }

  Widget _buildLogoutButton() {
    return SizedBox(
      width: double.infinity,
      child: TextButton.icon(
        onPressed: _handleLogout,
        icon: const FaIcon(FontAwesomeIcons.rightFromBracket, size: 16),
        label: const Text('Logout'),
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFFFF4B4B),
          backgroundColor: const Color(0xFFFFF1F1),
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
