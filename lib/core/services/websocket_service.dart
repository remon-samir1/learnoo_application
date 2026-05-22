import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:learnoo/features/auth/data/auth_repository.dart';

class WebSocketService {
  static final WebSocketService _instance = WebSocketService._internal();
  factory WebSocketService() => _instance;
  WebSocketService._internal();

  final AuthRepository _authRepository = AuthRepository();
  WebSocketChannel? _channel;
  final StreamController<Map<String, dynamic>> _notificationController =
      StreamController<Map<String, dynamic>>.broadcast();
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  bool _isConnected = false;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;
  static const Duration _reconnectDelay = Duration(seconds: 5);
  static const Duration _heartbeatInterval = Duration(seconds: 30);

  Stream<Map<String, dynamic>> get notificationStream =>
      _notificationController.stream;

  bool get isConnected => _isConnected;

  Future<void> connect() async {
    if (_isConnected) return;

    final token = await _authRepository.getToken();
    if (token == null) {
      debugPrint('WebSocket: No token found');
      return;
    }

    try {
      // Replace with your actual WebSocket URL
      final wsUrl = Uri.parse('wss://api.learnoo.app/ws');
      
      _channel = WebSocketChannel.connect(
        wsUrl.replace(queryParameters: {'token': token}),
      );

      _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
        cancelOnError: false,
      );

      _isConnected = true;
      _reconnectAttempts = 0;
      _startHeartbeat();
      debugPrint('WebSocket: Connected successfully');
    } catch (e) {
      debugPrint('WebSocket: Connection error - $e');
      _scheduleReconnect();
    }
  }

  void _onMessage(dynamic message) {
    try {
      final data = jsonDecode(message as String);
      debugPrint('WebSocket: Received message - $data');
      
      // Check if it's a notification
      if (data['type'] == 'notification' || data['event'] == 'notification') {
        _notificationController.add(data);
      }
    } catch (e) {
      debugPrint('WebSocket: Error parsing message - $e');
    }
  }

  void _onError(dynamic error) {
    debugPrint('WebSocket: Error - $error');
    _isConnected = false;
    _stopHeartbeat();
    _scheduleReconnect();
  }

  void _onDone() {
    debugPrint('WebSocket: Connection closed');
    _isConnected = false;
    _stopHeartbeat();
    _scheduleReconnect();
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
      if (_isConnected && _channel != null) {
        try {
          _channel!.sink.add(jsonEncode({'type': 'ping'}));
        } catch (e) {
          debugPrint('WebSocket: Heartbeat error - $e');
        }
      }
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void _scheduleReconnect() {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      debugPrint('WebSocket: Max reconnection attempts reached');
      return;
    }

    _reconnectTimer?.cancel();
    _reconnectAttempts++;
    
    debugPrint('WebSocket: Scheduling reconnect attempt $_reconnectAttempts');
    
    _reconnectTimer = Timer(_reconnectDelay, () {
      connect();
    });
  }

  Future<void> disconnect() async {
    _reconnectTimer?.cancel();
    _stopHeartbeat();
    _reconnectAttempts = 0;
    
    await _channel?.sink.close();
    _channel = null;
    _isConnected = false;
    
    debugPrint('WebSocket: Disconnected');
  }

  void subscribeToNotifications() {
    if (!_isConnected || _channel == null) {
      debugPrint('WebSocket: Cannot subscribe - not connected');
      return;
    }

    try {
      _channel!.sink.add(jsonEncode({
        'type': 'subscribe',
        'channel': 'notifications',
      }));
      debugPrint('WebSocket: Subscribed to notifications channel');
    } catch (e) {
      debugPrint('WebSocket: Subscribe error - $e');
    }
  }

  void unsubscribeFromNotifications() {
    if (!_isConnected || _channel == null) {
      debugPrint('WebSocket: Cannot unsubscribe - not connected');
      return;
    }

    try {
      _channel!.sink.add(jsonEncode({
        'type': 'unsubscribe',
        'channel': 'notifications',
      }));
      debugPrint('WebSocket: Unsubscribed from notifications channel');
    } catch (e) {
      debugPrint('WebSocket: Unsubscribe error - $e');
    }
  }

  void dispose() {
    disconnect();
    _notificationController.close();
  }
}
