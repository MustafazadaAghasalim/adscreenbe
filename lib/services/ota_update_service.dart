import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ota_update/ota_update.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:restart_app/restart_app.dart';
import '../config/server_config.dart';
import 'silent_update_service.dart';

/// OTAUpdateService — Production-grade silent OTA auto-updater.
///
/// Flow:
///   1. Periodic timer pings /api/tablet/check-update every 30 min
///   2. If update available, downloads APK in background
///   3. If DeviceOwner → silent install via MethodChannel (no prompt)
///   4. Fallback → standard ota_update package install
class OTAUpdateService {
  static const String _updateCheckUrl =
      '${ServerConfig.baseUrl}/api/tablet/check-update';

  static Timer? _pollTimer;
  static bool _isUpdating = false;

  /// Start the periodic OTA polling loop.
  /// Call once from main.dart after services are initialized.
  static void startPolling(String tabletId, {Duration interval = const Duration(minutes: 30)}) {
    // Immediate first check
    _checkAndUpdate(tabletId);

    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(interval, (_) {
      _checkAndUpdate(tabletId);
    });
    debugPrint('[OTA] Polling started (every ${interval.inMinutes} min)');
  }

  static void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// Check the Pi backend for available updates.
  static Future<bool> _checkAndUpdate(String tabletId) async {
    if (_isUpdating) {
      debugPrint('[OTA] Update already in progress, skipping check');
      return false;
    }

    try {
      debugPrint('[OTA] Checking for updates...');
      final response = await http.get(
        Uri.parse('$_updateCheckUrl?tablet_id=$tabletId'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['update_available'] == true) {
          final downloadUrl = data['download_url'] as String?;
          final version = data['version'] as String? ?? 'unknown';
          final versionCode = (data['version_code'] as num?)?.toInt() ?? 0;
          final sha256 = data['sha256'] as String?;

          if (downloadUrl == null || downloadUrl.isEmpty) {
            debugPrint('[OTA] Update available but no download_url');
            return false;
          }

          debugPrint('[OTA] Update available: v$version (code: $versionCode)');
          await _installUpdate(
            downloadUrl: downloadUrl,
            version: version,
            versionCode: versionCode,
            sha256: sha256,
          );
          return true;
        } else {
          debugPrint('[OTA] No update available');
        }
      } else {
        debugPrint('[OTA] Server returned ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[OTA] Check failed: $e');
    }
    return false;
  }

  /// One-shot check (called manually or from remote command).
  static Future<bool> checkForUpdates(String tabletId) async {
    return await _checkAndUpdate(tabletId);
  }

  /// Install the update — try silent first, fallback to standard.
  static Future<void> _installUpdate({
    required String downloadUrl,
    required String version,
    int versionCode = 0,
    String? sha256,
  }) async {
    _isUpdating = true;

    try {
      // === STRATEGY 1: Silent install via DeviceOwner MethodChannel ===
      final silentUpdater = SilentUpdateService();
      try {
        final versionInfo = await silentUpdater.getVersionInfo();
        final currentCode = (versionInfo['versionCode'] as num?)?.toInt() ?? 0;

        if (versionCode > 0 && versionCode <= currentCode) {
          debugPrint('[OTA] Already on v$currentCode, server offers v$versionCode — skipping');
          _isUpdating = false;
          return;
        }

        debugPrint('[OTA] Attempting silent install (DeviceOwner)...');
        final success = await silentUpdater.installUpdate(
          url: downloadUrl,
          expectedVersionCode: versionCode,
          sha256: sha256,
          force: false,
        );

        if (success) {
          debugPrint('[OTA] ✅ Silent install succeeded! App will restart.');
          _isUpdating = false;
          return;
        }
        debugPrint('[OTA] Silent install returned false, trying fallback...');
      } catch (e) {
        debugPrint('[OTA] Silent install error: $e — trying fallback...');
      }

      // === STRATEGY 2: ota_update package (shows system install prompt) ===
      try {
        debugPrint('[OTA] Using ota_update package...');
        await _otaPackageInstall(downloadUrl, version);
        return;
      } catch (e) {
        debugPrint('[OTA] ota_update failed: $e — trying manual download...');
      }

      // === STRATEGY 3: Manual download + intent ===
      await _manualDownloadAndInstall(downloadUrl);
    } finally {
      _isUpdating = false;
    }
  }

  /// Standard OTA update via ota_update package.
  static Future<void> _otaPackageInstall(String url, String version) async {
    final completer = Completer<void>();

    OtaUpdate().execute(
      url,
      destinationFilename: 'adscreen_update_$version.apk',
    ).listen(
      (OtaEvent event) {
        switch (event.status) {
          case OtaStatus.DOWNLOADING:
            debugPrint('[OTA] Download: ${event.value}%');
            break;
          case OtaStatus.INSTALLING:
            debugPrint('[OTA] Installing...');
            if (!completer.isCompleted) completer.complete();
            break;
          case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
            debugPrint('[OTA] Permission denied');
            if (!completer.isCompleted) {
              completer.completeError('Permission not granted');
            }
            break;
          case OtaStatus.INTERNAL_ERROR:
            debugPrint('[OTA] Internal error: ${event.value}');
            if (!completer.isCompleted) {
              completer.completeError(event.value ?? 'Unknown error');
            }
            break;
          default:
            break;
        }
      },
      onError: (e) {
        if (!completer.isCompleted) completer.completeError(e);
      },
    );

    await completer.future;
  }

  /// Fallback: Download APK manually and open with package installer intent.
  static Future<void> _manualDownloadAndInstall(String downloadUrl) async {
    try {
      debugPrint('[OTA] Manual download from: $downloadUrl');
      final response = await http.get(Uri.parse(downloadUrl))
          .timeout(const Duration(minutes: 10));

      if (response.statusCode == 200) {
        final directory = await getExternalStorageDirectory();
        final file = File('${directory!.path}/adscreen_update.apk');
        await file.writeAsBytes(response.bodyBytes);
        debugPrint('[OTA] APK saved to ${file.path}');

        final uri = Uri.file(file.path);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri);
        }
      } else {
        debugPrint('[OTA] Download failed: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[OTA] Manual install failed: $e');
    }
  }

  /// Handle remote commands dispatched from the dashboard.
  static Future<void> handleRemoteCommand(Map<String, dynamic> command) async {
    final action = command['action'];
    final params = command['params'] ?? {};

    debugPrint('[OTA] Remote command: $action');

    switch (action) {
      case 'restart_app':
        await Future.delayed(const Duration(seconds: 2));
        Restart.restartApp();
        break;

      case 'force_update_check':
        final tabletId = params['tablet_id'];
        if (tabletId != null) {
          await checkForUpdates(tabletId);
        }
        break;

      case 'install_apk':
        final downloadUrl = params['download_url'];
        final version = params['version'] ?? 'unknown';
        final versionCode = (params['version_code'] as num?)?.toInt() ?? 0;
        if (downloadUrl != null) {
          await _installUpdate(
            downloadUrl: downloadUrl,
            version: version,
            versionCode: versionCode,
          );
        }
        break;

      case 'clear_cache':
        await _clearAppCache();
        break;

      default:
        debugPrint('[OTA] Unknown command: $action');
    }
  }

  static Future<void> _clearAppCache() async {
    try {
      final tempDir = await getTemporaryDirectory();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
      debugPrint('[OTA] App cache cleared');
    } catch (e) {
      debugPrint('[OTA] Cache clear failed: $e');
    }
  }
}