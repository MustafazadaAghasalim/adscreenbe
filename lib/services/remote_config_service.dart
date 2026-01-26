import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class RemoteConfigService {
  static final FirebaseRemoteConfig _remoteConfig = FirebaseRemoteConfig.instance;
  static late SharedPreferences _prefs;
  
  // Configuration keys
  static const String _themeMode = 'theme_mode';
  static const String _kioskEnabled = 'kiosk_enabled';
  static const String _updateInterval = 'update_interval_seconds';
  static const String _navBarHeight = 'nav_bar_height';
  static const String _autoRestart = 'auto_restart_enabled';
  static const String _debugMode = 'debug_mode';
  
  static Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
    
    // Set default values
    await _remoteConfig.setDefaults({
      _themeMode: 'dark',
      _kioskEnabled: true,
      _updateInterval: 300,
      _navBarHeight: 120,
      _autoRestart: true,
      _debugMode: false,
    });
    
    // Configure settings
    await _remoteConfig.setConfigSettings(RemoteConfigSettings(
      fetchTimeout: const Duration(seconds: 10),
      minimumFetchInterval: const Duration(seconds: 60),
    ));
    
    // Initial fetch
    try {
      await _remoteConfig.fetchAndActivate();
      await _applyConfig();
    } catch (e) {
      debugPrint('RemoteConfig initial fetch failed: $e');
    }
    
    // Listen for real-time updates
    _remoteConfig.onConfigUpdated.listen((event) async {
      await _remoteConfig.activate();
      await _applyConfig();
      debugPrint('RemoteConfig updated and applied');
    });
  }
  
  static Future<void> _applyConfig() async {
    // Save current config to local storage for offline access
    final configMap = {
      _themeMode: _remoteConfig.getString(_themeMode),
      _kioskEnabled: _remoteConfig.getBool(_kioskEnabled),
      _updateInterval: _remoteConfig.getInt(_updateInterval),
      _navBarHeight: _remoteConfig.getInt(_navBarHeight),
      _autoRestart: _remoteConfig.getBool(_autoRestart),
      _debugMode: _remoteConfig.getBool(_debugMode),
    };
    
    await _prefs.setString('remote_config', jsonEncode(configMap));
    
    // Apply configurations immediately
    // You can add custom logic here to restart services, update UI, etc.
  }
  
  // Getters with fallback to local storage
  static String getThemeMode() {
    try {
      return _remoteConfig.getString(_themeMode);
    } catch (e) {
      return _getLocalConfig(_themeMode, 'dark');
    }
  }
  
  static bool isKioskEnabled() {
    try {
      return _remoteConfig.getBool(_kioskEnabled);
    } catch (e) {
      return _getLocalConfig(_kioskEnabled, true);
    }
  }
  
  static int getUpdateInterval() {
    try {
      return _remoteConfig.getInt(_updateInterval);
    } catch (e) {
      return _getLocalConfig(_updateInterval, 300);
    }
  }
  
  static int getNavBarHeight() {
    try {
      return _remoteConfig.getInt(_navBarHeight);
    } catch (e) {
      return _getLocalConfig(_navBarHeight, 120);
    }
  }
  
  static bool isAutoRestartEnabled() {
    try {
      return _remoteConfig.getBool(_autoRestart);
    } catch (e) {
      return _getLocalConfig(_autoRestart, true);
    }
  }
  
  static bool isDebugMode() {
    try {
      return _remoteConfig.getBool(_debugMode);
    } catch (e) {
      return _getLocalConfig(_debugMode, false);
    }
  }
  
  static T _getLocalConfig<T>(String key, T defaultValue) {
    try {
      final configJson = _prefs.getString('remote_config');
      if (configJson != null) {
        final config = jsonDecode(configJson);
        return config[key] ?? defaultValue;
      }
    } catch (e) {
      debugPrint('Error reading local config: $e');
    }
    return defaultValue;
  }
  
  // Force refresh config
  static Future<void> refreshConfig() async {
    try {
      await _remoteConfig.fetch();
      await _remoteConfig.activate();
      await _applyConfig();
    } catch (e) {
      debugPrint('Config refresh failed: $e');
    }
  }
}