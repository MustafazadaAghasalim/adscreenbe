import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:geolocator/geolocator.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/services.dart';
import 'package:disk_space_2/disk_space_2.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import '../config/server_config.dart';
import 'ad_service.dart';
import 'tablet_service.dart';
import 'admin_command_service.dart';
import 'silent_update_service.dart';

class TelemetryService {
  static final TelemetryService _instance = TelemetryService._internal();
  factory TelemetryService() => _instance;
  TelemetryService._internal();

  static const _platform = MethodChannel('com.adscreen.kiosk/telemetry');

  final Dio _dio = Dio();
  final _battery = Battery();
  final _deviceInfo = DeviceInfoPlugin();
  Timer? _timer;
  bool _started = false;
  bool _batterySaveMode = false;
  int _lastBatteryLevel = 100;

  // Cached app version — read once from native, stays constant until reinstall
  String _appVersion = '0.0.0';
  int _appVersionCode = 0;
  bool _versionFetched = false;

  // Use centralized ServerConfig instead of hardcoded URLs
  String get baseUrl => ServerConfig.baseUrl;

  void start() {
    if (_started) return;
    _started = true;
    _timer = Timer.periodic(const Duration(seconds: 30), (timer) => _sendTelemetry());
    _sendTelemetry(); // Send immediately
    print("TelemetryService: Started sending to $baseUrl every 30s");
  }

  /// Adjust polling rate based on battery level
  void _checkBatterySaveMode(int batteryLevel) {
    final shouldSave = batteryLevel <= 20;
    if (shouldSave != _batterySaveMode) {
      _batterySaveMode = shouldSave;
      _timer?.cancel();
      final interval = _batterySaveMode ? 120 : 30; // 2 min in save mode, 30s normal
      _timer = Timer.periodic(Duration(seconds: interval), (_) => _sendTelemetry());
      print("TelemetryService: Battery save mode ${_batterySaveMode ? 'ON (120s)' : 'OFF (30s)'}");
    }
    _lastBatteryLevel = batteryLevel;
  }

