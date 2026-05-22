import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/feature_manager.dart';
import 'app_colors.dart';

/// Dynamic Theme Service - Creates ThemeData based on remote feature settings
class DynamicThemeService extends ChangeNotifier {
  static final DynamicThemeService _instance = DynamicThemeService._internal();
  factory DynamicThemeService() => _instance;
  DynamicThemeService._internal();

  final FeatureManager _featureManager = FeatureManager();
  bool _isInitialized = false;

  ThemeData? _cachedTheme;
  ThemeData? _cachedDarkTheme;

  bool get isInitialized => _isInitialized;

  /// Initialize the theme service
  Future<void> initialize() async {
    if (_isInitialized) return;

    _featureManager.addListener(_onFeaturesChanged);
    _isInitialized = true;
    notifyListeners();
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
    final defaultColorScheme = ColorScheme.fromSeed(
      seedColor: primaryColor,
      brightness: brightness,
      primary: primaryColor,
      secondary: accentColor,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: defaultColorScheme,
      fontFamily: fontFamily.isNotEmpty ? fontFamily : 'Inter',
      scaffoldBackgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? const Color(0xFF2D2D2D) : primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: isDark ? const Color(0xFF2D2D2D) : primaryColor,
          statusBarIconBrightness: isDark ? Brightness.light : Brightness.light,
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: isDark ? const Color(0xFF2D2D2D) : Colors.white,
        selectedItemColor: primaryColor,
        unselectedItemColor: isDark ? Colors.grey : Colors.grey[600],
      ),
      cardTheme: CardThemeData(
        color: isDark ? const Color(0xFF2D2D2D) : Colors.white,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
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
        fillColor: isDark ? const Color(0xFF3D3D3D) : Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: isDark ? Colors.grey[700]! : Colors.grey[300]!),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: isDark ? Colors.grey[700]! : Colors.grey[300]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: primaryColor, width: 2),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: primaryColor,
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

/// Animated Theme Wrapper that reacts to feature changes
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
    return AnimatedTheme(
      data: _themeService.getLightTheme(),
      duration: const Duration(milliseconds: 300),
      child: widget.child,
    );
  }
}
