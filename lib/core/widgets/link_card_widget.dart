import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Enum for different link types
enum LinkType {
  whatsapp,
  telegram,
  external,
}

/// Widget for displaying a link with appropriate icon and styling
class LinkCardWidget extends StatelessWidget {
  final String url;
  final String? title;
  final String? description;
  final LinkType? linkType;
  final VoidCallback? onTap;

  const LinkCardWidget({
    super.key,
    required this.url,
    this.title,
    this.description,
    this.linkType,
    this.onTap,
  });

  /// Detect link type from URL
  factory LinkCardWidget.autoDetect({
    required String url,
    String? title,
    String? description,
    VoidCallback? onTap,
  }) {
    final type = _detectLinkType(url);
    return LinkCardWidget(
      url: url,
      title: title,
      description: description,
      linkType: type,
      onTap: onTap,
    );
  }

  static LinkType _detectLinkType(String url) {
    final lowerUrl = url.toLowerCase();
    if (lowerUrl.contains('whatsapp') || lowerUrl.contains('wa.me')) {
      return LinkType.whatsapp;
    } else if (lowerUrl.contains('telegram') || lowerUrl.contains('t.me')) {
      return LinkType.telegram;
    }
    return LinkType.external;
  }

  @override
  Widget build(BuildContext context) {
    final type = linkType ?? _detectLinkType(url);
    final config = _getLinkConfig(type);

    return Card(
      elevation: 0,
      color: config.backgroundColor.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: config.backgroundColor.withValues(alpha: 0.3)),
      ),
      child: InkWell(
        onTap: onTap ?? () => _launchUrl(context),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: config.iconBackgroundColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: FaIcon(
                    config.icon,
                    color: config.iconColor,
                    size: 24,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: config.badgeColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            config.label,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: config.badgeColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    if (title != null)
                      Text(
                        title!,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1F2937),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (description != null)
                      Text(
                        description!,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    const SizedBox(height: 4),
                    Text(
                      url,
                      style: TextStyle(
                        fontSize: 11,
                        color: config.badgeColor,
                        decoration: TextDecoration.underline,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => _shareLink(context),
                icon: Icon(
                  Icons.share,
                  color: Colors.grey[400],
                  size: 20,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _launchUrl(BuildContext context) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Could not open link: $url'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Invalid URL: $url'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _shareLink(BuildContext context) async {
    await Share.shareUri(Uri.parse(url));
  }

  _LinkConfig _getLinkConfig(LinkType type) {
    switch (type) {
      case LinkType.whatsapp:
        return _LinkConfig(
          icon: FontAwesomeIcons.whatsapp,
          iconColor: const Color(0xFF25D366),
          iconBackgroundColor: const Color(0xFF25D366).withValues(alpha: 0.1),
          backgroundColor: const Color(0xFF25D366),
          badgeColor: const Color(0xFF25D366),
          label: 'WhatsApp',
        );
      case LinkType.telegram:
        return _LinkConfig(
          icon: FontAwesomeIcons.telegram,
          iconColor: const Color(0xFF0088CC),
          iconBackgroundColor: const Color(0xFF0088CC).withValues(alpha: 0.1),
          backgroundColor: const Color(0xFF0088CC),
          badgeColor: const Color(0xFF0088CC),
          label: 'Telegram',
        );
      case LinkType.external:
        return _LinkConfig(
          icon: FontAwesomeIcons.link,
          iconColor: const Color(0xFF5A75FF),
          iconBackgroundColor: const Color(0xFF5A75FF).withValues(alpha: 0.1),
          backgroundColor: const Color(0xFF5A75FF),
          badgeColor: const Color(0xFF5A75FF),
          label: 'External Link',
        );
    }
  }
}

class _LinkConfig {
  final FaIconData icon;
  final Color iconColor;
  final Color iconBackgroundColor;
  final Color backgroundColor;
  final Color badgeColor;
  final String label;

  _LinkConfig({
    required this.icon,
    required this.iconColor,
    required this.iconBackgroundColor,
    required this.backgroundColor,
    required this.badgeColor,
    required this.label,
  });
}
