import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:learnoo/core/network/api_constants.dart';
import 'package:learnoo/features/course_content/domain/live_meeting_config.dart';

/// What the website hands `new JitsiMeetExternalAPI(domain, options)` for a
/// student, copied from `LiveSessionRoomClient.tsx` and `src/lib/jitsi.ts`
/// (website, 16 Nov 2026). `@jitsi/react-sdk` drops the props the page does
/// not set, so this is the whole object apart from `parentNode`.
Map<String, Object?> websiteStudentOptions({
  required String roomId,
  required String displayName,
  required bool chatEnabled,
}) {
  final toolbar = [
    'microphone',
    'raisehand',
    'reactions',
    if (chatEnabled) 'chat',
    'tileview',
    'settings',
    'fullscreen',
    'hangup',
  ];
  return {
    'roomName': 'learnooroom$roomId',
    'configOverwrite': {
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
        'collabServerBaseUrl': 'https://whiteboard.learnoo.app',
      },
      'toolbarButtons': toolbar,
      'lobby': {'enabled': true, 'autoKnock': true},
    },
    'interfaceConfigOverwrite': {
      'APP_NAME': 'Learnoo',
      'PROVIDER_NAME': 'Learnoo',
      'SHOW_JITSI_WATERMARK': false,
      'SHOW_BRAND_WATERMARK': false,
      'SHOW_POWERED_BY': false,
      'JITSI_WATERMARK_LINK': '',
      'BRAND_WATERMARK_LINK': '',
      'DEFAULT_WELCOME_PAGE_LOGO_URL': '',
      'DISABLE_JOIN_LEAVE_NOTIFICATIONS': false,
      'SHOW_CHROME_EXTENSION_BANNER': false,
      'MOBILE_APP_PROMO': false,
      'TOOLBAR_BUTTONS': toolbar,
      'SETTINGS_SECTIONS': ['devices', 'language'],
      'HIDE_INVITE_MORE_HEADER': true,
    },
    'userInfo': {'displayName': displayName, 'email': ''},
  };
}

/// Round-trips through JSON, as the options do on their way into the page.
Object? asJson(Object value) => jsonDecode(jsonEncode(value));

void main() {
  test('the app opens the same Jitsi room and options as the website', () {
    for (final chat in [true, false]) {
      final app = LiveMeetingConfig.studentMeetingOptions(
        roomId: '58',
        displayName: 'طالب تجربة',
        chatEnabled: chat,
      );
      expect(
        asJson(app),
        asJson(websiteStudentOptions(
          roomId: '58',
          displayName: 'طالب تجربة',
          chatEnabled: chat,
        )),
        reason: 'chatEnabled: $chat',
      );
    }
  });

  test('no pre-join screen: the key meet.learnoo.app reads is set', () {
    final config = LiveMeetingConfig.studentConfigOverwrite(chatEnabled: true);
    expect(config['prejoinConfig'], {'enabled': false});
    // The old key was ignored by the server and left students on Jitsi's
    // "Join meeting" screen, where they could rename themselves and change
    // devices before joining.
    expect(config.containsKey('prejoinPageEnabled'), isFalse);
  });

  test('students use the whiteboard server the teacher draws on', () {
    final config = LiveMeetingConfig.studentConfigOverwrite(chatEnabled: true);
    expect(
      (config['whiteboard'] as Map)['collabServerBaseUrl'],
      'https://whiteboard.learnoo.app',
    );
  });

  test('chat button and chat itself follow the room setting', () {
    final off = LiveMeetingConfig.studentConfigOverwrite(chatEnabled: false);
    expect(off['disableChat'], isTrue);
    expect(off['toolbarButtons'], isNot(contains('chat')));
    final on = LiveMeetingConfig.studentConfigOverwrite(chatEnabled: true);
    expect(on['disableChat'], isFalse);
    expect(on['toolbarButtons'], contains('chat'));
  });

  test('same domain and room name rule as the website', () {
    // `getJitsiDomain()` default in src/lib/jitsi.ts.
    expect(ApiConstants.jitsiDomain, 'meet.learnoo.app');
    expect(ApiConstants.jitsiRoomName('58'), 'learnooroom58');
    expect(ApiConstants.jitsiRoomName('5-8 '), 'learnooroom58');
  });
}
