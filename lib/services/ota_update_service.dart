import 'dart:io';
import 'package:flutter/material.dart';
import 'package:ota_update/ota_update.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:restart_app/restart_app.dart';
import 'dart:convert';
import '../config/server_config.dart';

class OTAUpdateService {
  static const String _updateCheckUrl = '${ServerConfig.baseUrl}/api/check_update';
  
  static Future<bool> checkForUpdates(String tabletId) async {
    try {
      final response = await http.get(
        Uri.parse('$_updateCheckUrl?tablet_id=$tabletId'),
        headers: {'Content-Type': 'application/json'},
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['update_available'] == true) {
          final shouldUpdate = await _showUpdateDialog();
          if (shouldUpdate) {
            await downloadAndInstallUpdate(
              data['download_url'],
              data['version'],
            );
            return true;
          }
        }
      }
    } catch (e) {
      debugPrint('Update check failed: $e');
    }
    return false;
  }
  
  static Future<bool> _showUpdateDialog() async {
    // This would show a dialog in the app context
    // For kiosk mode, you might want to auto-update
    return true; // Auto-approve updates for kiosk
  }
  
  static Future<void> downloadAndInstallUpdate(String downloadUrl, String version) async {
    try {
      debugPrint('Starting OTA update to version $version');
      
      // Use OTA Update plugin
      OtaUpdate().execute(
        downloadUrl,
        destinationFilename: 'adscreen_update_$version.apk',
      ).listen((OtaEvent event) {
        debugPrint('OTA Update Event: ${event.status} - ${event.value}');
        
        switch (event.status) {
          case OtaStatus.DOWNLOADING:
            debugPrint('Download progress: ${event.value}%');
            break;
          case OtaStatus.INSTALLING:
            debugPrint('Installing update...');
            break;
          case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
            debugPrint('Permission error - manual install required');
            _fallbackInstall(downloadUrl);
            break;
          case OtaStatus.INTERNAL_ERROR:
            debugPrint('Update failed: ${event.value}');
            break;
          default:
            break;
        }
      });
    } catch (e) {
      debugPrint('OTA update error: $e');
      await _fallbackInstall(downloadUrl);
    }
  }
  
  static Future<void> _fallbackInstall(String downloadUrl) async {
    try {
      // Download APK manually and open with package installer
      final response = await http.get(Uri.parse(downloadUrl));
      if (response.statusCode == 200) {
        final directory = await getExternalStorageDirectory();
        final file = File('${directory!.path}/adscreen_update.apk');
        await file.writeAsBytes(response.bodyBytes);
        
        // Open APK file for installation
        final uri = Uri.file(file.path);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri);
        }
      }
    } catch (e) {
      debugPrint('Fallback install failed: $e');
    }
  }
  
  // Remote commands
  static Future<void> handleRemoteCommand(Map<String, dynamic> command) async {
    final action = command['action'];
    final params = command['params'] ?? {};
    
    debugPrint('Executing remote command: $action');
    
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
        if (downloadUrl != null) {
          await downloadAndInstallUpdate(downloadUrl, version);
        }
        break;
        
      case 'clear_cache':
        await _clearAppCache();
        break;
        
      default:
        debugPrint('Unknown remote command: $action');
    }
  }
  
  static Future<void> _clearAppCache() async {
    try {
      final tempDir = await getTemporaryDirectory();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
      debugPrint('App cache cleared');
    } catch (e) {
      debugPrint('Cache clear failed: $e');
    }
  }
}