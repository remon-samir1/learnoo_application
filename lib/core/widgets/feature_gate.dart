import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:easy_localization/easy_localization.dart';

/// Enum representing different app features that can be gated
enum AppFeature {
  exams,
  liveStreaming,
  videoContent,
  pdfDownloads,
  community,
  notes,
  library,
}

/// Model for feature access control
class FeatureAccess {
  final AppFeature feature;
  final bool isEnabled;
  final String? requiredPlan;
  final DateTime? validUntil;

  FeatureAccess({
    required this.feature,
    required this.isEnabled,
    this.requiredPlan,
    this.validUntil,
  });

  bool get isCurrentlyValid {
    if (!isEnabled) return false;
    if (validUntil == null) return true;
    return DateTime.now().isBefore(validUntil!);
  }
}

/// Service to manage feature access control
class FeatureAccessService {
  static final FeatureAccessService _instance = FeatureAccessService._internal();
  factory FeatureAccessService() => _instance;
  FeatureAccessService._internal();

  final Map<AppFeature, FeatureAccess> _accessMap = {};

  /// Initialize with default access levels from user profile
  void initializeFromProfile(Map<String, dynamic> profile) {
    final attributes = profile['attributes'] ?? profile;
    
    // Parse feature flags from profile
    final features = attributes['features'] as Map<String, dynamic>? ?? {};
    final subscription = attributes['subscription'] as Map<String, dynamic>? ?? {};
    
    _accessMap[AppFeature.exams] = FeatureAccess(
      feature: AppFeature.exams,
      isEnabled: features['exams'] ?? true,
      requiredPlan: subscription['plan'],
      validUntil: _parseDate(subscription['valid_until']),
    );
    
    _accessMap[AppFeature.liveStreaming] = FeatureAccess(
      feature: AppFeature.liveStreaming,
      isEnabled: features['live_streaming'] ?? true,
      requiredPlan: subscription['plan'],
      validUntil: _parseDate(subscription['valid_until']),
    );
    
    _accessMap[AppFeature.videoContent] = FeatureAccess(
      feature: AppFeature.videoContent,
      isEnabled: features['video_content'] ?? true,
      requiredPlan: subscription['plan'],
      validUntil: _parseDate(subscription['valid_until']),
    );
    
    _accessMap[AppFeature.pdfDownloads] = FeatureAccess(
      feature: AppFeature.pdfDownloads,
      isEnabled: features['pdf_downloads'] ?? true,
      requiredPlan: subscription['plan'],
      validUntil: _parseDate(subscription['valid_until']),
    );
    
    _accessMap[AppFeature.community] = FeatureAccess(
      feature: AppFeature.community,
      isEnabled: features['community'] ?? true,
      requiredPlan: subscription['plan'],
      validUntil: _parseDate(subscription['valid_until']),
    );
    
    _accessMap[AppFeature.notes] = FeatureAccess(
      feature: AppFeature.notes,
      isEnabled: features['notes'] ?? true,
      requiredPlan: subscription['plan'],
      validUntil: _parseDate(subscription['valid_until']),
    );
    
    _accessMap[AppFeature.library] = FeatureAccess(
      feature: AppFeature.library,
      isEnabled: features['library'] ?? true,
      requiredPlan: subscription['plan'],
      validUntil: _parseDate(subscription['valid_until']),
    );
  }

  DateTime? _parseDate(String? dateStr) {
    if (dateStr == null) return null;
    return DateTime.tryParse(dateStr);
  }

  /// Check if a feature is accessible
  bool canAccess(AppFeature feature) {
    final access = _accessMap[feature];
    return access?.isCurrentlyValid ?? false;
  }

  /// Check if feature is completely disabled (not just expired)
  bool isFeatureDisabled(AppFeature feature) {
    final access = _accessMap[feature];
    return access?.isEnabled == false;
  }

  /// Get feature access details
  FeatureAccess? getFeatureAccess(AppFeature feature) {
    return _accessMap[feature];
  }

  /// Enable/disable a feature (for admin/override purposes)
  void setFeatureEnabled(AppFeature feature, bool enabled) {
    final current = _accessMap[feature];
    if (current != null) {
      _accessMap[feature] = FeatureAccess(
        feature: feature,
        isEnabled: enabled,
        requiredPlan: current.requiredPlan,
        validUntil: current.validUntil,
      );
    }
  }

