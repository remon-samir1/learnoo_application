import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../network/api_client.dart';
import '../network/api_constants.dart';
import 'feature_manager.dart';

/// Remote playback settings the dashboard owns, currently just how long the
/// phone's screen is held awake while a lecture plays.
///
/// `GET /v1/video-settings` answers `{"sleep_per_minute": 5}` — the number of
/// minutes the display stays on once playback starts. The value is cached on
/// the device the way [FeatureManager] caches feature flags, so it applies
/// offline and from the first frame instead of only after the first successful
/// request.
///
/// When no value was ever fetched the app keeps its previous behaviour: the
/// screen stays awake for as long as the video is playing ([screenAwakeTimeout]
/// is then `null`, which the player reads as "no timeout").
class VideoSettingsService extends ChangeNotifier {
  VideoSettingsService._internal();
  static final VideoSettingsService _instance =
      VideoSettingsService._internal();
  factory VideoSettingsService() => _instance;

  /// Cached value, in milliseconds. Only ever written with a parsed, clamped
  /// duration, so a stale cache can never produce a nonsense timeout.
  static const String _cacheKey = 'video_settings_screen_awake_ms';
  static const String _lastUpdateKey = 'video_settings_last_update';

  /// The key the dashboard writes.
  static const String sleepPerMinuteKey = 'sleep_per_minute';

  /// Guard rails around whatever the dashboard sends. A fat-fingered `100000`
  /// would otherwise hold the screen on for weeks, and `0.001` would release it
  /// before the student saw anything.
  static const Duration minScreenAwakeTimeout = Duration(seconds: 30);
  static const Duration maxScreenAwakeTimeout = Duration(hours: 12);

  Duration? _screenAwakeTimeout;
  bool _hasValue = false;
  bool _isInitialized = false;
  bool _isLoading = false;
  DateTime? _lastUpdate;
  SharedPreferences? _prefs;

  /// How long the screen is held awake after playback starts, or `null` when no
  /// usable value is known — in which case the screen stays awake for the whole
  /// of playback, exactly as it did before this setting existed.
  Duration? get screenAwakeTimeout => _screenAwakeTimeout;

  /// Whether a value (cached or freshly fetched) is actually known.
  bool get hasValue => _hasValue;

  bool get isInitialized => _isInitialized;

  DateTime? get lastUpdate => _lastUpdate;

