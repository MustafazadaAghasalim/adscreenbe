import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/server_config.dart';
import 'device_settings_service.dart';
import 'tablet_service.dart';

class RemoteConfigService {
  static late SharedPreferences _prefs;
  static bool _initialized = false;
  static Timer? _pollTimer;
  static final _configController = StreamController<Map<String, dynamic>>.broadcast();

  static const String _prefsKey = 'backend_remote_config_json';

  // Legacy getters retained for compatibility
  static const String _themeMode = 'theme_mode';
  static const String _kioskEnabled = 'kiosk_enabled';
  static const String _updateInterval = 'update_interval_seconds';
  static const String _navBarHeight = 'nav_bar_height';
  static const String _autoRestart = 'auto_restart_enabled';
  static const String _debugMode = 'debug_mode';

  static const Duration _pollInterval = Duration(minutes: 15);

  static Map<String, dynamic> _currentConfig = {
    'version': 1,
    'pollIntervalSeconds': 900,
    'theme_mode': 'dark',
    'kiosk_enabled': true,
    'update_interval_seconds': 300,
    'nav_bar_height': 120,
    'auto_restart_enabled': true,
    'debug_mode': false,
    'ads': {
      'rotationMultiplier': 1.0,
      'minDurationSeconds': 5,
      'maxDurationSeconds': 120,
    },
    'navbar': {}
  };

  static Stream<Map<String, dynamic>> get configStream => _configController.stream;

  static Future<void> initialize() async {
    if (_initialized) return;

    _prefs = await SharedPreferences.getInstance();
    _loadCachedConfig();

    // Initial fetch with fallback to cache if offline.
    await refreshConfig();

    // Poll every 15 minutes in taxi environment.
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) async {
      await refreshConfig();
    });

    _initialized = true;
  }

  static void _loadCachedConfig() {
    try {
      final cached = _prefs.getString(_prefsKey);
      if (cached == null) return;

      final parsed = jsonDecode(cached);
      if (parsed is Map<String, dynamic>) {
        _currentConfig = {
          ..._currentConfig,
          ...parsed,
        };
      }
    } catch (e) {
      debugPrint('RemoteConfig cache load failed: $e');
    }
  }

  static Future<void> _applyConfig() async {
    await _prefs.setString(_prefsKey, jsonEncode(_currentConfig));

    final navbar = _currentConfig['navbar'];
    if (navbar is Map<String, dynamic> && navbar.isNotEmpty) {
      // Reuse existing device settings stream to update bottom bar instantly.
      try {
        await DeviceSettingsService().applySettings(navbar);
      } catch (e) {
        debugPrint('RemoteConfig navbar apply skipped: $e');
      }
    }

    if (!_configController.isClosed) {
      _configController.add(Map<String, dynamic>.from(_currentConfig));
    }
  }

  // Getters with fallback to local storage
  static String getThemeMode() {
    return _read(_themeMode, 'dark');
  }

  static bool isKioskEnabled() {
    return _read(_kioskEnabled, true);
  }

  static int getUpdateInterval() {
    return _read(_updateInterval, 300);
  }

  static int getNavBarHeight() {
    return _read(_navBarHeight, 120);
  }

  static bool isAutoRestartEnabled() {
    return _read(_autoRestart, true);
  }

  static bool isDebugMode() {
    return _read(_debugMode, false);
  }

  static double getAdRotationMultiplier() {
    final ads = _currentConfig['ads'];
    if (ads is! Map<String, dynamic>) return 1.0;
    final value = ads['rotationMultiplier'];
    if (value is num) return value.toDouble().clamp(0.5, 3.0);
    return 1.0;
  }

  static int getMinAdDurationSeconds() {
    final ads = _currentConfig['ads'];
    if (ads is! Map<String, dynamic>) return 5;
    final value = ads['minDurationSeconds'];
    if (value is num) return value.toInt().clamp(3, 30);
    return 5;
  }

  static int getMaxAdDurationSeconds() {
    final ads = _currentConfig['ads'];
    if (ads is! Map<String, dynamic>) return 120;
    final value = ads['maxDurationSeconds'];
    if (value is num) return value.toInt().clamp(20, 600);
    return 120;
  }

  static T _read<T>(String key, T defaultValue) {
    final value = _currentConfig[key];
    if (value is T) return value;
    if (defaultValue is int && value is num) return value.toInt() as T;
    if (defaultValue is double && value is num) return value.toDouble() as T;
    if (defaultValue is bool && value is String) {
      return (value.toLowerCase() == 'true') as T;
    }
    return defaultValue;
  }

  // Force refresh config with bounded retry backoff.
  static Future<void> refreshConfig() async {
    final tabletId = TabletService().tabletId ?? 'unknown';
    final uri = Uri.parse('${ServerConfig.baseUrl}/api/tablet/config/$tabletId');

    var delay = const Duration(seconds: 2);
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        final response = await http
            .get(uri, headers: {'accept': 'application/json'})
            .timeout(const Duration(seconds: 8));

        if (response.statusCode >= 200 && response.statusCode < 300) {
          final parsed = jsonDecode(response.body);
          if (parsed is Map<String, dynamic>) {
            _currentConfig = {
              ..._currentConfig,
              ...parsed,
            };
            await _applyConfig();
            return;
          }
        }
      } catch (e) {
        debugPrint('RemoteConfig fetch attempt $attempt failed: $e');
      }

      if (attempt < 3) {
        await Future.delayed(delay);
        delay *= 2;
      }
    }

    // Keep running from cached config when network is down.
    try {
      final cached = _prefs.getString(_prefsKey);
      if (cached != null) {
        final parsed = jsonDecode(cached);
        if (parsed is Map<String, dynamic>) {
          _currentConfig = {
            ..._currentConfig,
            ...parsed,
          };
        }
      }
    } catch (e) {
      debugPrint('RemoteConfig cache fallback failed: $e');
    }
    await _applyConfig();
  }
}