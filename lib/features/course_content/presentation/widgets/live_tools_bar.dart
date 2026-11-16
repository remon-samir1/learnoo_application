import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// The website's "Live Interaction Tools" bar above the meeting
/// (`LiveSessionRoomClient.tsx`): microphone, raise hand and — when the room
/// allows chat — live chat with an unread count. Every button stays disabled
/// until the student is inside the conference, exactly like the website.
class LiveToolsBar extends StatelessWidget {
  const LiveToolsBar({
    super.key,
    required this.enabled,
    required this.chatEnabled,
    required this.audioMuted,
    required this.handRaised,
    required this.chatOpen,
    required this.unreadChatCount,
    required this.onToggleAudio,
    required this.onToggleRaiseHand,
    required this.onToggleChat,
  });

  /// `isConferenceJoined` on the website.
  final bool enabled;
  final bool chatEnabled;
  final bool audioMuted;
  final bool handRaised;
  final bool chatOpen;
  final int unreadChatCount;
  final VoidCallback onToggleAudio;
  final VoidCallback onToggleRaiseHand;
  final VoidCallback onToggleChat;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFF111827),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Color(0xFF10B981),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'live.live_tools'.tr(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ToolButton(
                key: const Key('live-tool-mic'),
                icon: audioMuted ? Icons.mic_off : Icons.mic,
                label: audioMuted
                    ? 'live.unmute_mic'.tr()
                    : 'live.mute_mic'.tr(),
                active: !audioMuted,
                activeColor: const Color(0xFF2563EB),
                onPressed: enabled ? onToggleAudio : null,
              ),
              _ToolButton(
                key: const Key('live-tool-hand'),
                icon: Icons.back_hand_outlined,
                label: handRaised
                    ? 'live.lower_hand'.tr()
                    : 'live.raise_hand'.tr(),
                active: handRaised,
                activeColor: const Color(0xFFF59E0B),
                onPressed: enabled ? onToggleRaiseHand : null,
              ),
              if (chatEnabled)
                _ToolButton(
                  key: const Key('live-tool-chat'),
                  icon: Icons.chat_bubble_outline,
                  label: chatOpen ? 'live.hide_chat'.tr() : 'live.chat'.tr(),
                  active: chatOpen,
                  activeColor: const Color(0xFF2563EB),
                  badge: !chatOpen && unreadChatCount > 0
                      ? (unreadChatCount > 9 ? '9+' : '$unreadChatCount')
                      : null,
                  onPressed: enabled ? onToggleChat : null,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    super.key,
    required this.icon,
    required this.label,
    required this.active,
    required this.activeColor,
    required this.onPressed,
    this.badge,
  });

  final IconData icon;
  final String label;
  final bool active;
  final Color activeColor;
  final VoidCallback? onPressed;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    return Opacity(
      opacity: disabled ? 0.4 : 1,
      child: Material(
        color: active ? activeColor : Colors.white.withValues(alpha: 0.08),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: active ? activeColor : Colors.white.withValues(alpha: 0.2),
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onPressed,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 18, color: Colors.white),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (badge != null) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        badge!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