  /// Load the last good value off the device. Safe to call more than once.
  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;
    try {
      _prefs = await SharedPreferences.getInstance();
      final cached = _prefs?.getInt(_cacheKey);
      final lastUpdateStr = _prefs?.getString(_lastUpdateKey);
      if (lastUpdateStr != null) {
        _lastUpdate = DateTime.tryParse(lastUpdateStr);
      }
      if (cached != null && cached > 0) {
        _screenAwakeTimeout = Duration(milliseconds: cached);
        _hasValue = true;
      }
    } catch (e) {
      debugPrint('VideoSettingsService: failed to read cached settings');
    }
  }

  /// Fetch `/v1/video-settings`.
  ///
  /// Returns `true` when a usable value came back. The call never signs the
  /// student out: this endpoint is authenticated, and a 401 here (a student who
  /// is not signed in yet, or a token that is being refreshed) must not tear
  /// down the session — it just leaves the cached value in place.
  Future<bool> refresh() async {
    if (_isLoading) return false;
    _isLoading = true;
    try {
      await initialize();
      Duration? timeout;
      try {
        final payload = await ApiClient().get(
          ApiConstants.videoSettings,
          skipAuthRedirect: true,
        );
        timeout = parseSleepPerMinute(readSleepPerMinute(payload));
      } catch (e) {
        debugPrint('VideoSettingsService: video-settings request failed');
      }

      // The dashboard saves this through the feature store
      // (`POST /v1/feature/store-or-update` with `key: sleep_per_minute`), and
      // `/v1/video-settings` may not be readable by a student token. The
      // features the app already loads carry the same value, so they stand in
      // when the dedicated endpoint gives nothing.
      timeout ??= _timeoutFromFeatures();

      if (timeout == null) {
        debugPrint('VideoSettingsService: no usable sleep_per_minute found');
        return false;
      }
      await _store(timeout);
      return true;
    } catch (e) {
      // Unreachable API, offline, 401, malformed body: keep the cached value.
      debugPrint('VideoSettingsService: refresh failed, keeping cached value');
      return false;
    } finally {
      _isLoading = false;
    }
  }

  /// Refresh only when the known value is older than [maxAge], mirroring how
  /// features are refreshed when the app returns to the foreground.
  Future<bool> refreshIfStale({
    Duration maxAge = const Duration(minutes: 5),
  }) async {
    if (!needsRefresh(maxAge: maxAge)) return false;
    return refresh();
  }

  bool needsRefresh({Duration maxAge = const Duration(minutes: 5)}) {
    final last = _lastUpdate;
    if (last == null) return true;
    return DateTime.now().difference(last) > maxAge;
  }

  Future<void> _store(Duration timeout) async {
    final changed = _screenAwakeTimeout != timeout || !_hasValue;
    _screenAwakeTimeout = timeout;
    _hasValue = true;
    _lastUpdate = DateTime.now();
    try {
      await _prefs?.setInt(_cacheKey, timeout.inMilliseconds);
      await _prefs?.setString(_lastUpdateKey, _lastUpdate!.toIso8601String());
    } catch (e) {
      debugPrint('VideoSettingsService: failed to cache settings');
    }
    if (changed) notifyListeners();
  }

  /// The same setting as it arrives through `/v1/feature`.
  Duration? _timeoutFromFeatures() {
    try {
      final feature = FeatureManager().allFeatures[sleepPerMinuteKey];
      return parseSleepPerMinute(feature?.value);
    } catch (e) {
      return null;
    }
  }

  /// Drop the cached value (used when the device is handed to another student).
  Future<void> clear() async {
    _screenAwakeTimeout = null;
    _hasValue = false;
    _lastUpdate = null;
    try {
      await _prefs?.remove(_cacheKey);
      await _prefs?.remove(_lastUpdateKey);
    } catch (_) {}
    notifyListeners();
  }

  // ------------------------------------------------------------------
  // Pure helpers (unit-tested)
  // ------------------------------------------------------------------

  /// Pull `sleep_per_minute` out of whatever envelope the API used.
  ///
  /// The endpoint answers a bare `{"sleep_per_minute": 5}` today, but every
  /// other list/detail endpoint wraps its payload in `data` (sometimes twice),
  /// so both shapes are accepted rather than depending on one of them.
  static Object? readSleepPerMinute(Object? payload) {
    if (payload is Map) {
      if (payload.containsKey(sleepPerMinuteKey)) {
        return payload[sleepPerMinuteKey];
      }
      final data = payload['data'];
      if (data != null) return readSleepPerMinute(data);
      final attributes = payload['attributes'];
      if (attributes != null) return readSleepPerMinute(attributes);
    }
    if (payload is List) {
      for (final item in payload) {
        final found = readSleepPerMinute(item);
        if (found != null) return found;
      }
    }
    return null;
  }

  /// Turn a raw `sleep_per_minute` into the duration the screen stays awake.
  ///
  /// Accepts a number or a numeric string (the dashboard stores settings as
  /// text). Returns `null` — meaning "no usable value, keep the old behaviour"
  /// — for a missing, null, empty, non-numeric, not-finite, zero or negative
  /// value. Anything outside [minScreenAwakeTimeout]..[maxScreenAwakeTimeout]
  /// is clamped into that range.
  static Duration? parseSleepPerMinute(Object? raw) {
    double? minutes;
    if (raw is num) {
      minutes = raw.toDouble();
    } else if (raw is String) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return null;
      minutes = double.tryParse(trimmed);
    }

    if (minutes == null || !minutes.isFinite || minutes <= 0) return null;

    // Milliseconds rather than whole minutes so "0.5" is honoured instead of
    // being rounded away.
    final millis = minutes * Duration.millisecondsPerMinute;
    if (millis >= maxScreenAwakeTimeout.inMilliseconds) {
      return maxScreenAwakeTimeout;
    }
    final timeout = Duration(milliseconds: millis.round());
    if (timeout < minScreenAwakeTimeout) return minScreenAwakeTimeout;
    return timeout;
  }
}
