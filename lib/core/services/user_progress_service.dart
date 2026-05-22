import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../network/api_constants.dart';

/// Service for tracking and syncing user video progress
/// Handles POST /user-progress API with lecture_id based tracking
class UserProgressService {
  static final UserProgressService _instance = UserProgressService._internal();
  factory UserProgressService() => _instance;
  UserProgressService._internal();

  final _storage = const FlutterSecureStorage();
  Timer? _debounceTimer;
  bool _isSending = false;
  bool _hasPendingUpdate = false;
  Map<String, dynamic>? _pendingPayload;

  /// Debounce duration for progress updates
  static const Duration _debounceDuration = Duration(seconds: 3);

  /// Minimum progress change to trigger update (in seconds)
  static const int _minProgressChange = 5;

  /// Last sent progress to avoid duplicate calls
  int _lastSentPosition = -1;
  String _lastLectureId = '';

  Future<String?> _getToken() async {
    return await _storage.read(key: 'auth_token');
  }

  /// Send user progress to backend
  /// POST /user-progress
  /// Payload: { lecture_id, current_video_position, total_duration }
  Future<Map<String, dynamic>> sendProgress({
    required String lectureId,
    required int currentPosition,
    required int totalDuration,
    bool immediate = false,
  }) async {
    // Validate inputs
    if (lectureId.isEmpty) {
      debugPrint('[UserProgressService] Error: lectureId is empty');
      return {'success': false, 'message': 'Lecture ID is required'};
    }

    // Skip if progress hasn't changed significantly (unless immediate)
    if (!immediate && 
        lectureId == _lastLectureId && 
        (currentPosition - _lastSentPosition).abs() < _minProgressChange) {
      debugPrint('[UserProgressService] Skipping: progress change too small');
      return {'success': true, 'skipped': true};
    }

    // Cancel any pending debounced call
    _debounceTimer?.cancel();

    // If already sending, queue the new data
    if (_isSending && !immediate) {
      _hasPendingUpdate = true;
      _pendingPayload = {
        'lecture_id': lectureId,
        'current_video_position': currentPosition,
        'total_duration': totalDuration,
      };
      debugPrint('[UserProgressService] Queued update while sending in progress');
      return {'success': true, 'queued': true};
    }

    // Debounce non-immediate calls
    if (!immediate) {
      final completer = Completer<Map<String, dynamic>>();
      
      _debounceTimer = Timer(_debounceDuration, () async {
        final result = await _executeSend(
          lectureId: lectureId,
          currentPosition: currentPosition,
          totalDuration: totalDuration,
        );
        completer.complete(result);
      });

      return completer.future;
    }

    // Immediate send (for app exit/dispose)
    return _executeSend(
      lectureId: lectureId,
      currentPosition: currentPosition,
      totalDuration: totalDuration,
    );
  }

  /// Execute the actual API call
  Future<Map<String, dynamic>> _executeSend({
    required String lectureId,
    required int currentPosition,
    required int totalDuration,
  }) async {
    _isSending = true;

    try {
      final token = await _getToken();
      if (token == null) {
        debugPrint('[UserProgressService] Error: No auth token');
        return {'success': false, 'message': 'Authentication required'};
      }

      final url = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.userProgress}');
      final payload = {
        'lecture_id': lectureId,
        'current_video_position': currentPosition,
        'total_duration': totalDuration,
      };

      debugPrint('[UserProgressService] Sending: lectureId=$lectureId, position=$currentPosition, duration=$totalDuration');

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        _lastSentPosition = currentPosition;
        _lastLectureId = lectureId;
        debugPrint('[UserProgressService] Success: progress saved');
        return {
          'success': true,
          'data': data['data'],
          'message': data['message'] ?? 'Progress saved',
        };
      } else {
        final data = jsonDecode(response.body);
        debugPrint('[UserProgressService] API Error: ${response.statusCode} - ${data['message']}');
        return {
          'success': false,
          'message': data['message'] ?? 'Failed to save progress (${response.statusCode})',
        };
      }
    } on TimeoutException {
      debugPrint('[UserProgressService] Error: Request timeout');
      return {'success': false, 'message': 'Request timeout'};
    } catch (e) {
      debugPrint('[UserProgressService] Error: $e');
      return {'success': false, 'message': 'Network error: $e'};
    } finally {
      _isSending = false;
      
      // Process any pending update
      if (_hasPendingUpdate && _pendingPayload != null) {
        _hasPendingUpdate = false;
        final pending = _pendingPayload!;
        _pendingPayload = null;
        
        // Small delay to avoid immediate consecutive calls
        await Future.delayed(const Duration(milliseconds: 500));
        
        if (pending['lecture_id'] == lectureId) {
          return sendProgress(
            lectureId: pending['lecture_id'],
            currentPosition: pending['current_video_position'],
            totalDuration: pending['total_duration'],
          );
        }
      }
    }
  }

  /// Force send any pending progress immediately
  /// Call this before app exit or screen dispose
  Future<Map<String, dynamic>> flushPending() async {
    _debounceTimer?.cancel();
    
    if (_hasPendingUpdate && _pendingPayload != null) {
      final pending = _pendingPayload!;
      _hasPendingUpdate = false;
      _pendingPayload = null;
      
      return _executeSend(
        lectureId: pending['lecture_id'],
        currentPosition: pending['current_video_position'],
        totalDuration: pending['total_duration'],
      );
    }
    
    return {'success': true, 'message': 'No pending updates'};
  }

  /// Cancel any pending debounced calls
  void cancelPending() {
    _debounceTimer?.cancel();
    _hasPendingUpdate = false;
    _pendingPayload = null;
    debugPrint('[UserProgressService] Cancelled pending updates');
  }

  /// Reset internal state (useful when switching lectures)
  void reset() {
    cancelPending();
    _lastSentPosition = -1;
    _lastLectureId = '';
    debugPrint('[UserProgressService] State reset');
  }
}
