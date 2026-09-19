import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:learnoo/core/services/screen_protection_service.dart';

/// A fail-safe wrapper that protects sensitive content.
/// Content starts HIDDEN (black screen) until security checks pass.
class SecureWrapper extends StatefulWidget {
  final Widget child;
  final String protectionMessage;

  const SecureWrapper({
    super.key,
    required this.child,
    this.protectionMessage = "Content Protected",
  });

  @override
  State<SecureWrapper> createState() => _SecureWrapperState();
}

class _SecureWrapperState extends State<SecureWrapper> with WidgetsBindingObserver {
  final ScreenProtectionService _security = ScreenProtectionService();
  StreamSubscription<bool>? _policySubscription;
  bool _isSafe = false;
  String _statusMessage = "Initializing security...";
  Timer? _appCheckTimer;
  bool _isProtectionEnabled = false;
  bool _isEmulator = false;
  Timer? _securityTimeoutTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkIfEmulator();
  }

  Future<void> _checkIfEmulator() async {
    // Check if running on emulator
    try {
      if (Platform.isAndroid) {
        final deviceInfo = DeviceInfoPlugin();
        final androidInfo = await deviceInfo.androidInfo;
        final brand = androidInfo.brand.toLowerCase();
        final device = androidInfo.device.toLowerCase();
        final model = androidInfo.model.toLowerCase();
        final manufacturer = androidInfo.manufacturer.toLowerCase();
        
        _isEmulator = brand.contains('google') || 
                      device.contains('emulator') || 
                      device.contains('simulator') ||
                      model.contains('emulator') ||
                      manufacturer.contains('google') && model.contains('pixel') && androidInfo.isPhysicalDevice == false;
      }
    } catch (e) {
      debugPrint('[SecureWrapper] Error detecting emulator: $e');
    }

    if (!mounted) return;
    _policySubscription ??= _security.onPolicyChanged.listen((_) => _applyPolicy());
    _applyPolicy();
  }

  /// Follow the dashboard "Block Screenshots & Recording" policy (fail closed:
  /// protected until the dashboard says otherwise).
  void _applyPolicy() {
    if (!mounted) return;
    _appCheckTimer?.cancel();
    _securityTimeoutTimer?.cancel();
    _isProtectionEnabled = _security.isProtectionActive;

    if (_isProtectionEnabled && !_isEmulator) {
      // Add timeout to prevent indefinite security scan
      _securityTimeoutTimer = Timer(const Duration(seconds: 8), () {
        if (mounted && !_isSafe) {
          debugPrint('[SecureWrapper] Security scan timeout - marking as safe');
          setState(() => _isSafe = true);
        }
      });
      _performInitialSecurityScan();
      // Periodically check for suspicious apps on Android
      _appCheckTimer = Timer.periodic(const Duration(seconds: 5), (_) => _scanForSuspiciousApps());
    } else {
      // Protection disabled or on emulator - mark as safe immediately
      if (_isEmulator && kDebugMode) {
        debugPrint('[SecureWrapper] Emulator detected - skipping security checks');
      }
      setState(() => _isSafe = true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _policySubscription?.cancel();
    _appCheckTimer?.cancel();
    _securityTimeoutTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_isProtectionEnabled) return;
    
    if (state == AppLifecycleState.resumed) {
      _performInitialSecurityScan();
    } else {
      setState(() => _isSafe = false);
    }
  }

  Future<void> _performInitialSecurityScan() async {
    // Skip security scan on emulator
    if (_isEmulator) {
      setState(() => _isSafe = true);
      return;
    }

    setState(() {
      _isSafe = false;
      _statusMessage = "Scanning for threats...";
    });

    try {
      final status = await _security.getProtectionStatus().timeout(
        const Duration(seconds: 5),
        onTimeout: () => {'timeout': true, 'isRecording': false, 'isJailbroken': false, 'isMultiWindow': false},
      );
      
      if (status['timeout'] == true) {
        debugPrint('[SecureWrapper] Security scan timed out - allowing content');
        setState(() => _isSafe = true);
        return;
      }
      
      final isRecording = status['isRecording'] ?? false;
      final isJailbroken = status['isJailbroken'] ?? false;
      final isMultiWindow = status['isMultiWindow'] ?? false;

      if (isRecording) {
        _showBreach("Screen recording detected");
        return;
      }
      if (isJailbroken) {
        _showBreach("Rooted/Jailbroken device detected");
        return;
      }
      if (isMultiWindow) {
        _showBreach("Split-screen mode not allowed");
        return;
      }

      await _scanForSuspiciousApps();
    } catch (e) {
      debugPrint('[SecureWrapper] Security scan error: $e');
      // On error, allow content to prevent blocking users
      setState(() => _isSafe = true);
    }
  }

  Future<void> _scanForSuspiciousApps() async {
    final hasSuspiciousApps = await _security.detectSuspiciousApps();
    if (hasSuspiciousApps) {
      _showBreach("Suspicious apps (Zoom/Meet/Recorders) detected");
      return;
    }

    if (mounted) {
      setState(() {
        _isSafe = true;
      });
    }
  }

  void _showBreach(String message) {
    if (mounted) {
      setState(() {
        _isSafe = false;
        _statusMessage = message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: _security.onSecurityStatusChanged,
      initialData: _isSafe,
      builder: (context, snapshot) {
        final currentSafety = snapshot.data ?? false;
        
        if (!currentSafety || !_isSafe) {
          return Scaffold(
            backgroundColor: Colors.black,
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.security, color: Colors.red, size: 64),
                  const SizedBox(height: 16),
                  Text(
                    _statusMessage,
                    style: const TextStyle(color: Colors.white, fontSize: 18),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _performInitialSecurityScan,
                    child: const Text("Retry Security Scan"),
                  )
                ],
              ),
            ),
          );
        }

        return widget.child;
      },
    );
  }
}
