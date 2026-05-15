import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:http/http.dart' as http;
import '../config/server_config.dart';

/// DeviceSettingsService — Manages the 50 advanced device/kiosk settings.
///
/// Responsibilities:
/// 1. Persists settings to SharedPreferences for offline access
/// 2. Applies hardware-level settings via MethodChannel (volume, brightness, rotation, USB)
/// 3. Exposes a Stream for UI widgets that need to react to changes
/// 4. Fetches initial settings from server on startup
///
/// Settings arrive via:
/// - AdminCommandService WebSocket: type 'device_settings_updated'
/// - Direct call to applySettings() from AdminCommandService handler
class DeviceSettingsService {
  static final DeviceSettingsService _instance = DeviceSettingsService._internal();
  factory DeviceSettingsService() => _instance;
  DeviceSettingsService._internal();

  static const String _prefsKey = 'device_settings_json';
  static const MethodChannel _settingsChannel =
      MethodChannel('com.adscreen.kiosk/settings');

  late SharedPreferences _prefs;
  Map<String, dynamic> _currentSettings = {};
  bool _isInitialized = false;

  final _settingsController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get settingsStream => _settingsController.stream;

  Map<String, dynamic> get currentSettings => Map.unmodifiable(_currentSettings);

  // ─── Default values for all 50 settings ─────────────────────────
  static const Map<String, dynamic> _defaults = {
    // Display & UI
    'navbarThemeColor': '#1A1A1A',
    'navbarButtons': [
      {'id': 'btn-1', 'label': 'Interactivity', 'actionId': 'interactivity'},
      {'id': 'btn-2', 'label': 'Surveys', 'actionId': 'surveys'},
      {'id': 'btn-3', 'label': 'Games', 'actionId': 'games'}
    ],
    'navbarTextColor': '#FFFFFF',
    'navbarQrUrl': 'https://adscreen.be',
    'navbarWebsiteText': 'adscreen.be',
    'navbarPhoneText': '+32 2 123 45 67',
    'navbarTimerTextColor': '#FFFFFF',
    'navbarTimerBorderColor': '#7C3AED',
    'navbarTimerStrokeWidth': 5,
    'navbarShowAdscreenLogo': true,
    'navbarShowMastercardLogo': true,
    'navbarShowVisaLogo': false,
    'screenDimScheduleEnabled': false,
    'screenDimStart': '22:00',
    'screenDimEnd': '06:00',
    'screenDimBrightness': 20,
    'rotationLock': 'landscape',
    'screensaverTimeout': 0,
    'overlayOpacity': 100,
    'fontScale': 100,
    'contentTransitionEffect': 'fade',
    'screenBurnInPrevention': true,
    // Audio
    'maxVolumeLimit': 80,
    'muteScheduleEnabled': false,
    'muteScheduleStart': '23:00',
    'muteScheduleEnd': '07:00',
    'startupSoundEnabled': true,
    'audioDuckingEnabled': true,
    'audioOutputDevice': 'speaker',
    // Network & Connectivity
    'wsHeartbeatInterval': 15,
    'bandwidthLimitMbps': 0,
    'offlineFallbackMode': 'lastContent',
    'vpnEnabled': false,
    'proxyHost': '',
    'proxyPort': 8080,
    'dnsOverride': '',
    'connectionRetryCount': 5,
    'ntpServer': 'pool.ntp.org',
    // Security & Lockdown
    'usbPortBlock': false,
    'cameraDisabled': false,
    'screenshotBlock': false,
    'appWhitelist': '',
    'autoLockTimeout': 0,
    'pinComplexity': '4digit',
    'failedAttemptsBeforeWipe': 10,
    'tamperDetection': true,
    // Media Playback & Caching
    'cacheSizeLimitMB': 500,
    'prefetchCount': 5,
    'videoQuality': 'auto',
    'loopGapInterval': 0,
    'fallbackMediaUrl': '',
    'contentExpiryHours': 72,
    'autoCleanupEnabled': true,
    'priorityMediaEnabled': false,
    'mediaTransitionDuration': 500,
    // Hardware & Maintenance
    'autoRebootDay': 'daily',
    'watchdogInterval': 30,
    'storageWarningThreshold': 90,
    'cpuThrottleTemp': 70,
    'fanControlMode': 'auto',
    'ledIndicatorEnabled': true,
    'peripheralScanInterval': 60,
  };

