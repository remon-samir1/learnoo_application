import 'package:flutter/material.dart';
import '../services/feature_manager.dart';

/// FeatureProvider - Provides reactive access to feature flags
/// 
/// Usage:
/// ```dart
/// FeatureProvider(
///   builder: (context, features, child) {
///     if (features.isEnabled('some_feature')) {
///       return SomeWidget();
///     }
///     return Container();
///   },
/// )
/// ```
class FeatureProvider extends StatefulWidget {
  final Widget? child;
  final Widget Function(BuildContext context, FeatureManager features, Widget? child) builder;

  const FeatureProvider({
    super.key,
    this.child,
    required this.builder,
  });

  @override
  State<FeatureProvider> createState() => _FeatureProviderState();
}

class _FeatureProviderState extends State<FeatureProvider> {
  final FeatureManager _featureManager = FeatureManager();

  @override
  void initState() {
    super.initState();
    _featureManager.addListener(_onFeaturesChanged);
  }

  @override
  void dispose() {
    _featureManager.removeListener(_onFeaturesChanged);
    super.dispose();
  }

  void _onFeaturesChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _featureManager, widget.child);
  }
}

/// FeatureBuilder - Simplified builder for conditional rendering based on a single feature
/// 
/// Usage:
/// ```dart
/// FeatureBuilder(
///   featureKey: 'enable_purchases',
///   builder: (context, isEnabled) {
///     if (!isEnabled) return SizedBox.shrink();
///     return PurchaseWidget();
///   },
/// )
/// ```
class FeatureBuilder extends StatelessWidget {
  final String featureKey;
  final Widget Function(BuildContext context, bool isEnabled) builder;
  final Widget? childWhenDisabled;

  const FeatureBuilder({
    super.key,
    required this.featureKey,
    required this.builder,
    this.childWhenDisabled,
  });

  @override
  Widget build(BuildContext context) {
    return FeatureProvider(
      builder: (context, features, _) {
        final isEnabled = features.isEnabled(featureKey);
        if (!isEnabled && childWhenDisabled != null) {
          return childWhenDisabled!;
        }
        return builder(context, isEnabled);
      },
    );
  }
}

/// FeatureSwitcher - Shows different widgets based on feature state without empty space
/// 
/// Usage:
/// ```dart
/// FeatureSwitcher(
///   featureKey: 'enable_electronic_library',
///   enabledChild: LibraryWidget(),
///   disabledChild: null, // Completely removes from UI
/// )
/// ```
class FeatureSwitcher extends StatelessWidget {
  final String featureKey;
  final Widget enabledChild;
  final Widget? disabledChild;
  final bool maintainSpace;

  const FeatureSwitcher({
    super.key,
    required this.featureKey,
    required this.enabledChild,
    this.disabledChild,
    this.maintainSpace = false,
  });

  @override
  Widget build(BuildContext context) {
    return FeatureProvider(
      builder: (context, features, _) {
        final isEnabled = features.isEnabled(featureKey);
        if (isEnabled) {
          return enabledChild;
        }
        return disabledChild ?? (maintainSpace ? const SizedBox.shrink() : const SizedBox.shrink());
      },
    );
  }
}

/// FeatureVisibility - Conditionally shows/hides a widget based on feature state
/// When hidden, it takes no space in the UI (avoids empty gaps)
///
/// Usage:
/// ```dart
/// FeatureVisibility(
///   featureKey: 'enable_continue_watching',
///   child: ContinueWatchingSection(),
/// )
/// ```
class FeatureVisibility extends StatelessWidget {
  final String featureKey;
  final Widget child;
  final bool defaultValue;

  const FeatureVisibility({
    super.key,
    required this.featureKey,
    required this.child,
    this.defaultValue = false,
  });

  @override
  Widget build(BuildContext context) {
    return FeatureProvider(
      builder: (context, features, _) {
        final isEnabled = features.isEnabled(featureKey, defaultValue: defaultValue);
        if (!isEnabled) {
          return const SizedBox.shrink();
        }
        return child;
      },
    );
  }
}

/// MultiFeatureVisibility - Shows child only if ALL specified features are enabled
///
/// Usage:
/// ```dart
/// MultiFeatureVisibility(
///   featureKeys: ['enable_purchases', 'enable_electronic_library'],
///   child: PurchaseLibraryWidget(),
/// )
/// ```
class MultiFeatureVisibility extends StatelessWidget {
  final List<String> featureKeys;
  final Widget child;
  final bool requireAll;

  const MultiFeatureVisibility({
    super.key,
    required this.featureKeys,
    required this.child,
    this.requireAll = true,
  });

  @override
  Widget build(BuildContext context) {
    return FeatureProvider(
      builder: (context, features, _) {
        bool shouldShow;
        if (requireAll) {
          shouldShow = featureKeys.every((key) => features.isEnabled(key));
        } else {
          shouldShow = featureKeys.any((key) => features.isEnabled(key));
        }

        if (!shouldShow) {
          return const SizedBox.shrink();
        }
        return child;
      },
    );
  }
}

/// FeatureAppBarTitle - Dynamic app title based on platform_name feature
///
/// Usage:
/// ```dart
/// AppBar(
///   title: FeatureAppBarTitle(),
/// )
/// ```
class FeatureAppBarTitle extends StatelessWidget {
  final TextStyle? style;

  const FeatureAppBarTitle({super.key, this.style});

  @override
  Widget build(BuildContext context) {
    return FeatureProvider(
      builder: (context, features, _) {
        return Text(
          features.platformName,
          style: style,
        );
      },
    );
  }
}

/// FeatureLogo - Dynamic logo widget based on logo feature
///
/// Usage:
/// ```dart
/// FeatureLogo(size: 85),
/// ```
class FeatureLogo extends StatelessWidget {
  final double size;
  final BoxFit fit;

  const FeatureLogo({
    super.key,
    this.size = 85,
    this.fit = BoxFit.contain,
  });

  @override
  Widget build(BuildContext context) {
    return FeatureProvider(
      builder: (context, features, _) {
        final logoUrl = features.logoUrl;
        if (logoUrl.isNotEmpty) {
          return Image.network(
            logoUrl,
            width: size,
            height: size,
            fit: fit,
            errorBuilder: (context, error, stackTrace) {
              return _buildDefaultLogo(size);
            },
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return _buildDefaultLogo(size);
            },
          );
        }
        return _buildDefaultLogo(size);
      },
    );
  }

  Widget _buildDefaultLogo(double size) {
    // Return default logo from assets
    return Image.asset(
      'assets/images/Logo.png',
      width: size,
      height: size,
      fit: fit,
    );
  }
}