  /// Get all available features for the user
  List<AppFeature> getAvailableFeatures() {
    return _accessMap.values
        .where((access) => access.isCurrentlyValid)
        .map((access) => access.feature)
        .toList();
  }

  /// Clear all access data (e.g., on logout)
  void clear() {
    _accessMap.clear();
  }
}

/// Widget that gates access to a feature based on user's subscription
class FeatureGate extends StatelessWidget {
  final AppFeature feature;
  final Widget child;
  final Widget? fallback;
  final VoidCallback? onUpgrade;

  const FeatureGate({
    super.key,
    required this.feature,
    required this.child,
    this.fallback,
    this.onUpgrade,
  });

  @override
  Widget build(BuildContext context) {
    final service = FeatureAccessService();
    final hasAccess = service.canAccess(feature);
    final isDisabled = service.isFeatureDisabled(feature);

    if (hasAccess) {
      return child;
    }

    if (fallback != null) {
      return fallback!;
    }

    return _DisabledFeatureView(
      feature: feature,
      isDisabled: isDisabled,
      onUpgrade: onUpgrade,
    );
  }
}

/// Widget to hide/show navigation items based on feature access
class FeatureNavGate extends StatelessWidget {
  final AppFeature feature;
  final Widget child;

  const FeatureNavGate({
    super.key,
    required this.feature,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final service = FeatureAccessService();
    final hasAccess = service.canAccess(feature);

    if (hasAccess) {
      return child;
    }

    return const SizedBox.shrink();
  }
}

/// View shown when a feature is disabled or locked
class _DisabledFeatureView extends StatelessWidget {
  final AppFeature feature;
  final bool isDisabled;
  final VoidCallback? onUpgrade;

  const _DisabledFeatureView({
    required this.feature,
    required this.isDisabled,
    this.onUpgrade,
  });

  @override
  Widget build(BuildContext context) {
    final config = _getFeatureConfig(feature);

    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFFFFF0F0),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: FaIcon(
                  config.icon,
                  size: 32,
                  color: const Color(0xFFFF4B4B),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              isDisabled
                  ? 'feature.disabled_title'.tr(args: [config.name])
                  : 'feature.locked_title'.tr(args: [config.name]),
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1F2937),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              isDisabled
                  ? 'feature.disabled_message'.tr(args: [config.name])
                  : 'feature.locked_message'.tr(args: [config.name]),
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            if (!isDisabled && onUpgrade != null)
              ElevatedButton.icon(
                onPressed: onUpgrade,
                icon: const FaIcon(FontAwesomeIcons.crown, size: 16),
                label: Text('feature.upgrade_now'.tr()),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF5A75FF),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  _FeatureConfig _getFeatureConfig(AppFeature feature) {
    switch (feature) {
      case AppFeature.exams:
        return _FeatureConfig(
          name: 'feature.exams'.tr(),
          icon: FontAwesomeIcons.fileSignature,
        );
      case AppFeature.liveStreaming:
        return _FeatureConfig(
          name: 'feature.live'.tr(),
          icon: FontAwesomeIcons.video,
        );
      case AppFeature.videoContent:
        return _FeatureConfig(
          name: 'feature.videos'.tr(),
          icon: FontAwesomeIcons.circlePlay,
        );
      case AppFeature.pdfDownloads:
        return _FeatureConfig(
          name: 'feature.pdfs'.tr(),
          icon: FontAwesomeIcons.filePdf,
        );
      case AppFeature.community:
        return _FeatureConfig(
          name: 'feature.community'.tr(),
          icon: FontAwesomeIcons.users,
        );
      case AppFeature.notes:
        return _FeatureConfig(
          name: 'feature.notes'.tr(),
          icon: FontAwesomeIcons.noteSticky,
        );
      case AppFeature.library:
        return _FeatureConfig(
          name: 'feature.library'.tr(),
          icon: FontAwesomeIcons.book,
        );
    }
  }
}

class _FeatureConfig {
  final String name;
  final FaIconData? icon;

  _FeatureConfig({required this.name, required this.icon});
}
