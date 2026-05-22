import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:shimmer/shimmer.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:better_player_plus/better_player_plus.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../../../../core/network/api_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/services/feature_manager.dart';
import '../../../../core/services/pdf_watermark_service.dart';
import '../../../../core/services/download_service.dart';
import '../../../../core/services/offline_view_service.dart';
import '../../../../core/services/chapter_audio_watermark_service.dart';
import '../../../../core/services/video_watch_tracker.dart';
import '../../../../core/services/encrypted_video_service.dart';
import '../../../../core/services/user_progress_service.dart';
import '../../../../core/widgets/watermark_wrapper.dart';
import '../../data/chapter_repository.dart';
import '../../data/course_files_repository.dart';
import '../../data/discussion_repository.dart';
import '../../../../features/exams/data/exam_repository.dart';
import '../../../../features/exams/models/quiz_models.dart';
import '../../services/attachment_permission_service.dart';
import '../../../auth/data/auth_repository.dart';
import '../widgets/lecture_header.dart';
import '../widgets/attachments_list.dart';
import '../widgets/quizzes_list.dart';
import '../widgets/discussion_panel.dart';
import 'pdf_reviewer_screen.dart';
import '../../../exams/presentation/screens/quiz_screen.dart';

enum VideoErrorType { network, source, unknown }

class VideoErrorMapper {
  static const List<String> _networkErrorKeywords = [
    'timeout',
    'connection',
    'socket',
    'network',
    'failed to load',
    'unable to load',
    'internet',
    'unreachable',
    'refused',
    'failed host lookup',
    'offline',
  ];

  static const List<String> _sourceErrorKeywords = [
    'invalid url',
    '404',
    'not found',
    'unavailable',
    'forbidden',
    '403',
    'format',
    'unsupported',
  ];

  static VideoErrorType mapError(String errorMessage) {
    final lowerError = errorMessage.toLowerCase();
    if (_networkErrorKeywords.any((k) => lowerError.contains(k))) {
      return VideoErrorType.network;
    }
    if (_sourceErrorKeywords.any((k) => lowerError.contains(k))) {
      return VideoErrorType.source;
    }
    return VideoErrorType.unknown;
  }

  static String getUserMessage(VideoErrorType type, String fallbackKey) {
    switch (type) {
      case VideoErrorType.network:
        return 'course.no_internet'.tr();
      case VideoErrorType.source:
        return 'course.video_unavailable'.tr();
      case VideoErrorType.unknown:
        return fallbackKey.tr();
    }
  }
}

class VideoControllerHandler {
  BetterPlayerController? _controller;
  bool _isRetrying = false;
  Timer? _initTimeoutTimer;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;
  bool _isPlaying = false;
  bool _isBuffering = false;
  bool _isCompleted = false;

  void Function(Duration position, Duration duration)? onPositionChanged;
  void Function(bool isPlaying)? onPlayingStateChanged;
  void Function(bool isBuffering)? onBufferingStateChanged;
  void Function()? onCompleted;
  void Function(bool visible)? onControlsVisibilityChanged;

  BetterPlayerController? get controller => _controller;
  get videoPlayerController => _controller?.videoPlayerController;
  bool get isRetrying => _isRetrying;

  Duration get currentPosition => _currentPosition;
  Duration get totalDuration => _totalDuration;
  bool get isPlaying => _isPlaying;
  bool get isBuffering => _isBuffering;
  bool get isCompleted => _isCompleted;

  void setRetrying(bool value) => _isRetrying = value;

  static const Duration _initTimeout = Duration(seconds: 90);

  Future<bool> checkConnectivity() async {
    final result = await Connectivity().checkConnectivity();
    return result != ConnectivityResult.none;
  }

  Future<void> dispose() async {
    _initTimeoutTimer?.cancel();
    _initTimeoutTimer = null;

    onPositionChanged = null;
    onPlayingStateChanged = null;
    onBufferingStateChanged = null;
    onCompleted = null;
    onControlsVisibilityChanged = null;

    final ctrl = _controller;
    _controller = null;
    if (ctrl != null) {
      try {
        await ctrl.pause();
        ctrl.dispose();
      } catch (_) {}
    }
  }

  BetterPlayerConfiguration _buildConfiguration() {
    return BetterPlayerConfiguration(
      autoPlay: true,
      looping: false,
      aspectRatio: 16 / 9,
      fit: BoxFit.contain,
      autoDispose: false,
      handleLifecycle: false,
      showPlaceholderUntilPlay: false,
      placeholderOnTop: false,
      placeholder: const SizedBox.shrink(),
      controlsConfiguration: const BetterPlayerControlsConfiguration(
        showControls: true,
        showControlsOnInitialize: false,
        controlsHideTime: Duration(milliseconds: 500),
        enablePlayPause: true,
        enableFullscreen: false,
        enableMute: false,
        enableProgressBar: true,
        enableProgressBarDrag: true,
        enableSkips: false,
        enableAudioTracks: false,
        enableSubtitles: false,
        enableQualities: true,
        progressBarPlayedColor: Color(0xFF3451E5),
        progressBarHandleColor: Color(0xFF3451E5),
        controlBarColor: Colors.black54,
      ),
      errorBuilder: (context, errorMessage) {
        final errorType = VideoErrorMapper.mapError(errorMessage ?? '');
        final userMessage = VideoErrorMapper.getUserMessage(
          errorType,
          'course.something_went_wrong',
        );
        return Center(
          child: Text(userMessage, style: const TextStyle(color: Colors.white)),
        );
      },
    );
  }

  Future<BetterPlayerController?> initializeFromFile({
    required File videoFile,
    required VoidCallback onError,
    required VoidCallback onBufferingStart,
    required VoidCallback onBufferingEnd,
    required VoidCallback onTimeout,
  }) async {
    await dispose();

    final dataSource = BetterPlayerDataSource(
      BetterPlayerDataSourceType.file,
      videoFile.path,
    );

    _controller = BetterPlayerController(_buildConfiguration());

    final completer = Completer<BetterPlayerController?>();

    _initTimeoutTimer = Timer(_initTimeout, () {
      if (!completer.isCompleted) {
        onTimeout();
        completer.complete(null);
      }
    });

    _controller!.addEventsListener((event) {
      if (_controller == null) return;
      switch (event.betterPlayerEventType) {
        case BetterPlayerEventType.initialized:
          _initTimeoutTimer?.cancel();
          _totalDuration =
              _controller?.videoPlayerController?.value.duration ??
              Duration.zero;
          onPositionChanged?.call(Duration.zero, _totalDuration);
          if (!completer.isCompleted) completer.complete(_controller);
          break;
        case BetterPlayerEventType.exception:
          _initTimeoutTimer?.cancel();
          onError();
          if (!completer.isCompleted) completer.complete(null);
          break;
        case BetterPlayerEventType.bufferingStart:
          onBufferingStart();
          break;
        case BetterPlayerEventType.bufferingEnd:
          onBufferingEnd();
          break;
        case BetterPlayerEventType.progress:
          _currentPosition =
              _controller?.videoPlayerController?.value.position ??
              Duration.zero;
          _totalDuration =
              _controller?.videoPlayerController?.value.duration ??
              _totalDuration;
          onPositionChanged?.call(_currentPosition, _totalDuration);
          break;
        case BetterPlayerEventType.pause:
          _isPlaying = false;
          onPlayingStateChanged?.call(false);
          break;
        case BetterPlayerEventType.finished:
          _isCompleted = true;
          onCompleted?.call();
          break;
        case BetterPlayerEventType.controlsVisible:
          debugPrint("[VideoControllerHandler] controlsVisible event received");
          onControlsVisibilityChanged?.call(true);
          break;
        case BetterPlayerEventType.controlsHiddenEnd:
          debugPrint(
            "[VideoControllerHandler] controlsHiddenEnd event received",
          );
          onControlsVisibilityChanged?.call(false);
          break;
        default:
          break;
      }
    });

    try {
      await _controller!.setupDataSource(dataSource);
    } catch (e) {
      _initTimeoutTimer?.cancel();
      if (!completer.isCompleted) {
        onError();
        completer.complete(null);
      }
    }

    return completer.future;
  }

  Future<BetterPlayerController?> initialize({
    required String videoUrl,
    required VoidCallback onError,
    required VoidCallback onBufferingStart,
    required VoidCallback onBufferingEnd,
    required VoidCallback onTimeout,
    Map<String, String>? headers,
  }) async {
    await dispose();

    final dataSource = BetterPlayerDataSource(
      BetterPlayerDataSourceType.network,
      videoUrl,
      headers: headers,
      videoFormat: (videoUrl.toLowerCase().contains('.m3u8') ||
                    videoUrl.toLowerCase().contains('/hls/'))
          ? BetterPlayerVideoFormat.hls
          : null,
      drmConfiguration: BetterPlayerDrmConfiguration(
        drmType: BetterPlayerDrmType.token,
        token: headers?['Authorization']?.replaceAll('Bearer ', ''),
        headers: headers,
      ),
      useAsmsTracks: true,
      asmsTrackNames: ["360p", "480p", "720p"],
    );

    _controller = BetterPlayerController(_buildConfiguration());

    final completer = Completer<BetterPlayerController?>();

    _initTimeoutTimer = Timer(_initTimeout, () {
      if (!completer.isCompleted) {
        onTimeout();
        completer.complete(null);
      }
    });

    _controller!.addEventsListener((event) {
      if (_controller == null) return;
      switch (event.betterPlayerEventType) {
        case BetterPlayerEventType.initialized:
          _initTimeoutTimer?.cancel();
          _totalDuration =
              _controller?.videoPlayerController?.value.duration ??
              Duration.zero;
          onPositionChanged?.call(Duration.zero, _totalDuration);
          if (!completer.isCompleted) completer.complete(_controller);
          break;
        case BetterPlayerEventType.exception:
          _initTimeoutTimer?.cancel();
          onError();
          if (!completer.isCompleted) completer.complete(null);
          break;
        case BetterPlayerEventType.bufferingStart:
          onBufferingStart();
          break;
        case BetterPlayerEventType.bufferingEnd:
          onBufferingEnd();
          break;
        case BetterPlayerEventType.progress:
          _currentPosition =
              _controller?.videoPlayerController?.value.position ??
              Duration.zero;
          _totalDuration =
              _controller?.videoPlayerController?.value.duration ??
              _totalDuration;
          onPositionChanged?.call(_currentPosition, _totalDuration);
          break;
        case BetterPlayerEventType.pause:
          _isPlaying = false;
          onPlayingStateChanged?.call(false);
          break;
        case BetterPlayerEventType.finished:
          _isCompleted = true;
          onCompleted?.call();
          break;
        case BetterPlayerEventType.controlsVisible:
          onControlsVisibilityChanged?.call(true);
          break;
        case BetterPlayerEventType.controlsHiddenEnd:
          onControlsVisibilityChanged?.call(false);
          break;
        default:
          break;
      }
    });

    try {
      await _controller!.setupDataSource(dataSource);
    } catch (e) {
      _initTimeoutTimer?.cancel();
      if (!completer.isCompleted) {
        onError();
        completer.complete(null);
      }
    }

    return completer.future;
  }
}

