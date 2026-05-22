import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:peerdart/peerdart.dart';

import '../../data/models/live_room.dart';
import '../../../auth/data/auth_repository.dart';

// ─── Chat message model ───────────────────────────────────────────────────────

class ChatMessage {
  final String id;
  final String senderName;
  final String senderInitial;
  final String message;
  final DateTime timestamp;
  final bool isInstructor;

  ChatMessage({
    required this.id,
    required this.senderName,
    required this.senderInitial,
    required this.message,
    required this.timestamp,
    this.isInstructor = false,
  });
}

// ─── Custom PeerJS server config ─────────────────────────────────────────────

/// Replace these values with your actual PeerJS-compatible server details.
const _kPeerHost = 'peer.learnoo.app'; // your PeerJS server host
const _kPeerPort = 443;
const _kPeerPath = '/server';
const _kPeerSecure = true; // use wss://

// ─── Screen ───────────────────────────────────────────────────────────────────

class LiveStreamScreen extends StatefulWidget {
  final LiveRoom liveRoom;

  /// Set to `true` if the current user is the instructor who is broadcasting.
  /// Set to `false` (default) for viewers / students.
  final bool isHost;

  const LiveStreamScreen({
    super.key,
    required this.liveRoom,
    this.isHost = false,
  });

  @override
  State<LiveStreamScreen> createState() => _LiveStreamScreenState();
}

