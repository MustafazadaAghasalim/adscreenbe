import 'dart:async';
import 'dart:io' show ProcessInfo;
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';

/// Memory Leak Guardian.
/// Periodically monitors app memory usage and triggers
/// GC hints / cache purging when approaching limits.
/// Prevents OOM crashes on kiosk tablets running 24/7.
class MemoryLeakGuardian {
  static final MemoryLeakGuardian _instance = MemoryLeakGuardian._internal();
  factory MemoryLeakGuardian() => _instance;
  MemoryLeakGuardian._internal();

  Timer? _monitorTimer;
  int _warningCount = 0;

  /// Memory warning threshold (MB)
  static const int warningThresholdMB = 300;

  /// Critical threshold triggers aggressive cleanup (MB)
  static const int criticalThresholdMB = 450;

  /// Check interval
  static const Duration checkInterval = Duration(minutes: 2);

  /// Callbacks for memory pressure
  final List<Future<void> Function()> _cleanupCallbacks = [];

  void start() {
    _monitorTimer = Timer.periodic(checkInterval, (_) => _checkMemory());
    print("MemoryGuardian: Started monitoring every ${checkInterval.inMinutes} min.");
  }

  /// Register a cleanup callback that will be called on memory pressure.
  void registerCleanup(Future<void> Function() callback) {
    _cleanupCallbacks.add(callback);
  }

  Future<void> _checkMemory() async {
    try {
      // Use ProcessInfo to get memory info on Android
      final memInfo = await _getMemoryInfo();
      final usedMB = memInfo['usedMB'] ?? 0;

      if (usedMB >= criticalThresholdMB) {
        print("MemoryGuardian: CRITICAL — ${usedMB}MB used. Aggressive cleanup...");
        _warningCount++;
        await _aggressiveCleanup();
      } else if (usedMB >= warningThresholdMB) {
        print("MemoryGuardian: WARNING — ${usedMB}MB used. Light cleanup...");
        _warningCount++;
        await _lightCleanup();
      } else {
        if (_warningCount > 0) {
          print("MemoryGuardian: Memory OK — ${usedMB}MB used. Warnings reset.");
          _warningCount = 0;
        }
      }

      // If too many warnings, suggest hot restart
      if (_warningCount >= 5) {
        print("MemoryGuardian: Too many warnings. Recommending hot restart.");
        _warningCount = 0;
      }
    } catch (e) {
      print("MemoryGuardian: Check failed — $e");
    }
  }

  Future<Map<String, int>> _getMemoryInfo() async {
    try {
      // Attempt to use platform channel for accurate info
      const channel = MethodChannel('com.example.adscreen/memory');
      final result = await channel.invokeMethod<Map>('getMemoryInfo');
      if (result != null) {
        return {
          'usedMB': (result['usedMB'] as num?)?.toInt() ?? 0,
          'totalMB': (result['totalMB'] as num?)?.toInt() ?? 0,
        };
      }
    } catch (_) {
      // Platform channel not available, use dart estimate
    }

    // Fallback: use Dart VM info
    final info = ProcessInfo.currentRss;
    return {
      'usedMB': info ~/ (1024 * 1024),
      'totalMB': 0, // Unknown without platform channel
    };
  }

  Future<void> _lightCleanup() async {
    // Clear image cache
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    print("MemoryGuardian: Cleared image cache.");
  }

  Future<void> _aggressiveCleanup() async {
    // Clear image cache
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();

    // Reduce image cache size limits temporarily
    PaintingBinding.instance.imageCache.maximumSize = 50;
    PaintingBinding.instance.imageCache.maximumSizeBytes = 20 * 1024 * 1024;

    // Run registered cleanup callbacks
    for (final callback in _cleanupCallbacks) {
      try {
        await callback();
      } catch (e) {
        print("MemoryGuardian: Cleanup callback error — $e");
      }
    }

    // Restore cache limits after GC pressure
    Future.delayed(const Duration(seconds: 30), () {
      PaintingBinding.instance.imageCache.maximumSize = 100;
      PaintingBinding.instance.imageCache.maximumSizeBytes = 50 * 1024 * 1024;
    });

    print("MemoryGuardian: Aggressive cleanup complete.");
  }

  Map<String, dynamic> getStatus() {
    return {
      'warningCount': _warningCount,
      'warningThresholdMB': warningThresholdMB,
      'criticalThresholdMB': criticalThresholdMB,
      'checkIntervalMin': checkInterval.inMinutes,
      'registeredCleanups': _cleanupCallbacks.length,
    };
  }

  void stop() {
    _monitorTimer?.cancel();
    _cleanupCallbacks.clear();
  }
}
