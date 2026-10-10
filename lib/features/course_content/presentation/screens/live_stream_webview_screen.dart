import 'dart:async';
import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import '../../../../core/network/api_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../auth/domain/student_profile.dart';
import '../../data/models/live_room.dart';
import 'live_stream_screen.dart';

/// Student live session rendered with the Jitsi **external API** inside a
/// WebView, mirroring the website's embed
/// (`components/student/live-sessions/LiveSessionRoomClient.tsx`).
///
/// The native `JitsiMeet().join` path opens its own activity/view controller,
/// so Flutter cannot draw anything on top of it and the SDK exposes no
/// whiteboard control. Embedding the same external API here lets the app reach
/// into the meeting page itself.
///
/// While the host's whiteboard is open the student must be able to watch but
/// never draw. Instead of covering the stage with a Flutter barrier — which also
/// swallowed the overflow ("⋯") menu and the chat panel — the page injects CSS
/// into the Jitsi iframe that makes *only* the whiteboard surface
/// `pointer-events: none` and hides Excalidraw's editing chrome. Every Jitsi
/// control (toolbar, overflow menu, chat, participants pane, filmstrip, dialogs)
/// stays fully interactive. The old [AbsorbPointer] barrier survives purely as a
/// fallback for the case where the iframe document cannot be reached.
class LiveStreamWebViewScreen extends StatefulWidget {
  const LiveStreamWebViewScreen({super.key, required this.liveRoom});

  final LiveRoom liveRoom;

  @override
  State<LiveStreamWebViewScreen> createState() =>
      _LiveStreamWebViewScreenState();
}

/// How the "student cannot draw" rule is currently being enforced.
enum WhiteboardLockMode {
  /// Nothing to enforce — the whiteboard is closed.
  none,

  /// The injected stylesheet neutralised the whiteboard surface in the page.
  /// No Flutter overlay is needed, so every Jitsi control stays reachable.
  css,

  /// The whiteboard is open but the page could not be reached (or no
  /// whiteboard element was found). Fall back to the Flutter barrier.
  shield,
}

class _LiveStreamWebViewScreenState extends State<LiveStreamWebViewScreen> {
  /// Height of the Jitsi toolbar strip that must stay interactive, in logical
  /// pixels — the same `bottom-[76px]` the website leaves uncovered. Only used
  /// by the fallback barrier.
  static const double _toolbarStripHeight = 76;

  /// Give the external API this long to come up before calling it a failure.
  static const Duration _startupTimeout = Duration(seconds: 30);

  /// Name of the JavaScript channel the injected page posts events on.
  static const String _channelName = 'LearnooLive';

  final _authRepository = AuthRepository();

  WebViewController? _controller;
  Timer? _startupTimer;

  bool _isLoading = true;
  bool _conferenceJoined = false;
  bool _whiteboardOpen = false;
  bool _chatOpen = false;
  bool _hasLeft = false;
  WhiteboardLockMode _lockMode = WhiteboardLockMode.none;
  String? _error;

  /// The Flutter barrier is the last resort: only while the whiteboard is open,
  /// the page-level lock did not take, and the chat panel is closed (the chat
  /// input lives inside the area the barrier would cover).
  bool get _showFallbackShield =>
      _conferenceJoined &&
      _whiteboardOpen &&
      _lockMode == WhiteboardLockMode.shield &&
      !_chatOpen;

