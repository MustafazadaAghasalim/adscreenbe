import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

/// SilentUpdateService — Flutter-side bridge for silent APK updates.
///
/// Communicates with the native SilentInstaller via MethodChannel to:
///   - Check current app version
///   - Download and install APK updates silently (Device Owner only)
///   - Verify update integrity via SHA-256 checksums
///
/// USAGE:
///   final updater = SilentUpdateService();
///   final versionInfo = await updater.getVersionInfo();
///   await updater.installUpdate(
///     url: 'https://cdn.example.com/adscreen-v2.0.apk',
///     expectedVersionCode: 20,
///     sha256: 'abc123...',
///   );
class SilentUpdateService {
  static const _channel = MethodChannel('com.adscreen.kiosk/silent_install');

  static final SilentUpdateService _instance = SilentUpdateService._();
  factory SilentUpdateService() => _instance;
  SilentUpdateService._();

  /// Get the current installed app version info.
  Future<Map<String, dynamic>> getVersionInfo() async {
    try {
      final result = await _channel.invokeMethod<Map>('getVersionInfo');
      return Map<String, dynamic>.from(result ?? {});
    } catch (e) {
      debugPrint('[SilentUpdate] Version info error: $e');
      return {'versionName': 'unknown', 'versionCode': 0};
    }
  }

  /// Trigger a silent APK update.
  ///
  /// [url] — Direct download URL for the APK
  /// [expectedVersionCode] — Version code to verify (0 = skip check)
  /// [sha256] — SHA-256 hex digest for integrity verification (null = skip)
  /// [force] — If true, allows downgrade installs
  Future<bool> installUpdate({
    required String url,
    int expectedVersionCode = 0,
    String? sha256,
    bool force = false,
  }) async {
    try {
      debugPrint('[SilentUpdate] Starting update from: $url');
      final result = await _channel.invokeMethod<bool>('installApk', {
        'url': url,
        'versionCode': expectedVersionCode,
        'sha256': sha256,
        'force': force,
      });
      return result ?? false;
    } catch (e) {
      debugPrint('[SilentUpdate] Install error: $e');
      return false;
    }
  }

  /// Check if an update is available by comparing with server version.
  Future<bool> isUpdateAvailable({
    required int serverVersionCode,
  }) async {
    final info = await getVersionInfo();
    final currentVersion = (info['versionCode'] as num?)?.toInt() ?? 0;
    return serverVersionCode > currentVersion;
  }
}
