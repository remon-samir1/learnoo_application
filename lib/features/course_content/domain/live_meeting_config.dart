import '../../../core/network/api_constants.dart';

/// The student's Jitsi meeting, exactly as the website opens it.
///
/// Source of truth on the web:
///  * `components/student/live-sessions/LiveSessionRoomClient.tsx` — the
///    `JitsiMeeting` props (`configOverwrite`, `interfaceConfigOverwrite`,
///    `userInfo`) and the student toolbar.
///  * `src/lib/jitsi.ts` — `liveWhiteboardConfig`, `liveMeetingBranding` and
///    `getJitsiRoomName`.
///
/// The app and the website must hand Jitsi the same options, otherwise the
/// student gets a different room experience in the app (a pre-join screen,
/// a whiteboard that never shows the teacher's drawing, extra settings).
class LiveMeetingConfig {
  LiveMeetingConfig._();

  /// `liveWhiteboardConfig.collabServerBaseUrl`: the teacher draws through this
  /// server, so a student must use the same one to see the drawing.
  static const String whiteboardCollabServer = 'https://whiteboard.learnoo.app';

  /// `liveMeetingBranding`.
  static const Map<String, Object> branding = {
    'APP_NAME': 'Learnoo',
    'PROVIDER_NAME': 'Learnoo',
    'SHOW_JITSI_WATERMARK': false,
    'SHOW_BRAND_WATERMARK': false,
    'SHOW_POWERED_BY': false,
    'JITSI_WATERMARK_LINK': '',
    'BRAND_WATERMARK_LINK': '',
    'DEFAULT_WELCOME_PAGE_LOGO_URL': '',
  };

  /// `studentToolbarButtons`: chat only when the room allows it.
  static List<String> studentToolbarButtons({required bool chatEnabled}) => [
    'microphone',
    'raisehand',
    'reactions',
    if (chatEnabled) 'chat',
    'tileview',
    'settings',
    'fullscreen',
    'hangup',
  ];

  /// The student's `configOverwrite`.
  ///
  /// `prejoinConfig.enabled: false` is what skips Jitsi's "Join meeting"
  /// screen; the older `prejoinPageEnabled` key is ignored by
  /// meet.learnoo.app, which is why the app used to stop on that screen.
  static Map<String, Object> studentConfigOverwrite({
    required bool chatEnabled,
  }) {
    final toolbar = studentToolbarButtons(chatEnabled: chatEnabled);
    return {
      'startWithAudioMuted': true,
      'startWithVideoMuted': true,
      'disableModeratorIndicator': true,
      'enableEmailInStats': false,
      'prejoinConfig': {'enabled': false},
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
        'collabServerBaseUrl': whiteboardCollabServer,
      },
      'toolbarButtons': toolbar,
      'lobby': {'enabled': true, 'autoKnock': true},
    };
  }

  /// The student's `interfaceConfigOverwrite`.
  static Map<String, Object> studentInterfaceConfigOverwrite({
    required bool chatEnabled,
  }) => {
    ...branding,
    'DISABLE_JOIN_LEAVE_NOTIFICATIONS': false,
    'SHOW_CHROME_EXTENSION_BANNER': false,
    'MOBILE_APP_PROMO': false,
    'TOOLBAR_BUTTONS': studentToolbarButtons(chatEnabled: chatEnabled),
    'SETTINGS_SECTIONS': ['devices', 'language'],
    'HIDE_INVITE_MORE_HEADER': true,
  };

  /// Everything handed to `new JitsiMeetExternalAPI(domain, options)` apart
  /// from `parentNode` — the same object `@jitsi/react-sdk` builds on the web.
  static Map<String, Object> studentMeetingOptions({
    required Object roomId,
    required String displayName,
    required bool chatEnabled,
  }) => {
    'roomName': ApiConstants.jitsiRoomName(roomId),
    'configOverwrite': studentConfigOverwrite(chatEnabled: chatEnabled),
    'interfaceConfigOverwrite': studentInterfaceConfigOverwrite(
      chatEnabled: chatEnabled,
    ),
    'userInfo': {'displayName': displayName, 'email': ''},
  };
}
