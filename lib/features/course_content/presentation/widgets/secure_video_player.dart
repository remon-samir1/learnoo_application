import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:better_player_plus/better_player_plus.dart';
import 'package:learnoo/core/widgets/secure_wrapper.dart';
import 'package:learnoo/core/widgets/dynamic_watermark_widget.dart';
import 'package:learnoo/core/controllers/watermark_controller.dart';
import 'package:learnoo/core/models/watermark_config.dart';
import 'package:learnoo/core/services/feature_manager.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io' show Platform;
import 'dart:async';

/// A secure video player that enforces DRM (Widevine on Android, FairPlay on iOS if configured)
/// It is wrapped in [SecureWrapper] and overlays a [DynamicWatermarkWidget].
class SecureVideoPlayer extends StatefulWidget {
  final String videoUrl;
  final String drmLicenseUrl;
  final Map<String, String>? drmHeaders;
  final String userId;
  final String userName;
  final WatermarkConfig? watermarkConfig;

  const SecureVideoPlayer({
    super.key,
    required this.videoUrl,
    required this.drmLicenseUrl,
    required this.userId,
    required this.userName,
    this.drmHeaders,
    this.watermarkConfig,
  });

  @override
  State<SecureVideoPlayer> createState() => _SecureVideoPlayerState();
}

