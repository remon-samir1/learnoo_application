import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'core/services/screen_protection_service.dart';
import 'core/services/notification_service.dart';
import 'core/network/api_client.dart';
import 'core/services/websocket_service.dart';
import 'core/services/feature_service.dart';
import 'core/services/feature_manager.dart';
import 'core/theme/dynamic_theme.dart';
import 'core/local/hive_service.dart';
import 'core/sync/sync_service.dart';
import 'core/sync/sync_processors.dart';
import 'core/widgets/back_button_handler.dart';
import 'features/auth/presentation/screens/login_screen.dart';
import 'features/auth/presentation/screens/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();

  // Initialize Hive local database for offline storage
  // This must be done before any repository operations
  final hiveService = HiveService();
  await hiveService.initialize();

  // Initialize sync service for background synchronization
  final syncService = SyncService();
  await syncService.initialize();

  // Register all sync processors for pending actions
  // This enables offline queue to sync comments, progress, posts, etc.
  SyncProcessors.registerAll(syncService);

  // Sync any pending offline actions if online on startup
  if (syncService.isOnline && syncService.pendingCount > 0) {
    unawaited(syncService.syncPendingActions());
  }

  // Parallelize independent service initializations for faster startup
  // These services don't depend on each other, so we can load them simultaneously
  final results = await Future.wait([
    screenProtectionInitialization(),
    notificationInitialization(),
    featureInitialization(),
  ]);

  final screenProtection = results[0] as ScreenProtectionService;
  final notificationService = results[1] as NotificationService;
  final featureServices = results[2] as Map<String, dynamic>;
  final featureManager = featureServices['manager'] as FeatureManager;
  final featureService = featureServices['service'] as FeatureService;
  final themeService = featureServices['theme'] as DynamicThemeService;

  // Optional: Enable global protection for the entire app
  // Uncomment to protect all screens by default
  // await screenProtection.enableGlobalProtection();
  
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
    ),
  );
  
  runApp(
    EasyLocalization(
      supportedLocales: const [Locale('en'), Locale('ar')],
      path: 'assets/translations',
      fallbackLocale: const Locale('en'),
      child: LearnooApp(
        themeService: themeService,
        featureManager: featureManager,
      ),
    ),
  );
}

class LearnooApp extends StatefulWidget {
  final DynamicThemeService themeService;
  final FeatureManager featureManager;

  const LearnooApp({
    super.key,
    required this.themeService,
    required this.featureManager,
  });

  @override
  State<LearnooApp> createState() => _HomeAppState();
}

class _HomeAppState extends State<LearnooApp> with WidgetsBindingObserver {
  final WebSocketService _webSocketService = WebSocketService();

  @override
  void initState() {
    super.initState();
    widget.featureManager.addListener(_onFeaturesChanged);
    WidgetsBinding.instance.addObserver(this);
    ApiClient.onUnauthorized = _onSessionRevoked;
  }

  @override
  void dispose() {
    widget.featureManager.removeListener(_onFeaturesChanged);
    WidgetsBinding.instance.removeObserver(this);
    ApiClient.onUnauthorized = null;
    _webSocketService.disconnect();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _webSocketService.connect();
        _webSocketService.subscribeToNotifications();
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        _webSocketService.unsubscribeFromNotifications();
        break;
      case AppLifecycleState.hidden:
        break;
    }
  }

  void _onFeaturesChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = context.locale;

    // Every API request carries this as the `lang` header, so the backend
    // returns content in the language the student is actually reading —
    // matching how the web dashboard sends its `locale` cookie.
    ApiClient.locale = locale.languageCode;

    return MaterialApp(
      navigatorKey: appNavigatorKey,
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: locale,
      title: widget.featureManager.platformName,
      debugShowCheckedModeBanner: false,
      theme: widget.themeService.getLightTheme(),
      darkTheme: widget.themeService.getDarkTheme(),
      home: const BackButtonHandler(
        child: SplashScreen(),
      ),
      builder: (context, child) {
        return Directionality(
          textDirection: locale.languageCode == 'ar'
              ? TextDirection.rtl
              : TextDirection.ltr,
          child: child!,
        );
      },
    );
  }

  /// Wired to [ApiClient.onUnauthorized]: any 401 that is not a business rule
  /// drops the session and returns the student to sign-in, from wherever they
  /// were. The web does the same in `handleResponse`.
  void _onSessionRevoked() {
    _webSocketService.disconnect();
    final navigator = appNavigatorKey.currentState;
    if (navigator == null) return;
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }
}

/// Lets services outside the widget tree drive navigation (session expiry).
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

// Helper functions for parallel service initialization
Future<ScreenProtectionService> screenProtectionInitialization() async {
  final service = ScreenProtectionService();
  await service.initialize();
  return service;
}

Future<NotificationService> notificationInitialization() async {
  final service = NotificationService();
  await service.initialize();
  await service.requestPermissions();
  return service;
}

Future<Map<String, dynamic>> featureInitialization() async {
  final featureManager = FeatureManager();
  await featureManager.initialize();

  final featureService = FeatureService();
  await featureService.initialize();

  final themeService = DynamicThemeService();
  await themeService.initialize();

  return {
    'manager': featureManager,
    'service': featureService,
    'theme': themeService,
  };
}
