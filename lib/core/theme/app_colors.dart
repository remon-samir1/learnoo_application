import 'package:flutter/material.dart';

class AppColors {
  // Main Primary Colors
  static const Color primaryBlue = Color(0xFF2137D6);
  static const Color accentBlue = Color(0xFF4A68F6);
  static const Color lightBlue = Color(0xFF7A92F8);
  
  // Backgrounds
  static const Color backgroundWhite = Color.fromARGB(255, 255, 255, 251);
  static const Color splashOverlay = Color(0x992D46D1); // Semi-transparent blue for splash background
  
  // Form Colors
  static const Color inputFill = Colors.white;
  static const Color inputBorder = Color.fromARGB(255, 238, 238, 238);
  static const Color inputHint = Color(0xFF9CA3AF);
  static const Color labelGray = Color(0xFF374151);
  
  // Text Colors
  static const Color textWhite = Colors.white;
  static const Color textGray = Color(0xFF6B7280);
  static const Color textDark = Color(0xFF111827);
  
  // Subject Colors
  static const Color accountingBg = Color(0xFFF0F2FF);
  static const Color accountingText = Color(0xFF5A75FF);
  static const Color businessBg = Color(0xFFF0FFF6);
  static const Color businessText = Color(0xFF27AE60);
  static const Color economicsBg = Color(0xFFFFF0F0);
  static const Color economicsText = Color(0xFFFF4B4B);
  static const Color financeBg = Color(0xFFFFF9F0);
  static const Color financeText = Color(0xFFF2994A);

  // Dynamic subject colors list
  static const List<Map<String, Color>> subjectColors = [
    {'bg': Color(0xFFF0F2FF), 'text': Color(0xFF5A75FF)},
    {'bg': Color(0xFFF0FFF6), 'text': Color(0xFF27AE60)},
    {'bg': Color(0xFFFFF0F0), 'text': Color(0xFFFF4B4B)},
    {'bg': Color(0xFFFFF9F0), 'text': Color(0xFFF2994A)},
    {'bg': Color(0xFFE6F7FF), 'text': Color(0xFF1890FF)},
    {'bg': Color(0xFFF6F0FF), 'text': Color(0xFF722ED1)},
    {'bg': Color(0xFFFFF0E6), 'text': Color(0xFFFA8C16)},
    {'bg': Color(0xFFE6FFFB), 'text': Color(0xFF13C2C2)},
  ];

  // Status Colors
  static const Color liveBg = Color(0xFFFFF0F0);
  static const Color liveText = Color(0xFFFF4B4B);
  static const Color joinLiveGreen = Color(0xFF2DBC77);

  // Background Gradients
  static const List<Color> bgGradients = [
    Color(0xFFFFF5F5), // Top Left (Pinkish)
    Color(0xFFF5F7FF), // Top Right (Bluish)
    Color(0xFFFFFFF5), // Bottom (Yellowish)
  ];
  
  // Gradients
  static const LinearGradient mainGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFF3451E5),
      Color(0xFF5A75FF),
      Color(0xFF7B93FF),
    ],
  );

  static const LinearGradient logoGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF8BA1FF),
      Color(0xFF5A75FF),
    ],
  );
}