class LectureDetailScreen extends StatefulWidget {
  final String lectureId;
  final String lectureTitle;
  final String chapterId;
  final String chapterTitle;
  final String courseId;
  final String? offlineVideoPath;
  final String? offlineVideoKey;
  final int initialPosition;
  final int? maxViews;

  const LectureDetailScreen({
    super.key,
    required this.lectureId,
    required this.lectureTitle,
    required this.chapterId,
    required this.chapterTitle,
    required this.courseId,
    this.offlineVideoPath,
    this.offlineVideoKey,
    this.initialPosition = 0,
    this.maxViews,
  });

  @override
  State<LectureDetailScreen> createState() => _LectureDetailScreenState();
}

class _LectureDetailScreenState extends State<LectureDetailScreen>
    with WidgetsBindingObserver {
  final _chapterRepository = ChapterRepository();
  final _discussionRepository = DiscussionRepository();
  final _permissionService = AttachmentPermissionService();
  final _featureManager = FeatureManager();
  final _authRepository = AuthRepository();
  final _userProgressService = UserProgressService();
  final _videoHandler = VideoControllerHandler();
  final _offlineViewService = OfflineViewService();
  final _encryptedVideoService = EncryptedVideoService();

  BetterPlayerController? get _betterPlayerController =>
      _videoHandler.controller;
  get _videoController => _videoHandler.videoPlayerController;

  VideoWatchTracker? _watchTracker;
  ChapterAudioWatermarkService? _audioWatermarkService;

  String _userId = '';
  String _studentCode = '';
  String _phoneNumber = '';

  int _lastSavedPosition = -1;
  int _lastSavedWatchedSeconds = -1;
  bool _viewCountApiCalled = false;

  bool _isLoadingChapter = true;
  bool _isLoadingDiscussions = false;
  bool _isOfflineMode = false;
  Map<String, dynamic>? _chapterData;

  bool _isLocked = true;
  bool _canWatch = false;
  bool _isActivated = false;
  bool _isFreePreview = false;
  bool _isFreePreviewAttachment = false;
  late int _maxViews;
  int _currentViews = 0;
  int _viewByMinute = 0;
  String _videoUrl = '';
  String _duration = '00:00';
  List<dynamic> _attachments = [];
  List<dynamic> _quizzes = [];
  List<dynamic> _discussions = [];

  bool _isPlaying = false;
  double _progress = 0.0;
  String _currentTime = '0:00';
  String _totalTime = '0:00';
  bool _offlineViewServiceInitialized = false;
  Duration _lastPosition = Duration.zero;
  bool _wasPlaying = false;

  bool _isVideoLoading = false;
  bool _isBuffering = false;
  bool _hasVideoError = false;
  VideoErrorType _videoErrorType = VideoErrorType.unknown;
  bool _isRetrying = false;
  bool _isEmulator = false;
  int _retryCount = 0;
  static const int _maxRetries = 3;
  static const List<int> _retryDelays = [1000, 3000, 5000];

  bool _isInFullScreen = false;

  double _playbackSpeed = 1.0;
  static const List<double> _speedOptions = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  bool _showControls = false;
  Timer? _hideControlsTimer;

  bool _hasSlowInternet = false;
  DateTime? _bufferingStartTime;
  Timer? _bufferingTimer;
  static const Duration _slowInternetThreshold = Duration(seconds: 8);

  bool _showDiscussionPanel = false;
  String _discussionTab = 'all';
  final _commentController = TextEditingController();

  final _audioRecorder = AudioRecorder();
  final _audioPlayer = AudioPlayer();
  final _recordedPlayer = AudioPlayer();
  bool _isRecording = false;
  String? _recordedPath;
  Duration _recordDuration = Duration.zero;

  final _recordedPosition = ValueNotifier<Duration>(Duration.zero);
  final _recordedTotalDuration = ValueNotifier<Duration>(Duration.zero);
  StreamSubscription<RecordState>? _recordSub;
  StreamSubscription<Duration>? _recordedPositionSub;
  StreamSubscription<Duration>? _recordedDurationSub;

  String? _currentlyPlayingUrl;
  final _listAudioPosition = ValueNotifier<Duration>(Duration.zero);
  final _listAudioDuration = ValueNotifier<Duration>(Duration.zero);
  StreamSubscription<Duration>? _listPositionSub;
  StreamSubscription<Duration>? _listDurationSub;

  String? _errorMessage;

  String? _selectedPdfUrl;
  String? _selectedPdfTitle;
  String? _localPdfPath;
  bool _isPdfLoading = false;

  bool _wasVideoPlayingBeforePdf = false;

  ValueNotifier<EncryptedDownloadProgress>? _downloadProgressNotifier;
  bool _isDownloaded = false;
  bool _isDownloading = false;

  bool _videoListenerAdded = false;
  bool _isOnline = true;

  Future<void> _loadUserData() async {
    final result = await _authRepository.getProfile();
    if (!mounted) return;
    if (result['success'] && mounted) {
      final userId = result['data']['id']?.toString() ?? '';
      final attributes = result['data']['attributes'];
      final studentCode = attributes?['student_code']?.toString() ?? '';
      final phoneNumber = attributes?['phone']?.toString() ?? '';
      setState(() {
        _userId = userId;
        _studentCode = studentCode;
        _phoneNumber = phoneNumber;
      });
    } else {
      // API failed or offline - use cached watermark data
      final cachedData = _authRepository.getCachedWatermarkData();
      if (mounted) {
        setState(() {
          _studentCode = cachedData['student_code'] ?? '';
          _phoneNumber = cachedData['phone'] ?? '';
        });
        debugPrint(
          '[LectureDetail] Using cached watermark data: studentCode=$_studentCode, phone=$_phoneNumber',
        );
      }
    }
  }

  Future<void> _detectEmulator() async {
    try {
      if (Platform.isAndroid) {
        final deviceInfo = DeviceInfoPlugin();
        final androidInfo = await deviceInfo.androidInfo;
        final brand = androidInfo.brand?.toLowerCase() ?? '';
        final device = androidInfo.device?.toLowerCase() ?? '';
        final model = androidInfo.model?.toLowerCase() ?? '';
        final manufacturer = androidInfo.manufacturer?.toLowerCase() ?? '';

        final isEmulator =
            brand.contains('google') ||
            device.contains('emulator') ||
            device.contains('simulator') ||
            model.contains('emulator') ||
            (manufacturer.contains('google') &&
                model.contains('pixel') &&
                androidInfo.isPhysicalDevice == false);

        if (isEmulator && mounted) {
          setState(() => _isEmulator = true);
          debugPrint(
            '[LectureDetail] Emulator detected - DRM video may not display',
          );
        }
      }
    } catch (e) {
      debugPrint('[LectureDetail] Error detecting emulator: $e');
    }
  }

  String? get _watermarkText {
    final config = _featureManager.getWatermarkConfig('chapters');
    final parts = <String>[];
    if (config.useStudentCode && _studentCode.isNotEmpty)
      parts.add(_studentCode);
    if (config.usePhoneNumber && _phoneNumber.isNotEmpty)
      parts.add(_phoneNumber);
    return parts.isNotEmpty ? parts.join(' | ') : null;
  }

  Future<void> _initAudioWatermark() async {
    _audioWatermarkService = ChapterAudioWatermarkService();
    await _audioWatermarkService!.init();
    if (!mounted) return;
    await _audioWatermarkService!.loadConfiguration();
  }

  @override
  void initState() {
    super.initState();
    _maxViews = widget.maxViews ?? 5;
    WidgetsBinding.instance.addObserver(this);
    _detectEmulator();
    _loadUserData();
    _initAudioWatermark();
    _encryptedVideoService.loadDownloadedVideos();

    if (widget.offlineVideoPath != null && widget.offlineVideoKey != null) {
      setState(() {
        _isOfflineMode = true;
        _isLocked = false;
        _canWatch = true;
        _isLoadingChapter = false;
        _videoUrl = 'offline';
      });
      _initializeOfflineVideo();
    } else {
      _loadChapterDetails();
      _loadDiscussions();
    }

    _recordSub = _audioRecorder.onStateChanged().listen((state) {});

    _recordedPositionSub = _recordedPlayer.onPositionChanged.listen((p) {
      _recordedPosition.value = p;
    });
    _recordedDurationSub = _recordedPlayer.onDurationChanged.listen((d) {
      _recordedTotalDuration.value = d;
    });
    _recordedPlayer.onPlayerComplete.listen((_) {
      _recordedPosition.value = Duration.zero;
    });

    _listPositionSub = _audioPlayer.onPositionChanged.listen((p) {
      _listAudioPosition.value = p;
    });
    _listDurationSub = _audioPlayer.onDurationChanged.listen((d) {
      _listAudioDuration.value = d;
    });
    _audioPlayer.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _currentlyPlayingUrl = null);
      _listAudioPosition.value = Duration.zero;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    _watchTracker?.onAppLifecycleStateChanged(state);

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _audioWatermarkService?.pause();
    } else if (state == AppLifecycleState.resumed) {
      _audioWatermarkService?.resume();
    }

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _saveProgressOnExit();
      _betterPlayerController?.pause();
      _audioPlayer.pause();
      _recordedPlayer.pause();
    }
  }

  void _initViewTracker() {
    _watchTracker?.dispose();
    _watchTracker = VideoWatchTracker(
      chapterId: widget.chapterId,
      viewByMinute: _viewByMinute,
      onThresholdReached: () async => await _onViewThresholdReached(),
    );
  }

  Future<void> _onViewThresholdReached() async {
    debugPrint(
      '[LectureDetail] _onViewThresholdReached() - _viewCountApiCalled=$_viewCountApiCalled, _isOfflineMode=$_isOfflineMode',
    );
    if (_viewCountApiCalled) return;
    _viewCountApiCalled = true;

    final chapterIdString = widget.chapterId;
    final chapterId = int.tryParse(chapterIdString);

    if (_isOfflineMode) {
      debugPrint(
        '[LectureDetail] Offline mode - incrementing local view count',
      );
      await _offlineViewService.incrementOfflineView(chapterIdString);

      final offlineViews = await _offlineViewService.getOfflineViews(
        chapterIdString,
      );
      final totalViews = _currentViews + offlineViews;

      debugPrint(
        '[LectureDetail] Offline view incremented. API: $_currentViews, Offline: $offlineViews, Total: $totalViews',
      );

      if (mounted) {
        await _checkAndEnforceViewLimit(totalViews);
      }
      return;
    }

    if (chapterId == null) {
      debugPrint(
        '[LectureDetail] Error: Failed to parse chapterId: $chapterIdString',
      );
      _viewCountApiCalled = false;
      return;
    }

    try {
      final watchedMinutes = (_watchTracker?.watchedSeconds ?? 0) ~/ 60;
      final minutesToSource = watchedMinutes > 0
          ? watchedMinutes
          : _viewByMinute;

      debugPrint(
        '[LectureDetail] Calling incrementViewCount: chapterId=$chapterId, watchedMinutes=$minutesToSource',
      );

      final result = await _chapterRepository.incrementViewCount(
        chapterId: chapterId,
        watchedMinutes: minutesToSource,
      );

      if (result['success'] && mounted) {
        debugPrint(
          '[LectureDetail] Successfully incremented view count. New views: ${result['current_views']}',
        );
        final newViewCount = result['current_views'] ?? _currentViews + 1;
        setState(() {
          _currentViews = newViewCount;
        });
        await _checkAndEnforceViewLimit(newViewCount);
      } else {
        debugPrint(
          '[LectureDetail] Failed to increment view count via API: ${result['message']}',
        );
        debugPrint('[LectureDetail] Falling back to offline view tracking');
        await _offlineViewService.incrementOfflineView(chapterIdString);

        if (mounted) {
          final offlineViews = await _offlineViewService.getOfflineViews(
            chapterIdString,
          );
          final totalViews = _currentViews + offlineViews;
          debugPrint(
            '[LectureDetail] Offline view incremented as fallback. API: $_currentViews, Offline: $offlineViews, Total: $totalViews',
          );
          await _checkAndEnforceViewLimit(totalViews);
        }
      }
    } catch (e) {
      debugPrint('[LectureDetail] Exception during incrementViewCount: $e');
      debugPrint(
        '[LectureDetail] Falling back to offline view tracking due to exception',
      );
      await _offlineViewService.incrementOfflineView(chapterIdString);

      if (mounted) {
        final offlineViews = await _offlineViewService.getOfflineViews(
          chapterIdString,
        );
        final totalViews = _currentViews + offlineViews;
        debugPrint(
          '[LectureDetail] Offline view incremented as fallback. API: $_currentViews, Offline: $offlineViews, Total: $totalViews',
        );
        await _checkAndEnforceViewLimit(totalViews);
      }
    }
  }

  Future<void> _checkAndEnforceViewLimit(int totalViews) async {
    debugPrint(
      '[LectureDetail] _checkAndEnforceViewLimit: totalViews=$totalViews, maxViews=$_maxViews',
    );

    if (totalViews >= _maxViews && _maxViews > 0) {
      debugPrint(
        '[LectureDetail] View limit reached ($totalViews >= $_maxViews). Blocking access.',
      );

      _betterPlayerController?.pause();

      if (_isOfflineMode) {
        final videoId = '${widget.courseId}_${widget.chapterId}';
        await _encryptedVideoService.deleteDownloadedVideo(videoId);
        debugPrint(
          '[LectureDetail] Deleted downloaded video due to exhausted views',
        );
      }

      setState(() {
        _canWatch = false;
        _errorMessage = 'course.maximum_views_reached'.tr();
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('course.maximum_views_reached'.tr()),
            backgroundColor: const Color(0xFFFF4B4B),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    _videoHandler.onPositionChanged = null;
    _videoHandler.onPlayingStateChanged = null;
    _videoHandler.onBufferingStateChanged = null;
    _videoHandler.onCompleted = null;

    _saveProgressOnExit();
    _watchTracker?.dispose();
    _audioWatermarkService?.dispose();
    _videoHandler.dispose();
    _commentController.dispose();
    _bufferingTimer?.cancel();
    _hideControlsTimer?.cancel();
    _recordSub?.cancel();
    _recordedPositionSub?.cancel();
    _recordedDurationSub?.cancel();
    _listPositionSub?.cancel();
    _listDurationSub?.cancel();
    _recordedPosition.dispose();
    _recordedTotalDuration.dispose();
    _listAudioPosition.dispose();
    _listAudioDuration.dispose();
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    _recordedPlayer.dispose();
    if (_downloadProgressNotifier != null) {
      _encryptedVideoService.disposeNotifier(_videoUrl);
    }
    if (_isOfflineMode) _cleanupTempOfflineVideo();
    super.dispose();
  }

  Future<void> _cleanupTempOfflineVideo() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final tempFile = File(
        '${tempDir.path}/offline_video_${widget.chapterId}.mp4',
      );
      if (await tempFile.exists()) await tempFile.delete();
    } catch (e) {
      debugPrint('Error cleaning up temp offline video: $e');
    }
  }

  void _saveProgressOnExit() {
    if (_isLocked || !_canWatch) return;

    final currentPosition = _videoHandler.currentPosition.inSeconds;
    final totalDuration = _videoHandler.totalDuration.inSeconds;
    final watchedSeconds = _watchTracker?.watchedSeconds ?? 0;
    final isCompleted =
        _videoHandler.isCompleted ||
        (totalDuration > 0 && currentPosition >= totalDuration - 5);

    if (widget.lectureId.isEmpty || totalDuration <= 0) return;

    if (currentPosition != _lastSavedPosition) {
      _lastSavedPosition = currentPosition;
      _userProgressService
          .sendProgress(
            lectureId: widget.lectureId,
            currentPosition: currentPosition,
            totalDuration: totalDuration,
            immediate: true,
          )
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () => {'success': false, 'timeout': true},
          )
          .catchError((e) => {'success': false, 'error': e.toString()});
    }

    final chapterIdInt = int.tryParse(widget.chapterId) ?? 0;
    if (chapterIdInt > 0 &&
        (watchedSeconds != _lastSavedWatchedSeconds || isCompleted)) {
      _lastSavedWatchedSeconds = watchedSeconds;
      _chapterRepository
          .updateUserProgress(
            chapterId: chapterIdInt,
            progressSeconds: watchedSeconds,
            isCompleted: isCompleted,
          )
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () => {'success': false, 'timeout': true},
          )
          .catchError((e) => {'success': false, 'error': e.toString()});
    }
  }

  void _checkDownloadStatus() {
    final videoId = '${widget.courseId}_${widget.chapterId}';
    final isDownloaded = _encryptedVideoService.isVideoDownloaded(videoId);
    if (mounted) setState(() => _isDownloaded = isDownloaded);
  }

  Future<void> _downloadVideo() async {
    if (!mounted) return;
    if (_isOfflineMode) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('course.video_already_downloaded'.tr()),
          backgroundColor: const Color(0xFF2DBC77),
        ),
      );
      return;
    }
    if (_videoUrl.isEmpty || _isLocked || !_canWatch) return;

    final videoId = '${widget.courseId}_${widget.chapterId}';
    if (_encryptedVideoService.isVideoDownloaded(videoId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('course.video_already_downloaded'.tr()),
          backgroundColor: const Color(0xFF2DBC77),
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('course.download_started'.tr()),
        backgroundColor: const Color(0xFF3451E5),
        duration: const Duration(seconds: 2),
      ),
    );

    final fileName = 'video_$videoId.enc';
    _downloadProgressNotifier = _encryptedVideoService.getProgressNotifier(
      _videoUrl,
      fileName,
    );
    if (mounted) setState(() => _isDownloading = true);

    _downloadProgressNotifier!.addListener(() {
      final progress = _downloadProgressNotifier!.value;
      if (progress.status == EncryptedDownloadStatus.completed) {
        if (mounted) {
          setState(() {
            _isDownloaded = true;
            _isDownloading = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('course.video_downloaded'.tr()),
              backgroundColor: const Color(0xFF2DBC77),
            ),
          );
        }
      } else if (progress.status == EncryptedDownloadStatus.failed) {
        if (mounted) {
          setState(() => _isDownloading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                progress.errorMessage ?? 'course.download_failed'.tr(),
              ),
              backgroundColor: const Color(0xFFFF4B4B),
            ),
          );
        }
      }
    });

    try {
      await _encryptedVideoService.downloadVideo(
        url: _videoUrl,
        chapterId: widget.chapterId,
        chapterTitle: widget.chapterTitle,
        lectureTitle: widget.lectureTitle,
        courseId: widget.courseId,
        duration: _duration,
        currentViews: _currentViews,
        maxViews: _maxViews,
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isDownloading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Download error: $e'),
            backgroundColor: const Color(0xFFFF4B4B),
          ),
        );
      }
    }
  }

  void _cancelDownload() {
    if (_isDownloading) {
      _encryptedVideoService.cancelDownload(_videoUrl);
      setState(() => _isDownloading = false);
    }
  }

  Future<void> _loadDiscussions() async {
    setState(() => _isLoadingDiscussions = true);
    try {
      final result = await _discussionRepository.getDiscussions(
        chapterId: int.tryParse(widget.chapterId),
      );
      if (result['success'] && mounted) {
        setState(() {
          _discussions = result['data'] ?? [];
          _isLoadingDiscussions = false;
        });
      } else if (mounted) {
        setState(() => _isLoadingDiscussions = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingDiscussions = false);
    }
  }

  Future<void> _ensureOfflineViewInitialized() async {
    if (_offlineViewServiceInitialized) return;
    await _offlineViewService.initialize();
    _offlineViewServiceInitialized = true;
  }

  Future<void> _startRecording() async {
    try {
      final hasPermission = await _audioRecorder.hasPermission();
      if (hasPermission) {
        final directory = await getApplicationDocumentsDirectory();
        final path =
            '${directory.path}/recording_${DateTime.now().millisecondsSinceEpoch}.m4a';
        await _audioRecorder.start(const RecordConfig(), path: path);
        setState(() {
          _isRecording = true;
          _recordedPath = null;
        });
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('course.mic_permission_required'.tr())),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('course.error_msg'.tr(args: [e.toString()]))),
        );
      }
    }
  }

  Future<void> _stopRecording() async {
    try {
      final path = await _audioRecorder.stop();
      setState(() {
        _isRecording = false;
        _recordedPath = path;
      });
    } catch (e) {
      debugPrint('Error stopping recording: $e');
    }
  }

  Future<void> _postDiscussion() async {
    if (widget.chapterId.isEmpty) return;
    final chapterId = int.tryParse(widget.chapterId);
    if (chapterId == null) return;

    final moment = _videoHandler.currentPosition.inSeconds;
    setState(() => _isLoadingDiscussions = true);

    Map<String, dynamic> result;
    if (_discussionTab == 'voice' && _recordedPath != null) {
      result = await _discussionRepository.postDiscussion(
        chapterId: chapterId,
        type: 'voice',
        content: '',
        moment: moment,
        voiceFile: File(_recordedPath!),
      );
    } else {
      if (_commentController.text.trim().isEmpty) {
        setState(() => _isLoadingDiscussions = false);
        return;
      }
      result = await _discussionRepository.postDiscussion(
        chapterId: chapterId,
        type: 'text',
        content: _commentController.text.trim(),
        moment: moment,
      );
    }

    if (result['success'] && mounted) {
      _commentController.clear();
      _recordedPath = null;
      _discussionTab = 'all';
      await _loadDiscussions();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('course.discussion_posted'.tr())));
    } else if (mounted) {
      setState(() => _isLoadingDiscussions = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result['message'] ?? 'course.failed_post_discussion'.tr(),
          ),
        ),
      );
    }
  }

  Future<void> _playDiscussionAudio(String url) async {
    if (_currentlyPlayingUrl == url &&
        _audioPlayer.state == PlayerState.playing) {
      await _audioPlayer.pause();
    } else {
      if (_currentlyPlayingUrl != url) {
        await _audioPlayer.stop();
        setState(() => _currentlyPlayingUrl = url);
        _listAudioPosition.value = Duration.zero;
      }
      final resolvedUrl = _resolveAudioUrl(url);
      try {
        await _audioPlayer.play(UrlSource(resolvedUrl));
      } catch (e) {
        debugPrint('Error playing discussion audio: $e');
      }
    }
    setState(() {});
  }

  Future<void> _playRecordedAudio() async {
    if (_recordedPath == null) return;
    try {
      if (_recordedPlayer.state == PlayerState.playing) {
        await _recordedPlayer.pause();
      } else {
        await _recordedPlayer.play(DeviceFileSource(_recordedPath!));
      }
    } catch (e) {
      debugPrint('Error playing recorded audio: $e');
    }
  }

  Future<void> _loadChapterDetails() async {
    if (widget.chapterId.isEmpty) {
      setState(() {
        _isLoadingChapter = false;
        _errorMessage = 'course.invalid_chapter_id'.tr();
      });
      return;
    }

    setState(() => _isLoadingChapter = true);
    try {
      final result = await _chapterRepository.getChapterById(widget.chapterId);
      if (result['success'] && mounted) {
        final data = result['data'] ?? {};
        final attributes = data['attributes'] ?? {};

        final apiMaxViews =
            int.tryParse(attributes['max_views']?.toString() ?? '') ?? 5;
        final apiCurrentViews =
            int.tryParse(attributes['current_user_views']?.toString() ?? '') ??
            0;

        await _ensureOfflineViewInitialized();
        final offlineViews = await _offlineViewService.syncWithApi(
          widget.chapterId,
          apiCurrentViews,
          apiMaxViews,
        );
        final totalViews = apiCurrentViews + offlineViews;

        setState(() {
          _chapterData = data;
          _isLocked = attributes['is_locked'] as bool? ?? true;
          _canWatch = attributes['can_watch'] as bool? ?? false;
          _isActivated = attributes['is_activated'] as bool? ?? false;
          _isFreePreview = attributes['is_free_preview'] as bool? ?? false;
          _isFreePreviewAttachment =
              attributes['is_free_preview_attachment'] as bool? ?? false;
          _maxViews = apiMaxViews;
          _currentViews = totalViews;
          _viewByMinute =
              int.tryParse(attributes['view_by_minute']?.toString() ?? '') ?? 0;
          _duration = attributes['duration']?.toString() ?? '00:00';
          _totalTime = _duration;

          String playlistUrl = attributes['video']?.toString() ?? '';
          String videoUrl = attributes['video']?.toString() ?? '';

          if (playlistUrl.isNotEmpty) {
            playlistUrl = playlistUrl.replaceAll('\\', '/');
            if (!playlistUrl.startsWith('http')) {
              if (!playlistUrl.startsWith('/')) playlistUrl = '/$playlistUrl';
              playlistUrl = '${ApiConstants.baseUrl}$playlistUrl';
            }
            _videoUrl = playlistUrl;
          } else if (videoUrl.isNotEmpty) {
            videoUrl = videoUrl.replaceAll('\\', '/');
            if (!videoUrl.startsWith('http')) {
              if (!videoUrl.startsWith('/')) videoUrl = '/$videoUrl';
              _videoUrl = '${ApiConstants.baseUrl}$videoUrl';
            } else {
              _videoUrl = videoUrl;
            }
          }
          _attachments = attributes['attachments'] as List<dynamic>? ?? [];
          _quizzes = attributes['quizzes'] as List<dynamic>? ?? [];
          _discussions = attributes['discussions'] as List<dynamic>? ?? [];
        });

        debugPrint(
          '[LectureDetail] Loaded chapter views - API: $apiCurrentViews, Offline: $offlineViews, Total: $totalViews, Max: $_maxViews',
        );

        if (totalViews >= apiMaxViews && apiMaxViews > 0) {
          setState(() {
            _errorMessage = 'course.maximum_views_reached'.tr();
            _canWatch = false;
            _isLoadingChapter = false;
          });
          return;
        }

        final shouldInitVideo =
            (!_isLocked || _canWatch) && _videoUrl.isNotEmpty;

        _initViewTracker();
        setState(() {
          _isLoadingChapter = false;
          if (shouldInitVideo) _isVideoLoading = true;
        });
        _checkDownloadStatus();

        if (shouldInitVideo) await _initializeVideoPlayer();
      } else if (mounted) {
        final maxViewsFromError = (result['max_views'] as num?)?.toInt();
        final currentViewsFromError = (result['current_views'] as num?)
            ?.toInt();

        setState(() {
          _isLoadingChapter = false;
          _errorMessage =
              result['message'] ?? 'course.failed_load_chapter'.tr();
          if (maxViewsFromError != null) _maxViews = maxViewsFromError;
          if (currentViewsFromError != null)
            _currentViews = currentViewsFromError;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingChapter = false;
          _errorMessage = 'course.connection_error'.tr(args: [e.toString()]);
        });
      }
    }
  }

  Future<void> _initializeVideoPlayer() async {
    if (_videoUrl.isEmpty) return;

    final hasInternet = await _videoHandler.checkConnectivity();
    if (!hasInternet && !_isOfflineMode) {
      setState(() {
        _hasVideoError = true;
        _videoErrorType = VideoErrorType.network;
        _isVideoLoading = false;
      });
      return;
    }

    setState(() {
      _isVideoLoading = true;
      _hasVideoError = false;
      _videoErrorType = VideoErrorType.unknown;
    });

    debugPrint(
      '[LectureDetail] Initializing video player with URL: $_videoUrl',
    );

    _videoHandler.onPositionChanged = (position, duration) {
      if (!mounted) return;
      final newTime = _formatDuration(position);
      final newProgress = duration.inSeconds > 0
          ? position.inSeconds / duration.inSeconds
          : 0.0;

      if (newTime != _currentTime || newProgress != _progress) {
        setState(() {
          _currentTime = newTime;
          _totalTime = _formatDuration(duration);
          _progress = newProgress;
        });
      }
    };

    _videoHandler.onPlayingStateChanged = (isPlaying) {
      setState(() => _isPlaying = isPlaying);
    };
    _videoHandler.onCompleted = () => _saveProgressOnExit();
    try {
      final token = await _authRepository.getToken();
      final Map<String, String> headers = {
        if (token != null) 'Authorization': 'Bearer $token',
        'Accept': 'application/json, text/plain, */*',
      };

      debugPrint('[LectureDetail] Pre-checking video URL: $_videoUrl');
      // Simple log to see if the URL is accessible with headers
      try {
        final client = HttpClient();
        final request = await client.getUrl(Uri.parse(_videoUrl));
        headers.forEach((key, value) => request.headers.add(key, value));
        final response = await request.close();
        debugPrint(
          '[LectureDetail] URL Check Response Code: ${response.statusCode}',
        );
        debugPrint(
          '[LectureDetail] URL Check Response Headers: ${response.headers}',
        );
        client.close();
      } catch (e) {
        debugPrint('[LectureDetail] URL Check Exception: $e');
      }

      final controller = await _videoHandler.initialize(
        videoUrl: _videoUrl,
        onError: _onVideoError,
        onBufferingStart: () => setState(() => _isBuffering = true),
        onBufferingEnd: () => setState(() => _isBuffering = false),
        onTimeout: _onVideoTimeout,
        headers: headers,
      );

      if (!mounted) return;
      if (controller == null) {
        if (!_hasVideoError) _onVideoTimeout();
        return;
      }

      setState(() {
        _isVideoLoading = false;
        _retryCount = 0;
        _totalTime = _formatDuration(_videoHandler.totalDuration);
      });

      // Add direct listener for controls visibility
      controller.addEventsListener((event) {
        if (!mounted) return;
        if (event.betterPlayerEventType ==
            BetterPlayerEventType.controlsVisible) {
          setState(() => _showControls = true);
        } else if (event.betterPlayerEventType ==
            BetterPlayerEventType.controlsHiddenEnd) {
          setState(() => _showControls = false);
        }
      });

      if (widget.initialPosition > 0) {
        await _betterPlayerController!.seekTo(
          Duration(seconds: widget.initialPosition),
        );
      }

      if (!_isOfflineMode && _betterPlayerController != null) {
        if (_watchTracker == null) {
          _initViewTracker();
        }
        _watchTracker?.attach(_betterPlayerController!);
      }

      if (_audioWatermarkService != null &&
          _audioWatermarkService!.isEnabled &&
          _audioWatermarkService!.interval > 0 &&
          _betterPlayerController != null) {
        _audioWatermarkService!.start(_betterPlayerController!);
      }
    } catch (e) {
      _onVideoErrorWithMessage(e.toString());
    }
  }

  void _onVideoTimeout() {
    if (!mounted) return;
    setState(() {
      _isVideoLoading = false;
      _isBuffering = false;
      _hasVideoError = true;
      _videoErrorType = VideoErrorType.network;
      _hasSlowInternet = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('course.video_loading_timeout'.tr()),
        backgroundColor: const Color(0xFFFF4B4B),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'Retry',
          textColor: Colors.white,
          onPressed: _retryVideo,
        ),
      ),
    );
  }

  void _onVideoError() {
    if (!mounted) return;
    final error = _videoController?.value.errorDescription ?? '';
    _onVideoErrorWithMessage(error);
  }

  void _onVideoErrorWithMessage(String errorMessage) {
    if (!mounted) return;
    debugPrint('[LectureDetail] Video Error: $errorMessage');
    final errorType = VideoErrorMapper.mapError(errorMessage);
    setState(() {
      _isVideoLoading = false;
      _isBuffering = false;
      _hasVideoError = true;
      _videoErrorType = errorType;
      if (errorType == VideoErrorType.network) _hasSlowInternet = true;
    });
  }

  Future<void> _retryVideo() async {
    if (_videoHandler.isRetrying) return;

    if (_retryCount >= _maxRetries) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('course.video_max_retries_reached'.tr()),
            backgroundColor: const Color(0xFFFF4B4B),
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'Try Again',
              textColor: Colors.white,
              onPressed: () {
                _retryCount = 0;
                _retryVideo();
              },
            ),
          ),
        );
      }
      return;
    }

    _videoHandler.setRetrying(true);
    _viewCountApiCalled = false;
    setState(() {
      _isRetrying = true;
      _hasVideoError = false;
      _videoErrorType = VideoErrorType.unknown;
      _hasSlowInternet = false;
    });

    final hasInternet = await _videoHandler.checkConnectivity();
    if (!hasInternet && !_isOfflineMode) {
      setState(() {
        _hasVideoError = true;
        _videoErrorType = VideoErrorType.network;
        _isRetrying = false;
      });
      _videoHandler.setRetrying(false);
      return;
    }

    if (_retryCount > 0 && _retryCount <= _retryDelays.length) {
      await Future.delayed(
        Duration(milliseconds: _retryDelays[_retryCount - 1]),
      );
    }

    _videoListenerAdded = false;
    await _videoHandler.dispose();
    await _initializeVideoPlayer();

    if (mounted) {
      setState(() => _isRetrying = false);
      if (!_hasVideoError) {
        _retryCount = 0;
      } else {
        _retryCount++;
      }
    }
    _videoHandler.setRetrying(false);
  }

  String _getVideoErrorMessage() => VideoErrorMapper.getUserMessage(
    _videoErrorType,
    'course.something_went_wrong',
  );

  Future<void> _initializeOfflineVideo() async {
    if (widget.offlineVideoPath == null || widget.offlineVideoKey == null)
      return;

    await _encryptedVideoService.loadDownloadedVideos();
    await _ensureOfflineViewInitialized();
    final videoId = '${widget.courseId}_${widget.chapterId}';
    final downloadedVideo = _encryptedVideoService.getDownloadedVideo(videoId);

    final offlineServiceViews = _offlineViewService.getOfflineViewsSync(
      widget.chapterId,
    );
    final downloadedViews = downloadedVideo?.currentViews ?? 0;
    final totalOfflineViews = downloadedViews + offlineServiceViews;
    final maxViews = downloadedVideo?.maxViews ?? _maxViews;

    debugPrint(
      '[LectureDetail] _initializeOfflineVideo - Downloaded views: $downloadedViews, Offline service views: $offlineServiceViews, Total: $totalOfflineViews, Max: $maxViews',
    );

    if (totalOfflineViews >= maxViews && maxViews > 0) {
      await _encryptedVideoService.deleteDownloadedVideo(videoId);
      await _offlineViewService.clearOfflineViews(widget.chapterId);
      if (mounted) {
        setState(() {
          _isVideoLoading = false;
          _hasVideoError = true;
          _videoErrorType = VideoErrorType.source;
          _canWatch = false;
          _currentViews = totalOfflineViews;
          _maxViews = maxViews;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('course.maximum_views_reached'.tr()),
            backgroundColor: const Color(0xFFFF4B4B),
            duration: const Duration(seconds: 5),
          ),
        );
      }
      return;
    }

    setState(() {
      _currentViews = totalOfflineViews;
      _maxViews = maxViews;
    });

    setState(() {
      _isVideoLoading = true;
      _hasVideoError = false;
    });

    try {
      final encryptedFile = File(widget.offlineVideoPath!);
      if (!await encryptedFile.exists()) {
        throw Exception('Downloaded video file not found');
      }

      final encryptedData = await encryptedFile.readAsBytes();
      final keyBytes = base64.decode(widget.offlineVideoKey!);
      final decryptedData = Uint8List(encryptedData.length);
      for (var i = 0; i < encryptedData.length; i++) {
        decryptedData[i] = encryptedData[i] ^ keyBytes[i % keyBytes.length];
      }

      final tempDir = await getTemporaryDirectory();
      final tempFile = File(
        '${tempDir.path}/offline_video_${widget.chapterId}.mp4',
      );
      await tempFile.writeAsBytes(decryptedData);

      _videoHandler.onPositionChanged = (position, duration) {
        if (!mounted) return;
        final newTime = _formatDuration(position);
        final newProgress = duration.inSeconds > 0
            ? position.inSeconds / duration.inSeconds
            : 0.0;

        if (newTime != _currentTime || newProgress != _progress) {
          setState(() {
            _currentTime = newTime;
            _totalTime = _formatDuration(duration);
            _progress = newProgress;
          });
        }
      };

      _videoHandler.onPlayingStateChanged = (isPlaying) =>
          setState(() => _isPlaying = isPlaying);
      _videoHandler.onCompleted = () => _saveProgressOnExit();

      final controller = await _videoHandler.initializeFromFile(
        videoFile: tempFile,
        onError: _onVideoError,
        onBufferingStart: () => setState(() => _isBuffering = true),
        onBufferingEnd: () => setState(() => _isBuffering = false),
        onTimeout: _onVideoTimeout,
      );

      if (!mounted) return;
      if (controller == null) {
        if (!_hasVideoError) _onVideoTimeout();
        return;
      }

      setState(() {
        _isVideoLoading = false;
        _retryCount = 0;
        _totalTime = _formatDuration(_videoHandler.totalDuration);
        _duration = _totalTime;
      });

      // Add direct listener for controls visibility
      controller.addEventsListener((event) {
        if (!mounted) return;
        if (event.betterPlayerEventType ==
            BetterPlayerEventType.controlsVisible) {
          setState(() => _showControls = true);
        } else if (event.betterPlayerEventType ==
            BetterPlayerEventType.controlsHiddenEnd) {
          setState(() => _showControls = false);
        }
      });

      if (widget.initialPosition > 0) {
        await _betterPlayerController!.seekTo(
          Duration(seconds: widget.initialPosition),
        );
      }

      if (_betterPlayerController != null) {
        if (_watchTracker == null) {
          _initViewTracker();
        }
        _watchTracker?.attach(_betterPlayerController!);
      }

      if (_audioWatermarkService != null &&
          _audioWatermarkService!.isEnabled &&
          _audioWatermarkService!.interval > 0 &&
          _betterPlayerController != null) {
        _audioWatermarkService!.start(_betterPlayerController!);
      }

      _viewCountApiCalled = false;
      _watchTracker?.reset();
      _lastPosition = _videoHandler.currentPosition;
    } catch (e) {
      debugPrint('Error initializing offline video: $e');
      if (mounted) {
        setState(() {
          _isVideoLoading = false;
          _hasVideoError = true;
          _videoErrorType = VideoErrorType.source;
        });
      }
    }
  }

  void _videoListener() {
    if (!mounted || _videoController == null) return;

    final position = _videoController!.value.position;
    final duration = _videoController!.value.duration;
    final isPlaying = _videoController!.value.isPlaying;
    final isBuffering = _videoController!.value.isBuffering;

    _detectSlowInternet(isBuffering, isPlaying);

    _lastPosition = position;
    _wasPlaying = isPlaying;

    final isBufferingChanged = isBuffering != _isBuffering;
    if (isBufferingChanged) {
      setState(() => _isBuffering = isBuffering);
    }
  }

  void _detectSlowInternet(bool isBuffering, bool isPlaying) {
    if (isBuffering && isPlaying) {
      if (_bufferingStartTime == null) {
        _bufferingStartTime = DateTime.now();
        _startBufferingTimer();
      }
    } else {
      _bufferingStartTime = null;
      _bufferingTimer?.cancel();
      if (_hasSlowInternet) setState(() => _hasSlowInternet = false);
    }
  }

  void _startBufferingTimer() {
    _bufferingTimer?.cancel();
    _bufferingTimer = Timer(_slowInternetThreshold, () {
      if (mounted && _bufferingStartTime != null) {
        setState(() => _hasSlowInternet = true);
      }
    });
  }

  bool _isNetworkError(String errorMessage) {
    final keywords = [
      'timeout',
      'connection',
      'socket',
      'network',
      'failed to load',
      'unable to load',
      'internet',
      'unreachable',
      'refused',
      'failed host lookup',
    ];
    final lower = errorMessage.toLowerCase();
    return keywords.any((k) => lower.contains(k));
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  void _togglePlay() {
    if (_betterPlayerController == null) return;
    if (_isPlaying) {
      _betterPlayerController!.pause();
    } else {
      _betterPlayerController!.play();
    }
  }

  void _seekTo(double value) {
    if (_videoController == null) return;
    final duration = _videoController!.value.duration;
    final position = Duration(seconds: (value * duration.inSeconds).round());
    _betterPlayerController!.seekTo(position);
  }

  void _cyclePlaybackSpeed() {
    final currentIndex = _speedOptions.indexOf(_playbackSpeed);
    final nextIndex = (currentIndex + 1) % _speedOptions.length;
    final newSpeed = _speedOptions[nextIndex];
    setState(() => _playbackSpeed = newSpeed);
    _betterPlayerController?.setSpeed(newSpeed);
  }

  String _formatSpeed(double speed) =>
      speed == speed.truncateToDouble() ? '${speed.toInt()}x' : '${speed}x';

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted && _isPlaying) {
        setState(() => _showControls = false);
      }
    });
  }

  void _onVideoTap() {
    setState(() => _showControls = true);
  }

  Future<void> _activateCode({
    required String code,
    required int itemId,
    required String itemType,
  }) async {
    if (code.isEmpty) return;
    final result = await _chapterRepository.activateCode(
      code: code,
      itemId: itemId,
      itemType: itemType,
    );
    if (mounted) {
      if (result['success']) {
        setState(() {
          _isLocked = false;
          _canWatch = true;
        });
        _loadChapterDetails();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('course.chapter_unlocked'.tr()),
            backgroundColor: const Color(0xFF2DBC77),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result['message'] ?? 'course.invalid_activation_code'.tr(),
            ),
            backgroundColor: const Color(0xFFFF4B4B),
          ),
        );
      }
    }
  }

  void _showActivationCodeDialog() {
    final codeController = TextEditingController();
    String selectedType = 'chapter';
    final courseId = int.tryParse(widget.courseId);

    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black.withValues(alpha: 0.6),
      transitionDuration: const Duration(milliseconds: 320),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutBack,
        );
        return ScaleTransition(
          scale: curved,
          child: FadeTransition(opacity: animation, child: child),
        );
      },
      pageBuilder: (context, animation, secondaryAnimation) => StatefulBuilder(
        builder: (context, setDialogState) => Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF3451E5).withValues(alpha: 0.18),
                    blurRadius: 40,
                    offset: const Offset(0, 16),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF3451E5), Color(0xFF6C47FF)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(24),
                      ),
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.3),
                              width: 2,
                            ),
                          ),
                          child: const Center(
                            child: FaIcon(
                              FontAwesomeIcons.lock,
                              color: Colors.white,
                              size: 28,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'course.chapter_locked'.tr(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'course.enter_activation_code'.tr(),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.82),
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 22, 24, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'course.apply_code_to'.tr(),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF374151),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setDialogState(
                                  () => selectedType = 'chapter',
                                ),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: selectedType == 'chapter'
                                        ? const Color(0xFF3451E5)
                                        : const Color(0xFFF3F4F6),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: selectedType == 'chapter'
                                          ? const Color(0xFF3451E5)
                                          : const Color(0xFFE5E7EB),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      FaIcon(
                                        FontAwesomeIcons.book,
                                        size: 13,
                                        color: selectedType == 'chapter'
                                            ? Colors.white
                                            : const Color(0xFF6B7280),
                                      ),
                                      const SizedBox(width: 7),
                                      Text(
                                        'course.this_chapter'.tr(),
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: selectedType == 'chapter'
                                              ? Colors.white
                                              : const Color(0xFF6B7280),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setDialogState(
                                  () => selectedType = 'course',
                                ),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: selectedType == 'course'
                                        ? const Color(0xFF3451E5)
                                        : const Color(0xFFF3F4F6),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: selectedType == 'course'
                                          ? const Color(0xFF3451E5)
                                          : const Color(0xFFE5E7EB),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      FaIcon(
                                        FontAwesomeIcons.layerGroup,
                                        size: 13,
                                        color: selectedType == 'course'
                                            ? Colors.white
                                            : const Color(0xFF6B7280),
                                      ),
                                      const SizedBox(width: 7),
                                      Text(
                                        'course.full_course'.tr(),
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: selectedType == 'course'
                                              ? Colors.white
                                              : const Color(0xFF6B7280),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        Text(
                          'course.activation_code'.tr(),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF374151),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: codeController,
                          textCapitalization: TextCapitalization.characters,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            letterSpacing: 1.5,
                            color: Color(0xFF111827),
                          ),
                          decoration: InputDecoration(
                            hintText: 'course.eg_code'.tr(),
                            hintStyle: const TextStyle(
                              letterSpacing: 0.5,
                              color: Color(0xFFD1D5DB),
                              fontWeight: FontWeight.w400,
                            ),
                            prefixIcon: Container(
                              margin: const EdgeInsets.all(10),
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEEF2FF),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const FaIcon(
                                FontAwesomeIcons.key,
                                size: 14,
                                color: Color(0xFF3451E5),
                              ),
                            ),
                            filled: true,
                            fillColor: const Color(0xFFF9FAFB),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(
                                color: Color(0xFFE5E7EB),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(
                                color: Color(0xFFE5E7EB),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(
                                color: Color(0xFF3451E5),
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.pop(context),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  side: const BorderSide(
                                    color: Color(0xFFE5E7EB),
                                    width: 1.5,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  foregroundColor: const Color(0xFF6B7280),
                                ),
                                child: Text(
                                  'course.cancel'.tr(),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFF3451E5),
                                      Color(0xFF6C47FF),
                                    ],
                                    begin: Alignment.centerLeft,
                                    end: Alignment.centerRight,
                                  ),
                                  borderRadius: BorderRadius.circular(14),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(
                                        0xFF3451E5,
                                      ).withValues(alpha: 0.35),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    final code = codeController.text.trim();
                                    if (code.isNotEmpty) {
                                      Navigator.pop(context);
                                      final itemId = selectedType == 'chapter'
                                          ? int.tryParse(widget.chapterId) ?? 0
                                          : courseId ?? 0;
                                      if (itemId > 0) {
                                        _activateCode(
                                          code: code,
                                          itemId: itemId,
                                          itemType: selectedType,
                                        );
                                      }
                                    }
                                  },
                                  icon: const FaIcon(
                                    FontAwesomeIcons.unlockKeyhole,
                                    size: 14,
                                    color: Colors.white,
                                  ),
                                  label: Text(
                                    'course.unlock_now'.tr(),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                      color: Colors.white,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                    shadowColor: Colors.transparent,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openAskMoment() => setState(() => _showDiscussionPanel = true);
  void _closeDiscussionPanel() => setState(() => _showDiscussionPanel = false);

  @override
  Widget build(BuildContext context) {
    if (_isLoadingChapter) return _buildLoadingScreen();
    final bool isViewLimitReached = _maxViews > 0 && _currentViews >= _maxViews;
    if (_errorMessage != null && _chapterData == null)
      return _buildErrorScreen();
    if (isViewLimitReached && _errorMessage != null) return _buildErrorScreen();

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) _saveProgressOnExit();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Stack(
          children: [
            SafeArea(
              child: Column(
                children: [
                  _buildVideoPlayer(),
                  Expanded(
                    child: _selectedPdfUrl != null
                        ? _buildEmbeddedPdfViewer()
                        : SingleChildScrollView(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildAskButton(),
                                  const SizedBox(height: 20),
                                  LectureHeader(
                                    lectureTitle: widget.lectureTitle,
                                    chapterTitle: widget.chapterTitle,
                                    currentViews: _currentViews,
                                    maxViews: _maxViews,
                                    duration: _duration,
                                    isLocked: _isLocked,
                                    isActivated: _isActivated,
                                  ),
                                  const SizedBox(height: 24),
                                  AttachmentsList(
                                    attachments: _attachments,
                                    onOpenPdf: _openPdf,
                                    chapterIsLocked: _isLocked,
                                    chapterIsActivated: _isActivated,
                                    chapterIsFreePreview: _isFreePreview,
                                    chapterIsFreePreviewAttachment:
                                        _isFreePreviewAttachment,
                                  ),
                                  const SizedBox(height: 24),
                                  QuizzesList(
                                    quizzes: _quizzes,
                                    onStartQuiz: _startQuiz,
                                  ),
                                  const SizedBox(height: 40),
                                ],
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
            if (_showDiscussionPanel)
              DiscussionPanel(
                currentPositionSeconds: _videoHandler.currentPosition.inSeconds,
                isLoading: _isLoadingDiscussions,
                discussions: _discussions,
                currentTab: _discussionTab,
                isRecording: _isRecording,
                recordedPath: _recordedPath,
                recordedPosition: _recordedPosition,
                recordedTotalDuration: _recordedTotalDuration,
                currentlyPlayingUrl: _currentlyPlayingUrl,
                listAudioPosition: _listAudioPosition,
                listAudioDuration: _listAudioDuration,
                onClose: _closeDiscussionPanel,
                onTabChanged: (tab) => setState(() => _discussionTab = tab),
                commentController: _commentController,
                onPost: _postDiscussion,
                onStartRecording: _startRecording,
                onStopRecording: _stopRecording,
                onDeleteRecorded: () {
                  setState(() {
                    _recordedPath = null;
                    _recordedPosition.value = Duration.zero;
                    _recordedTotalDuration.value = Duration.zero;
                  });
                  _recordedPlayer.stop();
                },
                onPlayPauseAudio: _playDiscussionAudio,
                onPlayRecorded: _playRecordedAudio,
                onAddReply: () {},
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingScreen() {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Shimmer.fromColors(
              baseColor: Colors.grey[300]!,
              highlightColor: Colors.grey[100]!,
              child: Container(
                height: 220,
                width: double.infinity,
                color: Colors.white,
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Shimmer.fromColors(
                  baseColor: Colors.grey[300]!,
                  highlightColor: Colors.grey[100]!,
                  child: Container(height: 20, width: 200, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorScreen() {
    final errorLower = _errorMessage?.toLowerCase() ?? '';
    final isLockedError =
        errorLower.contains('locked') == true ||
        _isLocked ||
        errorLower.contains('activate') == true;
    final isMaxViewsError =
        errorLower.contains('maximum') && errorLower.contains('views') ||
        (_currentViews > 0 && _maxViews > 0 && _currentViews >= _maxViews);
    final showActivationButton = isLockedError || isMaxViewsError;
    final primaryColor = showActivationButton
        ? const Color(0xFF3451E5)
        : const Color(0xFFFF4B4B);
    final accentColor = showActivationButton
        ? const Color(0xFF6C47FF)
        : const Color(0xFFFF6B6B);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [primaryColor, accentColor],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: primaryColor.withValues(alpha: 0.3),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Center(
                    child: FaIcon(
                      showActivationButton
                          ? FontAwesomeIcons.lock
                          : FontAwesomeIcons.circleExclamation,
                      color: Colors.white,
                      size: 40,
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  isMaxViewsError
                      ? 'course.views_exceeded_title'.tr()
                      : (showActivationButton
                            ? 'course.chapter_locked_title'.tr()
                            : 'course.error_title'.tr()),
                  style: TextStyle(
                    color: const Color(0xFF1F2937),
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  _errorMessage ?? 'course.an_error_occurred'.tr(),
                  style: const TextStyle(
                    color: Color(0xFF6B7280),
                    fontSize: 15,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                if (showActivationButton && _maxViews > 0) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                    decoration: BoxDecoration(
                      color: isMaxViewsError
                          ? const Color(0xFFFFEBEE)
                          : const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isMaxViewsError
                            ? const Color(0xFFEF5350).withValues(alpha: 0.3)
                            : const Color(0xFFE5E7EB),
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            FaIcon(
                              FontAwesomeIcons.eye,
                              size: 16,
                              color: isMaxViewsError
                                  ? const Color(0xFFEF5350)
                                  : const Color(0xFF3451E5),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'course.views_usage'.tr(),
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            width: 200,
                            height: 8,
                            child: LinearProgressIndicator(
                              value: _maxViews > 0
                                  ? (_currentViews / _maxViews).clamp(0.0, 1.0)
                                  : 0,
                              backgroundColor: Colors.grey[300],
                              valueColor: AlwaysStoppedAnimation<Color>(
                                isMaxViewsError
                                    ? const Color(0xFFEF5350)
                                    : const Color(0xFF3451E5),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${_currentViews} / ${_maxViews} ${'course.views'.tr()}',
                          style: TextStyle(
                            color: isMaxViewsError
                                ? const Color(0xFFEF5350)
                                : const Color(0xFF3451E5),
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (isMaxViewsError) ...[
                          const SizedBox(height: 4),
                          Text(
                            'course.views_exceeded_hint'.tr(),
                            style: TextStyle(
                              color: Colors.grey[500],
                              fontSize: 12,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
                if (showActivationButton)
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [primaryColor, accentColor],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: primaryColor.withValues(alpha: 0.35),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ElevatedButton.icon(
                      onPressed: _showActivationCodeDialog,
                      icon: const FaIcon(
                        FontAwesomeIcons.key,
                        size: 16,
                        color: Colors.white,
                      ),
                      label: Text(
                        'course.enter_activation_code_btn'.tr(),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: Colors.white,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 28,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  )
                else
                  ElevatedButton.icon(
                    onPressed: _loadChapterDetails,
                    icon: const FaIcon(FontAwesomeIcons.rotateRight, size: 16),
                    label: Text('course.retry'.tr()),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _enterFullScreen() async {
    if (_betterPlayerController == null ||
        !(_betterPlayerController!.isVideoInitialized() ?? false))
      return;

    setState(() => _isInFullScreen = true);

    await Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => _FullScreenVideoPlayer(
          sourceController: _betterPlayerController!,
          watermarkText: _watermarkText,
          featureManager: _featureManager,
          onExit: () {
            if (mounted) {
              setState(() => _isInFullScreen = false);
            }
          },
        ),
      ),
    );

    if (mounted) setState(() => _isInFullScreen = false);
  }

  Widget _buildVideoPlayer() {
    final bool isVideoReady =
        _betterPlayerController != null && !_isVideoLoading;

    return Container(
      height: 220,
      width: double.infinity,
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_isInFullScreen) Container(color: Colors.black),
          if (isVideoReady)
            Offstage(
              offstage: _isInFullScreen,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _onVideoTap,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    WatermarkWrapper(
                      type: WatermarkType.chapters,
                      studentCode: _watermarkText,
                      featureManager: _featureManager,
                      child: Positioned.fill(
                        child: BetterPlayer(
                          controller: _betterPlayerController!,
                          key: ValueKey('video_${widget.chapterId}'),
                        ),
                      ),
                    ),
                    if (_isBuffering)
                      Positioned.fill(
                        child: Container(
                          color: Colors.black.withValues(alpha: 0.3),
                          child: const Center(
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 3,
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      top: 8,
                      left: 8,
                      child: AnimatedOpacity(
                        opacity: _showControls ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 300),
                        child: IgnorePointer(
                          ignoring: !_showControls,
                          child: IconButton(
                            icon: const Icon(
                              Icons.fullscreen,
                              color: Colors.white,
                            ),
                            onPressed: _enterFullScreen,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 40,
                      right: 8,
                      child: AnimatedOpacity(
                        opacity: _showControls ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 300),
                        child: IgnorePointer(
                          ignoring: !_showControls,
                          child: GestureDetector(
                            onTap: () {
                              _cyclePlaybackSpeed();
                              _onVideoTap();
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.65),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.3),
                                ),
                              ),
                              child: Text(
                                _formatSpeed(_playbackSpeed),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (_isEmulator)
                      Positioned(
                        top: 40,
                        left: 0,
                        right: 0,
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 16),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.warning_amber_rounded,
                                color: Colors.white,
                                size: 16,
                              ),
                              SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  'DRM video may not display on emulator. Use physical device.',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            )
          else if (_isVideoLoading || _isRetrying)
            Container(
              color: const Color(0xFF1F2937),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 3,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'course.loading_video'.tr(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'course.please_wait'.tr(),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                    if (_isRetrying) ...[
                      const SizedBox(height: 12),
                      Text(
                        'course.retrying'.tr(
                          args: [
                            _retryCount.toString(),
                            _maxRetries.toString(),
                          ],
                        ),
                        style: const TextStyle(
                          color: Colors.orange,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            )
          else if (_hasVideoError)
            Container(
              color: const Color(0xFF1F2937),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FaIcon(
                      _videoErrorType == VideoErrorType.network
                          ? FontAwesomeIcons.wifi
                          : FontAwesomeIcons.circleExclamation,
                      color: _videoErrorType == VideoErrorType.network
                          ? Colors.orange
                          : const Color(0xFFFF4B4B),
                      size: 48,
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Text(
                        _getVideoErrorMessage(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _retryVideo,
                      icon: _isRetrying
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const FaIcon(
                              FontAwesomeIcons.rotateRight,
                              size: 14,
                            ),
                      label: Text('course.retry'.tr()),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3451E5),
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else if (_isLocked)
            Container(
              color: const Color(0xFF1F2937),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const FaIcon(
                      FontAwesomeIcons.lock,
                      color: Colors.white,
                      size: 48,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'course.chapter_locked'.tr(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'course.views_used'.tr(
                        args: [_currentViews.toString(), _maxViews.toString()],
                      ),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _showActivationCodeDialog,
                      icon: const FaIcon(FontAwesomeIcons.key, size: 14),
                      label: Text('course.unlock_now'.tr()),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3451E5),
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else if (_videoUrl.isEmpty)
            Container(
              color: const Color(0xFF1F2937),
              child: const Center(
                child: FaIcon(
                  FontAwesomeIcons.film,
                  color: Colors.white,
                  size: 48,
                ),
              ),
            )
          else if (_errorMessage != null)
            Container(
              color: const Color(0xFF1F2937),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const FaIcon(
                      FontAwesomeIcons.circleExclamation,
                      color: Color(0xFFFF4B4B),
                      size: 48,
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _initializeVideoPlayer,
                      icon: const FaIcon(
                        FontAwesomeIcons.rotateRight,
                        size: 14,
                      ),
                      label: Text('course.retry_video'.tr()),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3451E5),
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else if (!_canWatch)
            Container(
              color: const Color(0xFF1F2937),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const FaIcon(
                      FontAwesomeIcons.circlePlay,
                      color: Colors.white54,
                      size: 48,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'course.views_exhausted'.tr(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'course.views_used'.tr(
                        args: [_currentViews.toString(), _maxViews.toString()],
                      ),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'course.max_views_reached'.tr(),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          else
            Container(
              color: const Color(0xFF1F2937),
              child: Center(
                child: Text(
                  'course.video_unavailable'.tr(),
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),

          if (_hasSlowInternet && !_isOfflineMode)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.7),
                child: _buildSlowInternetWidget(),
              ),
            ),

          if (_isOfflineMode)
            Positioned(
              top: 12,
              right: 12,
              child: Container(
                height: 36,
                width: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFF2DBC77).withValues(alpha: 0.8),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: FaIcon(
                    FontAwesomeIcons.check,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ),
            )
          else if (_videoUrl.isNotEmpty && !_isLocked && _canWatch)
            Positioned(
              top: 12,
              right: 52,
              child: AnimatedOpacity(
                opacity: _showControls ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: IgnorePointer(
                  ignoring: !_showControls,
                  child: _buildDownloadButton(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSlowInternetWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            height: 48,
            width: 48,
            child: CircularProgressIndicator(
              color: Colors.white,
              strokeWidth: 3,
            ),
          ),
          const SizedBox(height: 20),
          const FaIcon(FontAwesomeIcons.wifi, color: Colors.orange, size: 32),
          const SizedBox(height: 16),
          Text(
            'course.slow_internet_title'.tr(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              'course.slow_internet_message'.tr(),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 20),

          TextButton.icon(
            onPressed: () {
              setState(() => _hasSlowInternet = false);
              _initializeVideoPlayer();
            },
            icon: const FaIcon(
              FontAwesomeIcons.rotateRight,
              size: 14,
              color: Colors.white70,
            ),
            label: Text(
              'course.retry'.tr(),
              style: const TextStyle(color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDownloadButton() {
    if (_isDownloading && _downloadProgressNotifier != null) {
      return ValueListenableBuilder<EncryptedDownloadProgress>(
        valueListenable: _downloadProgressNotifier!,
        builder: (context, progress, child) {
          return GestureDetector(
            onTap: _cancelDownload,
            child: Container(
              height: 36,
              width: 36,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: progress.progress,
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                    const FaIcon(
                      FontAwesomeIcons.xmark,
                      color: Colors.white,
                      size: 12,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    }

    if (_isDownloaded) {
      return Container(
        height: 36,
        width: 36,
        decoration: BoxDecoration(
          color: const Color(0xFF2DBC77).withValues(alpha: 0.8),
          shape: BoxShape.circle,
        ),
        child: const Center(
          child: FaIcon(FontAwesomeIcons.check, color: Colors.white, size: 16),
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _downloadVideo,
        customBorder: const CircleBorder(),
        splashColor: Colors.white.withValues(alpha: 0.3),
        highlightColor: Colors.white.withValues(alpha: 0.1),
        child: Container(
          height: 44,
          width: 44,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.6),
            shape: BoxShape.circle,
          ),
          child: const Center(
            child: FaIcon(
              FontAwesomeIcons.download,
              color: Colors.white,
              size: 18,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAskButton() {
    return GestureDetector(
      onTap: _openAskMoment,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF3451E5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const FaIcon(
              FontAwesomeIcons.solidCommentDots,
              color: Colors.white,
              size: 16,
            ),
            const SizedBox(width: 10),
            Text(
              'course.ask_about_moment'.tr(args: [_currentTime]),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // التعديل الأساسي: فتح الـ PDF مع إيقاف الفيديو مؤقتًا
  void _openPdf(String path, String name) async {
    // Check permission before opening
    final canOpen = _permissionService.canOpenAttachment(
      fileIsLocked: false, // Attachments don't have file-level lock in lecture detail
      chapterIsLocked: _isLocked,
      chapterIsActivated: _isActivated,
      chapterIsFreePreview: _isFreePreview,
      chapterIsFreePreviewAttachment: _isFreePreviewAttachment,
      currentViews: _currentViews,
      maxViews: _maxViews,
    );

    if (!canOpen) {
      // Show locked attachment dialog
      _permissionService.showLockedAttachmentDialog(
        context: context,
        chapterId: int.tryParse(widget.chapterId) ?? 0,
        courseId: null, // Course ID not available in lecture detail
        onRefresh: () {
          _loadChapterDetails();
        },
      );
      return;
    }

    String pdfUrl = path.replaceAll('\\', '/');
    if (!pdfUrl.startsWith('http')) {
      if (!pdfUrl.startsWith('/')) pdfUrl = '/$pdfUrl';
      pdfUrl = '${ApiConstants.baseUrl}$pdfUrl';
    }

    // حفظ حالة الفيديو وإيقافه
    _wasVideoPlayingBeforePdf = _isPlaying;
    _betterPlayerController?.pause();

    setState(() {
      _selectedPdfUrl = pdfUrl;
      _selectedPdfTitle = name;
      _isPdfLoading = true;
    });

    try {
      final downloadService = DownloadService();
      final fileName = '${name.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}.pdf';
      // استخدام مجلد دائم للـ PDF لتجنب الحذف المؤقت
      final result = await downloadService.downloadFile(
        url: pdfUrl,
        fileName: fileName,
        subDirectory: 'pdfs',
      );

      if (!mounted) return;

      if (result.status == DownloadStatus.completed &&
          result.localPath != null) {
        String finalPath = result.localPath!;

        // 1. Get watermark text
        final watermark = _watermarkText;
        final watermarkConfig = _featureManager.getWatermarkConfig('files');

        // 2. Apply built-in watermark if enabled
        if (watermark != null && watermarkConfig.enabled) {
          try {
            final watermarkedPath = await PdfWatermarkService().embedWatermark(
              sourcePdfPath: finalPath,
              watermarkText: watermark,
              opacity: watermarkConfig.opacity,
              fontSize: watermarkConfig.fontSize,
              rotationDeg:
                  watermarkConfig.rotation *
                  (180.0 / pi), // Convert radians to degrees
              position: watermarkConfig.position,
              color: watermarkConfig.color,
            );
            finalPath = watermarkedPath;
          } catch (e) {
            debugPrint('Error applying built-in watermark: $e');
            // Fallback to original path if watermarking fails
          }
        }

        final file = File(finalPath);

        if (await file.exists()) {
          setState(() {
            _localPdfPath = finalPath;
            _isPdfLoading = false;
          });
        } else {
          setState(() {
            _isPdfLoading = false;
            _errorMessage = 'course.pdf_file_missing'.tr();
          });
        }
      } else {
        setState(() {
          _isPdfLoading = false;
          _errorMessage = result.errorMessage ?? 'course.failed_load_pdf'.tr();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isPdfLoading = false;
          _errorMessage = 'Error loading PDF: $e';
        });
      }
    }
  }

  // التعديل: إغلاق الـ PDF مع استئناف الفيديو إن كان يعمل
  void _closePdf() {
    if (_wasVideoPlayingBeforePdf && _betterPlayerController != null) {
      _betterPlayerController!.play();
    }
    setState(() {
      _selectedPdfUrl = null;
      _selectedPdfTitle = null;
      _localPdfPath = null;
      _isPdfLoading = false;
    });
  }

  // ترويسة الـ PDF لتقليل التكرار
  Widget _buildPdfHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 8),
          const FaIcon(
            FontAwesomeIcons.filePdf,
            color: Color(0xFFE74C3C),
            size: 18,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _selectedPdfTitle ?? '',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Color(0xFF1F2937),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (_isPdfLoading)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: LinearProgressIndicator(
                      backgroundColor: Colors.grey,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Color(0xFF3451E5),
                      ),
                      minHeight: 2,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            onPressed: _closePdf,
            icon: const Icon(Icons.close, size: 20),
          ),
        ],
      ),
    );
  }

  // التعديل: عارض PDF آمن مع مفتاح فريد
  Widget _buildEmbeddedPdfViewer() {
    // إذا لم يتوفر مسار محلي أو الملف غير موجود نعرض رسالة بدل العارض
    if (_localPdfPath == null || !File(_localPdfPath!).existsSync()) {
      return SizedBox(
        width: double.infinity,
        child: Container(
          color: Colors.white,
          child: Column(
            children: [
              _buildPdfHeader(),
              // const Expanded(
              //   child: Center(
              //     child: Text(
              //       'course.unable_load_pdf',
              //       style: TextStyle(color: Colors.grey),
              //     ).tr(),
              //   ),
              // ),
            ],
          ),
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      child: Container(
        color: Colors.white,
        child: Column(
          children: [
            _buildPdfHeader(),
            Expanded(
              // مفتاح فريد يضمن تحميل نظيف للملف
              child: KeyedSubtree(
                key: ValueKey(_localPdfPath),
                child: SfPdfViewer.file(
                  File(_localPdfPath!),
                  enableTextSelection: true,
                  enableDocumentLinkAnnotation: true,
                  enableHyperlinkNavigation: true,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _startQuiz(int quizId, dynamic quizData) async {
    if (quizId == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('course.invalid_quiz_id'.tr()),
          backgroundColor: const Color(0xFFFF4B4B),
        ),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: Color(0xFF2DBC77)),
      ),
    );

    final examRepository = ExamRepository();
    final attemptResult = await examRepository.startQuizAttempt(quizId);

    if (!mounted) return;
    Navigator.pop(context);

    if (attemptResult['success']) {
      final attempt = attemptResult['data'] as QuizAttempt;
      final quiz = Quiz.fromJson(quizData);
      _betterPlayerController?.pause();
      _audioPlayer.pause();
      _recordedPlayer.pause();

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => QuizScreen(quiz: quiz, attempt: attempt),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            attemptResult['message'] ?? 'course.failed_start_quiz'.tr(),
          ),
          backgroundColor: const Color(0xFFFF4B4B),
        ),
      );
    }
  }

  String _resolveAudioUrl(String url) {
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
    final cleanUrl = url.replaceAll('\\', '/');
    if (cleanUrl.startsWith('/')) {
      return '${ApiConstants.baseUrl}$cleanUrl';
    }
    return '${ApiConstants.baseUrl}/$cleanUrl';
  }
}

class _FullScreenVideoPlayer extends StatefulWidget {
  final BetterPlayerController sourceController;
  final String? watermarkText;
  final FeatureManager featureManager;
  final VoidCallback? onExit;

  const _FullScreenVideoPlayer({
    required this.sourceController,
    required this.watermarkText,
    required this.featureManager,
    this.onExit,
  });

  @override
  State<_FullScreenVideoPlayer> createState() => _FullScreenVideoPlayerState();
}

class _FullScreenVideoPlayerState extends State<_FullScreenVideoPlayer> {
  bool _exitCalled = false;
  bool _showControls = true;
  double _playbackSpeed = 1.0;
  final List<double> _speedOptions = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
  Timer? _hideControlsTimer;
  late void Function(BetterPlayerEvent) _eventsListener;

  @override
  void initState() {
    super.initState();
    _enterFullScreenMode();
    _eventsListener = (event) {
      if (!mounted) return;
      if (event.betterPlayerEventType ==
          BetterPlayerEventType.controlsVisible) {
        setState(() => _showControls = true);
      } else if (event.betterPlayerEventType ==
          BetterPlayerEventType.controlsHiddenEnd) {
        setState(() => _showControls = false);
      }
    };
    widget.sourceController.addEventsListener(_eventsListener);
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    widget.sourceController.removeEventsListener(_eventsListener);
    if (!_exitCalled) {
      _exitFullScreenMode();
    }
    super.dispose();
  }

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() => _showControls = false);
      }
    });
  }

  void _onVideoTap() {
    setState(() => _showControls = true);
  }

  void _cyclePlaybackSpeed() {
    final currentIndex = _speedOptions.indexOf(_playbackSpeed);
    final nextIndex = (currentIndex + 1) % _speedOptions.length;
    final newSpeed = _speedOptions[nextIndex];
    setState(() => _playbackSpeed = newSpeed);
    widget.sourceController.setSpeed(newSpeed);
  }

  String _formatSpeed(double speed) =>
      speed == speed.truncateToDouble() ? '${speed.toInt()}x' : '${speed}x';

  Future<void> _enterFullScreenMode() async {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  Future<void> _exitFullScreenMode() async {
    if (_exitCalled) return;
    _exitCalled = true;

    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    widget.onExit?.call();

    try {
      final isInit = widget.sourceController.isVideoInitialized() ?? false;
      if (isInit) {
        await widget.sourceController.play();
      }
    } catch (e) {
      debugPrint('[Fullscreen] Error resuming source: $e');
    }
  }

  void _pop() {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop && !_exitCalled) {
          await _exitFullScreenMode();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              onTap: _onVideoTap,
              child: WatermarkWrapper(
                type: WatermarkType.chapters,
                studentCode: widget.watermarkText,
                featureManager: widget.featureManager,
                child: BetterPlayer(controller: widget.sourceController),
              ),
            ),
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 8,
              child: AnimatedOpacity(
                opacity: _showControls ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: IgnorePointer(
                  ignoring: !_showControls,
                  child: IconButton(
                    icon: const Icon(
                      Icons.fullscreen_exit,
                      color: Colors.white,
                    ),
                    onPressed: _pop,
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 40,
              right: 8,
              child: AnimatedOpacity(
                opacity: _showControls ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: IgnorePointer(
                  ignoring: !_showControls,
                  child: GestureDetector(
                    onTap: () {
                      _cyclePlaybackSpeed();
                      _onVideoTap();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Text(
                        _formatSpeed(_playbackSpeed),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
