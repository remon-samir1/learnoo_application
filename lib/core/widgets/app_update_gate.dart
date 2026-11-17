import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/app_update_service.dart';
import '../theme/app_colors.dart';
import 'app_logo.dart';

/// Forced update (dashboard: Settings → App Update). Sits above every screen:
/// when the installed version is below the store's minimum, the app shows only
/// [UpdateRequiredScreen]; nothing else is built, so nothing else is reachable.
///
/// Checked at start and each time the app returns to the foreground. When the
/// server cannot be reached the last answer stands, and at start that means
/// the app opens normally — students are never locked out offline.
class AppUpdateGate extends StatefulWidget {
  const AppUpdateGate({
    super.key,
    required this.child,
    this.check,
    this.openStore,
  });

  final Widget child;

  /// Defaults to [AppUpdateService.check]; tests supply their own.
  final Future<AppUpdateStatus> Function()? check;

  /// Defaults to opening the link in the store app.
  final Future<bool> Function(Uri storeUrl)? openStore;

  @override
  State<AppUpdateGate> createState() => _AppUpdateGateState();
}

class _AppUpdateGateState extends State<AppUpdateGate>
    with WidgetsBindingObserver {
  late final Future<AppUpdateStatus> Function() _check =
      widget.check ?? AppUpdateService().check;

  /// Set while this version must update first.
  String? _storeUrl;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_runCheck());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_runCheck());
  }

  Future<void> _runCheck() async {
    if (_checking) return;
    _checking = true;
    try {
      final status = await _check();
      if (!mounted) return;
      switch (status.kind) {
        case AppUpdateStatusKind.required:
          setState(() => _storeUrl = status.storeUrl);
        case AppUpdateStatusKind.allowed:
          if (_storeUrl != null) setState(() => _storeUrl = null);
        case AppUpdateStatusKind.unknown:
          break;
      }
    } finally {
      _checking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final storeUrl = _storeUrl;
    if (storeUrl == null) return widget.child;
    return UpdateRequiredScreen(
      storeUrl: storeUrl,
      openStore: widget.openStore ?? _openInStore,
    );
  }

  static Future<bool> _openInStore(Uri storeUrl) =>
      launchUrl(storeUrl, mode: LaunchMode.externalApplication);
}

/// Full-screen, no way past it: a short message and one button to the store.
class UpdateRequiredScreen extends StatefulWidget {
  const UpdateRequiredScreen({
    super.key,
    required this.storeUrl,
    required this.openStore,
  });

  final String storeUrl;
  final Future<bool> Function(Uri storeUrl) openStore;

  @override
  State<UpdateRequiredScreen> createState() => _UpdateRequiredScreenState();
}

class _UpdateRequiredScreenState extends State<UpdateRequiredScreen> {
  bool _opening = false;

  Future<void> _update() async {
    setState(() => _opening = true);
    var opened = false;
    try {
      final uri = Uri.tryParse(widget.storeUrl);
      opened = uri != null && await widget.openStore(uri);
    } catch (error) {
      debugPrint('Could not open the store: $error');
    }
    if (!mounted) return;
    setState(() => _opening = false);
    if (!opened) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text('update_store_open_failed'.tr())));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // White status bar text on the blue background.
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.primaryBlue,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const AppLogo(size: 96),
                  const SizedBox(height: 32),
                  const Icon(
                    Icons.system_update,
                    color: Colors.white,
                    size: 40,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'update_required_title'.tr(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'update_required_message'.tr(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _opening ? null : _update,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppColors.primaryBlue,
                        disabledBackgroundColor: Colors.white70,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      child: _opening
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                              ),
                            )
                          : Text('update_required_button'.tr()),
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
}
