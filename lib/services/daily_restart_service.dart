import 'dart:async';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';

/// Daily Hot-Restart Service.
/// Schedules a full app state reset at 4:00 AM local time
/// to prevent memory drift, stale caches, and ensure
/// fresh state for kiosk devices running 24/7.
class DailyHotRestartService {
  static final DailyHotRestartService _instance = DailyHotRestartService._internal();
  factory DailyHotRestartService() => _instance;
  DailyHotRestartService._internal();

  Timer? _schedulerTimer;
  int _restartHour = 4; // 4:00 AM
  int _restartMinute = 0;

  /// Callbacks to run before restart (flush logs, save state, etc.)
  final List<Future<void> Function()> _preRestartCallbacks = [];

  void start({int hour = 4, int minute = 0}) {
    _restartHour = hour;
    _restartMinute = minute;

    _scheduleNext();
    print("DailyRestart: Scheduled daily restart at ${_restartHour.toString().padLeft(2, '0')}:${_restartMinute.toString().padLeft(2, '0')}");
  }

  /// Register a callback to run before the restart.
  void registerPreRestart(Future<void> Function() callback) {
    _preRestartCallbacks.add(callback);
  }

  void _scheduleNext() {
    _schedulerTimer?.cancel();

    final now = DateTime.now();
    var nextRestart = DateTime(
      now.year,
      now.month,
      now.day,
      _restartHour,
      _restartMinute,
    );

    // If we've already passed today's restart time, schedule for tomorrow
    if (nextRestart.isBefore(now)) {
      nextRestart = nextRestart.add(const Duration(days: 1));
    }

    final delay = nextRestart.difference(now);
    print("DailyRestart: Next restart in ${delay.inHours}h ${delay.inMinutes % 60}m");

    _schedulerTimer = Timer(delay, _performRestart);
  }

  Future<void> _performRestart() async {
    print("DailyRestart: === INITIATING 4AM HOT RESTART ===");

    // Run pre-restart callbacks
    for (final callback in _preRestartCallbacks) {
      try {
        await callback();
      } catch (e) {
        print("DailyRestart: Pre-restart callback error — $e");
      }
    }

    // Clear image cache
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();

    // Attempt SystemNavigator to restart app
    try {
      // On Android with device owner, we can use the alarm manager
      // or simply restart the activity
      const channel = MethodChannel('com.example.adscreen/restart');
      await channel.invokeMethod('restartApp');
    } catch (e) {
      print("DailyRestart: Platform restart failed, using SystemNavigator — $e");
      // Fallback: pop to root and request fresh activity
      SystemNavigator.pop();
    }

    // If still alive, schedule next
    _scheduleNext();
  }

  /// Get next scheduled restart time.
  DateTime getNextRestartTime() {
    final now = DateTime.now();
    var next = DateTime(now.year, now.month, now.day, _restartHour, _restartMinute);
    if (next.isBefore(now)) {
      next = next.add(const Duration(days: 1));
    }
    return next;
  }

  void stop() {
    _schedulerTimer?.cancel();
    _preRestartCallbacks.clear();
  }
}
