# Screen Protection System - Setup Guide

Production-grade screen protection for Flutter with native Android (FLAG_SECURE) and iOS (best-effort detection + overlay) implementations.

---

## 1. Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                         FLUTTER LAYER                          │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────────────────┐  ┌─────────────────────────────────┐  │
│  │ ScreenProtection    │  │ ProtectedScreen Widget          │  │
│  │ Service (Singleton) │  │ - Declarative screen protection │  │
│  │                     │  │ - Lifecycle management          │  │
│  │ Methods:            │  │ - Event callbacks               │  │
│  │ - enableGlobal()    │  │ - Blur overlays                 │  │
│  │ - disableGlobal()   │  └─────────────────────────────────┘  │
│  │ - enableLocal()     │                                       │
│  │ - disableLocal()   │  ┌─────────────────────────────────┐  │
│  │ - onEvent (stream) │  │ ScreenProtectionMixin           │  │
│  └─────────────────────┘  │ - For existing StatefulWidgets    │  │
│           │               └─────────────────────────────────┘  │
│           │                                                      │
│           ▼                                                      │
├─────────────────────────────────────────────────────────────────┤
│                    PLATFORM CHANNEL (Method + Event)              │
│                   com.learnoo.screen_protection                 │
├─────────────────────────────┬───────────────────────────────────┤
│         ANDROID             │               iOS                 │
│  ┌─────────────────────┐    │    ┌──────────────────────────┐   │
│  │ MainActivity.kt     │    │    │ AppDelegate.swift        │   │
│  │                     │    │    │                          │   │
│  │ FLAG_SECURE         │    │    │ - Screenshot detection   │   │
│  │ (hardware-level)    │    │    │ - Recording detection    │   │
│  │                     │    │    │ - Blur overlay window    │   │
│  │ Blocks:             │    │    │ - App switcher blur      │   │
│  │ - Screenshots       │    │    │                          │   │
│  │ - Screen recording  │    │    │ Best-effort (no blocking)│   │
│  │ - Recent apps       │    │    │                          │   │
│  └─────────────────────┘    │    └──────────────────────────┘   │
└─────────────────────────────┴───────────────────────────────────┘
```

---

## 2. Files Created/Modified

### Dart Layer
| File | Purpose |
|------|---------|
| `lib/core/services/screen_protection_service.dart` | Core service with platform channel |
| `lib/core/widgets/protected_screen.dart` | Wrapper widget + mixin |
| `lib/core/services/screen_protection_example.dart` | Usage examples |
| `lib/main.dart` | Integration example (modified) |

### Android Native
| File | Purpose |
|------|---------|
| `android/app/src/main/kotlin/com/example/learnoo/MainActivity.kt` | FLAG_SECURE implementation |

### iOS Native
| File | Purpose |
|------|---------|
| `ios/Runner/AppDelegate.swift` | Detection + overlay implementation |
| `ios/Runner/SceneDelegate.swift` | Scene lifecycle hooks |

---

## 3. API Reference

### ScreenProtectionService

```dart
// Initialize (call in main.dart before runApp)
final protection = ScreenProtectionService();
await protection.initialize();

// Global protection (entire app)
await protection.enableGlobalProtection();
await protection.disableGlobalProtection();

// Per-screen protection (reference counted)
await protection.enableForCurrentScreen();  // Call in initState
await protection.disableForCurrentScreen();   // Call in dispose

// Event stream (iOS mainly)
protection.onEvent.listen((event) {
  switch (event.event) {
    case ScreenProtectionEvent.screenshotAttempted:
      // Handle screenshot
      break;
    case ScreenProtectionEvent.recordingStarted:
      // Handle recording start
      break;
  }
});

// Get status
final status = await protection.getProtectionStatus();
```

### ProtectedScreen Widget

```dart
// Basic usage
ProtectedScreen(
  child: MySensitiveScreen(),
)

// With options
ProtectedScreen(
  mode: ProtectionMode.strict,  // or .standard, .debug
  onScreenshotAttempt: () => showWarning(),
  onRecordingStarted: () => showRecordingWarning(),
  protectionMessage: 'Banking Data Protected',
  showDebugIndicator: true,  // Visual indicator in debug mode
  child: MyScreen(),
)
```

### ScreenProtectionMixin

```dart
class _MyScreenState extends State<MyScreen> with ScreenProtectionMixin {
  @override
  void initState() {
    super.initState();
    enableScreenProtection();
    listenToProtectionEvents((event) => handleEvent(event));
  }

  @override
  void dispose() {
    cancelProtectionEventSubscription();
    disableScreenProtection();
    super.dispose();
  }
}
```

---

## 4. Integration Steps

### Step 1: Initialize in main.dart

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize screen protection
  final protection = ScreenProtectionService();
  await protection.initialize();
  
  // Optional: Enable global protection
  // await protection.enableGlobalProtection();
  
  runApp(const MyApp());
}
```

### Step 2: Protect Sensitive Screens

**Option A: ProtectedScreen Widget (Recommended)**

```dart
class BankingScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ProtectedScreen(
      child: Scaffold(
        appBar: AppBar(title: Text('Banking')),
        body: // ...
      ),
    );
  }
}
```

**Option B: Mixin (for existing StatefulWidgets)**