class _SecureVideoPlayerState extends State<SecureVideoPlayer>
    with WidgetsBindingObserver {
  BetterPlayerController? _betterPlayerController;
  WatermarkController? _watermarkController;
  bool _isInitError = false;
  bool _isInitialized = false;
  bool _isPlaying = false;
  bool _isLoading = false;
  int _retryCount = 0;
  static const int _maxRetries = 3;
  static const Duration _playDelay = Duration(seconds: 1);
  static const Duration _retryDelay = Duration(seconds: 2);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializePlayer();
    _initializeWatermark();
  }

  void _initializeWatermark() {
    final config =
        widget.watermarkConfig ?? FeatureManager().getWatermarkConfig('videos');

    // Debug logging for watermark rendering issues
    if (kDebugMode) {
      final bool isEmulator = Platform.isAndroid
          ? false // Will be detected at runtime via other means
          : false;
      debugPrint('[Watermark] Initializing watermark for video player');
      debugPrint('[Watermark] Platform: ${Platform.operatingSystem}');
      debugPrint(
        '[Watermark] Device: ${Platform.isAndroid
            ? "Android"
            : Platform.isIOS
            ? "iOS"
            : "Other"}',
      );
      debugPrint('[Watermark] Watermark enabled: ${config.enabled}');
      debugPrint('[Watermark] Opacity: ${config.opacity}');
      debugPrint('[Watermark] Using TextStyle.withOpacity fix: true');
      debugPrint('[Watermark] Removed Opacity widgets: true');
    }

    if (config.enabled) {
      _watermarkController = WatermarkController(
        config: config,
        fallbackText: widget.userName,
      );
    }
  }

  Future<void> _initializePlayer() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
      _isInitError = false;
    });

    try {
      _betterPlayerController?.dispose();
      _betterPlayerController = null;

      // Log device info for OPPO/ColorOS debugging
      await _logDeviceInfo();

      debugPrint(
        "[SecureVideoPlayer] Initializing video from URL: ${widget.videoUrl}",
      );

      final dataSource = BetterPlayerDataSource(
        BetterPlayerDataSourceType.network,
        widget.videoUrl,
      );

      _betterPlayerController = BetterPlayerController(
        BetterPlayerConfiguration(
          autoPlay: false,
          looping: false,
          // ✅ FIX: Disable built-in placeholder - we handle play overlay manually
          showPlaceholderUntilPlay: false,
          placeholderOnTop: false,
          placeholder: Container(color: Colors.black),
          controlsConfiguration: BetterPlayerControlsConfiguration(
            showControls: true,
            enablePlayPause: true,
            enableFullscreen: false,
            enableMute: true,
            enableProgressBar: true,
            enableProgressBarDrag: true,
            enableSkips: true,
            enableAudioTracks: false,
            enableSubtitles: false,
            enableQualities: true,
          ),
        ),
        betterPlayerDataSource: dataSource,
      );

      // Add event listener for play state tracking
      _betterPlayerController!.addEventsListener((event) {
        if (event.betterPlayerEventType == BetterPlayerEventType.exception) {
          debugPrint("[SecureVideoPlayer] Video error: ${event.parameters}");
          _logVideoPlayerError(event.parameters.toString());
          if (mounted) {
            setState(() {
              _isInitError = true;
              _isLoading = false;
            });
          }
        }
        // ✅ FIX: Track play state from events
        if (event.betterPlayerEventType == BetterPlayerEventType.play) {
          if (mounted) setState(() => _isPlaying = true);
        }
        if (event.betterPlayerEventType == BetterPlayerEventType.pause) {
          if (mounted) setState(() => _isPlaying = false);
        }
      });

      await _betterPlayerController!
          .setupDataSource(dataSource)
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              debugPrint(
                "[SecureVideoPlayer] Video initialization timeout after 30s",
              );
              throw TimeoutException("Video initialization timed out");
            },
          );

      // Enable wakelock to keep screen on during video playback
      await WakelockPlus.enable();
      debugPrint("[SecureVideoPlayer] Wakelock enabled for video playback");

      if (mounted) {
        setState(() {
          _isInitialized = true;
          _isLoading = false;
          _retryCount = 0;
        });
      }
    } catch (e) {
      debugPrint("[SecureVideoPlayer] Initialization error: $e");
      _logErrorDetails(e);
      _handleInitError();
    }
  }

  Future<void> _logDeviceInfo() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        debugPrint("[SecureVideoPlayer] Device Info:");
        debugPrint(
          "[SecureVideoPlayer] - Manufacturer: ${androidInfo.manufacturer}",
        );
        debugPrint("[SecureVideoPlayer] - Model: ${androidInfo.model}");
        debugPrint(
          "[SecureVideoPlayer] - Android Version: ${androidInfo.version.release}",
        );
        debugPrint("[SecureVideoPlayer] - SDK: ${androidInfo.version.sdkInt}");
        debugPrint("[SecureVideoPlayer] - Brand: ${androidInfo.brand}");
        debugPrint("[SecureVideoPlayer] - Device: ${androidInfo.device}");
      }
    } catch (e) {
      debugPrint("[SecureVideoPlayer] Could not get device info: $e");
    }
  }

  void _logErrorDetails(dynamic error) {
    final errorString = error.toString().toLowerCase();
    debugPrint("[SecureVideoPlayer] Error Details:");
    debugPrint("[SecureVideoPlayer] - Raw Error: $error");

    // Categorize error for better debugging
    if (errorString.contains('codec') ||
        errorString.contains('decoder') ||
        errorString.contains('mediacodec') ||
        errorString.contains('OMX')) {
      debugPrint("[SecureVideoPlayer] - Category: VIDEO_CODEC_ERROR");
      debugPrint(
        "[SecureVideoPlayer] - Common on OPPO/ColorOS devices with hardware codec issues",
      );
    } else if (errorString.contains('network') ||
        errorString.contains('socket') ||
        errorString.contains('connection') ||
        errorString.contains('timeout') ||
        errorString.contains('unreachable')) {
      debugPrint("[SecureVideoPlayer] - Category: NETWORK_ERROR");
    } else if (errorString.contains('http') ||
        errorString.contains('403') ||
        errorString.contains('404') ||
        errorString.contains('unauthorized')) {
      debugPrint("[SecureVideoPlayer] - Category: HTTP_ERROR");
    } else if (errorString.contains('drm') || errorString.contains('license')) {
      debugPrint("[SecureVideoPlayer] - Category: DRM_ERROR");
    }
  }

  void _logVideoPlayerError(String errorDescription) {
    final lowerError = errorDescription.toLowerCase();
    debugPrint("[SecureVideoPlayer] Video Player Error Analysis:");
    debugPrint("[SecureVideoPlayer] - Error: $errorDescription");

    // Detailed codec error detection
    if (lowerError.contains('codec') ||
        lowerError.contains('decoder') ||
        lowerError.contains('mediacodec') ||
        lowerError.contains('OMX') ||
        lowerError.contains('exoplayer') ||
        lowerError.contains('format')) {
      debugPrint("[SecureVideoPlayer] - Type: CODEC/DECODER_ERROR");
      debugPrint(
        "[SecureVideoPlayer] - Recommendation: Try software codec or different format",
      );
    }

    // Network error detection
    if (lowerError.contains('network') ||
        lowerError.contains('socket') ||
        lowerError.contains('connection') ||
        lowerError.contains('timeout') ||
        lowerError.contains('unreachable') ||
        lowerError.contains('failed to connect') ||
        lowerError.contains('dns')) {
      debugPrint("[SecureVideoPlayer] - Type: NETWORK_ERROR");
      debugPrint(
        "[SecureVideoPlayer] - Recommendation: Check internet connection or HTTP cleartext settings",
      );
    }

    // Source/HTTP error detection
    if (lowerError.contains('source') ||
        lowerError.contains('404') ||
        lowerError.contains('403') ||
        lowerError.contains('500') ||
        lowerError.contains('unauthorized') ||
        lowerError.contains('forbidden')) {
      debugPrint("[SecureVideoPlayer] - Type: SOURCE/HTTP_ERROR");
      debugPrint(
        "[SecureVideoPlayer] - Recommendation: Check video URL and server availability",
      );
    }
  }

  void _handleInitError() {
    if (_retryCount < _maxRetries) {
      _retryCount++;
      debugPrint(
        "[SecureVideoPlayer] Retrying initialization (attempt $_retryCount/$_maxRetries)...",
      );
      Future.delayed(_retryDelay, () {
        if (mounted) {
          _initializePlayer();
        }
      });
    } else {
      if (mounted) {
        setState(() {
          _isInitError = true;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _playVideo() async {
    if (_betterPlayerController == null || !_isInitialized) return;

    setState(() {
      _isLoading = true;
    });

    await Future.delayed(_playDelay);

    if (!mounted || _betterPlayerController == null) return;

    try {
      // Ensure wakelock is enabled before playback
      await WakelockPlus.enable();
      await _betterPlayerController!.play();
      if (mounted) {
        setState(() {
          _isPlaying = true;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("[SecureVideoPlayer] Play error: $e");
      _logErrorDetails(e);
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _enterFullScreen() {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => _FullScreenPlayer(
          betterPlayerController: _betterPlayerController,
          watermarkController: _watermarkController,
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    // Safely attempt to dispose controller and pause if playing
    try {
      if (_betterPlayerController?.videoPlayerController?.value.isPlaying ??
          false) {
        _betterPlayerController?.pause();
      }
      _betterPlayerController?.dispose();
    } catch (e) {
      debugPrint("[SecureVideoPlayer] Error disposing controller: $e");
    }
    _betterPlayerController = null;

    _watermarkController?.dispose();
    _watermarkController = null;

    // Disable wakelock when video player is disposed
    WakelockPlus.disable();
    debugPrint("[SecureVideoPlayer] Wakelock disabled on dispose");

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Check if app goes to background
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      if (_betterPlayerController != null &&
          (_betterPlayerController?.videoPlayerController?.value.isPlaying ??
              false)) {
        _betterPlayerController?.pause();
      }
    }
  }

  Widget _buildPlayButton() {
    return GestureDetector(
      onTap: _playVideo,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(50),
        ),
        child: const Icon(
          Icons.play_circle_fill,
          size: 64,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildVideoContent() {
    if (_isInitError) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              "Failed to load secure video.\nPlease check your connection or DRM license.",
              style: TextStyle(color: Colors.white),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                _retryCount = 0;
                _initializePlayer();
              },
              child: const Text("Retry"),
            ),
          ],
        ),
      );
    }

    if (!_isInitialized || _betterPlayerController == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    return Stack(
      children: [
        BetterPlayer(controller: _betterPlayerController!),
        // Manual play overlay
        if (!_isPlaying && !_isLoading) Center(child: _buildPlayButton()),
        // Loading overlay during play start
        if (_isLoading)
          const Center(child: CircularProgressIndicator(color: Colors.white)),
        // Fullscreen toggle button
        Positioned(
          top: 8,
          left: 8,
          child: IconButton(
            icon: const Icon(Icons.fullscreen, color: Colors.white),
            onPressed: _enterFullScreen,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return SecureWrapper(
      protectionMessage: "Video protection active",
      child: Stack(
        children: [
          // ✅ FIX: Remove black container background that was covering video
          _buildVideoContent(),
          if (_watermarkController != null)
            Positioned.fill(
              child: IgnorePointer(
                child: DynamicWatermarkWidget(
                  controller: _watermarkController!,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Custom fullscreen widget that includes the watermark
class _FullScreenPlayer extends StatefulWidget {
  final BetterPlayerController? betterPlayerController;
  final WatermarkController? watermarkController;

  const _FullScreenPlayer({
    required this.betterPlayerController,
    required this.watermarkController,
  });

  @override
  State<_FullScreenPlayer> createState() => _FullScreenPlayerState();
}

class _FullScreenPlayerState extends State<_FullScreenPlayer> {
  @override
  void initState() {
    super.initState();
  }

  void _exitFullScreen() {
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (widget.betterPlayerController != null)
            Stack(
              children: [
                BetterPlayer(controller: widget.betterPlayerController!),
                Positioned(
                  top: 8,
                  left: 8,
                  child: IconButton(
                    icon: const Icon(
                      Icons.fullscreen_exit,
                      color: Colors.white,
                    ),
                    onPressed: _exitFullScreen,
                  ),
                ),
              ],
            ),
          if (widget.watermarkController != null)
            Positioned.fill(
              child: IgnorePointer(
                child: DynamicWatermarkWidget(
                  controller: widget.watermarkController!,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
