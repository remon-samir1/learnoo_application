import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/watermark_config.dart';

/// Feature model representing a single feature flag or setting
class Feature {
  final String id;
  final String key;
  final String value;
  final String group;
  final String type;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Feature({
    required this.id,
    required this.key,
    required this.value,
    required this.group,
    required this.type,
    this.createdAt,
    this.updatedAt,
  });

  factory Feature.fromJson(Map<String, dynamic> json) {
    final attributes = json['attributes'] ?? {};
    return Feature(
      id: json['id']?.toString() ?? '',
      key: attributes['key']?.toString() ?? '',
      value: attributes['value']?.toString() ?? '',
      group: attributes['group']?.toString() ?? 'general',
      type: attributes['type']?.toString() ?? 'text',
      createdAt: attributes['created_at'] != null
          ? DateTime.tryParse(attributes['created_at'])
          : null,
      updatedAt: attributes['updated_at'] != null
          ? DateTime.tryParse(attributes['updated_at'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'attributes': {
        'key': key,
        'value': value,
        'group': group,
        'type': type,
        'created_at': createdAt?.toIso8601String(),
        'updated_at': updatedAt?.toIso8601String(),
      },
    };
  }

  /// Parse value as boolean
  bool get boolValue {
    final lowerValue = value.toLowerCase().trim();
    return lowerValue == 'true' || lowerValue == '1' || lowerValue == 'yes';
  }

  /// Parse value as integer
  int get intValue => int.tryParse(value) ?? 0;

  /// Parse value as double
  double get doubleValue => double.tryParse(value) ?? 0.0;

  /// Get value as string
  String get stringValue => value;

  /// Parse value as color
  Color? get colorValue {
    if (value.isEmpty) return null;
    try {
      if (value.startsWith('#')) {
        final hex = value.replaceFirst('#', '');
        if (hex.length == 6) {
          return Color(int.parse('FF$hex', radix: 16));
        } else if (hex.length == 8) {
          return Color(int.parse(hex, radix: 16));
        }
      }
    } catch (e) {
      debugPrint('Failed to parse color: $value');
    }
    return null;
  }
}

/// Feature Manager - Centralized management of feature flags and remote settings
/// Uses ChangeNotifier for reactive UI updates
class FeatureManager extends ChangeNotifier {
  static final FeatureManager _instance = FeatureManager._internal();
  factory FeatureManager() => _instance;
  FeatureManager._internal();

  // Storage keys
  static const String _featuresCacheKey = 'cached_features';
  static const String _lastUpdateKey = 'features_last_update';

  // Internal storage
  final Map<String, Feature> _features = {};
  SharedPreferences? _prefs;
  bool _isInitialized = false;
  DateTime? _lastUpdate;

  // Stream controller for feature changes
  final StreamController<String> _featureChangesController =
      StreamController<String>.broadcast();

  // Getters
  bool get isInitialized => _isInitialized;
  DateTime? get lastUpdate => _lastUpdate;
  Map<String, Feature> get allFeatures => Map.unmodifiable(_features);
  Stream<String> get featureChanges => _featureChangesController.stream;

  /// Initialize FeatureManager and load cached features
  Future<void> initialize() async {
    if (_isInitialized) return;

    _prefs = await SharedPreferences.getInstance();
    await _loadCachedFeatures();
    _isInitialized = true;
    notifyListeners();
  }

  /// Load features from cache
  Future<void> _loadCachedFeatures() async {
    try {
      final cachedData = _prefs?.getString(_featuresCacheKey);
      final lastUpdateStr = _prefs?.getString(_lastUpdateKey);

      if (lastUpdateStr != null) {
        _lastUpdate = DateTime.tryParse(lastUpdateStr);
      }

      if (cachedData != null && cachedData.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(cachedData);
        _features.clear();

        for (final item in decoded) {
          final feature = Feature.fromJson(item);
          if (feature.key.isNotEmpty) {
            _features[feature.key] = feature;
          }
        }

        debugPrint('Loaded ${_features.length} features from cache');
      }
    } catch (e) {
      debugPrint('Error loading cached features: $e');
    }
  }

  /// Save features to cache
  Future<void> _saveToCache() async {
    try {
      final List<Map<String, dynamic>> data =
          _features.values.map((f) => f.toJson()).toList();
      final encoded = jsonEncode(data);
      await _prefs?.setString(_featuresCacheKey, encoded);
      await _prefs?.setString(_lastUpdateKey, DateTime.now().toIso8601String());
    } catch (e) {
      debugPrint('Error saving features to cache: $e');
    }
  }

  /// Process API response and update features
  /// Handles duplicate keys by prioritizing feature_* over enable_*
  Future<void> processApiResponse(List<dynamic> data) async {
    final Map<String, Feature> newFeatures = {};
    final Map<String, List<Feature>> duplicateKeys = {};

    // Parse all features from response
    for (final item in data) {
      try {
        final feature = Feature.fromJson(item);
        if (feature.key.isNotEmpty) {
          if (!duplicateKeys.containsKey(feature.key)) {
            duplicateKeys[feature.key] = [];
          }
          duplicateKeys[feature.key]!.add(feature);
        }
      } catch (e) {
        debugPrint('Error parsing feature: $e');
      }
    }

    // Handle duplicates - prioritize feature_* keys
    for (final entry in duplicateKeys.entries) {
      final key = entry.key;
      final features = entry.value;

      if (features.length == 1) {
        newFeatures[key] = features.first;
      } else {
        // Find feature_* variant
        Feature? prioritizedFeature;
        for (final f in features) {
          if (f.key.startsWith('feature_')) {
            prioritizedFeature = f;
            break;
          }
        }
        // If no feature_* found, look for enable_*
        if (prioritizedFeature == null) {
          for (final f in features) {
            if (f.key.startsWith('enable_')) {
              prioritizedFeature = f;
              break;
            }
          }
        }
        // Fallback to first feature
        newFeatures[key] = prioritizedFeature ?? features.first;
      }
    }

    // Check for changes and notify
    final Set<String> changedKeys = {};
    for (final entry in newFeatures.entries) {
      final key = entry.key;
      final newFeature = entry.value;
      final oldFeature = _features[key];

      if (oldFeature == null || oldFeature.value != newFeature.value) {
        changedKeys.add(key);
        _featureChangesController.add(key);
      }
    }

    // Also check for removed features
    for (final oldKey in _features.keys) {
      if (!newFeatures.containsKey(oldKey)) {
        changedKeys.add(oldKey);
        _featureChangesController.add(oldKey);
      }
    }

    // Update storage
    _features.clear();
    _features.addAll(newFeatures);
    _lastUpdate = DateTime.now();

    // Save to cache
    await _saveToCache();

    // Notify listeners if there were changes
    if (changedKeys.isNotEmpty) {
      debugPrint('Features updated: ${changedKeys.length} changes');
      notifyListeners();
    }
  }

  /// Check if a feature is enabled (boolean)
  bool isEnabled(String key, {bool defaultValue = false}) {
    final feature = _features[key];
    if (feature == null) return defaultValue;
    return feature.boolValue;
  }

  /// Get string value
  String getString(String key, {String defaultValue = ''}) {
    final feature = _features[key];
    if (feature == null) return defaultValue;
    return feature.stringValue;
  }

  /// Get integer value
  int getInt(String key, {int defaultValue = 0}) {
    final feature = _features[key];
    if (feature == null) return defaultValue;
    return feature.intValue;
  }

  /// Get double value
  double getDouble(String key, {double defaultValue = 0.0}) {
    final feature = _features[key];
    if (feature == null) return defaultValue;
    return feature.doubleValue;
  }

  /// Get color value
  Color? getColor(String key) {
    final feature = _features[key];
    if (feature == null) return null;
    return feature.colorValue;
  }

  /// Get feature by key
  Feature? getFeature(String key) => _features[key];

  /// Check if feature exists
  bool hasFeature(String key) => _features.containsKey(key);

  /// Get all features by group
  Map<String, Feature> getFeaturesByGroup(String group) {
    return Map.fromEntries(
      _features.entries.where((e) => e.value.group == group),
    );
  }

  /// Get all feature keys
  Iterable<String> get featureKeys => _features.keys;

  /// Clear all features
  Future<void> clear() async {
    _features.clear();
    await _prefs?.remove(_featuresCacheKey);
    await _prefs?.remove(_lastUpdateKey);
    notifyListeners();
  }

  /// Feature-specific helpers

  /// OTP Verification enabled
  bool get isOtpVerificationEnabled =>
      isEnabled('feature_otp_verification') ||
      isEnabled('enable_otp_verification');

  /// Login without OTP allowed
  bool get isLoginWithoutOtpAllowed =>
      isEnabled('feature_login_without_otp') ||
      isEnabled('allow_login_without_otp');

  /// Purchases enabled
  bool get isPurchasesEnabled =>
      isEnabled('feature_library_purchases') ||
      isEnabled('enable_purchases');

  /// Electronic library enabled
  bool get isElectronicLibraryEnabled =>
      isEnabled('feature_electronic_library') ||
      isEnabled('enable_electronic_library');

  /// Continue watching enabled
  bool get isContinueWatchingEnabled =>
      isEnabled('feature_continue_watching') ||
      isEnabled('enable_continue_watching');

  /// Profile editing enabled
  bool get isProfileEditingEnabled =>
      isEnabled('feature_profile_editing') ||
      isEnabled('enable_profile_editing');

  /// Block screenshots enabled
  bool get isBlockScreenshotsEnabled =>
      isEnabled('feature_block_screenshots') ||
      isEnabled('enable_block_screenshots');

  /// Screen share max resolution enabled
  bool get isScreenShareMaxResolutionEnabled =>
      isEnabled('feature_screen_share_max_resolution') ||
      isEnabled('enable_screen_share_max_resolution');

  /// App settings
  String get platformName => getString('platform_name', defaultValue: 'Learnoo');
  String get tagline => getString('tagline', defaultValue: 'academic_journey');
  String get supportEmail => getString('support_email', defaultValue: 'support@example.com');
  String get logoUrl => getString('logo');
  String get fontFamily => getString('font_family', defaultValue: 'Inter');

  /// Theme colors
  Color? get primaryColor => getColor('primary_color');
  Color? get accentColor => getColor('accent_color');

  /// Buckets to try, in order, for a given content type.
  ///
  /// Port of `resolveEnabledWatermarkBucket`: a chapter falls back to the
  /// video bucket and then to exams, so a platform that only configured
  /// `watermark_videos_*` still watermarks chapter playback exactly as the web
  /// does. Any other content type is used on its own.
  static List<String> _watermarkBucketOrder(String type) {
    switch (type) {
      case 'chapters':
        return const ['chapters', 'videos', 'exams'];
      case 'videos':
        return const ['videos', 'chapters', 'exams'];
      default:
        return [type];
    }
  }

  /// The first bucket in [_watermarkBucketOrder] whose watermark is enabled.
  ///
  /// Returns the primary bucket's (disabled) config when none is enabled, so
  /// callers can keep reading `enabled` rather than handling null.
  WatermarkConfig resolveWatermarkConfig(String type) {
    for (final bucket in _watermarkBucketOrder(type)) {
      final config = getWatermarkConfig(bucket);
      if (config.enabled) return config;
    }
    return getWatermarkConfig(type);
  }

  /// Watermark settings helpers
  /// Handles API keys like: feature_watermark_pdfs_enabled, enable_watermark_videos_enabled
  WatermarkConfig getWatermarkConfig(String type) {
    final apiType = _mapTypeToApi(type);

    final bool enabled = _isWatermarkEnabled(type, apiType);
    // Defaults below match DEFAULT_WATERMARK_CONFIG on the web, so a platform
    // that has not set a key renders the same on both clients.
    final String text = _getWatermarkSetting('text', type, apiType, defaultValue: 'Learnoo');
    final bool useStudentCode = _isWatermarkEnabled(type, apiType, suffix: 'use_student_code');
    final bool usePhoneNumber = _isWatermarkEnabled(type, apiType, suffix: 'use_phone_number');
    final String positionStr = _getWatermarkSetting('position', type, apiType, defaultValue: 'full');
    final double opacity = (double.tryParse(_getWatermarkSetting('opacity', type, apiType, defaultValue: '10')) ?? 10) / 100.0;
    final double rotationDegrees = double.tryParse(_getWatermarkSetting('rotation', type, apiType, defaultValue: '-12')) ?? -12.0;
    final String size = _getWatermarkSetting('size', type, apiType, defaultValue: 'medium');

    final bool dynamicPosition = _isWatermarkEnabled(type, apiType, suffix: 'dynamic_position');
    final int dynamicInterval = int.tryParse(_getWatermarkSetting('dynamic_interval', type, apiType, defaultValue: '2')) ?? 2;
    final bool randomCoordinates = _isWatermarkEnabled(type, apiType, suffix: 'random_coordinates');
    
    final String animationStyleStr = _getWatermarkSetting('animation_style', type, apiType, defaultValue: 'glide');
    final String easingTypeStr = _getWatermarkSetting('easing_type', type, apiType, defaultValue: 'easeInOut');
    final String movementPattern = _getWatermarkSetting('movement_pattern', type, apiType, defaultValue: 'random');

    final bool voiceEnabled = _isWatermarkEnabled(type, apiType, suffix: 'voice_enabled');
    final int voiceInterval = int.tryParse(_getWatermarkSetting('voice_interval', type, apiType, defaultValue: '5')) ?? 5;

    // Get color from API
    final Color? color = getColor('watermark_${apiType}_color');

    return WatermarkConfig(
      enabled: enabled,
      text: text,
      useStudentCode: useStudentCode,
      usePhoneNumber: usePhoneNumber,
      position: WatermarkConfig.parsePosition(positionStr),
      opacity: opacity,
      rotation: rotationDegrees * (math.pi / 180.0), // convert to radians
      size: size,
      dynamicPosition: dynamicPosition,
      dynamicInterval: dynamicInterval,
      randomCoordinates: randomCoordinates,
      animationStyle: WatermarkConfig.parseAnimationStyle(animationStyleStr),
      color: color,
      easingType: WatermarkConfig.parseEasingType(easingTypeStr),
      voiceEnabled: voiceEnabled,
      voiceInterval: voiceInterval,
      movementPattern: movementPattern,
    );
  }

  /// Map internal type names to API type names
  String _mapTypeToApi(String type) {
    // The API uses the exact keys provided in the JSON
    // e.g., watermark_chapters_enabled, watermark_files_enabled, etc.
    // So we don't need much mapping if the caller uses the right enum.
    return type;
  }

  /// Check if watermark is enabled with various key patterns
  bool _isWatermarkEnabled(String type, String apiType, {String suffix = 'enabled'}) {
    // Try different key patterns
    final patterns = [
      'feature_watermark_${apiType}_$suffix',
      'enable_watermark_${apiType}_$suffix',
      'watermark_${apiType}_$suffix',
      'feature_watermark_${type}_$suffix',
      'enable_watermark_${type}_$suffix',
      'watermark_${type}_$suffix',
    ];

    for (final key in patterns) {
      if (hasFeature(key)) {
        return isEnabled(key);
      }
    }

    // Default: disabled
    return false;
  }

  /// Get watermark setting with various key patterns
  String _getWatermarkSetting(String setting, String type, String apiType, {required String defaultValue}) {
    // Try different key patterns
    final patterns = [
      'feature_watermark_${apiType}_$setting',
      'enable_watermark_${apiType}_$setting',
      'watermark_${apiType}_$setting',
      'feature_watermark_${type}_$setting',
      'enable_watermark_${type}_$setting',
      'watermark_${type}_$setting',
    ];

    for (final key in patterns) {
      if (hasFeature(key)) {
        return getString(key, defaultValue: defaultValue);
      }
    }

    return defaultValue;
  }

  @override
  void dispose() {
    _featureChangesController.close();
    super.dispose();
  }
}