  /// Initialize the service. Load saved settings from SharedPreferences,
  /// then try to fetch latest from server.
  Future<void> initialize() async {
    if (_isInitialized) return;

    _prefs = await SharedPreferences.getInstance();

    // 1. Load from local storage (offline-first)
    final savedJson = _prefs.getString(_prefsKey);
    if (savedJson != null) {
      try {
        _currentSettings = Map<String, dynamic>.from(jsonDecode(savedJson));
        debugPrint('[DeviceSettings] Loaded ${_currentSettings.length} settings from local storage');
      } catch (e) {
        debugPrint('[DeviceSettings] Error parsing saved settings: $e');
        _currentSettings = Map<String, dynamic>.from(_defaults);
      }
    } else {
      _currentSettings = Map<String, dynamic>.from(_defaults);
      debugPrint('[DeviceSettings] Using default settings (first launch)');
    }

    // 2. Apply all current settings immediately
    await _applyAllSettings();

    _isInitialized = true;
    debugPrint('[DeviceSettings] Service initialized with ${_currentSettings.length} settings');

    // 3. Try to fetch latest from server (non-blocking)
    fetchFromServer();
  }

  /// Fetch latest settings from the server REST API.
  Future<void> fetchFromServer() async {
    if (!_isInitialized) {
      debugPrint('[DeviceSettings] fetchFromServer called before initialize() — skipping');
      return;
    }
    try {
      final uri = Uri.parse('${ServerConfig.baseUrl}/api/admin/get_device_settings');
      final response = await http.get(uri);
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        await applySettings(data);
        debugPrint('[DeviceSettings] Fetched latest settings from server upon connection');
      } else {
        debugPrint('[DeviceSettings] Failed to fetch settings: status ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[DeviceSettings] Server fetch error (using local): $e');
    }
  }

  /// Called by AdminCommandService when a 'device_settings_updated' message arrives.
  Future<void> applySettings(Map<String, dynamic> incoming) async {
    if (!_isInitialized) {
      debugPrint('[DeviceSettings] applySettings called before initialize() — skipping');
      return;
    }
    debugPrint('[DeviceSettings] Received ${incoming.length} settings via WebSocket/REST');

    // Remove server metadata / envelope keys
    final sanitized = Map<String, dynamic>.from(incoming);
    sanitized.remove('updated_at');
    sanitized.remove('type');
    sanitized.remove('timestamp');

    // Normalize types based on defaults (handles "50" vs 50, "true" vs true, etc.)
    final normalizedIncoming = _normalizeIncoming(sanitized);

    // Merge incoming with defaults and current (incoming takes precedence)
    final merged = <String, dynamic>{
      ..._defaults,
      ..._currentSettings,
      ...normalizedIncoming,
    };

    _currentSettings = merged;

    // Persist to local storage
    await _prefs.setString(_prefsKey, jsonEncode(_currentSettings));

    // Apply hardware-level settings
    await _applyAllSettings();

    // Notify listeners (UI widgets)
    _settingsController.add(Map.unmodifiable(_currentSettings));

    debugPrint('[DeviceSettings] All settings applied and persisted (${_currentSettings.length} keys)');
  }

  /// Apply all settings that require native platform interaction.
  Future<void> _applyAllSettings() async {
    await _applyVolume();
    await _applyBrightness();
    await _applyRotationLock();
    await _applyUsbBlock();
    await _applyScreenTimeout();
  }

  // ─── Native Platform Interactions (MethodChannel) ───────────────

  /// Set maximum system volume (0.0 – 1.0)
  Future<void> _applyVolume() async {
    try {
      final maxVolume = (_get<int>('maxVolumeLimit', 80)) / 100.0;
      VolumeController().setVolume(maxVolume, showSystemUI: false);
      debugPrint('[DeviceSettings] Volume set to ${(maxVolume * 100).round()}%');
    } catch (e) {
      debugPrint('[DeviceSettings] Volume control error: $e');
    }
  }

  /// Set screen brightness via MethodChannel
  Future<void> _applyBrightness() async {
    try {
      final brightness = _get<int>('screenDimBrightness', 20) / 100.0;
      final dimEnabled = _get<bool>('screenDimScheduleEnabled', false);
      if (dimEnabled) {
        await _settingsChannel.invokeMethod('setBrightness', {'value': brightness});
        debugPrint('[DeviceSettings] Brightness set to ${(brightness * 100).round()}% (dim mode)');
      }
    } catch (e) {
      debugPrint('[DeviceSettings] Brightness error: $e');
    }
  }

