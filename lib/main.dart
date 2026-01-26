import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 1. Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

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
  WakelockPlus.enable();

  // 4. Start Telemetry (Robust)
  final tabletService = TabletHeartbeatService();
  await tabletService.initialize();
  
  // 5. Check for updates on startup
  // await tabletService.checkForUpdates(); // Temporarily disabled if method missing, or ensure it exists

  runApp(const ProviderScope(child: AdscreenApp()));
}


class AdscreenApp extends StatelessWidget {
  const AdscreenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Adscreen Kiosk',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const KioskScreen(),
    );
  }
}
