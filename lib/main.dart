import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_core/firebase_core.dart';
import 'ui/kiosk_screen.dart';
import 'ui/power_wake_wrapper.dart';
import 'services/tablet_heartbeat_service.dart';
import 'services/remote_config_service.dart';
import 'package:kiosk_mode/kiosk_mode.dart';
import 'firebase_options.dart'; // Ensure this file is generated via `flutterfire configure`
import 'package:flutter/foundation.dart' show kIsWeb;
import 'web/web_dashboard.dart';
import 'services/telemetry_service.dart';

// === NEW SERVICES ===
import 'services/isolate_prefetch_service.dart';
import 'services/proof_of_play_service.dart';
import 'services/kiosk_lifecycle_observer.dart';
import 'services/admin_command_service.dart';
import 'services/device_settings_service.dart';
import 'services/network_bitrate_service.dart';
import 'services/kiosk_error_boundary.dart';
import 'services/adaptive_cache_manager.dart';
import 'services/memory_leak_guardian.dart';
import 'services/daily_restart_service.dart';
import 'services/heatmap_telemetry_service.dart';
import 'services/face_attention_service.dart';
import 'services/mqtt_command_service.dart';
import 'services/webrtc_service.dart';
import 'ui/ux_widgets.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();
  print("App starting...");
  
  // 1. Initialize Firebase (with duplicate app check and timeout)
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ).timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        print('Firebase initialization timed out');
        throw Exception('Firebase timeout');
      },
    );
    print("Firebase initialized successfully");
  } catch (e) {
    if (e.toString().contains('duplicate-app')) {
      print('Firebase already initialized, continuing...');
    } else {
      print('Firebase initialization error: $e - continuing anyway');
    }
  }

  // WEB ENTRY POINT
  if (kIsWeb) {
    runApp(const MaterialApp(
      title: 'Adscreen Admin',
      home: WebDashboard(),
    ));
    return;
  }

  // ANDROID TABLET ENTRY POINT
  // RemoteConfigService now uses the firebase instance
  // await RemoteConfigService.initialize(); // Move this inside or after ensuring it works with new init

  // 2. Formatting
  // Force Landscape
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  
  // Hide UI aggressively
  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.immersiveSticky,
    overlays: [],
  );

  // Start Kiosk Mode
  startKioskMode();
  
  // Also trigger custom native lockdown for blocking status bar/volume etc
  const platform = MethodChannel('com.adscreen.kiosk/telemetry');
  try {
    platform.invokeMethod('startKiosk');
  } catch (e) {
    print("Native startKiosk error: $e");
  }

  // 3. Keep Screen On (Re-enabled per user request "make it screen always awake")
  try {
    await WakelockPlus.enable();
  } catch (e) {
    print("Wakelock error: $e");
  }

  // 4. Start Telemetry (Robust) - with timeout to prevent blocking
  final tabletService = TabletHeartbeatService();
  try {
    await tabletService.initialize().timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        print("TabletService initialization timed out - continuing anyway");
      },
    );
  } catch (e) {
    print("TabletService initialization error: $e");
  }
  
  // 4b. Start Telemetry Service (API communication)
  try {
    TelemetryService().start();
    print("TelemetryService started");
  } catch (e) {
    print("TelemetryService start error: $e");
  }

  // === NEW SERVICES INITIALIZATION ===

  // 6. Install branded error boundaries (replaces red error screen)
  KioskErrorBoundary.install();

  // 7. Initialize adaptive cache manager
  try {
    await AdaptiveCacheManager().initialize();
    print("AdaptiveCacheManager initialized");
  } catch (e) {
    print("AdaptiveCacheManager init error: $e");
  }

  // 8. Start Proof-of-Play SQLite logger
  try {
    await ProofOfPlayService().initialize();
    print("ProofOfPlayService initialized");
  } catch (e) {
    print("ProofOfPlayService init error: $e");
  }

  // 9. Start Isolate Prefetch Service
  try {
    await IsolatePrefetchService().start();
    print("IsolatePrefetchService started");
  } catch (e) {
    print("IsolatePrefetchService start error: $e");
  }

  // 10. Start Admin WebSocket Command Channel
  try {
    AdminCommandService().connect();
    print("AdminCommandService connected");
  } catch (e) {
    print("AdminCommandService connect error: $e");
  }

  // 11. Initialize Device Settings Service (50 advanced settings)
  try {
    await DeviceSettingsService().initialize();
    print("DeviceSettingsService initialized");
  } catch (e) {
    print("DeviceSettingsService init error: $e");
  }

  // 11b. Start backend JSON remote config polling (15 min)
  try {
    RemoteConfigService.initialize().then((_) => print("RemoteConfigService initialized"));
  } catch (e) {
    print("RemoteConfigService init error: $e");
  }

  // 11c. Start MQTT command bus alongside WebSocket path
  try {
    MqttCommandService().connect().then((_) => print("MqttCommandService connected"));
  } catch (e) {
    print("MqttCommandService connect error: $e");
  }

  // 11d. Start WebRTC signaling service for live screen viewing
  try {
    WebRtcService().initialize().then((_) => print("WebRtcService initialized"));
  } catch (e) {
    print("WebRtcService init error: $e");
  }

  // 11. Start Network-Aware Bitrate Service
  try {
    NetworkAwareBitrateService().start();
    print("NetworkBitrateService started");
  } catch (e) {
    print("NetworkBitrateService start error: $e");
  }

  // 12. Start Memory Leak Guardian
  try {
    MemoryLeakGuardian().start();
    // Register adaptive cache cleanup on memory pressure
    MemoryLeakGuardian().registerCleanup(() async {
      await AdaptiveCacheManager().clearAll();
    });
    print("MemoryLeakGuardian started");
  } catch (e) {
    print("MemoryLeakGuardian start error: $e");
  }

  // 13. Schedule Daily Hot-Restart (4:00 AM)
  try {
    DailyHotRestartService().start(hour: 4, minute: 0);
    // Flush logs before restart
    DailyHotRestartService().registerPreRestart(() async {
      ProofOfPlayService().dispose();
    });
    print("DailyHotRestartService scheduled");
  } catch (e) {
    print("DailyHotRestartService error: $e");
  }

  // 14. Start Heatmap Telemetry
  try {
    HeatmapTelemetryService().start(
      deviceId: tabletService.tabletId ?? 'unknown',
    );
    print("HeatmapTelemetryService started");
  } catch (e) {
    print("HeatmapTelemetryService start error: $e");
  }

  // 15. Start Face Attention Service
  try {
    FaceAttentionService().start(
      deviceId: tabletService.tabletId ?? 'unknown',
    );
    print("FaceAttentionService started");
  } catch (e) {
    print("FaceAttentionService start error: $e");
  }

  // 16. Attach Kiosk Lifecycle Observer
  WidgetsBinding.instance.addObserver(KioskLifecycleObserver());
  
  // 5. Check for updates on startup
  // await tabletService.checkForUpdates(); // Temporarily disabled if method missing, or ensure it exists

  print("Starting app UI...");
  runApp(
    EasyLocalization(
      supportedLocales: const [
        Locale('nl'),
        Locale('fr'),
        Locale('en'),
      ],
      path: 'assets/translations',
      fallbackLocale: const Locale('en'),
      startLocale: const Locale('nl'),
      child: const ProviderScope(child: AdscreenApp()),
    ),
  );
}


class AdscreenApp extends StatelessWidget {
  const AdscreenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Adscreen Kiosk',
      debugShowCheckedModeBanner: false,
      theme: KioskTheme.currentTheme,
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      home: const KioskScreen(),
    );
  }
}
