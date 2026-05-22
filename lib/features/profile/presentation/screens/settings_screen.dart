import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:easy_localization/easy_localization.dart';

import 'change_password_screen.dart';
import 'help_faq_screen.dart';
import 'terms_privacy_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notificationsEnabled = true;
  bool _darkModeEnabled = false;
  bool _autoDownloadEnabled = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFBFF),
      body: Column(
        children: [
          _buildHeader(context),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _buildSectionHeader('settings.section_preferences'.tr()),
                _buildToggleItem(
                  icon: FontAwesomeIcons.bell,
                  label: 'settings.notifications'.tr(),
                  value: _notificationsEnabled,
                  onChanged: (val) => setState(() => _notificationsEnabled = val),
                  iconColor: const Color(0xFF3B82F6),
                ),
                _buildToggleItem(
                  icon: FontAwesomeIcons.moon,
                  label: 'settings.dark_mode'.tr(),
                  value: _darkModeEnabled,
                  onChanged: (val) => setState(() => _darkModeEnabled = val),
                  iconColor: const Color(0xFF8B5CF6),
                ),
                _buildToggleItem(
                  icon: FontAwesomeIcons.globe,
                  label: 'settings.auto_download'.tr(),
                  value: _autoDownloadEnabled,
                  onChanged: (val) => setState(() => _autoDownloadEnabled = val),
                  iconColor: const Color(0xFF10B981),
                ),
                const SizedBox(height: 24),
                _buildSectionHeader('settings.section_account'.tr()),
                _buildNavigationItem(
                  icon: FontAwesomeIcons.lock,
                  label: 'settings.change_password'.tr(),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const ChangePasswordScreen(),
                      ),
                    );
                  },
                  iconColor: const Color(0xFFF59E0B),
                ),
                Container(
                  margin: const EdgeInsets.only(bottom: 2),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(bottom: BorderSide(color: Color(0xFFF3F4F6))),
                  ),
                  child: ListTile(
                    leading: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: const Color(0xFF14B8A6).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Center(
                        child: FaIcon(FontAwesomeIcons.globe, color: Color(0xFF14B8A6), size: 16),
                      ),
                    ),
                    title: Text('settings.language'.tr(), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                    trailing: DropdownButton<String>(
                      value: context.locale.languageCode,
                      underline: const SizedBox(),
                      icon: const Icon(Icons.arrow_drop_down, color: Colors.grey),
                      items: const [
                        DropdownMenuItem(value: 'en', child: Text('English')),
                        DropdownMenuItem(value: 'ar', child: Text('العربية')),
                      ],
                      onChanged: (String? newLanguage) {
                        if (newLanguage != null) {
                          context.setLocale(Locale(newLanguage));
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                _buildSectionHeader('settings.section_support'.tr()),
                _buildNavigationItem(
                  icon: FontAwesomeIcons.circleQuestion,
                  label: 'settings.help_faq'.tr(),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const HelpFaqScreen(),
                      ),
                    );
                  },
                  iconColor: const Color(0xFF6366F1),
                ),
                _buildNavigationItem(
                  icon: FontAwesomeIcons.shieldHalved,
                  label: 'settings.terms_privacy'.tr(),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const TermsPrivacyScreen(),
                      ),
                    );
                  },
                  iconColor: const Color(0xFF64748B),
                ),
                const SizedBox(height: 32),
                Center(
                  child: Text(
                    'Learnoo v1.0.0',
                    style: TextStyle(color: Colors.grey[400], fontSize: 13),
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 180,
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
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned(
              left: 10,
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.2),
                ),
              ),
            ),
            Text(
              'settings.title'.tr(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: Color(0xFF1F2937),
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildToggleItem({
    required dynamic icon,
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
    required Color iconColor,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFF3F4F6))),
      ),
      child: ListTile(
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(child: FaIcon(icon is FaIconData ? icon : FontAwesomeIcons.circleQuestion, color: iconColor, size: 16)),
        ),
        title: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
        trailing: Switch(
          value: value,
          onChanged: onChanged,
          activeColor: const Color(0xFF263EE2),
        ),
      ),
    );
  }

  Widget _buildNavigationItem({
    required dynamic icon,
    required String label,
    String? trailing,
    required VoidCallback onTap,
    required Color iconColor,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFF3F4F6))),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(child: FaIcon(icon is FaIconData ? icon : FontAwesomeIcons.circleQuestion, color: iconColor, size: 16)),
        ),
        title: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (trailing != null)
              Text(
                trailing,
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
          ],
        ),
      ),
    );
  }
}
