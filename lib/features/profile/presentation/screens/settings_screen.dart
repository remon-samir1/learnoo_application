import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../../../core/theme/dynamic_theme.dart';
import 'change_password_screen.dart';
import 'help_faq_screen.dart';
import 'terms_privacy_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final DynamicThemeService _themeService = DynamicThemeService();
  bool _notificationsEnabled = true;
  bool _darkModeEnabled = false;
  bool _autoDownloadEnabled = false;

  @override
  void initState() {
    super.initState();
    _darkModeEnabled = _themeService.isDarkMode;
    _themeService.addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    _themeService.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() {
    if (mounted) {
      setState(() {
        _darkModeEnabled = _themeService.isDarkMode;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF13151B) : const Color(0xFFFAFBFF),
      body: Column(
        children: [
          _buildHeader(context),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _buildSectionHeader('settings.section_preferences'.tr(), isDark),
                _buildToggleItem(
                  icon: FontAwesomeIcons.bell,
                  label: 'settings.notifications'.tr(),
                  value: _notificationsEnabled,
                  onChanged: (val) => setState(() => _notificationsEnabled = val),
                  iconColor: const Color(0xFF3B82F6),
                  isDark: isDark,
                ),
                _buildToggleItem(
                  icon: FontAwesomeIcons.moon,
                  label: 'settings.dark_mode'.tr(),
                  value: _darkModeEnabled,
                  onChanged: (val) async {
                    setState(() => _darkModeEnabled = val);
                    await _themeService.toggleDarkMode(val);
                  },
                  iconColor: const Color(0xFF8B5CF6),
                  isDark: isDark,
                ),
                _buildToggleItem(
                  icon: FontAwesomeIcons.globe,
                  label: 'settings.auto_download'.tr(),
                  value: _autoDownloadEnabled,
                  onChanged: (val) => setState(() => _autoDownloadEnabled = val),
                  iconColor: const Color(0xFF10B981),
                  isDark: isDark,
                ),
                const SizedBox(height: 24),
                _buildSectionHeader('settings.section_account'.tr(), isDark),
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
                  isDark: isDark,
                ),
                Container(
                  margin: const EdgeInsets.only(bottom: 2),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E212B) : Colors.white,
                    border: Border(
                      bottom: BorderSide(
                        color: isDark ? const Color(0xFF2E3344) : const Color(0xFFF3F4F6),
                      ),
                    ),
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
                    title: Text(
                      'settings.language'.tr(),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF1F2937),
                      ),
                    ),
                    trailing: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: context.locale.languageCode,
                        dropdownColor: isDark ? const Color(0xFF1E212B) : Colors.white,
                        icon: Icon(
                          Icons.arrow_drop_down,
                          color: isDark ? const Color(0xFFCBD5E1) : Colors.grey,
                        ),
                        items: [
                          DropdownMenuItem(
                            value: 'en',
                            child: Text(
                              'English',
                              style: TextStyle(
                                fontSize: 14,
                                color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF1F2937),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'ar',
                            child: Text(
                              'العربية',
                              style: TextStyle(
                                fontSize: 14,
                                color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF1F2937),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                        onChanged: (String? newLanguage) {
                          if (newLanguage != null) {
                            context.setLocale(Locale(newLanguage));
                          }
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                _buildSectionHeader('settings.section_support'.tr(), isDark),
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
                  isDark: isDark,
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
                  isDark: isDark,
                ),
                const SizedBox(height: 32),
                Center(
                  child: Text(
                    'Learnoo v1.0.0',
                    style: TextStyle(
                      color: isDark ? const Color(0xFF64748B) : Colors.grey[400],
                      fontSize: 13,
                    ),
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
    final textDir = Directionality.of(context);

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
            Positioned.directional(
              textDirection: textDir,
              start: 10,
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

  Widget _buildSectionHeader(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, right: 4, bottom: 12),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF1F2937),
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
    required bool isDark,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E212B) : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xFF2E3344) : const Color(0xFFF3F4F6),
          ),
        ),
      ),
      child: ListTile(
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: FaIcon(
              icon is FaIconData ? icon : FontAwesomeIcons.circleQuestion,
              color: iconColor,
              size: 16,
            ),
          ),
        ),
        title: Text(
          label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF1F2937),
          ),
        ),
        trailing: Switch(
          value: value,
          onChanged: onChanged,
          activeColor: const Color(0xFF5A75FF),
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
    required bool isDark,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E212B) : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xFF2E3344) : const Color(0xFFF3F4F6),
          ),
        ),
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
          child: Center(
            child: FaIcon(
              icon is FaIconData ? icon : FontAwesomeIcons.circleQuestion,
              color: iconColor,
              size: 16,
            ),
          ),
        ),
        title: Text(
          label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF1F2937),
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (trailing != null)
              Text(
                trailing,
                style: TextStyle(
                  color: isDark ? const Color(0xFF94A3B8) : Colors.grey,
                  fontSize: 13,
                ),
              ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right,
              color: isDark ? const Color(0xFF64748B) : Colors.grey,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