```dart
class _DocumentScreenState extends State<DocumentScreen> 
    with ScreenProtectionMixin {
  @override
  void initState() {
    super.initState();
    enableScreenProtection();
  }

  @override
  void dispose() {
    disableScreenProtection();
    super.dispose();
  }
}
```

**Option C: Direct Service API**

```dart
// Manual control
await protection.enableForCurrentScreen();
await protection.disableForCurrentScreen();
```

### Step 3: Build and Test

```bash
# Android
flutter clean
flutter pub get
cd android
./gradlew clean
cd ..
flutter run

# iOS
flutter clean
flutter pub get
cd ios
pod install
cd ..
flutter run
```

---

## 5. Platform Differences & Limitations

### Android
| Feature | Status | Notes |
|---------|--------|-------|
| Screenshots | BLOCKED | FLAG_SECURE prevents all screenshots |
| Screen Recording | BLOCKED | Recording shows black screen |
| Recent Apps | BLOCKED | Thumbnail is black/empty |
| Reliability | 100% | Hardware-level, cannot be bypassed |

### iOS
| Feature | Status | Notes |
|---------|--------|-------|
| Screenshots | DETECTED | Cannot block, only detect after capture |
| Screen Recording | DETECTED | ~1-2s latency in detection |
| App Switcher | BLURRED | Blur overlay shown, not hidden |
| Reliability | Best-effort | No hardware-level protection API |

### Known Limitations

**iOS:**
- Screenshots: Cannot be prevented. Detection fires AFTER screenshot is taken.
- Screen recording: Cannot be prevented. Detection has latency.
- App switcher: Cannot hide thumbnail. Best we can do is blur overlay when user returns.
- iOS Simulator: Detection notifications may not work as reliably as physical devices.

**Android:**
- FLAG_SECURE is system-level and reliable, but some OEM skins may behave differently.
- Recent apps behavior varies slightly across Android versions.

---

## 6. Why This Approach?

### vs Flutter Packages

| Package | Issue | This Solution |
|---------|-------|---------------|
| flutter_windowmanager | Unmaintained, Android-only | Native implementation, both platforms |
| secure_screen | Limited features, iOS issues | Full feature set, proper iOS handling |
| screen_protector | Basic, limited events | Full event stream, flexible API |

### Advantages

1. **Native Implementation**: No third-party dependencies, full control
2. **Platform Channels**: Clean Flutter ↔ Native communication
3. **Reference Counting**: Multiple protected screens work correctly
4. **Event Stream**: Real-time detection callbacks
5. **Flexible API**: Widget, Mixin, or Service API
6. **Proper Lifecycle**: Handles app backgrounding, navigation, etc.
7. **Production Ready**: Error handling, state management, logging

### Security Model

- **Android**: Hardware-level blocking via FLAG_SECURE (100% effective)
- **iOS**: Best-effort detection + UX deterrents (compliance-focused)

---

## 7. Testing Checklist

### Android
- [ ] Screenshot attempt shows "Cannot capture screen"
- [ ] Screen recording shows black screen
- [ ] Recent apps shows black thumbnail
- [ ] Protection persists after app background/foreground
- [ ] Multiple protected screens work correctly

### iOS
- [ ] Screenshot triggers callback (check logs)
- [ ] Screen recording triggers callback (wait 1-2s)
- [ ] App switcher shows blur overlay on return
- [ ] Background/foreground transitions work
- [ ] Multiple protected screens work correctly

### General
- [ ] Global protection enables/disables correctly
- [ ] Local protection reference counting works
- [ ] Event stream receives events
- [ ] No crashes on rapid navigation
- [ ] Works on physical devices (not just simulators)

---

## 8. Troubleshooting

### "No implementation found for method"
- Ensure MainActivity.kt / AppDelegate.swift are properly updated
- Run `flutter clean` and rebuild
- Check channel names match exactly

### iOS events not firing
- Test on physical device (simulator may be unreliable)
- Check that UIApplication notifications are working
- Verify event channel is properly set up

### Android FLAG_SECURE not working
- Check that window flags are being set on UI thread
- Verify no other flags are conflicting
- Test on physical device

### Protection not persisting
- Check lifecycle methods (onResume/onPause)
- Verify reference counting is correct
- Ensure global protection state is preserved

---

## 9. Security Best Practices

1. **Use Global Protection** for apps with mostly sensitive content
2. **Use Local Protection** for specific screens (better UX)
3. **Log Security Events** for compliance/auditing
4. **Show User Feedback** when protection is active (iOS)
5. **Test on Physical Devices** before release
6. **Document Limitations** for security team/users
7. **Combine with Other Measures**: Encryption, secure storage, certificate pinning

---

## 10. Maintenance

### Adding New Features
- Add method to `ScreenProtectionService` (Dart)
- Implement in `MainActivity.kt` (Android) and `AppDelegate.swift` (iOS)
- Update this documentation

### Debugging
- Check native logs: `[ScreenProtection]` tag
- Use `getProtectionStatus()` for state inspection
- Enable `ProtectionMode.debug` for visual indicators

---

## Summary

This system provides production-grade screen protection with:
- **Hard blocking** on Android (FLAG_SECURE)
- **Best-effort detection** on iOS (notifications + blur)
- **Clean API**: Widget, Mixin, or Service
- **Full lifecycle handling**
- **No third-party dependencies**

For questions or issues, refer to the example file and this documentation.
