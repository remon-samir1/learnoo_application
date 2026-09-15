import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:shimmer/shimmer.dart';
import 'package:better_player_plus/better_player_plus.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import '../models/pdf_annotation.dart';
import '../managers/pdf_annotation_manager.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../../../../core/utils/coerce.dart';
import '../../../../core/network/api_constants.dart';
import '../../../../core/utils/watermark_text.dart';
import '../../../../core/services/feature_manager.dart';
import '../../../../core/services/pdf_watermark_service.dart';
import '../../../../core/services/download_service.dart';
import '../../../../core/services/offline_view_service.dart';
import '../../../../core/services/chapter_audio_watermark_service.dart';
import '../../../../core/services/video_watch_tracker.dart';
import '../../services/video_frame_capture_service.dart';
import '../../../../core/services/encrypted_video_service.dart';
import '../../../../core/services/user_progress_service.dart';
import '../../../../core/widgets/watermark_wrapper.dart';
import '../../data/chapter_repository.dart';
import '../../data/discussion_repository.dart';
import '../../../../features/exams/data/exam_repository.dart';
import '../../../../features/exams/models/quiz_models.dart';
import '../../services/attachment_permission_service.dart';
import '../../../auth/data/auth_repository.dart';
import '../widgets/learnoo_video_controls.dart';
import '../widgets/lecture_header.dart';
import '../widgets/attachments_list.dart';
import '../widgets/quizzes_list.dart';
import '../widgets/discussion_panel.dart';
import '../../../exams/presentation/screens/quiz_screen.dart';
import 'pdf_reviewer_screen.dart';
import '../../domain/chapter_access.dart';