class _LiveStreamScreenState extends State<LiveStreamScreen>
    with WidgetsBindingObserver {
  // ── Peer ─────────────────────────────────────────────────────────────────
  late final Peer _peer;

  // ── Media ─────────────────────────────────────────────────────────────────
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  MediaStream? _localStream;

  // ── Connections ───────────────────────────────────────────────────────────
  MediaConnection? _mediaConnection;

  /// All open data connections (host ↔ every viewer).
  final List<DataConnection> _dataConnections = [];

  // ── Chat ──────────────────────────────────────────────────────────────────
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  bool _isTyping = false;
  String? _currentUserName;

  // ── UI state ──────────────────────────────────────────────────────────────
  bool _isConnected = false;
  bool _isConnecting = true;
  String _statusMessage = 'Connecting…';
  int _viewerCount = 0;
  bool _isMicMuted = false;
  bool _isCameraOff = false;
  bool _showChat = true;
  bool _isSpeakerOn = true;
  bool _joinSent = false;

  // ─────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _messageController.addListener(_onTextChanged);
    _loadUserInfo();
    _initRenderers();
  }

  Future<void> _loadUserInfo() async {
    try {
      final profile = await AuthRepository().getProfile();
      if (profile['success'] && mounted) {
        final data = profile['data'];
        final firstName = data['attributes']?['first_name'] ?? '';
        final lastName = data['attributes']?['last_name'] ?? '';
        setState(() {
          _currentUserName = '$firstName $lastName'.trim();
        });
      }
    } catch (e) {
      debugPrint('Error loading user info: $e');
    }
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    await _initPeer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _messageController.dispose();
    _chatScrollController.dispose();
    _cleanUp();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _localStream?.getVideoTracks().forEach((t) => t.enabled = false);
    } else if (state == AppLifecycleState.resumed) {
      if (!_isCameraOff) {
        _localStream?.getVideoTracks().forEach((t) => t.enabled = true);
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PeerDart initialisation
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _initPeer() async {
    // HOST uses the liveRoom.id directly as the peer ID.
    // VIEWER uses a short random suffix to avoid ID collisions.
    final peerId = widget.isHost
        ? widget.liveRoom.id
        : 'viewer-${_randomSuffix()}';

    _peer = Peer(
      id: peerId,
      options: PeerOptions(
        host: _kPeerHost,
        port: _kPeerPort,
        path: _kPeerPath,
        secure: _kPeerSecure,
        config: {
          'iceServers': [
            {'urls': 'stun:stun.l.google.com:19302'},
            {
              'urls': 'turn:global.relay.metered.ca:80',
              'username': 'f29e7283f4043b41d539ce22',
              'credential': '+61zZCdLwcLhN0KX',
            },
            {
              'urls': 'turn:global.relay.metered.ca:80?transport=tcp',
              'username': 'f29e7283f4043b41d539ce22',
              'credential': '+61zZCdLwcLhN0KX',
            },
            {
              'urls': 'turn:global.relay.metered.ca:443',
              'username': 'f29e7283f4043b41d539ce22',
              'credential': '+61zZCdLwcLhN0KX',
            },
            {
              'urls': 'turns:global.relay.metered.ca:443?transport=tcp',
              'username': 'f29e7283f4043b41d539ce22',
              'credential': '+61zZCdLwcLhN0KX',
            },
          ],
        },
      ),
    );

    _peer.on('open').listen((id) {
      debugPrint('✅ Peer opened with ID: $id');
      if (!mounted) return;
      setState(() {
        _statusMessage = widget.isHost ? 'Broadcasting…' : 'Joining stream…';
      });
      if (widget.isHost) {
        _startBroadcast();
      } else {
        _joinAsViewer();
      }
    });

    _peer.on('error').listen((err) {
      debugPrint('❌ Peer error: $err');
      if (!mounted) return;
      setState(() {
        _isConnecting = false;
        _statusMessage = 'Error: $err';
      });
      _showSnack('Connection error: $err');
    });

    _peer.on('disconnected').listen((_) {
      if (!mounted) return;
      setState(() {
        _isConnected = false;
        _statusMessage = 'Disconnected. Reconnecting…';
      });
      _peer.reconnect();
    });

    // Connection timeout fallback for peer initialization
    Future.delayed(const Duration(seconds: 10), () {
      if (mounted && _isConnecting && _statusMessage == 'Connecting…') {
        setState(() {
          _isConnecting = false;
          _statusMessage = 'Server unreachable. Check connection.';
        });
        _showSnack(
          'Could not connect to peer server. Please check your internet or try again.',
        );
      }
    });

    // Listen for incoming media calls and data connections.
    if (!widget.isHost) {
      _peer.on<MediaConnection>('call').listen(_answerCall);
    }
    if (widget.isHost) {
      _peer.on<DataConnection>('connection').listen(_onIncomingData);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Host (broadcaster) logic
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _startBroadcast() async {
    try {
      _localStream = await navigator.mediaDevices.getUserMedia({
        'video': {'facingMode': 'user'},
        'audio': true,
      });
      _localRenderer.srcObject = _localStream;
      if (mounted) {
        setState(() {
          _isConnecting = false;
          _isConnected = true;
          _statusMessage = 'Live!';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isConnecting = false;
          _statusMessage = 'Camera/mic permission denied';
        });
      }
    }
  }

  /// Called when an incoming media call arrives (host → viewer).
  /// Mirrors the HTML viewer: `call.answer()` with no local stream.
  Future<void> _answerCall(MediaConnection call) async {
    debugPrint('📞 Incoming call from ${call.peer}');

    if (!widget.isHost) {
      final emptyStream = null;
      call.answer(emptyStream);
      _mediaConnection = call;

      call.on<MediaStream>('stream').listen((stream) {
        debugPrint('🎬 Got remote stream');
        if (!mounted) return;
        _remoteRenderer.srcObject = stream;
        setState(() {
          _isConnecting = false;
          _isConnected = true;
          _statusMessage = 'Connected to live stream';
        });
      });

      call.on('error').listen((err) {
        debugPrint('❌ MediaConnection error: $err');
      });

      call.on('close').listen((_) {
        if (mounted) {
          setState(() {
            _isConnected = false;
            _statusMessage = 'Stream ended';
          });
        }
      });
    }
  }

  /// Called when a viewer opens a data channel to the host.
  void _onIncomingData(DataConnection conn) {
    _dataConnections.add(conn);

    conn.on('open').listen((_) {
      debugPrint('✅ Viewer data channel opened: ${conn.peer}');
    });

    conn.on<dynamic>('data').listen((data) {
      debugPrint('📨 Host received data from ${conn.peer}: $data');
      _onDataReceived(data, conn);
    });

    conn.on('close').listen((_) {
      _dataConnections.remove(conn);
      if (mounted) setState(() => _viewerCount = max(0, _viewerCount - 1));
    });

    if (mounted) setState(() => _viewerCount++);
  }

  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _joinAsViewer() async {
    _joinSent = false;

    void _sendJoin(DataConnection conn) {
      if (_joinSent) return;
      _joinSent = true;

      final myId = _peer.id ?? '';
      debugPrint(
        '→ Sending join: id=$myId name=${_currentUserName ?? "Student"}',
      );

      conn.send({
        'action': 'join',
        'id': myId,
        'name': _currentUserName ?? 'Student',
      });

      if (mounted) setState(() => _statusMessage = 'Waiting for host stream…');
    }

    final hostId = widget.liveRoom.id;
    debugPrint('🔗 Connecting to host: $hostId');

    // ── Data channel ───────────────────────────────────────────────────────
    // PeerDart ALWAYS defaults to JSON serialization, but the working HTML viewer
    // uses PeerJS default = BINARY (binarypack). We must explicitly force Binary
    // so the host's binarypack encoder/decoder is used — matching the HTML viewer.
    //
    // Screenshot proof: HTML viewer shows serialization:"binary", Flutter showed
    // serialization:"json" → causing the "TextDecoder ArrayBuffer" error on host.
    //
    // We send a plain Map; PeerDart's binary serializer (msgpack/binarypack)
    // encodes it, PeerJS host decodes with binarypack automatically.
    final dataConn = _peer.connect(
      hostId,
      options: PeerConnectOption(
        serialization: SerializationType.Binary,
        reliable: true,
      ),
    );

    _dataConnections.add(dataConn);

    dataConn.on('open').listen((_) {
      _sendJoin(dataConn);
    });

    dataConn
        .on<dynamic>('data')
        .listen((raw) => _onDataReceived(raw, dataConn));

    dataConn.on('close').listen((_) {
      debugPrint('⚠️ Data channel to host closed');
      _dataConnections.remove(dataConn);
      if (mounted)
        setState(() {
          _isConnected = false;
          _statusMessage = 'Disconnected';
        });
    });

    dataConn
        .on('error')
        .listen((err) => debugPrint('❌ Data channel error: $err'));

    Future.delayed(const Duration(seconds: 20), () {
      if (mounted && _isConnecting) {
        setState(() {
          _isConnecting = false;
          _statusMessage = 'Host not reachable';
        });
      }
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────────────

  /// Decode incoming data which may be Uint8List (from JS/PeerJS) or Map (from Dart peer).
  Map<String, dynamic>? _decodeIncoming(dynamic data) {
    try {
      if (data is Uint8List) {
        return jsonDecode(utf8.decode(data)) as Map<String, dynamic>?;
      } else if (data is List<int>) {
        return jsonDecode(utf8.decode(data)) as Map<String, dynamic>?;
      } else if (data is Map) {
        return data.cast<String, dynamic>();
      } else if (data is String) {
        return jsonDecode(data) as Map<String, dynamic>?;
      }
    } catch (e) {
      debugPrint(
        '⚠️ Could not decode incoming data: $e (type: ${data.runtimeType})',
      );
    }
    return null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Chat / data channel
  // ─────────────────────────────────────────────────────────────────────────

  void _onDataReceived(dynamic raw, DataConnection source) {
    debugPrint('📨 Raw data received: type=${raw.runtimeType}');
    // PeerJS (binarypack) decodes incoming data automatically to a Map.
    // We still handle Uint8List/String fallbacks just in case.
    final Map<String, dynamic>? data;
    if (raw is Map) {
      data = raw.cast<String, dynamic>();
    } else if (raw is Uint8List) {
      try {
        data = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>?;
      } catch (_) {
        debugPrint('⚠️ Cannot decode Uint8List data');
        return;
      }
    } else if (raw is String) {
      try {
        data = jsonDecode(raw) as Map<String, dynamic>?;
      } catch (_) {
        debugPrint('⚠️ Cannot decode String data');
        return;
      }
    } else {
      debugPrint('⚠️ Unknown data type: ${raw.runtimeType}');
      return;
    }
    if (data == null) return;
    debugPrint('📨 Decoded: $data');

    final type = data['type'] as String?;
    final action = data['action'] as String?;

    // Handle handshake join action (Host side)
    if (action == 'join' && widget.isHost) {
      final peerId = data['id'] as String?;
      print("🤝 Join from: $peerId | localStream=${_localStream != null}");
      if (peerId != null && _localStream != null) {
        final call = _peer.call(peerId, _localStream!);
        print("📞 Called viewer: $peerId | call=$call");
      }
    }
    // Handle chat message from host: { type: 'chat-message', name: '', content: '', timestamp: 123, isHost: true }
    if (type == 'chat-message') {
      final msg = ChatMessage(
        id: (data['timestamp'] ?? DateTime.now().millisecondsSinceEpoch)
            .toString(),
        senderName: data['name'] ?? 'Instructor',
        senderInitial: (data['name'] ?? 'I')
            .toString()
            .substring(0, 1)
            .toUpperCase(),
        message: data['content'] ?? '',
        timestamp: DateTime.fromMillisecondsSinceEpoch(
          data['timestamp'] ?? DateTime.now().millisecondsSinceEpoch,
        ),
        isInstructor: data['isHost'] == true,
      );
      if (mounted) {
        setState(() => _messages.add(msg));
        _scrollToBottom();
      }
    }

    // Handle chat message action from other students (relayed via host or direct): { action: 'message', id: '', name: '', content: '' }
    if (action == 'message') {
      final msg = ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        senderName: data['name'] ?? 'Student',
        senderInitial: (data['name'] ?? 'S')
            .toString()
            .substring(0, 1)
            .toUpperCase(),
        message: data['content'] ?? '',
        timestamp: DateTime.now(),
        isInstructor: false,
      );
      if (mounted) {
        setState(() => _messages.add(msg));
        _scrollToBottom();
      }
    }

    // Legacy support for 'chat' type if needed
    if (type == 'chat') {
      final msg = ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        senderName: data['name'] ?? 'Student',
        senderInitial: (data['name'] ?? 'S')
            .toString()
            .substring(0, 1)
            .toUpperCase(),
        message: data['message'] ?? '',
        timestamp: DateTime.now(),
        isInstructor: data['isInstructor'] == true,
      );
      if (mounted) {
        setState(() => _messages.add(msg));
        _scrollToBottom();
        // HOST: relay the message to all other viewers.
        if (widget.isHost) {
          for (final conn in _dataConnections) {
            if (conn != source) conn.send(data);
          }
        }
      }
    }
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final payload = {
      'action': 'message',
      'id': _peer.id,
      'name': widget.isHost
          ? widget.liveRoom.instructorName
          : (_currentUserName ?? 'You'),
      'content': text,
    };

    // Add locally.
    setState(() {
      _messages.add(
        ChatMessage(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          senderName: widget.isHost
              ? widget.liveRoom.instructorName
              : (_currentUserName ?? 'You'),
          senderInitial: widget.isHost
              ? widget.liveRoom.instructorName.substring(0, 1)
              : (_currentUserName != null
                    ? _currentUserName!.substring(0, 1)
                    : 'Y'),
          message: text,
          timestamp: DateTime.now(),
          isInstructor: widget.isHost,
        ),
      );
      _messageController.clear();
    });

    // Send via data connections — plain Map, PeerDart encodes natively.
    for (final conn in _dataConnections) {
      conn.send(payload);
    }
    _scrollToBottom();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Media controls
  // ─────────────────────────────────────────────────────────────────────────

  void _toggleMic() {
    final audioTracks = _localStream?.getAudioTracks() ?? [];
    for (final track in audioTracks) {
      track.enabled = !track.enabled;
    }
    setState(() => _isMicMuted = !_isMicMuted);
  }

  void _toggleCamera() {
    final videoTracks = _localStream?.getVideoTracks() ?? [];
    for (final track in videoTracks) {
      track.enabled = !track.enabled;
    }
    setState(() => _isCameraOff = !_isCameraOff);
  }

  void _toggleSpeaker() {
    // On mobile flutter_webrtc: switch audio output.
    Helper.setSpeakerphoneOn(!_isSpeakerOn);
    setState(() => _isSpeakerOn = !_isSpeakerOn);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────────────

  String _randomSuffix() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final rng = Random.secure();
    return List.generate(8, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
    );
  }

  void _cleanUp() {
    for (final conn in _dataConnections) {
      conn.close();
    }
    _mediaConnection?.close();
    _localStream?.getTracks().forEach((t) => t.stop());
    _localStream?.dispose();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    _peer.dispose();
  }

  void _leaveLive() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Leave Live Session?'),
        content: const Text(
          'Are you sure you want to leave this live session?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Stay'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _cleanUp();
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
  }

  void _onTextChanged() =>
      setState(() => _isTyping = _messageController.text.isNotEmpty);

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildVideoArea(),
            if (_showChat)
              Expanded(
                child: Container(
                  color: Colors.white,
                  child: Column(
                    children: [
                      _buildChatHeader(),
                      Expanded(child: _buildChatList()),
                      _buildChatInput(),
                    ],
                  ),
                ),
              ),
            _buildControlBar(),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Header
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: const Color(0xFF0F172A),
      child: Row(
        children: [
          GestureDetector(
            onTap: _leaveLive,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.arrow_back,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Blinking LIVE dot
                    _LiveDot(isConnected: _isConnected),
                    const SizedBox(width: 6),
                    Text(
                      _isConnected
                          ? 'LIVE'
                          : _isConnecting
                          ? 'CONNECTING'
                          : 'OFFLINE',
                      style: TextStyle(
                        color: _isConnected
                            ? Colors.red
                            : _isConnecting
                            ? Colors.orange
                            : Colors.grey,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  widget.liveRoom.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (!_isConnected)
                  Text(
                    _statusMessage,
                    style: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          // Viewer count
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                const FaIcon(
                  FontAwesomeIcons.users,
                  color: Colors.white70,
                  size: 14,
                ),
                const SizedBox(width: 6),
                Text(
                  '$_viewerCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Video area
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildVideoArea() {
    return GestureDetector(
      onTap: () => setState(() => _showChat = !_showChat),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        height: _showChat ? 240 : MediaQuery.of(context).size.height - 200,
        width: double.infinity,
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── Remote / Local video ──────────────────────────────────────
            if (widget.isHost && _localStream != null)
              RTCVideoView(
                _localRenderer,
                mirror: true,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              )
            else if (!widget.isHost && _isConnected)
              RTCVideoView(
                _remoteRenderer,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              )
            else
              _buildVideoPlaceholder(),

            // ── Gradient overlay ─────────────────────────────────────────
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.3),
                    Colors.transparent,
                    const Color(0xFF0F172A).withValues(alpha: 0.7),
                  ],
                  stops: const [0, 0.4, 1],
                ),
              ),
            ),

            // ── LIVE badge ──────────────────────────────────────────────
            Positioned(
              top: 14,
              left: 14,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: _isConnected ? Colors.red : Colors.orange,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      _isConnected ? 'LIVE' : _statusMessage,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Expand/collapse hint ─────────────────────────────────────
            Positioned(
              top: 14,
              right: 14,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.black38,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _showChat ? Icons.fullscreen : Icons.fullscreen_exit,
                  color: Colors.white70,
                  size: 18,
                ),
              ),
            ),

            // ── Host's local preview (PIP) when viewer ──────────────────
            if (!widget.isHost && _isConnected && _localStream != null)
              Positioned(
                right: 12,
                bottom: 12,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 90,
                    height: 120,
                    child: RTCVideoView(
                      _localRenderer,
                      mirror: true,
                      objectFit:
                          RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    ),
                  ),
                ),
              ),

            // ── Instructor label ─────────────────────────────────────────
            Positioned(
              left: 14,
              bottom: 14,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4A68F6).withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      widget.isHost
                          ? 'You (Host)'
                          : widget.liveRoom.instructorName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoPlaceholder() {
    return Container(
      decoration: BoxDecoration(
        image: widget.liveRoom.courseThumbnail != null
            ? DecorationImage(
                image: NetworkImage(widget.liveRoom.courseThumbnail!),
                fit: BoxFit.cover,
                colorFilter: ColorFilter.mode(
                  Colors.black.withValues(alpha: 0.55),
                  BlendMode.darken,
                ),
              )
            : null,
        color: const Color(0xFF1E293B),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isConnecting) ...[
              const SizedBox(
                width: 48,
                height: 48,
                child: CircularProgressIndicator(
                  color: Color(0xFF4A68F6),
                  strokeWidth: 3,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _statusMessage,
                style: const TextStyle(color: Colors.white70, fontSize: 15),
              ),
            ] else ...[
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.wifi_tethering,
                  color: Colors.white60,
                  size: 34,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _statusMessage,
                style: const TextStyle(color: Colors.white, fontSize: 15),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Chat
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildChatHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: const Row(
        children: [
          Icon(Icons.chat_bubble_outline, color: Color(0xFF4A68F6), size: 20),
          SizedBox(width: 8),
          Text(
            'Live Chat',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1F2937),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatList() {
    if (_messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              color: Colors.grey.shade300,
              size: 40,
            ),
            const SizedBox(height: 8),
            Text(
              'No messages yet',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 14),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      controller: _chatScrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: _messages.length,
      itemBuilder: (_, i) => _buildChatMessageWidget(_messages[i]),
    );
  }

  Widget _buildChatMessageWidget(ChatMessage msg) {
    if (msg.isInstructor) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: const Color(0xFF4A68F6),
              child: Text(
                msg.senderInitial,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          msg.senderName,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF4A68F6),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF4A68F6),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text(
                            'Instructor',
                            style: TextStyle(
                              fontSize: 9,
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          _formatTime(msg.timestamp),
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      msg.message,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: Colors.grey.shade300,
            child: Text(
              msg.senderInitial,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      msg.senderName,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _formatTime(msg.timestamp),
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  msg.message,
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatInput() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: TextField(
                controller: _messageController,
                decoration: const InputDecoration(
                  hintText: 'Type a message…',
                  hintStyle: TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 13),
                ),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _sendMessage,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: _isTyping
                    ? const Color(0xFF4A68F6)
                    : const Color(0xFFE5E7EB),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.send_rounded,
                color: _isTyping ? Colors.white : const Color(0xFF9CA3AF),
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Control bar (mic / camera / speaker / leave)
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildControlBar() {
    return Container(
      color: const Color(0xFF0F172A),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Mute mic
          _ControlButton(
            icon: _isMicMuted ? Icons.mic_off : Icons.mic,
            label: _isMicMuted ? 'Unmute' : 'Mute',
            active: !_isMicMuted,
            onTap: _toggleMic,
          ),
          // Camera (host only)
          if (widget.isHost)
            _ControlButton(
              icon: _isCameraOff ? Icons.videocam_off : Icons.videocam,
              label: _isCameraOff ? 'Camera off' : 'Camera',
              active: !_isCameraOff,
              onTap: _toggleCamera,
            ),
          // Speaker
          _ControlButton(
            icon: _isSpeakerOn ? Icons.volume_up : Icons.volume_off,
            label: _isSpeakerOn ? 'Speaker' : 'Earpiece',
            active: _isSpeakerOn,
            onTap: _toggleSpeaker,
          ),
          // Chat toggle
          _ControlButton(
            icon: _showChat ? Icons.chat : Icons.chat_outlined,
            label: 'Chat',
            active: _showChat,
            onTap: () => setState(() => _showChat = !_showChat),
          ),
          // Leave
          _ControlButton(
            icon: Icons.call_end,
            label: 'Leave',
            active: false,
            activeColor: Colors.red,
            onTap: _leaveLive,
          ),
        ],
      ),
    );
  }
}

// ─── Supporting widgets ───────────────────────────────────────────────────────

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final Color? activeColor;

  const _ControlButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = active
        ? (activeColor ?? const Color(0xFF4A68F6))
        : Colors.red;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: active
                  ? (activeColor != null
                        ? activeColor!.withValues(alpha: 0.15)
                        : const Color(0xFF1E3A8A).withValues(alpha: 0.4))
                  : Colors.red.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(color: Colors.white60, fontSize: 10)),
        ],
      ),
    );
  }
}

class _LiveDot extends StatefulWidget {
  final bool isConnected;
  const _LiveDot({required this.isConnected});

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.3, end: 1.0).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _anim,
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: widget.isConnected ? Colors.red : Colors.orange,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