  Future<String> _getIpAddress() async {
    try {
      for (var interface in await NetworkInterface.list()) {
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            return addr.address;
          }
        }
      }
    } catch (_) {}
    return "Unknown";
  }

  /// Get real battery temperature from native Android channel
  Future<double> _getBatteryTemperature() async {
    try {
      if (Platform.isAndroid) {
        final temp = await _platform.invokeMethod('getBatteryTemperature');
        if (temp is double) return temp;
        if (temp is int) return temp.toDouble();
      }
    } catch (e) {
      print("TelemetryService: getBatteryTemperature error: $e");
    }
    return 0.0;
  }

  /// Get real screen brightness from native Android channel
  Future<double> _getScreenBrightness() async {
    try {
      if (Platform.isAndroid) {
        final brightness = await _platform.invokeMethod('getScreenBrightness');
        if (brightness is double) return brightness;
        if (brightness is int) return brightness.toDouble();
      }
    } catch (e) {
      print("TelemetryService: getScreenBrightness error: $e");
    }
    return 0.0;
  }

  /// Get real WiFi signal strength (RSSI) from native Android channel
  Future<String> _getSignalStrength() async {
    try {
      if (Platform.isAndroid) {
        final rssi = await _platform.invokeMethod('getWifiRssi');
        if (rssi is int) {
          if (rssi >= -50) return "Excellent ($rssi dBm)";
          if (rssi >= -60) return "Good ($rssi dBm)";
          if (rssi >= -70) return "Fair ($rssi dBm)";
          return "Weak ($rssi dBm)";
        }
      }
    } catch (e) {
      print("TelemetryService: getWifiRssi error: $e");
    }
    return "Unknown";
  }

  Future<void> _sendTelemetry() async {
    try {
      final tabletId = TabletService().tabletId;
      if (tabletId == null) {
        print("TelemetryService: No tablet ID yet, skipping.");
        return;
      }

      final int batteryLevel = await _battery.batteryLevel;
      final batteryState = await _battery.batteryState;

      // Auto-adjust polling rate based on battery level
      _checkBatterySaveMode(batteryLevel);

      // Get Location & Speed with Timeout
      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
          timeLimit: const Duration(seconds: 5),
        );
      } catch (e) {
        print("TelemetryService: GPS Timeout or Error: $e");
      }

      final lat = position?.latitude ?? 0.0;
      final lng = position?.longitude ?? 0.0;
      final speed = position?.speed ?? 0.0;

      // Get IP
      String ip = await _getIpAddress();

      // Get Storage (REAL)
      double? freeSpace = await DiskSpace.getFreeDiskSpace;
      double? totalSpace = await DiskSpace.getTotalDiskSpace;

      // Get Connectivity (REAL)
      var connectivityResult = await (Connectivity().checkConnectivity());
      String networkType = "None";
      if (connectivityResult == ConnectivityResult.mobile) networkType = "Cellular";
      else if (connectivityResult == ConnectivityResult.wifi) networkType = "WiFi";
      else if (connectivityResult == ConnectivityResult.ethernet) networkType = "Ethernet";

      // Get device info (REAL)
      String deviceModel = "Unknown";
      String osVersion = "Unknown";
      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        deviceModel = "${androidInfo.brand} ${androidInfo.model}";
        osVersion = "Android ${androidInfo.version.release}";
      }

      // Get REAL sensor values from native Android (skip in battery save mode)
      final double temperature = _batterySaveMode ? 0.0 : await _getBatteryTemperature();
      final double brightness = _batterySaveMode ? 0.0 : await _getScreenBrightness();
      final String signalStrength = _batterySaveMode ? "Save Mode" : await _getSignalStrength();

      // Read app version from native (cached after first call)
      if (!_versionFetched) {
        try {
          final info = await SilentUpdateService().getVersionInfo();
          _appVersion = (info['versionName'] as String?) ?? '0.0.0';
          _appVersionCode = (info['versionCode'] as num?)?.toInt() ?? 0;
          _versionFetched = true;
        } catch (e) {
          print("TelemetryService: Could not read app version: $e");
        }
      }

      final payload = {
        "tablet_id": tabletId,
        "app_version": _appVersion,
        "app_version_code": _appVersionCode,
        "battery_percent": batteryLevel,
        "is_charging": batteryState == BatteryState.charging || batteryState == BatteryState.full,
        "charging_status": batteryState.toString().split('.').last,
        "latitude": lat,
        "longitude": lng,
        "speed": speed,
        "ip_address": ip,
        "storage_free": "${((freeSpace ?? 0) / 1024).toStringAsFixed(1)} GB",
        "storage_total": "${((totalSpace ?? 0) / 1024).toStringAsFixed(1)} GB",
        "network_type": networkType,
        "device_model": deviceModel,
        "os_version": osVersion,
        "current_creative": AdService().currentCreative,
        "impressions_today": AdService().impressionsToday,
        "loop_status": AdService().loopStatus,
        "temperature": "${temperature.toStringAsFixed(1)}°C",
        "brightness": brightness,
        "signal_strength": signalStrength,
      };

      final response = await _dio.post(
        "${ServerConfig.updateEndpoint}",
        data: payload,
      );

      // Handle server response (lock commands, etc.)
      if (response.statusCode == 200 && response.data != null) {
        final data = response.data;
        if (data is Map) {
          // Handle lock state from server
          final bool? locked = data['locked'] as bool?;
          final String? unlockPin = data['unlock_pin']?.toString();
          if (locked != null) {
            TabletService().updateLockState(locked, unlockPin);
          }

          // Handle pending commands delivered via heartbeat response
          final pendingCommands = data['pending_commands'];
          if (pendingCommands is List && pendingCommands.isNotEmpty) {
            print("TelemetryService: Received ${pendingCommands.length} pending command(s) via heartbeat");
            for (final cmd in pendingCommands) {
              if (cmd is Map) {
                final cmdMap = Map<String, dynamic>.from(cmd);
                cmdMap['type'] = cmdMap['command'] ?? cmdMap['type'] ?? '';
                AdminCommandService().handleIncomingCommand(cmdMap);
              }
            }
          }
        }
      }

      print("TelemetryService: Sent real data → battery=$batteryLevel%, loc=($lat,$lng), temp=${temperature.toStringAsFixed(1)}°C, signal=$signalStrength");

      // Also push latest data via Socket.IO for real-time updates
      AdService().emitTelemetry(payload);

    } catch (e) {
      print("TelemetryService Error: $e");
    }
  }

  void stop() {
    _timer?.cancel();
    _started = false;
  }
}
