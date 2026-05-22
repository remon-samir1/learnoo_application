import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:learnoo/features/exams/presentation/screens/exams_list_screen.dart';
import 'package:learnoo/features/home/presentation/screens/home_screen.dart';
import 'package:learnoo/features/home/presentation/screens/my_courses_screen.dart';
import 'package:learnoo/features/community/presentation/screens/community_screen.dart';
import 'package:learnoo/features/course_content/presentation/screens/live_sessions_screen.dart';
import 'package:learnoo/features/home/presentation/screens/main_screen.dart';

class AppBottomNavigationBar extends StatelessWidget {
  const AppBottomNavigationBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        selectedItemColor: const Color(0xFF5A75FF),
        unselectedItemColor: const Color(0xFF9CA3AF),
        selectedFontSize: 11,
        unselectedFontSize: 11,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w400),
        elevation: 0,
        onTap: (index) => _navigateToScreen(context, index),
        items: [
          _buildNavItem(FontAwesomeIcons.house, 'home.nav_home'.tr()),
          _buildNavItem(FontAwesomeIcons.bookOpen, 'home.nav_courses'.tr()),
          _buildNavItem(FontAwesomeIcons.users, 'home.nav_community'.tr()),
          _buildNavItem(FontAwesomeIcons.video, 'home.nav_live'.tr()),
          _buildNavItem(FontAwesomeIcons.fileSignature, 'home.nav_exams'.tr()),
        ],
      ),
    );
  }

  BottomNavigationBarItem _buildNavItem(FaIconData icon, String label) {
    return BottomNavigationBarItem(
      icon: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: FaIcon(icon, size: 20),
      ),
      activeIcon: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FaIcon(icon, color: const Color(0xFF5A75FF), size: 20),
            const SizedBox(height: 4),
            Container(
              width: 4,
              height: 4,
              decoration: const BoxDecoration(
                color: Color(0xFF5A75FF),
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      ),
      label: label,
    );
  }

  void _navigateToScreen(BuildContext context, int index) {
    switch (index) {
      case 0:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const MainScreen()),
        );
        break;
      case 1:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const MyCoursesScreen()),
        );
        break;
      case 2:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const CommunityScreen()),
        );
        break;
      case 3:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const LiveSessionsScreen()),
        );
        break;
      case 4:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const ExamsListScreen()),
        );
        break;
    }
  }
}