  /// Full-bleed WebView while the whiteboard is up, so the board gets the
  /// AppBar's height back. Jitsi's own hangup button and the Android back
  /// button remain the ways out.
  bool get _isWhiteboardFullBleed => _conferenceJoined && _whiteboardOpen;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _startupTimer?.cancel();
    // Leave the conference if the student backs out of the screen.
    _controller?.runJavaScript('window.learnooHangup && window.learnooHangup();');
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _conferenceJoined = false;
      _whiteboardOpen = false;
      _chatOpen = false;
      _lockMode = WhiteboardLockMode.none;
    });

    try {
      await _requestMediaPermissions();
      final profile = await _loadProfile();
      if (!mounted) return;

      final controller = await _buildController();
      if (!mounted) return;

      await controller.loadHtmlString(
        _buildMeetingHtml(
          displayName: profile?.fullName.isNotEmpty == true
              ? profile!.fullName
              : 'common.student'.tr(),
        ),
        baseUrl: ApiConstants.jitsiServerUrl,
      );
      if (!mounted) return;

      setState(() => _controller = controller);

      _startupTimer?.cancel();
      _startupTimer = Timer(_startupTimeout, () {
        if (!mounted || _conferenceJoined) return;
        setState(() {
          _isLoading = false;
          _error = 'course.live_webview_failed'.tr();
        });
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'course.live_webview_failed'.tr();
      });
      debugPrint('LiveStreamWebViewScreen: failed to start ($e)');
    }
  }

  /// The WebView can only reach the mic/camera once the OS grants them to the
  /// app itself; the in-page prompt is granted separately on Android below.
  Future<void> _requestMediaPermissions() async {
    try {
      await [Permission.microphone, Permission.camera].request();
    } catch (_) {
      // A denied permission still lets the student watch and listen.
    }
  }

  Future<WebViewController> _buildController() async {
    late final PlatformWebViewControllerCreationParams params;
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      );
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    final controller = WebViewController.fromPlatformCreationParams(params);

    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await controller.setBackgroundColor(Colors.black);
    await controller.addJavaScriptChannel(
      _channelName,
      onMessageReceived: (message) => _onWebMessage(message.message),
    );
    await controller.setNavigationDelegate(
      NavigationDelegate(
        onWebResourceError: (error) {
          // Sub-resource failures are noisy; only a failed main frame matters.
          if (error.isForMainFrame != true) return;
          if (!mounted || _conferenceJoined) return;
          setState(() {
            _isLoading = false;
            _error = 'course.live_webview_failed'.tr();
          });
        },
      ),
    );

    final platform = controller.platform;
    if (platform is AndroidWebViewController) {
      await platform.setMediaPlaybackRequiresUserGesture(false);
      await platform.setOnPlatformPermissionRequest((request) {
        // The page is our own Jitsi meeting; it only ever asks for A/V.
        request.grant();
      });
    } else if (platform is WebKitWebViewController) {
      await platform.setAllowsBackForwardNavigationGestures(false);
    }

    return controller;
  }

  Future<StudentProfile?> _loadProfile() async {
    try {
      final result = await _authRepository.getProfile();
      if (result['success'] != true) return null;
      final data = result['data'];
      if (data is! Map) return null;
      return StudentProfile.fromData(Map<String, dynamic>.from(data));
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Events coming back from the page
  // ---------------------------------------------------------------------------

  void _onWebMessage(String raw) {
    Map<String, dynamic> message;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      message = Map<String, dynamic>.from(decoded);
    } catch (_) {
      return;
    }

    final type = message['type']?.toString() ?? '';
    final payload = message['payload'];

    switch (type) {
      case 'apiReady':
        _startupTimer?.cancel();
        if (mounted) setState(() => _isLoading = false);
        break;
      case 'conferenceJoined':
        _startupTimer?.cancel();
        if (mounted) {
          setState(() {
            _isLoading = false;
            _conferenceJoined = true;
          });
        }
        break;
      case 'conferenceLeft':
        if (mounted) {
          setState(() {
            _conferenceJoined = false;
            _whiteboardOpen = false;
            _chatOpen = false;
            _lockMode = WhiteboardLockMode.none;
          });
        }
        break;
      case 'readyToClose':
        _handleLeave();
        break;
      case 'participantRole':
        // Kept for parity with the website; a student is always a viewer here.
        break;
      case 'whiteboardStatusChanged':
        final open = _isWhiteboardOpen(payload);
        if (mounted && open != _whiteboardOpen) {
          setState(() {
            _whiteboardOpen = open;
            // Until the page reports back, assume the worst so the student can
            // never draw during the hand-over.
            _lockMode =
                open ? WhiteboardLockMode.shield : WhiteboardLockMode.none;
          });
        }
        break;
      case 'whiteboardLock':
        final mode = payload is Map ? payload['mode']?.toString() : null;
        final resolved = switch (mode) {
          'css' => WhiteboardLockMode.css,
          'shield' => WhiteboardLockMode.shield,
          _ => WhiteboardLockMode.none,
        };
        if (mounted && resolved != _lockMode) {
          setState(() => _lockMode = resolved);
        }
        break;
      case 'chatUpdated':
        final open = payload is Map && payload['isOpen'] == true;
        if (mounted && open != _chatOpen) {
          setState(() => _chatOpen = open);
        }
        break;
      case 'error':
        _startupTimer?.cancel();
        if (mounted && !_conferenceJoined) {
          setState(() {
            _isLoading = false;
            _error = 'course.live_webview_failed'.tr();
          });
        }
        break;
    }
  }

  /// Same parsing as the website: Jitsi reports
  /// `INSTANTIATED | SHOWN | HIDDEN | FORBIDDEN | RESET`, and some builds send
  /// a bare string or an `isOpen` flag instead.
  static bool _isWhiteboardOpen(Object? payload) {
    String status = '';
    bool isOpenFlag = false;

    if (payload is String) {
      status = payload;
    } else if (payload is Map) {
      status = payload['status']?.toString() ?? '';
      isOpenFlag = payload['isOpen'] == true;
    }

    switch (status.toLowerCase()) {
      case 'shown':
      case 'instantiated':
      case 'visible':
      case 'open':
      case 'opened':
      case 'showing':
      case 'active':
      case 'started':
        return true;
      case 'hidden':
      case 'reset':
      case 'forbidden':
        return false;
      default:
        return isOpenFlag;
    }
  }

  void _handleLeave() {
    if (_hasLeft) return;
    _hasLeft = true;
    if (!mounted) return;
    // `pop`, not `maybePop`: the screen's own PopScope blocks the latter.
    final navigator = Navigator.of(context);
    if (navigator.canPop()) navigator.pop();
  }

  /// Escape hatch when the WebView meeting cannot start at all.
  void _joinWithNativeMeeting() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => NativeLiveStreamScreen(liveRoom: widget.liveRoom),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // The embedded page
  // ---------------------------------------------------------------------------

  String _buildMeetingHtml({required String displayName}) {
    final chatEnabled = widget.liveRoom.enableChat;
    final toolbarButtons = <String>[
      'microphone',
      'raisehand',
      'reactions',
      if (chatEnabled) 'chat',
      'tileview',
      'settings',
      'fullscreen',
      'hangup',
    ];

    // Identical to the website's student `JitsiMeeting` embed.
    final configOverwrite = <String, dynamic>{
      'startWithAudioMuted': true,
      'startWithVideoMuted': true,
      'disableModeratorIndicator': true,
      'enableEmailInStats': false,
      'prejoinPageEnabled': false,
      'disableDeepLinking': true,
      'disableChat': !chatEnabled,
      'remoteVideoMenu': {
        'disabled': true,
        'disableKick': true,
        'disableGrantModerator': true,
        'disablePrivateChat': true,
        'disableDemote': true,
      },
      'disableRemoteMute': true,
      'disableKick': true,
      'disableGrantModerator': true,
      'disablePrivateChat': true,
      'disableInviteFunctions': true,
      'hideConferenceSubject': true,
      'hideConferenceTimer': false,
      'moderator': {'enabled': false},
      'participantsPane': {
        'hideModeratorSettingsTab': true,
        'hideMoreActionsButton': true,
        'hideMuteAllButton': true,
      },
      'whiteboard': {
        'enabled': true,
        'collabServerBaseUrl': 'https://whiteboard.jitsi.net',
      },
      'toolbarButtons': toolbarButtons,
      'lobby': {'enabled': true, 'autoKnock': true},
    };

    final interfaceConfigOverwrite = <String, dynamic>{
      'DISABLE_JOIN_LEAVE_NOTIFICATIONS': false,
      'SHOW_CHROME_EXTENSION_BANNER': false,
      'MOBILE_APP_PROMO': false,
      'TOOLBAR_BUTTONS': toolbarButtons,
      'SETTINGS_SECTIONS': ['devices', 'language'],
      'HIDE_INVITE_MORE_HEADER': true,
    };

    final options = <String, dynamic>{
      'roomName': ApiConstants.jitsiRoomName(widget.liveRoom.id),
      'configOverwrite': configOverwrite,
      'interfaceConfigOverwrite': interfaceConfigOverwrite,
      'userInfo': {'displayName': displayName, 'email': ''},
    };

    final optionsJson = jsonEncode(options);
    final domainJson = jsonEncode(ApiConstants.jitsiDomain);
    final scriptUrl = '${ApiConstants.jitsiServerUrl}/external_api.js';

    return '''
<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8" />
    <meta name="viewport"
          content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover" />
    <style>
      html, body { margin: 0; padding: 0; height: 100%; width: 100%;
                   background: #000; overflow: hidden; }
      #meet { height: 100%; width: 100%; }
      #meet iframe { border: 0; height: 100%; width: 100%; }
    </style>
  </head>
  <body>
    <div id="meet"></div>
    <script src="$scriptUrl"></script>
    <script>
      (function () {
        function post(type, payload) {
          try {
            $_channelName.postMessage(JSON.stringify({
              type: type,
              payload: typeof payload === 'undefined' ? null : payload
            }));
          } catch (e) {}
        }

        // Jitsi reports INSTANTIATED | SHOWN | HIDDEN | FORBIDDEN | RESET;
        // some builds send a bare string or an isOpen flag instead. Kept in
        // step with _isWhiteboardOpen on the Dart side.
        var OPEN_STATUSES = ['shown', 'instantiated', 'visible', 'open',
          'opened', 'showing', 'active', 'started'];
        var CLOSED_STATUSES = ['hidden', 'reset', 'forbidden'];

        function isOpenStatus(status, flag) {
          var value = String(status || '').toLowerCase();
          if (OPEN_STATUSES.indexOf(value) >= 0) { return true; }
          if (CLOSED_STATUSES.indexOf(value) >= 0) { return false; }
          return !!flag;
        }

        if (typeof JitsiMeetExternalAPI === 'undefined') {
          post('error', 'external_api_unavailable');
          return;
        }

        var api;
        try {
          api = new JitsiMeetExternalAPI($domainJson, Object.assign(
            { parentNode: document.getElementById('meet') },
            $optionsJson
          ));
        } catch (e) {
          post('error', String(e && e.message ? e.message : e));
          return;
        }

        window.learnooHangup = function () {
          try { setFilmstripHidden(false); } catch (e) {}
          try { api.executeCommand('hangup'); } catch (e) {}
          try { api.dispose(); } catch (e) {}
        };

        // ------------------------------------------------------------------
        // View-only whiteboard enforcement
        //
        // JitsiMeetExternalAPI renders meet.learnoo.app in an iframe. The page
        // around it is loaded with that same origin as its base URL, so the
        // iframe document is normally reachable and we can style it directly.
        // Everything below degrades to the Flutter barrier if it is not.
        // ------------------------------------------------------------------

        var LOCK_CLASS = 'learnoo-wb-lock';
        var MARK_CLASS = 'learnoo-wb-surface';
        var STYLE_ID = 'learnoo-wb-lock-style';

        // The drawing surface itself. Jitsi wraps Excalidraw in
        // `.whiteboard-container > .excalidraw-wrapper`; Excalidraw's own root
        // is `.excalidraw` and its canvases are `.excalidraw__canvas` inside
        // `.excalidraw__canvas-wrapper`. The id/attribute variants are there for
        // older and newer builds of both projects.
        var SURFACE_SELECTORS = [
          '.whiteboard-container',
          '.excalidraw-wrapper',
          '.excalidraw-container',
          '.excalidraw',
          '.excalidraw__canvas-wrapper',
          '.excalidraw__canvas',
          '#whiteboard',
          '#whiteboard-container',
          '[class*="whiteboard"] canvas',
          '[id*="whiteboard"] canvas'
        ];

        // Excalidraw's editing chrome. Useless in view-only mode and it eats a
        // lot of room on a phone, so it is hidden rather than just disabled.
        var CHROME_SELECTORS = [
          '.layer-ui__wrapper',
          '.App-top-bar',
          '.App-menu',
          '.App-menu_top',
          '.App-menu_bottom',
          '.App-menu__left',
          '.App-toolbar',
          '.App-toolbar-content',
          '.App-bottom-bar',
          '.App-mobile-menu',
          '.mobile-misc-tools-container',
          '.selected-shape-actions',
          '.selected-shape-actions-container',
          '.undo-redo-buttons',
          '.reset-zoom-button',
          '.eraser-buttons',
          '.zoom-actions',
          '.excalidraw-ui-top-left',
          '.excalidraw-ui-top-right',
          '.excalidraw-contextMenu',
          '.excalidraw .context-menu',
          '.excalidraw .Stats',
          '.excalidraw .help-icon',
          '.excalidraw .scroll-back-to-content',
          '.excalidraw .layer-ui__library',
          '.excalidraw .sidebar',
          '.excalidraw .default-sidebar',
          '.layer-ui__sidebar'
        ];

        function scoped(list) {
          var out = [];
          for (var i = 0; i < list.length; i++) {
            out.push('html.' + LOCK_CLASS + ' ' + list[i]);
          }
          return out.join(',\\n');
        }

        function buildCss() {
          return scoped(SURFACE_SELECTORS.concat(['.' + MARK_CLASS])) +
            ' { pointer-events: none !important;' +
            ' touch-action: none !important;' +
            ' user-select: none !important;' +
            ' -webkit-user-select: none !important;' +
            ' -webkit-touch-callout: none !important;' +
            ' caret-color: transparent !important;' +
            ' cursor: default !important; }\\n' +
            scoped(CHROME_SELECTORS) +
            ' { display: none !important; }\\n';
        }

        function meetFrame() {
          var host = document.getElementById('meet');
          return host ? host.querySelector('iframe') : null;
        }

        function frameDoc() {
          var frame = meetFrame();
          if (!frame) { return null; }
          try {
            var doc = frame.contentDocument ||
              (frame.contentWindow && frame.contentWindow.document);
            return (doc && doc.documentElement) ? doc : null;
          } catch (e) {
            return null;
          }
        }

        function ensureStyle(doc) {
          var head = doc.head || doc.documentElement;
          var style = doc.getElementById(STYLE_ID);
          if (style && style.parentNode === head) { return; }
          style = doc.createElement('style');
          style.id = STYLE_ID;
          style.textContent = buildCss();
          head.appendChild(style);
        }

        function markSurfaces(doc) {
          var found = 0;
          var i;
          for (i = 0; i < SURFACE_SELECTORS.length; i++) {
            var nodes;
            try { nodes = doc.querySelectorAll(SURFACE_SELECTORS[i]); }
            catch (e) { continue; }
            for (var j = 0; j < nodes.length; j++) {
              nodes[j].classList.add(MARK_CLASS);
              found++;
            }
          }

          // Whatever the wrapper is called in this build, the canvas is the
          // thing that receives the strokes: walk up from it to the nearest
          // positioned container and neutralise that too.
          var canvases = [];
          try {
            canvases = doc.querySelectorAll(
              '.excalidraw canvas, [class*="whiteboard"] canvas, [id*="whiteboard"] canvas');
          } catch (e) {}
          for (i = 0; i < canvases.length; i++) {
            canvases[i].classList.add(MARK_CLASS);
            found++;
            var parent = canvases[i].parentElement;
            var steps = 0;
            while (parent && steps < 4 && parent !== doc.body) {
              parent.classList.add(MARK_CLASS);
              var position = '';
              try {
                position = doc.defaultView.getComputedStyle(parent).position;
              } catch (e) {}
              if (position && position !== 'static') { break; }
              parent = parent.parentElement;
              steps++;
            }
          }
          return found;
        }

        function clearMarks(doc) {
          var marked;
          try { marked = doc.querySelectorAll('.' + MARK_CLASS); }
          catch (e) { return; }
          for (var i = 0; i < marked.length; i++) {
            marked[i].classList.remove(MARK_CLASS);
          }
        }

        function isOverSurface(node) {
          while (node) {
            if (node.classList && (
              node.classList.contains(MARK_CLASS) ||
              node.classList.contains('whiteboard-container') ||
              node.classList.contains('excalidraw'))) {
              return true;
            }
            node = node.parentElement;
          }
          return false;
        }

        // Long-press / right-click never reaches a pointer-events:none node,
        // but it does reach whatever sits behind it, so block it explicitly.
        function blockGesture(event) {
          if (!whiteboardOpen) { return; }
          if (isOverSurface(event.target)) {
            event.preventDefault();
            event.stopPropagation();
          }
        }

        function ensureGuards(doc) {
          if (doc.learnooGuardsInstalled) { return; }
          doc.learnooGuardsInstalled = true;
          doc.addEventListener('contextmenu', blockGesture, true);
          doc.addEventListener('selectstart', blockGesture, true);
          doc.addEventListener('dragstart', blockGesture, true);
        }

        var observer = null;
        var observedDoc = null;
        var reapplyTimer = null;

        function ensureObserver(doc) {
          if (observedDoc === doc && observer) { return; }
          if (observer) { try { observer.disconnect(); } catch (e) {} }
          observedDoc = doc;
          observer = new doc.defaultView.MutationObserver(function () {
            if (!whiteboardOpen) { return; }
            if (reapplyTimer) { return; }
            reapplyTimer = setTimeout(function () {
              reapplyTimer = null;
              applyLock();
            }, 200);
          });
          try {
            observer.observe(doc.documentElement, {
              childList: true,
              subtree: true
            });
          } catch (e) {}
        }

        function stopObserver() {
          if (observer) { try { observer.disconnect(); } catch (e) {} }
          observer = null;
          observedDoc = null;
          if (reapplyTimer) { clearTimeout(reapplyTimer); reapplyTimer = null; }
        }

        var whiteboardOpen = false;
        var lockMode = 'none';

        function reportMode(mode) {
          if (mode === lockMode) { return; }
          lockMode = mode;
          post('whiteboardLock', { mode: mode });
        }

        function applyLock() {
          var doc = frameDoc();

          if (!whiteboardOpen) {
            stopObserver();
            if (doc) {
              doc.documentElement.classList.remove(LOCK_CLASS);
              clearMarks(doc);
            }
            reportMode('none');
            return;
          }

          if (!doc) {
            // Cross-origin or not attached yet: Flutter has to shield instead.
            reportMode('shield');
            return;
          }

          ensureStyle(doc);
          ensureGuards(doc);
          ensureObserver(doc);

          if (markSurfaces(doc) > 0) {
            doc.documentElement.classList.add(LOCK_CLASS);
            reportMode('css');
          } else {
            doc.documentElement.classList.remove(LOCK_CLASS);
            reportMode('shield');
          }
        }

        // Excalidraw is lazy-loaded, so the surface may not exist for a second
        // or two after the status event arrives.
        var retryTimers = [];
        function scheduleRetries() {
          for (var i = 0; i < retryTimers.length; i++) {
            clearTimeout(retryTimers[i]);
          }
          retryTimers = [];
          var delays = [0, 150, 400, 800, 1500, 3000, 5000, 8000];
          for (var j = 0; j < delays.length; j++) {
            retryTimers.push(setTimeout(applyLock, delays[j]));
          }
        }

        // --- Filmstrip: give the board the vertical space back -------------
        var filmstripVisible = null;
        var filmstripHiddenByUs = false;

        function setFilmstripHidden(hidden) {
          try {
            if (hidden) {
              if (!filmstripHiddenByUs && filmstripVisible !== false) {
                api.executeCommand('toggleFilmStrip');
                filmstripHiddenByUs = true;
              }
            } else if (filmstripHiddenByUs) {
              filmstripHiddenByUs = false;
              // Only restore if it is still hidden — the student may have
              // brought it back themselves in the meantime.
              if (filmstripVisible === false) {
                api.executeCommand('toggleFilmStrip');
              }
            }
          } catch (e) {}
        }

        window.learnooSetWhiteboard = function (open) {
          whiteboardOpen = !!open;
          setFilmstripHidden(whiteboardOpen);
          scheduleRetries();
        };

        // A reload of the meeting frame throws the injected stylesheet and the
        // observer away, so put them back.
        try {
          var frame = meetFrame();
          if (frame) {
            frame.addEventListener('load', function () {
              stopObserver();
              if (whiteboardOpen) { scheduleRetries(); }
            });
          }
        } catch (e) {}

        post('apiReady', null);

        api.addEventListeners({
          filmstripDisplayChanged: function (event) {
            filmstripVisible = !!(event && event.visible);
          },
          chatUpdated: function (event) {
            post('chatUpdated', { isOpen: !!(event && event.isOpen) });
          },
          videoConferenceJoined: function (user) {
            post('conferenceJoined', { id: user && user.id ? user.id : null });
          },
          videoConferenceLeft: function () {
            window.learnooSetWhiteboard(false);
            post('conferenceLeft', null);
          },
          readyToClose: function () {
            window.learnooSetWhiteboard(false);
            post('readyToClose', null);
          },
          participantRoleChanged: function (event) {
            post('participantRole', { role: event && event.role ? event.role : null });
          },
          whiteboardStatusChanged: function (event) {
            var status = (typeof event === 'string')
              ? event
              : (event && event.status ? String(event.status) : '');
            var flag = (typeof event === 'object') && !!(event && event.isOpen);
            var open = isOpenStatus(status, flag);
            window.learnooSetWhiteboard(open);
            if (typeof event === 'string') {
              post('whiteboardStatusChanged', event);
            } else {
              post('whiteboardStatusChanged', { status: status, isOpen: flag });
            }
          },
          errorOccurred: function (event) {
            post('error', { message: event && event.error ? String(event.error.message || '') : '' });
          }
        });
      })();
    </script>
  </body>
</html>
''';
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _leaveFromBackButton();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        // The AppBar is dropped while the whiteboard is open so the board gets
        // the whole screen. Jitsi's hangup button and the Android back button
        // are still there to leave with.
        appBar: _isWhiteboardFullBleed
            ? null
            : AppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                title: Text(
                  widget.liveRoom.title,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
                iconTheme: const IconThemeData(color: Colors.white),
              ),
        body: _error != null
            ? _buildError()
            : Stack(
                children: [
                  if (controller != null)
                    Positioned.fill(
                      child: WebViewWidget(controller: controller),
                    ),

                  // Fallback only: the injected stylesheet normally makes the
                  // whiteboard surface itself inert, which leaves the toolbar,
                  // the overflow menu and the chat panel fully usable. This
                  // barrier comes back only when the page could not be reached,
                  // and steps aside while the chat panel is open because the
                  // chat input sits in the area it would cover.
                  if (_showFallbackShield)
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      bottom: _toolbarStripHeight,
                      child: const AbsorbPointer(
                        child: SizedBox.expand(),
                      ),
                    ),

                  if (_conferenceJoined && _whiteboardOpen)
                    Positioned(
                      left: 0,
                      right: 0,
                      // Sits just above the Jitsi toolbar strip instead of over
                      // the top-left controls, and never takes a pointer.
                      bottom: _toolbarStripHeight + 8,
                      child: IgnorePointer(child: _buildViewOnlyHint()),
                    ),

                  if (_isLoading) Positioned.fill(child: _buildLoading()),
                ],
              ),
      ),
    );
  }

  /// Android back button: leave the meeting cleanly instead of tearing the
  /// WebView down under Jitsi's feet.
  void _leaveFromBackButton() {
    _controller?.runJavaScript(
      'window.learnooHangup && window.learnooHangup();',
    );
    _handleLeave();
  }

  Widget _buildViewOnlyHint() {
    // A Row (not Center) because the badge is laid out with an unbounded
    // height inside the Positioned strip.
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              border: Border.all(
                color: Colors.amber.shade200.withValues(alpha: 0.7),
              ),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.visibility_outlined,
                    size: 14, color: Colors.amber.shade200),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'course.whiteboard_view_only'.tr(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.amber.shade100,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoading() {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: AppColors.primaryBlue),
            const SizedBox(height: 24),
            Text(
              'course.joining_live'.tr(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.liveRoom.instructorName,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.videocam_off_outlined,
                size: 56, color: Colors.white54),
            const SizedBox(height: 16),
            Text(
              'course.live_join_failed'.tr(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? '',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _start,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
              ),
              child: Text('course.retry'.tr()),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _joinWithNativeMeeting,
              child: Text(
                'course.join_with_native_meeting'.tr(),
                style: const TextStyle(color: Colors.white70),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
