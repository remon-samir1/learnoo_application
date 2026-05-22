import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:learnoo/features/exams/presentation/screens/exams_list_screen.dart';
import 'package:learnoo/features/home/presentation/screens/home_screen.dart';
import 'package:learnoo/features/home/presentation/screens/my_courses_screen.dart';
import 'package:learnoo/features/community/presentation/screens/community_screen.dart';
import 'package:learnoo/features/course_content/presentation/screens/live_sessions_screen.dart';
import 'package:learnoo/core/services/feature_service.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  final List<Widget> _screens = [
    const HomeScreen(),
    const MyCoursesScreen(),
    const CommunityScreen(),
    const LiveSessionsScreen(),
    const ExamsListScreen(),
  ];

  @override
  void initState() {
    super.initState();
    // Fetch features after user is authenticated and navigating to MainScreen
    FeatureService().fetchFeatures().then((success) {
      if (success) {
        debugPrint('Features refreshed from API in MainScreen');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_selectedIndex],
      bottomNavigationBar: Container(
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
          currentIndex: _selectedIndex,
          onTap: (index) => setState(() => _selectedIndex = index),
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.white,
          selectedItemColor: const Color(0xFF5A75FF),
          unselectedItemColor: const Color(0xFF9CA3AF),
          selectedFontSize: 11,
          unselectedFontSize: 11,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w400),
          elevation: 0,
          items: [
            _buildNavItem(FontAwesomeIcons.house, FontAwesomeIcons.house, 'home.nav_home'.tr(), 0),
            _buildNavItem(FontAwesomeIcons.bookOpen, FontAwesomeIcons.bookOpen, 'home.nav_courses'.tr(), 1),
            _buildNavItem(FontAwesomeIcons.users, FontAwesomeIcons.users, 'home.nav_community'.tr(), 2),
            _buildNavItem(FontAwesomeIcons.video, FontAwesomeIcons.video, 'home.nav_live'.tr(), 3),
            _buildNavItem(FontAwesomeIcons.fileSignature, FontAwesomeIcons.fileSignature, 'home.nav_exams'.tr(), 4),
          ],
        ),
      ),
    );
  }

  BottomNavigationBarItem _buildNavItem(
    FaIconData icon,
    FaIconData activeIcon,
    String label,
    int index,
  ) {
    final isSelected = _selectedIndex == index;
    return BottomNavigationBarItem(
      icon: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: FaIcon(isSelected ? activeIcon : icon, size: 20),
      ),
      activeIcon: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FaIcon(activeIcon, color: const Color(0xFF5A75FF), size: 20),
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
}
