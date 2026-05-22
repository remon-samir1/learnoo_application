// lib/core/services/screen_protection_example.dart
// Example usage of the updated HIGH-SECURITY screen protection system

import 'package:flutter/material.dart';
import 'screen_protection_service.dart';
import '../widgets/secure_wrapper.dart';
import '../widgets/watermark_widget.dart';

// ============================================================================
// EXAMPLE 1: Global Protection (App-wide)
// ============================================================================
// In your main.dart (Global Native Hardening):
/*
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize screen protection service
  final screenProtection = ScreenProtectionService();
  await screenProtection.initialize();
  
  // Global protection (FLAG_SECURE on Android, high-priority window on iOS) 
  // is enabled dynamically via the Native plugins now upon detection.
  
  runApp(const MyApp());
}
*/

// ============================================================================
// EXAMPLE 2: SecureWrapper Widget (Fail-Safe Declarative)
// ============================================================================
// Use this for any sensitive screen. The screen will literally be BLACK
// until the security checks (jailbreak, screen recording, suspicious apps) PASS.
class BankingScreen extends StatelessWidget {
  const BankingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SecureWrapper(
      protectionMessage: 'Checking environment security...',
      child: Scaffold(
        appBar: AppBar(title: const Text('Banking')),
        body: const Center(
          child: Text('Sensitive banking information visible.'),
        ),
      ),
    );
  }
}

// ============================================================================
// EXAMPLE 3: Service API Direct Usage
// ============================================================================
// How to manually trigger threat scans and checks.
class SecuritySettingsScreen extends StatefulWidget {
  const SecuritySettingsScreen({super.key});

  @override
  State<SecuritySettingsScreen> createState() => _SecuritySettingsScreenState();
}

class _SecuritySettingsScreenState extends State<SecuritySettingsScreen> {
  final ScreenProtectionService _protection = ScreenProtectionService();
  Map<String, dynamic> _status = {};

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    final status = await _protection.getProtectionStatus();
    setState(() {
      _status = status;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Security Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text("Is Global Native FLAG_SECURE Active? ${_status['isGlobalEnabled'] ?? false}"),
          Text("Is Jailbroken/Rooted? ${_status['isJailbroken'] ?? false}"),
          Text("Is Screen Recording Active? ${_status['isRecording'] ?? false}"),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () async {
               bool suspicious = await _protection.detectSuspiciousApps();
               if (!context.mounted) return;
               ScaffoldMessenger.of(context).showSnackBar(
                 SnackBar(content: Text('Suspicious background apps detected: $suspicious')),
               );
            },
            child: const Text('Scan For Suspicious Apps (Android)'),
          ),
          ElevatedButton(
            onPressed: () async {
               await _protection.requestUsageStatsPermission();
            },
            child: const Text('Request Usage Access Permission'),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// EXAMPLE 4: Adding the Dynamic Watermark Layer
// ============================================================================
// Combine the SecureWrapper and the changing WatermarkWidget to deter physical cameras.
class ProtectedDocumentScreen extends StatelessWidget {
  const ProtectedDocumentScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SecureWrapper(
      child: Scaffold(
        appBar: AppBar(title: const Text('Confidential Doc')),
        body: const Stack(
          children: [
            // Your document
            Center(child: Text("Top Secret Data")),
            // The watermark
            Positioned.fill(
              child: WatermarkWidget(
                userName: "John Doe",
                userId: "USER_101",
              ),
            ),
          ],
        ),
      ),
    );
  }
}