enum AnnotationMode { none, pen, highlighter, eraser }

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

  /// How long to wait for a source before trying the next candidate.
  ///
  /// 90s meant a dead URL held the student on a spinner for a minute and a
  /// half before the fallback was even attempted.
  static const Duration _initTimeout = Duration(seconds: 20);

  Future<bool> checkConnectivity() async {
    final result = await Connectivity().checkConnectivity();
    return result.any((r) => r != ConnectivityResult.none);
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
        // The app draws its own chrome (LearnooVideoControls) so the player
        // matches the website's control bar instead of the packaged one.
        showControls: false,
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

    final isHls = videoUrl.toLowerCase().contains('.m3u8') ||
        videoUrl.toLowerCase().contains('/hls/');

    final dataSource = BetterPlayerDataSource(
      BetterPlayerDataSourceType.network,
      videoUrl,
      headers: headers,
      videoFormat: isHls
          ? BetterPlayerVideoFormat.hls
          : BetterPlayerVideoFormat.other,
      useAsmsTracks: isHls,
      // ExoPlayer's defaults fill a 25s buffer and wait for 3s of media before
      // the first frame, which is why the app sat on a spinner for several
      // seconds where the website — hls.js, which starts on the first
      // fragment — began playing almost immediately. These bring the start
      // threshold down to roughly one segment while still keeping a healthy
      // buffer running ahead once playback is under way.
      bufferingConfiguration: const BetterPlayerBufferingConfiguration(
        minBufferMs: 8000,
        maxBufferMs: 60000,
        bufferForPlaybackMs: 800,
        bufferForPlaybackAfterRebufferMs: 2000,
      ),
      // Re-opening a chapter should not re-download what was already fetched.
      // The key is the chapter's own URL so segments are reused across
      // sessions, matching the browser's HTTP cache on the web.
      cacheConfiguration: const BetterPlayerCacheConfiguration(
        useCache: true,
        maxCacheSize: 300 * 1024 * 1024,
        maxCacheFileSize: 50 * 1024 * 1024,
        preCacheSize: 5 * 1024 * 1024,
      ),
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
  /// Path to the encrypted download. Its presence is what puts the screen into
  /// offline mode; the decryption key is never passed around, it is derived
  /// inside [EncryptedVideoService] from the platform keystore.
  final String? offlineVideoPath;

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

  final _frameCapture = VideoFrameCaptureService();

  /// Wraps the player so the capture service can rasterise it (level 2).
  final GlobalKey _playerBoundaryKey = GlobalKey();

  /// Frame snapshotted when the student tapped "ask about this moment",
  /// attached to the next comment they post. Mirrors the web's
  /// `composerFrameFile`.
  File? _momentFrame;

  /// The moment the frame belongs to, so the comment anchors to the instant
  /// the student asked about rather than wherever the video has since reached.
  int? _momentSeconds;

  bool _isCapturingMoment = false;

  /// Set when the student dismisses the attached frame.
  bool _momentFrameDismissed = false;

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
  bool _isNotPublished = false;
  bool _canWatch = false;
  bool _isActivated = false;
  bool _isFreePreview = false;
  bool _isFreePreviewAttachment = false;
  late int _maxViews;
  int _currentViews = 0;
  int _viewByMinute = 0;
  String _videoUrl = '';
  List<String> _videoCandidates = [];
  int _candidateIndex = 0;
  String _duration = '00:00';
  List<dynamic> _attachments = [];
  List<dynamic> _quizzes = [];
  List<dynamic> _discussions = [];

  bool _isPlaying = false;
  double _progress = 0.0;
  String _currentTime = '00:00';
  String _totalTime = '00:00';
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

  // Playback speed, the sleep timer and quality now live in
  // LearnooVideoControls, which owns the settings sheet.

  bool _showControls = false;
  Timer? _hideControlsTimer;

  bool _hasSlowInternet = false;
  DateTime? _bufferingStartTime;
  Timer? _bufferingTimer;
  static const Duration _slowInternetThreshold = Duration(seconds: 8);

  bool _showDiscussionPanel = false;
  String _discussionTab = 'all';
  final _commentController = TextEditingController();
  final _commentFocusNode = FocusNode();

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

  // PDF annotation state — mirrors PdfReviewerScreen
  final _pdfViewerController = PdfViewerController();
  final _pdfViewerKey = GlobalKey<SfPdfViewerState>();
  final _annotationManager = PdfAnnotationManager();
  AnnotationMode _currentAnnotationMode = AnnotationMode.none;
  bool _showAnnotationToolbar = false;
  List<AnnotationPoint> _currentStrokePoints = [];
  int _pdfCurrentPage = 0;
  int _pdfPageCount = 0;
  double _pdfZoomLevel = 1.0;
  static const List<Color> _annotationColors = [
    Colors.red,
    Colors.blue,
    Colors.green,
    Colors.yellow,
    Colors.purple,
    Colors.orange,
    Colors.black,
  ];

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

  /// The watermark line for this chapter, built the same way as on the web.
  ///
  /// Previously this joined the code and phone with " | " and returned null
  /// when neither toggle was on, so a platform watermarking with custom text
  /// got no watermark at all in the app.
  String? get _watermarkText {
    final config = _featureManager.resolveWatermarkConfig('chapters');
    final text = buildWatermarkText(
      config: config,
      studentCode: _studentCode,
      phone: _phoneNumber,
    );
    return text.trim().isEmpty ? null : text;
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
    // Captures live in temp; drop yesterday's so they do not accumulate.
    _frameCapture.clearOldCaptures();

    if (widget.offlineVideoPath != null) {
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
      final watchedMinutes = (_watchTracker?.watchedSeconds ?? 0) ~/ 60;
      await _offlineViewService.incrementOfflineView(
        chapterIdString,
        watchedMinutes: watchedMinutes > 0 ? watchedMinutes : _viewByMinute,
      );

      final videoId = '${widget.courseId}_${widget.chapterId}';
      await _encryptedVideoService.incrementViewCount(videoId);

      final offlineViews = await _offlineViewService.getOfflineViews(
        chapterIdString,
      );
      final downloadedVideo = _encryptedVideoService.getDownloadedVideo(videoId);
      final totalViews = downloadedVideo?.currentViews ?? offlineViews;

      debugPrint(
        '[LectureDetail] Offline view incremented. Total: $totalViews, Max: $_maxViews',
      );

      if (mounted) {
        setState(() {
          _currentViews = totalViews;
        });
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

      final videoId = '${widget.courseId}_${widget.chapterId}';
      await _encryptedVideoService.deleteDownloadedVideo(videoId);
      debugPrint(
        '[LectureDetail] Deleted downloaded video due to exhausted views',
      );

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
    _commentFocusNode.dispose();
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

    String targetDownloadUrl = _videoUrl;
    for (final candidate in _videoCandidates) {
      final lower = candidate.toLowerCase();
      if (lower.endsWith('.mp4') ||
          lower.contains('.mp4?') ||
          (lower.contains('/storage/') && !lower.contains('/hls/'))) {
        targetDownloadUrl = candidate;
        break;
      }
    }

    final token = await _authRepository.getToken();
    final Map<String, String> headers = {
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      'Accept': '*/*',
    };

    final fileName = 'video_$videoId.enc';
    _downloadProgressNotifier = _encryptedVideoService.getProgressNotifier(
      targetDownloadUrl,
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
        url: targetDownloadUrl,
        chapterId: widget.chapterId,
        chapterTitle: widget.chapterTitle,
        lectureTitle: widget.lectureTitle,
        courseId: widget.courseId,
        duration: _duration,
        currentViews: _currentViews,
        maxViews: _maxViews,
        headers: headers,
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
    if (widget.chapterId.isEmpty) return;
    setState(() => _isLoadingDiscussions = true);
    try {
      final result = await _chapterRepository.getChapterById(widget.chapterId);
      if (result['success'] && mounted) {
        final data = result['data'] ?? {};
        final attributes = data['attributes'] ?? {};
        setState(() {
          _discussions = (attributes['discussions'] as List<dynamic>?) ?? [];
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

  /// Snapshots the current frame so the next comment is anchored to it.
  ///
  /// The web takes this snapshot the instant "ask about this moment" is
  /// tapped, not at post time — otherwise the video keeps playing while the
  /// student types and the attached frame no longer shows what they asked
  /// about.
  Future<void> _captureMoment() async {
    if (_isCapturingMoment) return;
    if (widget.chapterId.isEmpty) return;

    final moment = _videoHandler.currentPosition.inSeconds;
    setState(() {
      _isCapturingMoment = true;
      _momentSeconds = moment;
      _momentFrameDismissed = false;
    });

    // Pause so the frame the student sees is the frame they get.
    final wasPlaying = _isPlaying;
    if (wasPlaying) {
      try {
        _betterPlayerController?.pause();
      } catch (_) {}
    }

    File? frame;
    try {
      final token = await _authRepository.getToken();
      frame = await _frameCapture.capture(
        videoUrl: _videoUrl,
        positionSeconds: moment,
        chapterId: widget.chapterId,
        betterPlayerController: _betterPlayerController,
        headers: {
          if (token != null) 'Authorization': 'Bearer $token',
          'Accept': 'application/json, text/plain, */*',
        },
        boundaryKey: _playerBoundaryKey,
        chapterTitle: widget.chapterTitle,
      );
    } catch (e) {
      debugPrint('[LectureDetail] moment capture failed: $e');
    }

    if (!mounted) return;
    setState(() {
      _momentFrame = frame;
      _isCapturingMoment = false;
      _discussionTab = 'text';
    });

    // Give the composer focus so the student can type straight away.
    FocusScope.of(context).requestFocus(_commentFocusNode);
  }

  void _dismissMomentFrame() {
    setState(() {
      _momentFrameDismissed = true;
      _momentFrame = null;
    });
  }

  void _clearMomentCapture() {
    _momentFrame = null;
    _momentSeconds = null;
    _momentFrameDismissed = false;
  }

  /// Captures the current frame for a discussion that has none yet.
  ///
  /// The web runs its capture pipeline as soon as the composer opens, so every
  /// discussion — text or voice — carries the frame the student was looking at.
  /// In the app the composer is a tab that can be used without ever tapping
  /// "ask about this moment", so the capture is run here instead, right before
  /// posting. A failure is not fatal: the discussion posts without an image,
  /// exactly as on the web.
  Future<File?> _captureFrameForPost(int momentSeconds) async {
    if (widget.chapterId.isEmpty) return null;
    if (_videoUrl.isEmpty && _betterPlayerController == null) return null;

    try {
      final token = await _authRepository.getToken();
      return await _frameCapture.capture(
        videoUrl: _videoUrl,
        positionSeconds: momentSeconds,
        chapterId: widget.chapterId,
        betterPlayerController: _betterPlayerController,
        headers: {
          if (token != null) 'Authorization': 'Bearer $token',
          'Accept': 'application/json, text/plain, */*',
        },
        boundaryKey: _playerBoundaryKey,
        chapterTitle: widget.chapterTitle,
      );
    } catch (e) {
      debugPrint('[LectureDetail] automatic discussion capture failed: $e');
      return null;
    }
  }
  Future<void> _postReply(int parentId, String content) async {
    if (widget.chapterId.isEmpty) return;
    final chapterId = int.tryParse(widget.chapterId);
    if (chapterId == null) return;

    final moment = _videoHandler.currentPosition.inSeconds;
    
    // Using setState to trigger UI rebuild isn't strictly necessary since DiscussionPanel 
    // manages its own loading state for inline replies, but we'll fetch discussions afterwards.
    final result = await _discussionRepository.postDiscussion(
      chapterId: chapterId,
      type: 'text',
      content: content,
      moment: moment,
      parentId: parentId,
    );

    if (result['success'] && mounted) {
      if (result['offline'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('course.reply_offline_queued'.tr()),
            backgroundColor: const Color(0xFF3451E5),
            duration: const Duration(seconds: 3),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('course.reply_posted'.tr()),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
      _loadDiscussions();
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message'] ?? 'course.error_posting_reply'.tr()),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }


  Future<void> _postDiscussion() async {
    if (widget.chapterId.isEmpty) return;
    final chapterId = int.tryParse(widget.chapterId);
    if (chapterId == null) return;

    // Prefer the moment the student snapshotted over the live position.
    final moment = _momentSeconds ?? _videoHandler.currentPosition.inSeconds;
    var frame = _momentFrameDismissed ? null : _momentFrame;

    setState(() => _isLoadingDiscussions = true);

    // No snapshot yet, and the student did not deliberately remove one: take
    // it now so text and voice discussions are both anchored to a frame.
    if (frame == null && !_momentFrameDismissed) {
      frame = await _captureFrameForPost(moment);
    }

    Map<String, dynamic> result;
    if (_discussionTab == 'voice' && _recordedPath != null) {
      result = await _discussionRepository.postDiscussion(
        chapterId: chapterId,
        type: 'voice',
        content: '',
        moment: moment,
        voiceFile: File(_recordedPath!),
        // The web sends the clip length so the player can show it before
        // the audio is fetched.
        durationSeconds: _recordDuration.inSeconds,
        screenshotFile: frame,
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
        screenshotFile: frame,
      );
    }

    if (result['success'] && mounted) {
      _commentController.clear();
      _recordedPath = null;
      _discussionTab = 'all';
      _clearMomentCapture();
      await _loadDiscussions();
      if (!mounted) return;
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

  bool _isNoVideoUrl(String? url) {
    if (url == null) return true;
    final s = url.trim();
    if (s.isEmpty) return true;
    return s == 'https://api.learnoo.app/storage' ||
        s == 'https://api.learnoo.app/storage/';
  }

  String _normaliseVideoUrl(dynamic raw) {
    if (raw == null) return '';
    var str = raw.toString().trim().replaceAll('\\', '/');
    if (str.isEmpty || str == 'null') return '';
    if (!str.startsWith('http://') && !str.startsWith('https://')) {
      if (!str.startsWith('/')) str = '/$str';
      str = '${ApiConstants.baseUrl}$str';
    }
    return str;
  }

  List<String> _buildVideoCandidates(Map<String, dynamic> attributes) {
    final chapterNumericId = int.tryParse(widget.chapterId.toString());
    final rawList = [
      attributes['video_hls_url'],
      attributes['video'],
      attributes['main_video'],
      attributes['video_mp4_url'],
      attributes['playlist'],
    ];

    final seen = <String>{};
    final candidates = <String>[];
    for (final raw in rawList) {
      final url = _normaliseVideoUrl(raw);
      if (url.isNotEmpty && !_isNoVideoUrl(url) && !seen.contains(url)) {
        seen.add(url);
        candidates.add(url);
      }
    }

    // Only add the constructed HLS playlist fallback when at least one
    // explicit video field carried a real URL.  For PDF-only chapters none of
    // the five fields above will survive filtering, so we avoid injecting a
    // phantom candidate that forces a broken video load.
    if (candidates.isNotEmpty &&
        chapterNumericId != null &&
        chapterNumericId > 0) {
      final hlsUrl = ApiConstants.chapterHlsPlaylist(chapterNumericId);
      if (!seen.contains(hlsUrl)) {
        candidates.add(hlsUrl);
      }
    }

    return candidates;
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
          // Same coercion as everywhere else: the API mixes true, 1 and "1".
          _isLocked = coerceFlagOrNull(attributes['is_locked']) ?? true;
          _isNotPublished =
              attributes['watch_access_state']?.toString() == 'not_published';
          _canWatch = coerceCanWatchExplicitTrue(attributes['can_watch']);
          _isActivated = coerceFlagOrNull(attributes['is_activated']) == true;
          _isFreePreview = coerceFlag(attributes['is_free_preview']);
          _isFreePreviewAttachment =
              coerceFlag(attributes['is_free_preview_attachment']);
          _maxViews = apiMaxViews;
          _currentViews = totalViews;
          _viewByMinute =
              int.tryParse(attributes['view_by_minute']?.toString() ?? '') ?? 0;
          _duration = attributes['duration']?.toString() ?? '00:00';
          _totalTime = _duration;

          _videoCandidates = _buildVideoCandidates(attributes);
          _candidateIndex = 0;
          _videoUrl = _videoCandidates.isNotEmpty ? _videoCandidates.first : '';

          _attachments = attributes['attachments'] as List<dynamic>? ?? [];
          _quizzes = attributes['quizzes'] as List<dynamic>? ?? [];
          _discussions = attributes['discussions'] as List<dynamic>? ?? [];
        });

        debugPrint(
          '[LectureDetail] Loaded chapter views - API: $apiCurrentViews, Offline: $offlineViews, Total: $totalViews, Max: $_maxViews, Candidates: ${_videoCandidates.length}, Initial URL: $_videoUrl',
        );

        if (totalViews >= apiMaxViews && apiMaxViews > 0) {
          setState(() {
            _errorMessage = 'course.maximum_views_reached'.tr();
            _canWatch = false;
            _isLoadingChapter = false;
          });
          return;
        }

        // If chapter is PDF-only (no video and has PDF attachment), redirect to PdfReviewerScreen
        if ((_videoCandidates.isEmpty || _videoUrl.isEmpty) &&
            (chapterIsPdfOnly(_chapterData) || _attachments.isNotEmpty)) {
          final pdfList = chapterPdfAttachments(_chapterData);
          dynamic chosenPdf = pdfList.isNotEmpty ? pdfList.first : null;
          if (chosenPdf == null && _attachments.isNotEmpty) {
            chosenPdf = _attachments.firstWhere(
              (att) {
                if (att is! Map) return false;
                final a = att['attributes'] is Map ? att['attributes'] as Map : att;
                final ext = coerceString(a['extension'])?.toLowerCase() ?? '';
                final p = coerceString(a['path'])?.toLowerCase() ?? '';
                final n = coerceString(a['name'])?.toLowerCase() ?? '';
                return ext == 'pdf' || p.endsWith('.pdf') || n.endsWith('.pdf');
              },
              orElse: () => _attachments.first,
            );
          }

          if (chosenPdf != null) {
            final attAttrs = chosenPdf['attributes'] is Map ? chosenPdf['attributes'] as Map : chosenPdf;
            String pdfPath = attAttrs['path']?.toString() ?? '';
            final pdfName = attAttrs['name']?.toString() ?? widget.chapterTitle;
            if (pdfPath.isNotEmpty) {
              if (!pdfPath.startsWith('http')) {
                pdfPath = pdfPath.replaceAll('\\', '/');
                if (!pdfPath.startsWith('/')) pdfPath = '/$pdfPath';
                pdfPath = '${ApiConstants.baseUrl}$pdfPath';
              }
              debugPrint('[LectureDetail] Chapter has no video, redirecting to PdfReviewerScreen: $pdfPath');
              setState(() => _isLoadingChapter = false);
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => PdfReviewerScreen(
                    pdfUrl: pdfPath,
                    title: pdfName,
                  ),
                ),
              );
              return;
            }
          }
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
          _isNotPublished =
              result['watch_access_state']?.toString() == 'not_published';
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
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
        'Accept': '*/*',
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

      // The packaged controls are off, so their visibility events no longer
      // fire; the chrome is shown on load and hidden by [_startHideControlsTimer].
      _revealControls();

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

  Future<bool> _tryNextCandidate() async {
    if (_candidateIndex + 1 < _videoCandidates.length) {
      _candidateIndex++;
      _videoUrl = _videoCandidates[_candidateIndex];
      debugPrint(
        '[LectureDetail] Fallback triggered: switching to candidate #$_candidateIndex/${_videoCandidates.length}: $_videoUrl',
      );
      await _videoHandler.dispose();
      await _initializeVideoPlayer();
      return true;
    }
    return false;
  }

  void _onVideoTimeout() {
    if (!mounted) return;
    _handleVideoTimeout();
  }

  Future<void> _handleVideoTimeout() async {
    if (!mounted) return;
    debugPrint(
      '[LectureDetail] Video Timeout on candidate #$_candidateIndex ($_videoUrl)',
    );

    if (_candidateIndex + 1 < _videoCandidates.length) {
      final switched = await _tryNextCandidate();
      if (switched) return;
    }

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

  Future<void> _onVideoErrorWithMessage(String errorMessage) async {
    if (!mounted) return;
    debugPrint(
      '[LectureDetail] Video Error on candidate #$_candidateIndex ($_videoUrl): $errorMessage',
    );

    if (_candidateIndex + 1 < _videoCandidates.length) {
      final switched = await _tryNextCandidate();
      if (switched) return;
    }

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

    // Reset candidate sequence on explicit retry
    if (_videoCandidates.isNotEmpty) {
      _candidateIndex = 0;
      _videoUrl = _videoCandidates[0];
    }

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
    if (widget.offlineVideoPath == null) return;

    await _encryptedVideoService.loadDownloadedVideos();
    await _ensureOfflineViewInitialized();
    final videoId = '${widget.courseId}_${widget.chapterId}';
    final downloadedVideo = _encryptedVideoService.getDownloadedVideo(videoId);

    final offlineServiceViews = _offlineViewService.getOfflineViewsSync(
      widget.chapterId,
    );
    final downloadedViews = downloadedVideo?.currentViews ?? 0;
    final totalOfflineViews = downloadedViews > offlineServiceViews ? downloadedViews : offlineServiceViews;
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

      // Decryption belongs to EncryptedVideoService, which picks the right
      // scheme from the container itself, streams the file instead of holding
      // it in memory, and rejects anything that fails authentication. This
      // screen used to XOR the bytes inline with a key handed in through the
      // widget, which both duplicated the crypto in the UI layer and could not
      // read an authenticated download at all.
      final decryptedPath =
          await _encryptedVideoService.getDecryptedVideoPath(videoId);
      if (decryptedPath == null) {
        throw Exception('Downloaded video could not be decrypted');
      }
      final tempFile = File(decryptedPath);

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

  /// Shows the chrome and restarts the auto-hide countdown.
  void _revealControls() {
    if (!mounted) return;
    setState(() => _showControls = true);
    _startHideControlsTimer();
  }

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _isPlaying) {
        setState(() => _showControls = false);
      }
    });
  }

  /// The "ask about this moment" affordance, rendered inside the control bar.
  ///
  /// Kept here rather than in [LearnooVideoControls] because the capture and
  /// the composer belong to this screen; the control layer only places it.
  Widget _buildAskMomentAction() {
    return Semantics(
      button: true,
      label: 'course.ask_this_moment'.tr(),
      child: InkResponse(
        onTap: _isCapturingMoment
            ? null
            : () {
                _revealControls();
                _openAskMoment();
                _captureMoment();
              },
        radius: 26,
        child: Container(
          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: _isCapturingMoment
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(
                  Icons.add_comment_outlined,
                  color: Colors.white,
                  size: 20,
                ),
        ),
      ),
    );
  }

  /// A tap on the video toggles the chrome, the way the web player does.
  void _onVideoTap() {
    if (_showControls) {
      _hideControlsTimer?.cancel();
      setState(() => _showControls = false);
      return;
    }
    _revealControls();
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
                          keyboardType: TextInputType.visiblePassword,
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
                onPostReply: _postReply,
                momentFrame: _momentFrameDismissed ? null : _momentFrame,
                isCapturingFrame: _isCapturingMoment,
                onDismissFrame: _dismissMomentFrame,
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
        !_isNotPublished &&
        (errorLower.contains('locked') == true ||
            _isLocked ||
            errorLower.contains('activate') == true);
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
                      _isNotPublished
                          ? FontAwesomeIcons.clock
                          : showActivationButton
                          ? FontAwesomeIcons.lock
                          : FontAwesomeIcons.circleExclamation,
                      color: Colors.white,
                      size: 40,
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  _isNotPublished
                      ? 'course.chapter_not_available_yet'.tr()
                      : isMaxViewsError
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
          studentCode: _studentCode,
          phone: _phoneNumber,
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
                    // The boundary is what the capture service rasterises when
                    // native frame extraction is unavailable, so it has to sit
                    // outside the watermark to include it in the snapshot.
                    Positioned.fill(
                      child: RepaintBoundary(
                        key: _playerBoundaryKey,
                        child: WatermarkWrapper(
                          type: WatermarkType.chapters,
                          studentCode: _studentCode,
                          phone: _phoneNumber,
                          featureManager: _featureManager,
                          child: BetterPlayer(
                            controller: _betterPlayerController!,
                            key: ValueKey('video_${widget.chapterId}'),
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: LearnooVideoControls(
                        controller: _betterPlayerController!,
                        visible: _showControls,
                        onInteraction: _revealControls,
                        isBuffering: _isBuffering,
                        onToggleFullScreen: _enterFullScreen,
                        leadingAction: _buildAskMomentAction(),
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
          else if (_isNotPublished)
            Container(
              color: const Color(0xFF1F2937),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const FaIcon(
                      FontAwesomeIcons.clock,
                      color: Colors.white,
                      size: 48,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'course.chapter_not_available_yet'.tr(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
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
      onTap: () {
        _openAskMoment();
        _captureMoment();
      },
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
            if (_isCapturingMoment)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            else
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
    // Reset annotation state so the next PDF opens fresh.
    _annotationManager.discardAll();
    _currentStrokePoints.clear();
    setState(() {
      _selectedPdfUrl = null;
      _selectedPdfTitle = null;
      _localPdfPath = null;
      _isPdfLoading = false;
      _showAnnotationToolbar = false;
      _currentAnnotationMode = AnnotationMode.none;
      _pdfCurrentPage = 0;
      _pdfPageCount = 0;
      _pdfZoomLevel = 1.0;
    });
  }

  void _showGoToPageDialog() {
    if (_pdfPageCount <= 1) return;
    final controller = TextEditingController(
      text: _pdfCurrentPage.toString(),
    );
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('انتقال إلى صفحة', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: '1 - $_pdfPageCount',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                onSubmitted: (value) {
                  final page = int.tryParse(value);
                  if (page != null && page >= 1 && page <= _pdfPageCount) {
                    _pdfViewerController.jumpToPage(page);
                    Navigator.pop(context);
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            Text('/ $_pdfPageCount', style: const TextStyle(color: Color(0xFF6B7280))),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () {
              final page = int.tryParse(controller.text);
              if (page != null && page >= 1 && page <= _pdfPageCount) {
                _pdfViewerController.jumpToPage(page);
                Navigator.pop(context);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3451E5),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('انتقال'),
          ),
        ],
      ),
    );
  }

  // ───────────────── PDF annotation helpers ─────────────────

  void _setPdfAnnotationMode(AnnotationMode mode) {
    setState(() {
      _currentAnnotationMode = mode;
      _currentStrokePoints.clear();
      if (mode == AnnotationMode.pen) {
        _annotationManager.isHighlighterMode = false;
      } else if (mode == AnnotationMode.highlighter) {
        _annotationManager.isHighlighterMode = true;
      }
    });
  }

  void _setPdfAnnotationColor(Color color) {
    setState(() => _annotationManager.currentColor = color);
  }

  void _setPdfStrokeWidth(double width) {
    setState(() => _annotationManager.currentStrokeWidth = width);
  }

  void _erasePdfNearbyPoints(Offset position) {
    final pageNumber = _pdfViewerController.pageNumber;
    if (pageNumber == 0) return;
    final eraseRadius = _annotationManager.currentStrokeWidth * 5;
    final annotations = _annotationManager.getAnnotationsForPage(pageNumber);
    setState(() {
      for (final stroke in annotations) {
        stroke.points.removeWhere(
          (p) => (p.offset - position).distance < eraseRadius,
        );
      }
      annotations.removeWhere((s) => s.points.isEmpty);
    });
  }

  Future<void> _savePdfCurrentStroke() async {
    if (_currentStrokePoints.length < 2) {
      _currentStrokePoints.clear();
      return;
    }
    final pageNumber = _pdfViewerController.pageNumber;
    if (pageNumber == 0) return;
    _annotationManager.addStroke(
      pageNumber,
      InkStroke(
        points: List.from(_currentStrokePoints),
        color: _annotationManager.currentColor,
        strokeWidth: _annotationManager.currentStrokeWidth,
        isHighlighter: _annotationManager.isHighlighterMode,
      ),
    );
    _currentStrokePoints.clear();
    setState(() {});
  }

  void _undoPdfAnnotation() {
    final page = _pdfViewerController.pageNumber;
    if (page == 0) return;
    _annotationManager.undo(page);
    setState(() {});
  }

  void _clearPdfCurrentPage() {
    final page = _pdfViewerController.pageNumber;
    if (page == 0) return;
    _annotationManager.clearPage(page);
    setState(() {});
  }

  // ───────────────── PDF header with annotation actions ─────────────────

  Widget _buildPdfHeader() {
    return Column(
      children: [
        // Title bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
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
              const SizedBox(width: 10),
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
              // Zoom out
              IconButton(
                icon: const Icon(Icons.zoom_out, size: 20, color: Color(0xFF6B7280)),
                tooltip: 'تصغير',
                onPressed: _pdfZoomLevel > 0.5
                    ? () {
                        setState(() {
                          _pdfZoomLevel = (_pdfZoomLevel - 0.25).clamp(0.5, 5.0);
                          _pdfViewerController.zoomLevel = _pdfZoomLevel;
                        });
                      }
                    : null,
              ),
              // Zoom level indicator
              GestureDetector(
                onTap: () {
                  setState(() {
                    _pdfZoomLevel = 1.0;
                    _pdfViewerController.zoomLevel = 1.0;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${(_pdfZoomLevel * 100).round()}%',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF374151),
                    ),
                  ),
                ),
              ),
              // Zoom in
              IconButton(
                icon: const Icon(Icons.zoom_in, size: 20, color: Color(0xFF6B7280)),
                tooltip: 'تكبير',
                onPressed: _pdfZoomLevel < 5.0
                    ? () {
                        setState(() {
                          _pdfZoomLevel = (_pdfZoomLevel + 0.25).clamp(0.5, 5.0);
                          _pdfViewerController.zoomLevel = _pdfZoomLevel;
                        });
                      }
                    : null,
              ),
              // Page number input
              if (_pdfPageCount > 1)
                GestureDetector(
                  onTap: () => _showGoToPageDialog(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: Text(
                      '$_pdfCurrentPage/$_pdfPageCount',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF374151),
                      ),
                    ),
                  ),
                ),
              // Annotation toolbar toggle
              IconButton(
                icon: FaIcon(
                  _showAnnotationToolbar
                      ? FontAwesomeIcons.penToSquare
                      : FontAwesomeIcons.highlighter,
                  size: 18,
                  color: _showAnnotationToolbar
                      ? const Color(0xFF3451E5)
                      : const Color(0xFF6B7280),
                ),
                tooltip: 'أدوات التعليق',
                onPressed: () {
                  setState(() {
                    _showAnnotationToolbar = !_showAnnotationToolbar;
                    if (!_showAnnotationToolbar) {
                      _currentAnnotationMode = AnnotationMode.none;
                    }
                  });
                },
              ),
              // Undo
              if (_showAnnotationToolbar)
                IconButton(
                  icon: const FaIcon(FontAwesomeIcons.rotateLeft, size: 16),
                  tooltip: 'تراجع',
                  onPressed:
                      _annotationManager.canUndo(_pdfViewerController.pageNumber)
                          ? _undoPdfAnnotation
                          : null,
                ),
              // Clear page
              if (_showAnnotationToolbar)
                IconButton(
                  icon: const FaIcon(
                    FontAwesomeIcons.trash,
                    size: 16,
                    color: Color(0xFFEF4444),
                  ),
                  tooltip: 'مسح الصفحة',
                  onPressed: _clearPdfCurrentPage,
                ),
              // Close
              IconButton(
                onPressed: _closePdf,
                icon: const Icon(Icons.close, size: 20),
              ),
            ],
          ),
        ),
        // Annotation toolbar (shown when toggled)
        if (_showAnnotationToolbar) _buildPdfAnnotationToolbar(),
      ],
    );
  }

  Widget _buildPdfAnnotationToolbar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Mode buttons + stroke width
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                _buildPdfModeButton(
                  FontAwesomeIcons.pen,
                  'قلم',
                  AnnotationMode.pen,
                  Colors.red,
                ),
                _buildPdfModeButton(
                  FontAwesomeIcons.highlighter,
                  'تحديد',
                  AnnotationMode.highlighter,
                  Colors.amber,
                ),
                _buildPdfModeButton(
                  FontAwesomeIcons.eraser,
                  'ممحاة',
                  AnnotationMode.eraser,
                  Colors.grey,
                ),
                const SizedBox(width: 8),
                Container(
                  height: 36,
                  width: 1,
                  color: Colors.grey[300],
                ),
                const SizedBox(width: 8),
                const Text(
                  'سُمك',
                  style: TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
                ),
                SizedBox(
                  width: 90,
                  child: Slider(
                    value: _annotationManager.currentStrokeWidth,
                    min: 1,
                    max: 10,
                    activeColor: const Color(0xFF3451E5),
                    onChanged: _setPdfStrokeWidth,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Color palette
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: _annotationColors.map((color) {
                final isSelected =
                    _annotationManager.currentColor == color;
                return Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: GestureDetector(
                    onTap: () => _setPdfAnnotationColor(color),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: isSelected ? 34 : 28,
                      height: isSelected ? 34 : 28,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected
                              ? Colors.black87
                              : Colors.transparent,
                          width: 2.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.18),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      child: isSelected
                          ? const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 16,
                            )
                          : null,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPdfModeButton(
    FaIconData icon,
    String label,
    AnnotationMode mode,
    Color activeColor,
  ) {
    final isSelected = _currentAnnotationMode == mode;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: InkWell(
        onTap: () => _setPdfAnnotationMode(
          isSelected ? AnnotationMode.none : mode,
        ),
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? activeColor.withValues(alpha: 0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected
                  ? activeColor
                  : Colors.grey.withValues(alpha: 0.3),
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FaIcon(
                icon,
                size: 18,
                color: isSelected ? activeColor : Colors.grey[600],
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  color: isSelected ? activeColor : Colors.grey[600],
                  fontWeight:
                      isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ───────────────── Embedded PDF viewer with drawing overlay ─────────────────

  Widget _buildEmbeddedPdfViewer() {
    if (_localPdfPath == null || !File(_localPdfPath!).existsSync()) {
      return SizedBox(
        width: double.infinity,
        child: Container(
          color: Colors.white,
          child: Column(
            children: [_buildPdfHeader()],
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
              child: Stack(
                children: [
                  // PDF viewer
                  KeyedSubtree(
                    key: ValueKey(_localPdfPath),
                    child: SfPdfViewer.file(
                      File(_localPdfPath!),
                      controller: _pdfViewerController,
                      key: _pdfViewerKey,
                      enableTextSelection:
                          _currentAnnotationMode == AnnotationMode.none,
                      enableDocumentLinkAnnotation: true,
                      enableHyperlinkNavigation: true,
                      onDocumentLoaded: (details) {
                        setState(() {
                          _pdfPageCount = details.document.pages.count;
                          _pdfCurrentPage =
                              _pdfViewerController.pageNumber;
                        });
                      },
                      onPageChanged: (details) {
                        setState(() {
                          _pdfCurrentPage = details.newPageNumber;
                        });
                      },
                    ),
                  ),
                  // Drawing overlay — active only when a mode is selected
                  if (_showAnnotationToolbar &&
                      _currentAnnotationMode != AnnotationMode.none)
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanStart: (d) {
                          if (_currentAnnotationMode ==
                              AnnotationMode.eraser) {
                            _erasePdfNearbyPoints(d.localPosition);
                          } else {
                            setState(() {
                              _currentStrokePoints.add(
                                AnnotationPoint(
                                  offset: d.localPosition,
                                  color: _annotationManager.currentColor,
                                  strokeWidth:
                                      _annotationManager.currentStrokeWidth,
                                  isHighlighter:
                                      _annotationManager.isHighlighterMode,
                                ),
                              );
                            });
                          }
                        },
                        onPanUpdate: (d) {
                          if (_currentAnnotationMode ==
                              AnnotationMode.eraser) {
                            _erasePdfNearbyPoints(d.localPosition);
                          } else {
                            setState(() {
                              _currentStrokePoints.add(
                                AnnotationPoint(
                                  offset: d.localPosition,
                                  color: _annotationManager.currentColor,
                                  strokeWidth:
                                      _annotationManager.currentStrokeWidth,
                                  isHighlighter:
                                      _annotationManager.isHighlighterMode,
                                ),
                              );
                            });
                          }
                        },
                        onPanEnd: (_) async {
                          if (_currentAnnotationMode !=
                              AnnotationMode.eraser) {
                            await _savePdfCurrentStroke();
                          }
                        },
                        child: CustomPaint(
                          size: Size.infinite,
                          painter: _PdfAnnotationPainter(
                            currentStrokePoints: _currentStrokePoints,
                            pageAnnotations:
                                _annotationManager.getAnnotationsForPage(
                              _pdfViewerController.pageNumber,
                            ),
                          ),
                        ),
                      ),
                    ),
                  // Page navigation bar at bottom
                  if (_pdfPageCount > 1)
                    Positioned(
                      bottom: 12,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.65),
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Previous page
                              GestureDetector(
                                onTap: _pdfCurrentPage > 1
                                    ? () {
                                        _pdfViewerController.previousPage();
                                      }
                                    : null,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  child: Icon(
                                    Icons.chevron_left,
                                    color: _pdfCurrentPage > 1
                                        ? Colors.white
                                        : Colors.white38,
                                    size: 20,
                                  ),
                                ),
                              ),
                              // Tappable page number to jump
                              GestureDetector(
                                onTap: () => _showGoToPageDialog(),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                  child: Text(
                                    '$_pdfCurrentPage / $_pdfPageCount',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                              // Next page
                              GestureDetector(
                                onTap: _pdfCurrentPage < _pdfPageCount
                                    ? () {
                                        _pdfViewerController.nextPage();
                                      }
                                    : null,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  child: Icon(
                                    Icons.chevron_right,
                                    color: _pdfCurrentPage < _pdfPageCount
                                        ? Colors.white
                                        : Colors.white38,
                                    size: 20,
                                  ),
                                ),
                              ),
                            ],
                          ),
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
  final String? studentCode;
  final String? phone;
  final FeatureManager featureManager;
  final VoidCallback? onExit;

  const _FullScreenVideoPlayer({
    required this.sourceController,
    required this.studentCode,
    required this.phone,
    required this.featureManager,
    this.onExit,
  });

  @override
  State<_FullScreenVideoPlayer> createState() => _FullScreenVideoPlayerState();
}

class _FullScreenVideoPlayerState extends State<_FullScreenVideoPlayer> {
  bool _exitCalled = false;
  bool _showControls = true;
  Timer? _hideControlsTimer;

  @override
  void initState() {
    super.initState();
    _enterFullScreenMode();
    // The packaged controls are off, so the chrome is shown on entry and then
    // hidden by the same auto-hide the inline player uses.
    _startHideControlsTimer();
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    if (!_exitCalled) {
      _exitFullScreenMode();
    }
    super.dispose();
  }

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() => _showControls = false);
      }
    });
  }

  /// Shows the chrome and restarts the auto-hide countdown.
  void _revealControls() {
    if (!mounted) return;
    setState(() => _showControls = true);
    _startHideControlsTimer();
  }

  void _onVideoTap() {
    if (_showControls) {
      _hideControlsTimer?.cancel();
      setState(() => _showControls = false);
      return;
    }
    _revealControls();
  }

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
                studentCode: widget.studentCode,
                phone: widget.phone,
                featureManager: widget.featureManager,
                child: BetterPlayer(controller: widget.sourceController),
              ),
            ),
            Positioned.fill(
              child: LearnooVideoControls(
                controller: widget.sourceController,
                visible: _showControls,
                onInteraction: _revealControls,
                isFullScreen: true,
                onToggleFullScreen: _pop,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// CustomPainter that renders the live annotation strokes on top of the PDF.
///
/// Identical in logic to the private `_AnnotationPainter` inside
/// [PdfReviewerScreen] — kept separate so both screens remain self-contained.
class _PdfAnnotationPainter extends CustomPainter {
  final List<AnnotationPoint> currentStrokePoints;
  final List<InkStroke> pageAnnotations;

  const _PdfAnnotationPainter({
    required this.currentStrokePoints,
    required this.pageAnnotations,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in pageAnnotations) {
      _drawStroke(
        canvas,
        stroke.points,
        stroke.color,
        stroke.strokeWidth,
        stroke.isHighlighter,
      );
    }
    if (currentStrokePoints.isNotEmpty) {
      _drawStroke(
        canvas,
        currentStrokePoints,
        currentStrokePoints.first.color,
        currentStrokePoints.first.strokeWidth,
        currentStrokePoints.first.isHighlighter,
      );
    }
  }

  void _drawStroke(
    Canvas canvas,
    List<AnnotationPoint> points,
    Color color,
    double strokeWidth,
    bool isHighlighter,
  ) {
    if (points.isEmpty) return;
    for (int i = 0; i < points.length - 1; i++) {
      final p = points[i];
      final next = points[i + 1];
      if ((p.offset - next.offset).distance > 50) continue;
      final paint = Paint()
        ..color = isHighlighter ? color.withValues(alpha: 0.3) : color
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      canvas.drawLine(p.offset, next.offset, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
