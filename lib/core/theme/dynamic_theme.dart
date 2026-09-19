import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/feature_manager.dart';
import 'app_colors.dart';

/// Dynamic Theme Service - Creates ThemeData based on remote feature settings and manages ThemeMode
class DynamicThemeService extends ChangeNotifier {
  static final DynamicThemeService _instance = DynamicThemeService._internal();
  factory DynamicThemeService() => _instance;
  DynamicThemeService._internal();

  static const String _themeModeKey = 'app_theme_mode';
  final FeatureManager _featureManager = FeatureManager();
  bool _isInitialized = false;

  ThemeMode _themeMode = ThemeMode.system;
  ThemeData? _cachedTheme;
  ThemeData? _cachedDarkTheme;

  bool get isInitialized => _isInitialized;
  ThemeMode get themeMode => _themeMode;
  bool get isDarkMode => _themeMode == ThemeMode.dark;

  /// Initialize the theme service
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final savedMode = prefs.getString(_themeModeKey);
      if (savedMode == 'dark') {
        _themeMode = ThemeMode.dark;
      } else if (savedMode == 'light') {
        _themeMode = ThemeMode.light;
      } else {
        _themeMode = ThemeMode.system;
      }
    } catch (e) {
      debugPrint('Error loading saved theme mode: $e');
    }

    _featureManager.addListener(_onFeaturesChanged);
    _isInitialized = true;
    notifyListeners();
  }

  /// Change theme mode and persist to SharedPreferences
  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      String value = 'system';
      if (mode == ThemeMode.dark) value = 'dark';
      if (mode == ThemeMode.light) value = 'light';
      await prefs.setString(_themeModeKey, value);
    } catch (e) {
      debugPrint('Error saving theme mode: $e');
    }
  }

  /// Toggle dark mode on or off
  Future<void> toggleDarkMode(bool isDark) async {
    await setThemeMode(isDark ? ThemeMode.dark : ThemeMode.light);
  }

  void _onFeaturesChanged() {
    // Clear cached themes when features change
    _cachedTheme = null;
    _cachedDarkTheme = null;
    notifyListeners();
  }

  /// Get light theme based on remote settings
  ThemeData getLightTheme() {
    if (_cachedTheme != null) return _cachedTheme!;

    final primaryColor = _featureManager.primaryColor ?? AppColors.primaryBlue;
    final accentColor = _featureManager.accentColor ?? AppColors.accentBlue;
    final fontFamily = _featureManager.fontFamily;

    _cachedTheme = _buildTheme(
      brightness: Brightness.light,
      primaryColor: primaryColor,
      accentColor: accentColor,
      fontFamily: fontFamily,
    );

    return _cachedTheme!;
  }

  /// Get dark theme based on remote settings
  ThemeData getDarkTheme() {
    if (_cachedDarkTheme != null) return _cachedDarkTheme!;

    final primaryColor = _featureManager.primaryColor ?? AppColors.primaryBlue;
    final accentColor = _featureManager.accentColor ?? AppColors.accentBlue;
    final fontFamily = _featureManager.fontFamily;

    _cachedDarkTheme = _buildTheme(
      brightness: Brightness.dark,
      primaryColor: primaryColor,
      accentColor: accentColor,
      fontFamily: fontFamily,
    );

    return _cachedDarkTheme!;
  }

  /// Build theme data with given parameters
  ThemeData _buildTheme({
    required Brightness brightness,
    required Color primaryColor,
    required Color accentColor,
    required String fontFamily,
  }) {
    final isDark = brightness == Brightness.dark;

    // Dark mode colors
    const darkScaffoldBg = Color(0xFF13151B);
    const darkSurface = Color(0xFF1E212B);
    const darkInputFill = Color(0xFF262A36);
    const darkBorder = Color(0xFF383E52);
    const darkDivider = Color(0xFF2E3344);
    const darkTextPrimary = Color(0xFFF8FAFC);
    const darkTextSecondary = Color(0xFFCBD5E1);
    const darkTextMuted = Color(0xFF94A3B8);

    // Light mode colors
    const lightTextPrimary = Color(0xFF111827);
    const lightTextSecondary = Color(0xFF4B5563);
    const lightTextMuted = Color(0xFF9CA3AF);

    final fontName = fontFamily.isNotEmpty ? fontFamily : 'Inter';

    final defaultColorScheme = ColorScheme.fromSeed(
      seedColor: primaryColor,
      brightness: brightness,
      primary: primaryColor,
      secondary: accentColor,
      surface: isDark ? darkSurface : Colors.white,
      onSurface: isDark ? darkTextPrimary : lightTextPrimary,
    );

    final baseTextTheme = Typography.material2021(platform: TargetPlatform.android);
    final textThemeToUse = isDark ? baseTextTheme.white : baseTextTheme.black;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: defaultColorScheme,
      fontFamily: fontName,
      scaffoldBackgroundColor: isDark ? darkScaffoldBg : Colors.white,
      canvasColor: isDark ? darkSurface : Colors.white,
      cardColor: isDark ? darkSurface : Colors.white,
      dialogBackgroundColor: isDark ? darkSurface : Colors.white,
      dividerColor: isDark ? darkDivider : const Color(0xFFE5E7EB),
      dividerTheme: DividerThemeData(
        color: isDark ? darkDivider : const Color(0xFFE5E7EB),
        thickness: 1,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? darkSurface : primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: isDark ? darkSurface : primaryColor,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: isDark ? darkSurface : Colors.white,
        selectedItemColor: primaryColor,
        unselectedItemColor: isDark ? darkTextMuted : Colors.grey[600],
      ),
      cardTheme: CardThemeData(
        color: isDark ? darkSurface : Colors.white,
        elevation: isDark ? 0 : 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: isDark ? const BorderSide(color: darkDivider, width: 1) : BorderSide.none,
        ),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(isDark ? darkSurface : Colors.white),
          elevation: const WidgetStatePropertyAll(4),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: isDark ? darkBorder : const Color(0xFFE2E8F0)),
            ),
          ),
        ),
        textStyle: TextStyle(
          color: isDark ? darkTextPrimary : lightTextPrimary,
          fontFamily: fontName,
          fontSize: 14,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: isDark ? darkSurface : Colors.white,
        surfaceTintColor: Colors.transparent,
        textStyle: TextStyle(
          color: isDark ? darkTextPrimary : lightTextPrimary,
          fontFamily: fontName,
          fontSize: 14,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: isDark ? darkBorder : const Color(0xFFE2E8F0)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isDark ? darkSurface : Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        titleTextStyle: TextStyle(
          color: isDark ? darkTextPrimary : lightTextPrimary,
          fontSize: 18,
          fontWeight: FontWeight.bold,
          fontFamily: fontName,
        ),
        contentTextStyle: TextStyle(
          color: isDark ? darkTextSecondary : lightTextSecondary,
          fontSize: 14,
          fontFamily: fontName,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryColor,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? darkInputFill : Colors.white,
        hintStyle: TextStyle(
          color: isDark ? darkTextMuted : lightTextMuted,
          fontSize: 14,
          fontFamily: fontName,
        ),
        labelStyle: TextStyle(
          color: isDark ? darkTextSecondary : lightTextSecondary,
          fontFamily: fontName,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: isDark ? darkBorder : Colors.grey[300]!),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: isDark ? darkBorder : Colors.grey[300]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: primaryColor, width: 2),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: primaryColor,
      ),
      textTheme: textThemeToUse.apply(
        fontFamily: fontName,
        bodyColor: isDark ? darkTextPrimary : lightTextPrimary,
        displayColor: isDark ? darkTextPrimary : lightTextPrimary,
      ),
    );
  }

  /// Get current app title
  String get appTitle => _featureManager.platformName;

  /// Dispose the service
  @override
  void dispose() {
    _featureManager.removeListener(_onFeaturesChanged);
    super.dispose();
  }
}

/// Animated Theme Wrapper that reacts to feature and theme mode changes
class DynamicThemeWrapper extends StatefulWidget {
  final Widget child;

  const DynamicThemeWrapper({super.key, required this.child});

  @override
  State<DynamicThemeWrapper> createState() => _DynamicThemeWrapperState();
}

class _DynamicThemeWrapperState extends State<DynamicThemeWrapper> {
  final DynamicThemeService _themeService = DynamicThemeService();

  @override
  void initState() {
    super.initState();
    _themeService.addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    _themeService.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = _themeService.isDarkMode ||
        (_themeService.themeMode == ThemeMode.system &&
            MediaQuery.platformBrightnessOf(context) == Brightness.dark);

    return AnimatedTheme(
      data: isDark ? _themeService.getDarkTheme() : _themeService.getLightTheme(),
      duration: const Duration(milliseconds: 300),
      child: widget.child,
    );
  }
}
