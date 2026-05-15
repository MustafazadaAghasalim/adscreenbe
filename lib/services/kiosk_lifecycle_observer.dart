import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kiosk_mode/kiosk_mode.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// App Lifecycle Observer for Kiosk Lockdown.
/// Detects when the system pauses the app and forces it back to resumed state.
/// Ensures the kiosk app is ALWAYS visible during a 12-hour shift.
class KioskLifecycleObserver extends WidgetsBindingObserver {
  static final KioskLifecycleObserver _instance = KioskLifecycleObserver._internal();
  factory KioskLifecycleObserver() => _instance;
  KioskLifecycleObserver._internal();

  /// When true, the lifecycle observer skips its force-resume behaviour so an
  /// admin can leave the kiosk app (settings, system UI, etc.) without being
  /// snapped back. Set to `true` from the admin unlock flow and reset to
  /// `false` when re-entering kiosk mode.
  static bool isAdminUnlocked = false;

  bool _isRegistered = false;
  int _pauseCount = 0;
  DateTime? _lastPaused;

  void register() {
    if (_isRegistered) return;
    WidgetsBinding.instance.addObserver(this);
    _isRegistered = true;
    print("KioskLifecycle: Observer registered.");
  }

  void unregister() {
    WidgetsBinding.instance.removeObserver(this);
    _isRegistered = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    print("KioskLifecycle: State changed to $state");

    switch (state) {
      case AppLifecycleState.paused:
        _pauseCount++;
        _lastPaused = DateTime.now();
        print("KioskLifecycle: App PAUSED (count: $_pauseCount). Forcing resume...");
        _forceResume();
        break;

      case AppLifecycleState.resumed:
        print("KioskLifecycle: App RESUMED.");
        _ensureKioskState();
        break;

      case AppLifecycleState.inactive:
        print("KioskLifecycle: App INACTIVE. Monitoring...");
        // Short grace period, then force resume
        Future.delayed(const Duration(seconds: 2), () {
          if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
            _forceResume();
          }
        });
        break;

      case AppLifecycleState.detached:
        print("KioskLifecycle: App DETACHED. Critical — attempting recovery.");
        _forceResume();
        break;

      case AppLifecycleState.hidden:
        print("KioskLifecycle: App HIDDEN. Forcing back...");
        _forceResume();
        break;
    }
  }

  @override
  void didChangeMetrics() {
    // Screen rotation or size change — re-lock to landscape
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky, overlays: []);
  }

  /// Force the app back to foreground + kiosk state.
  void _forceResume() async {
    try {
      // Re-enter immersive sticky
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky, overlays: []);

      // Re-enable kiosk mode
      await startKioskMode();

      // Re-enable wakelock
      await WakelockPlus.enable();

      // Use platform channel to bring app to front
      const platform = MethodChannel('com.adscreen.kiosk/telemetry');
      try {
        await platform.invokeMethod('bringToFront');
      } catch (_) {
        // Fallback: use startKiosk
        try {
          await platform.invokeMethod('startKiosk');
        } catch (_) {}
      }

      print("KioskLifecycle: Force resume executed.");
    } catch (e) {
      print("KioskLifecycle: Error forcing resume: $e");
    }
  }

  /// Ensure all kiosk lockdown features are active.
  void _ensureKioskState() async {
    try {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky, overlays: []);
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      await WakelockPlus.enable();
    } catch (e) {
      print("KioskLifecycle: Error ensuring kiosk state: $e");
    }
  }

  int get pauseCount => _pauseCount;
  DateTime? get lastPaused => _lastPaused;
}
