import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:easy_localization/easy_localization.dart';

/// Widget to display subscription status (locked/unlocked)
class SubscriptionBadge extends StatelessWidget {
  final bool isSubscribed;
  final bool showLabel;
  final double size;

  const SubscriptionBadge({
    super.key,
    required this.isSubscribed,
    this.showLabel = true,
    this.size = 20,
  });

  @override
  Widget build(BuildContext context) {
    if (isSubscribed) {
      return Container(
        padding: EdgeInsets.symmetric(
          horizontal: showLabel ? 10 : 6,
          vertical: showLabel ? 4 : 6,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFFE6F7F0),
          borderRadius: BorderRadius.circular(showLabel ? 20 : 8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FaIcon(
              FontAwesomeIcons.unlock,
              size: size * 0.6,
              color: const Color(0xFF27AE60),
            ),
            if (showLabel) ...[
              const SizedBox(width: 6),
              Text(
                'subscription.active'.tr(),
                style: TextStyle(
                  fontSize: size * 0.55,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF27AE60),
                ),
              ),
            ],
          ],
        ),
      );
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: showLabel ? 10 : 6,
        vertical: showLabel ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF0F0),
        borderRadius: BorderRadius.circular(showLabel ? 20 : 8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FaIcon(
            FontAwesomeIcons.lock,
            size: size * 0.6,
            color: const Color(0xFFFF4B4B),
          ),
          if (showLabel) ...[
            const SizedBox(width: 6),
            Text(
              'subscription.locked'.tr(),
              style: TextStyle(
                fontSize: size * 0.55,
                fontWeight: FontWeight.w600,
                color: const Color(0xFFFF4B4B),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Overlay widget for locked content
class LockedContentOverlay extends StatelessWidget {
  final VoidCallback? onUnlock;
  final String? message;

  const LockedContentOverlay({
    super.key,
    this.onUnlock,
    this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.7),
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(32),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF0F0),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: FaIcon(
                    FontAwesomeIcons.lock,
                    size: 28,
                    color: Color(0xFFFF4B4B),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                message ?? 'subscription.content_locked'.tr(),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1F2937),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'subscription.subscribe_to_access'.tr(),
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              if (onUnlock != null)
                ElevatedButton.icon(
                  onPressed: onUnlock,
                  icon: const FaIcon(FontAwesomeIcons.unlock, size: 16),
                  label: Text('subscription.unlock_now'.tr()),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF5A75FF),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Widget that conditionally shows content based on subscription status
class SubscriptionGuard extends StatelessWidget {
  final bool isSubscribed;
  final Widget child;
  final VoidCallback? onUnlock;
  final String? lockedMessage;

  const SubscriptionGuard({
    super.key,
    required this.isSubscribed,
    required this.child,
    this.onUnlock,
    this.lockedMessage,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        if (!isSubscribed)
          Positioned.fill(
            child: LockedContentOverlay(
              onUnlock: onUnlock,
              message: lockedMessage,
            ),
          ),
      ],
    );
  }
}
