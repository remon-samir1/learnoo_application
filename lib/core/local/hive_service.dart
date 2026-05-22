import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import 'hive_boxes.dart';

/// Service to initialize and manage Hive local database
class HiveService {
  static final HiveService _instance = HiveService._internal();
  factory HiveService() => _instance;
  HiveService._internal();

  bool _initialized = false;

  /// Initialize Hive and open all required boxes
  Future<void> initialize() async {
    if (_initialized) return;

    await Hive.initFlutter();

    // Open all required boxes
    await Hive.openBox<dynamic>(HiveBoxes.courses);
    await Hive.openBox<dynamic>(HiveBoxes.chapters);
    await Hive.openBox<dynamic>(HiveBoxes.lectures);
    await Hive.openBox<dynamic>(HiveBoxes.pendingActions);
    await Hive.openBox<dynamic>(HiveBoxes.userProfile);
    await Hive.openBox<dynamic>(HiveBoxes.appState);
    await Hive.openBox<dynamic>(HiveBoxes.comments);
    await Hive.openBox<dynamic>(HiveBoxes.progress);

    _initialized = true;
  }

  /// Get a box by name
  Box<dynamic> getBox(String name) {
    if (!_initialized) {
      throw StateError('HiveService not initialized. Call initialize() first.');
    }
    return Hive.box<dynamic>(name);
  }

  /// Clear all cached data (useful for logout)
  Future<void> clearAllCache() async {
    await getBox(HiveBoxes.courses).clear();
    await getBox(HiveBoxes.chapters).clear();
    await getBox(HiveBoxes.lectures).clear();
    await getBox(HiveBoxes.comments).clear();
    await getBox(HiveBoxes.progress).clear();
    await getBox(HiveBoxes.userProfile).clear();
  }

  /// Clear only pending actions
  Future<void> clearPendingActions() async {
    await getBox(HiveBoxes.pendingActions).clear();
  }

  /// Store data with timestamp for cache validation
  Future<void> storeWithTimestamp(String boxName, String key, dynamic data) async {
    final box = getBox(boxName);
    final cacheEntry = {
      'data': data,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    await box.put(key, jsonEncode(cacheEntry));
  }

  /// Retrieve data with timestamp info
  Map<String, dynamic>? retrieveWithTimestamp(String boxName, String key) {
    final box = getBox(boxName);
    final cached = box.get(key);
    if (cached == null) return null;

    try {
      final decoded = jsonDecode(cached.toString()) as Map<String, dynamic>;
      return {
        'data': decoded['data'],
        'timestamp': decoded['timestamp'],
        'ageMs': DateTime.now().millisecondsSinceEpoch - (decoded['timestamp'] as int),
      };
    } catch (e) {
      return null;
    }
  }

  /// Check if cached data is still valid (not expired)
  bool isCacheValid(String boxName, String key, {Duration maxAge = const Duration(hours: 24)}) {
    final cached = retrieveWithTimestamp(boxName, key);
    if (cached == null) return false;

    final ageMs = cached['ageMs'] as int;
    return ageMs < maxAge.inMilliseconds;
  }

  /// Get all keys from a box
  List<dynamic> getAllKeys(String boxName) {
    final box = getBox(boxName);
    return box.keys.toList();
  }

  /// Get all values from a box
  List<dynamic> getAllValues(String boxName) {
    final box = getBox(boxName);
    return box.values.toList();
  }

  /// Delete a specific entry
  Future<void> delete(String boxName, String key) async {
    final box = getBox(boxName);
    await box.delete(key);
  }
}