  /// Lock screen rotation via MethodChannel
  Future<void> _applyRotationLock() async {
    try {
      final rotation = _get<String>('rotationLock', 'landscape');
      await _settingsChannel.invokeMethod('setRotationLock', {'mode': rotation});
      debugPrint('[DeviceSettings] Rotation locked to: $rotation');
    } catch (e) {
      debugPrint('[DeviceSettings] Rotation lock error: $e');
    }
  }

  /// Block USB data transfer via MethodChannel (requires Device Owner)
  Future<void> _applyUsbBlock() async {
    try {
      final block = _get<bool>('usbPortBlock', false);
      await _settingsChannel.invokeMethod('setUsbDisabled', {'disabled': block});
      debugPrint('[DeviceSettings] USB block: $block');
    } catch (e) {
      debugPrint('[DeviceSettings] USB block error: $e');
    }
  }

  /// Set screen timeout via MethodChannel
  Future<void> _applyScreenTimeout() async {
    try {
      final timeout = _get<int>('screensaverTimeout', 0);
      await _settingsChannel.invokeMethod('setScreenTimeout', {'minutes': timeout});
      debugPrint('[DeviceSettings] Screen timeout: ${timeout}min');
    } catch (e) {
      debugPrint('[DeviceSettings] Screen timeout error: $e');
    }
  }

  // ─── Getter helpers ─────────────────────────────────────────────

  /// Type-safe getter with default fallback
  T _get<T>(String key, T defaultValue) {
    final value = _currentSettings[key];
    if (value == null) return defaultValue;
    if (value is T) return value;

    try {
      if (T == int) {
        return _coerceToInt(value, defaultValue is int ? defaultValue : 0) as T;
      }
      if (T == double) {
        return _coerceToDouble(value, defaultValue is double ? defaultValue : 0.0)
            as T;
      }
      if (T == bool) {
        return _coerceToBool(value, defaultValue is bool ? defaultValue : false)
            as T;
      }
      if (T == String) {
        return value.toString() as T;
      }
    } catch (e) {
      debugPrint(
          '[DeviceSettings] _get<$T> parse error for $key: $e (value=$value)');
    }

    return defaultValue;
  }

  /// Public getter for any setting key
  T getSetting<T>(String key, T defaultValue) => _get<T>(key, defaultValue);

  /// Check if a setting is enabled (for toggle types)
  bool isEnabled(String key) => _get<bool>(key, false);

  // ─── Normalization helpers for incoming JSON ────────────────────

  Map<String, dynamic> _normalizeIncoming(Map<String, dynamic> incoming) {
    final normalized = <String, dynamic>{};

    incoming.forEach((key, value) {
      if (_defaults.containsKey(key)) {
        final defaultVal = _defaults[key];
        if (defaultVal is int) {
          normalized[key] = _coerceToInt(value, defaultVal);
        } else if (defaultVal is double) {
          normalized[key] = _coerceToDouble(value, defaultVal);
        } else if (defaultVal is bool) {
          normalized[key] = _coerceToBool(value, defaultVal);
        } else if (defaultVal is String) {
          normalized[key] = (value ?? defaultVal).toString();
        } else {
          normalized[key] = value ?? defaultVal;
        }
      } else {
        // Unknown key, keep as-is but JSON-safe
        normalized[key] = value;
      }
    });

    return normalized;
  }

  int _coerceToInt(dynamic value, int fallback) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is double) return value.round();
    if (value is String) {
      final v = value.trim();
      final parsed = int.tryParse(v);
      if (parsed != null) return parsed;
      final asDouble = double.tryParse(v);
      if (asDouble != null) return asDouble.round();
    }
    return fallback;
  }

  double _coerceToDouble(dynamic value, double fallback) {
    if (value == null) return fallback;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) {
      final v = value.trim();
      final parsed = double.tryParse(v);
      if (parsed != null) return parsed;
    }
    return fallback;
  }

  bool _coerceToBool(dynamic value, bool fallback) {
    if (value == null) return fallback;
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final v = value.trim().toLowerCase();
      if (v == 'true' || v == 'yes' || v == '1' || v == 'on') return true;
      if (v == 'false' || v == 'no' || v == '0' || v == 'off') return false;
    }
    return fallback;
  }

  void dispose() {
    _settingsController.close();
  }
}
