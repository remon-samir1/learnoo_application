import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../network/api_constants.dart';
import 'feature_manager.dart';

/// Service to fetch and manage features from the API
class FeatureService {
  static final FeatureService _instance = FeatureService._internal();
  factory FeatureService() => _instance;
  FeatureService._internal();

  final _storage = const FlutterSecureStorage();
  final FeatureManager _featureManager = FeatureManager();

  bool _isLoading = false;
  String? _lastError;

  // Getters
  bool get isLoading => _isLoading;
  String? get lastError => _lastError;
  FeatureManager get featureManager => _featureManager;

  /// Initialize the service and load cached features
  Future<void> initialize() async {
    await _featureManager.initialize();
  }

  /// Fetch features from the API
  /// This requires authentication, so it should be called after login
  /// or using a token if available
  Future<bool> fetchFeatures({String? token}) async {
    if (_isLoading) return false;

    _isLoading = true;
    _lastError = null;

    try {
      // Use provided token or try to get from storage
      final authToken = token ?? await _storage.read(key: 'auth_token');

      final url = Uri.parse('${ApiConstants.baseUrl}/v1/feature');

      final headers = {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

      // Add authorization if token is available
      if (authToken != null && authToken.isNotEmpty) {
        headers['Authorization'] = 'Bearer $authToken';
      }

      final response = await http.get(url, headers: headers);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> features = data['data'] ?? [];

        if (features.isNotEmpty) {
          await _featureManager.processApiResponse(features);
          debugPrint('Successfully fetched ${features.length} features');
          _isLoading = false;
          return true;
        }
      } else if (response.statusCode == 401) {
        _lastError = 'Authentication required to fetch features';
        debugPrint('Feature API requires authentication');
      } else {
        _lastError = 'Failed to fetch features: ${response.statusCode}';
        debugPrint('Feature API error: ${response.statusCode}');
      }
    } catch (e) {
      _lastError = 'Network error: $e';
      debugPrint('Error fetching features: $e');
    }

    _isLoading = false;
    return false;
  }

  /// Fetch features with retry logic
  Future<bool> fetchFeaturesWithRetry({
    String? token,
    int maxRetries = 3,
    Duration delay = const Duration(seconds: 2),
  }) async {
    for (int i = 0; i < maxRetries; i++) {
      final success = await fetchFeatures(token: token);
      if (success) return true;

      if (i < maxRetries - 1) {
        await Future.delayed(delay * (i + 1));
      }
    }
    return false;
  }

  /// Refresh features from API (force update)
  Future<bool> refresh() async {
    return await fetchFeatures();
  }

  /// Get features by group
  Map<String, dynamic> getFeaturesByGroup(String group) {
    final features = _featureManager.getFeaturesByGroup(group);
    return features.map((key, feature) => MapEntry(key, feature.value));
  }

  /// Check if features need refresh (e.g., older than 1 hour)
  bool needsRefresh({Duration maxAge = const Duration(hours: 1)}) {
    final lastUpdate = _featureManager.lastUpdate;
    if (lastUpdate == null) return true;
    return DateTime.now().difference(lastUpdate) > maxAge;
  }

  /// Clear all cached features
  Future<void> clearCache() async {
    await _featureManager.clear();
  }
}
